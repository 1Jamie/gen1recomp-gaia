-- NX launcher pad-cursor lag guards (Switch-only).
-- Proves the virtual mouse no longer warps love.mouse via setPosition on NX,
-- that FlexLove still sees pad coords through the getPosition bridge, that
-- desktop keeps setPosition, and that LauncherView wires NX perf guards.
-- Also prints a small metric block (setPosition counts + update cost).
--
-- FlexLove itself is not loaded here: the engine tier runs under plain luajit
-- without luautf8, which FlexLove requires. RomImporter owns the pointer
-- bridge; LauncherView wiring is asserted via source seams.
--   luajit tests/engine/launcher_nx_pad_cursor_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- Instrument setPosition so we can count warps (love_stub has none).
local setPositionCalls = 0
local mouseX, mouseY = 0, 0
love.mouse.getPosition = function() return mouseX, mouseY end
love.mouse.setPosition = function(x, y)
  setPositionCalls = setPositionCalls + 1
  mouseX, mouseY = x, y
end

local RomImporter = require("src.import.RomImporter")

local function freshImporter(isNX)
  return setmetatable({
    isNX = isNX and true or false,
    _padCursor = { x = 100, y = 100 },
    _padCursorActive = false,
    _padAxis = { leftx = 0, lefty = 0, righty = 0 },
    _padDir = {},
    _rawHatDirs = {},
    _padInited = true,
    _flex = true,
    tab = "red",
  }, RomImporter)
end

local function stickRight(imp, frames, dt)
  dt = dt or (1 / 60)
  imp._padAxis.leftx = 1
  for _ = 1, frames do
    imp:_updatePadCursor(dt)
  end
end

local function read(path)
  local f = assert(io.open(path, "r"))
  local src = f:read("*a")
  f:close()
  return src
end

-- ------- NX: no setPosition warps; getPosition bridge tracks the pad

do
  setPositionCalls = 0
  mouseX, mouseY = 0, 0
  local imp = freshImporter(true)
  local x0 = imp._padCursor.x
  stickRight(imp, 30)
  check(imp._padCursorActive, "NX stick activates pad cursor")
  check(imp._padCursor.x > x0, "NX stick moves pad cursor right")
  eq(setPositionCalls, 0, "NX pad move never calls love.mouse.setPosition")
  check(imp._nxPointerBridge, "NX installs getPosition bridge")
  local gx, gy = love.mouse.getPosition()
  eq(gx, imp._padCursor.x, "NX getPosition X matches pad cursor")
  eq(gy, imp._padCursor.y, "NX getPosition Y matches pad cursor")
  -- Real (stored) mouse must stay where the stub left it — bridge only.
  eq(mouseX, 0, "NX does not warp the underlying mouse X")
  eq(mouseY, 0, "NX does not warp the underlying mouse Y")
  imp:_restoreNxPointerBridge()
  check(not imp._nxPointerBridge, "restore clears NX mouse bridge")
  local rx, ry = love.mouse.getPosition()
  eq(rx, 0, "after restore getPosition is the real stub again")
  eq(ry, 0, "after restore getPosition Y is the real stub again")
end

-- ------- NX: A after idle must not false-yield the pad cursor

do
  mouseX, mouseY = 10, 20
  local imp = freshImporter(true)
  imp._padCursor.x, imp._padCursor.y = 400, 300
  -- Idle frames pin _lastMouse* to the real pointer.
  imp:_updatePadCursor(1 / 60)
  eq(imp._lastMouseX, 10, "idle samples real mouse X")
  eq(imp._lastMouseY, 20, "idle samples real mouse Y")
  -- A / activate without stick motion (clickAt path).
  imp:_activatePadCursor()
  imp:_updatePadCursor(1 / 60)
  check(imp._padCursorActive,
    "NX A after idle keeps pad cursor (no false yield via bridged getPosition)")
  local gx, gy = love.mouse.getPosition()
  eq(gx, 400, "bridged getPosition still reports pad X after A")
  eq(gy, 300, "bridged getPosition still reports pad Y after A")
  -- Real USB-ish motion still yields.
  mouseX, mouseY = 80, 90
  imp:_updatePadCursor(1 / 60)
  check(not imp._padCursorActive, "NX real mouse motion still yields pad cursor")
  imp:parkNxPointerForHost()
end

-- ------- NX: parkNxPointerForHost restores mouse for embedded editor

do
  mouseX, mouseY = 5, 6
  local imp = freshImporter(true)
  stickRight(imp, 5)
  check(imp._nxPointerBridge, "bridge on before park")
  check(imp._padCursorActive, "pad active before park")
  imp:parkNxPointerForHost()
  check(not imp._nxPointerBridge, "park clears bridge")
  check(not imp._padCursorActive, "park clears pad active")
  local gx, gy = love.mouse.getPosition()
  eq(gx, 5, "after park getPosition is real mouse X")
  eq(gy, 6, "after park getPosition is real mouse Y")
  -- Desktop no-op.
  local desk = freshImporter(false)
  desk._padCursorActive = true
  desk:parkNxPointerForHost()
  check(desk._padCursorActive, "desktop parkNxPointerForHost is a no-op")
end

-- ------- Desktop: setPosition still warps (unchanged path)

do
  setPositionCalls = 0
  mouseX, mouseY = 0, 0
  local imp = freshImporter(false)
  local x0 = imp._padCursor.x
  stickRight(imp, 30)
  check(imp._padCursorActive, "desktop stick activates pad cursor")
  check(imp._padCursor.x > x0, "desktop stick moves pad cursor right")
  eq(setPositionCalls, 30, "desktop pad move warps mouse every frame")
  eq(mouseX, imp._padCursor.x, "desktop setPosition tracks pad X")
  eq(mouseY, imp._padCursor.y, "desktop setPosition tracks pad Y")
  check(not imp._nxPointerBridge, "desktop never installs NX bridge")
end

-- ------- Metrics: setPosition counts + pad-update cost (NX vs desktop)

do
  local frames = 120
  local dt = 1 / 60

  setPositionCalls = 0
  local nx = freshImporter(true)
  local t0 = os.clock()
  stickRight(nx, frames, dt)
  local nxMs = (os.clock() - t0) * 1000
  local nxSet = setPositionCalls
  nx:_restoreNxPointerBridge()

  setPositionCalls = 0
  local desk = freshImporter(false)
  t0 = os.clock()
  stickRight(desk, frames, dt)
  local deskMs = (os.clock() - t0) * 1000
  local deskSet = setPositionCalls

  eq(nxSet, 0, "metric: NX setPosition count is 0 over 120 frames")
  eq(deskSet, frames, "metric: desktop setPosition count equals frame count")

  print(string.format(
    "METRICS nx_pad_cursor: frames=%d nx_setPosition=%d desk_setPosition=%d nx_update_ms=%.3f desk_update_ms=%.3f",
    frames, nxSet, deskSet, nxMs, deskMs))
end

-- ------- Source seams: LauncherView NX perf + detach restore

do
  local view = read("src/import/LauncherView.lua")
  check(view:find("function LauncherView.applyNxPerfGuards", 1, true) ~= nil,
    "LauncherView exports applyNxPerfGuards")
  check(view:find("LauncherView.applyNxPerfGuards(imp)", 1, true) ~= nil,
    "ensureFlex calls applyNxPerfGuards")
  check(view:find("FlexLove._Performance.enabled = false", 1, true) ~= nil,
    "NX guard disables Performance.enabled")
  check(view:find("mp.enabled = false", 1, true) ~= nil,
    "NX guard disables memory profiling")
  check(view:find("if not (imp and imp.isNX", 1, true) ~= nil,
    "perf guard is gated on imp.isNX")
  check(view:find("parkNxPointerForHost", 1, true) ~= nil,
    "detach parks NX pointer before tearing down")

  local impSrc = read("src/import/RomImporter.lua")
  check(impSrc:find("function RomImporter:_ensureNxPointerBridge", 1, true) ~= nil,
    "RomImporter owns NX getPosition bridge")
  check(impSrc:find("function RomImporter:parkNxPointerForHost", 1, true) ~= nil,
    "RomImporter exports parkNxPointerForHost")
  check(impSrc:find("_nxRealGetPosition()", 1, true) ~= nil,
    "NX yield samples real mouse, not bridged getPosition")
  check(impSrc:find("if not self.isNX and love.mouse.setPosition", 1, true) ~= nil,
    "RomImporter skips setPosition on NX")

  local mainSrc = read("main.lua")
  check(mainSrc:find("parkNxPointerForHost", 1, true) ~= nil,
    "openEditor parks NX pointer before save editor")
end

T.finish("launcher_nx_pad_cursor")
