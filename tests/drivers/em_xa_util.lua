local U = require("tests.drivers.util")

local X = {}

function X.new(name, defaultDir)
  local d = {
    name = name,
    dir = os.getenv("POKEPORT_SHOT_DIR") or defaultDir,
    failures = 0,
    vmLogs = {},
  }
  function d.check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then d.failures = d.failures + 1 end
    return ok
  end
  function d.note(msg) print("[driver] " .. msg) end
  local function capture(msg)
    msg = tostring(msg)
    if msg:find("skip unknown", 1, true) or msg:find("skip op", 1, true) or msg:find("not ported", 1, true)
        or msg:find("missing script", 1, true) or msg:find("runaway", 1, true) or msg:find("LUA ERROR", 1, true) then
      d.vmLogs[#d.vmLogs + 1] = msg
    end
  end
  local origPrint = print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    capture(table.concat(parts, "\t"))
    return origPrint(...)
  end
  local Vm = require("src.core.game3.scripting.vm")
  local origNew = Vm.new
  Vm.new = function(opts)
    local vm = origNew(opts)
    local a = vm.adapters
    if a and a.log and not a._xaWrapped then
      local inner = a.log
      a.log = function(msg) capture(msg) return inner(msg) end
      a._xaWrapped = true
    end
    return vm
  end
  function d.finish(label)
    if d.finished then return end
    d.finished = true
    d.check(#d.vmLogs == 0, "no unknown-op / unported-system VM logs" .. (label and (" " .. label) or "") .. " (" .. #d.vmLogs .. ")")
    for i = 1, math.min(#d.vmLogs, 10) do d.note("VM LOG " .. d.vmLogs[i]) end
    print((d.failures == 0 and "PASS" or "FAIL") .. " " .. d.name .. " failures=" .. d.failures)
    love.event.quit(d.failures == 0 and 0 or 1)
    U.wait(10)
  end
  function d.try(label, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then d.note(label .. " error: " .. tostring(err)) end
    return ok, err
  end
  function d.shot(game, file)
    return U.shot(game, d.dir .. "/" .. file)
  end
  function d.still(game, file)
    return U.still(game, d.dir .. "/" .. file)
  end
  return d
end

function X.newGame(d, game, gender)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not d.check(game.boot ~= nil, "boot reached") then return nil end
  d.try("new_game", function()
    game:_handleBootAction({ action = "new_game", name = gender == 1 and "MAY" or "BRENDAN", gender = gender or 0 })
  end)
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  d.check(session ~= nil, "new game session exists")
  return session
end

function X.session()
  return require("src.core.game3.runtime").getSession()
end

function X.settle(game, frames)
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  for _ = 1, frames or 600 do
    local busy = Warp.isBusy() or (Message.isOpen and Message.isOpen())
    if not busy then break end
    if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
    U.wait(1)
  end
end

function X.goTo(d, game, mapId, x, y, facing)
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  X.settle(game)
  local ok = d.try("Map.load " .. mapId, function()
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
  end)
  local s = X.session()
  if s then s.x, s.y, s.facing = x, y, facing end
  Player.cellX, Player.cellY = x, y
  Player.px, Player.py = x * 16, y * 16
  Player.targetX, Player.targetY = x, y
  Player.facing = facing
  U.wait(40)
  return ok and s and s.map == mapId
end

function X.flags()
  local Flags = require("src.core.game3.scripting.flags")
  return Flags.forVersion("emerald")
end

function X.setFlag(name, on)
  local Space = require("src.core.game3.scripting.space")
  local F = X.flags()
  require("src.core.game3.scripting.flags").setFlag(Space.store, nil, assert(F.IDS[name], name), on ~= false)
end

function X.flag(name)
  local Space = require("src.core.game3.scripting.space")
  local F = X.flags()
  return require("src.core.game3.scripting.flags").getFlag(Space.store, nil, assert(F.IDS[name], name)) == true
end

function X.setVar(name, v)
  local Space = require("src.core.game3.scripting.space")
  local F = X.flags()
  require("src.core.game3.scripting.flags").setVar(Space.store, nil, assert(F.VAR_IDS[name], name), v)
end

function X.var(name)
  local Space = require("src.core.game3.scripting.space")
  local F = X.flags()
  return tonumber(require("src.core.game3.scripting.flags").getVar(Space.store, nil, assert(F.VAR_IDS[name], name))) or 0
end

function X.scriptRunning()
  local Space = require("src.core.game3.scripting.space")
  return Space.vm and Space.vm:isRunning()
end

function X.vmWhere()
  local Space = require("src.core.game3.scripting.space")
  local vm = Space.vm
  if not (vm and vm:isRunning()) then return "idle" end
  local pc = vm.ctx.pc
  local list = pc and vm.scripts[pc.listKey]
  local row = list and list[pc.index]
  return string.format("%s/%s #%s op=%s mode=%s status=%s", tostring(vm._scriptKey), tostring(pc and pc.listKey), tostring(pc and pc.index),
    tostring(row and row.op), tostring(vm.ctx.mode), tostring(vm.ctx.status))
end

function X.stepOnto(d, game, mapId, tx, ty)
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Collision = require("src.core.game3.collision")
  for _, n in ipairs({ { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" } }) do
    if X.session().map == mapId and not Collision.canEnter(game, tx + n[1], ty + n[2]) then goto continue end
    X.goTo(d, game, mapId, tx + n[1], ty + n[2], n[3])
    X.settle(game, 120)
    Player.forceStep(n[3])
    for _ = 1, 200 do
      if not Player.moving and not Warp.isBusy() then break end
      U.wait(1)
    end
    if Player.cellX == tx and Player.cellY == ty then return true end
    ::continue::
  end
  return false
end

function X.metatile(x, y)
  local Collision = package.loaded["src.core.game3.collision"]
  local def = Collision and Collision._mapDef
  local layout = def and def.midLayout
  return layout and layout:midAt(x, y) or nil
end

function X.label(name)
  local C = require("src.core.game3.constants").of("emerald")
  return C:require("metatile_labels", name)
end

function X.mash(game, until_, frames, button, gap)
  for _ = 1, frames or 1200 do
    if until_() then return true end
    U.tap(game, button or "a")
    U.wait(gap or 2)
  end
  return until_()
end

function X.waitFor(pred, frames)
  for _ = 1, frames or 1200 do
    if pred() then return true end
    U.wait(1)
  end
  return pred()
end

return X
