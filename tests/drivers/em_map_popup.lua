local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_map_popup"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_map_popup failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  try("new_game", function()
    game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  end)
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Popup = require("src.ui.game3.map_name_popup")
  local FieldModules = require("src.core.game3.field_modules")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session ~= nil, "new game session") then return finish() end
  check(FieldModules.enabled("mapNamePopup", session), "Emerald enables the map name popup field module")

  local function mapNow()
    local s = Runtime.getSession()
    return s and s.map
  end

  local function settle(frames)
    for _ = 1, frames or 600 do
      local busy = Warp.isBusy() or (Message.isOpen and Message.isOpen())
      if not busy then break end
      if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
      U.wait(1)
    end
  end

  local function place(mapId, x, y, facing)
    settle()
    local ok = try("Map.load " .. mapId, function()
      Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    end)
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    return ok
  end

  local S = Popup.Rse.STATE
  local function waitState(st, limit)
    for _ = 1, limit or 400 do
      local t = Popup.Rse.task
      if t and t.state == st then return true end
      U.wait(1)
    end
    return false
  end

  local function popupAt(label, mapId, x, y, name, theme, shot)
    Popup.dismiss()
    check(not Flags.getFlag(Space.store, nil, C:flag("FLAG_HIDE_MAP_NAME_POPUP")), label .. ": FLAG_HIDE_MAP_NAME_POPUP clear")
    check(place(mapId, x, y, "down"), label .. ": " .. mapId .. " loads")
    local t = Popup.Rse.task
    check(t ~= nil and t.state == S.PRINT and t.yOffset == Popup.Rse.OFFSCREEN_Y,
      label .. ": ShowMapNamePopup starts in the print wait, offscreen")
    local printed = 0
    while Popup.Rse.task and Popup.Rse.task.state == S.PRINT and printed < 60 do
      U.wait(1)
      printed = printed + 1
    end
    check(printed >= 30 and printed <= 32, label .. ": print delay " .. printed .. " frames (pokeemerald/src/map_name_popup.c:262)")
    local w = Popup.Rse.window
    check(w ~= nil and w.name == name, label .. ": name " .. tostring(w and w.name))
    check(w ~= nil and w.theme == theme, label .. ": theme " .. tostring(w and w.theme))
    local slid = 0
    while Popup.Rse.task and Popup.Rse.task.state == S.SLIDE_IN and slid < 60 do
      if slid == 10 then U.still(game, DIR .. "/" .. shot .. "_slide_in.png") end
      U.wait(1)
      slid = slid + 1
    end
    check(slid >= 19 and slid <= 21, label .. ": slide in " .. slid .. " frames at 2px")
    check(waitState(S.WAIT, 10), label .. ": popup fully shown")
    U.wait(20)
    U.still(game, DIR .. "/" .. shot .. ".png")
    return w
  end

  Flags.setVar(Space.store, nil, C:var("VAR_LITTLEROOT_INTRO_STATE"), 7)
  Flags.setVar(Space.store, nil, C:var("VAR_LITTLEROOT_TOWN_STATE"), 4)
  Flags.setVar(Space.store, nil, C:var("VAR_ROUTE101_STATE"), 3)
  Flags.setFlag(Space.store, nil, C:flag("FLAG_RESCUED_BIRCH"), true)
  Flags.setFlag(Space.store, nil, C:flag("FLAG_HIDE_MAP_NAME_POPUP"), false)
  local SX, SY = 10, 3
  place("EM_LITTLEROOT_TOWN", SX, SY, "up")
  U.wait(80)
  Popup.dismiss()
  local routed = false
  for _ = 1, 12 do
    U.hold(game, "up", 16)
    for _ = 1, 200 do
      if not Warp.isBusy() then break end
      U.wait(1)
    end
    if mapNow() == "EM_ROUTE101" then routed = true break end
  end
  check(routed, "walking north crosses the connection into EM_ROUTE101 (" .. tostring(mapNow()) .. ")")
  local t = Popup.Rse.task
  check(t ~= nil, "the connection shows the popup (pokeemerald/src/overworld.c:824)")
  if waitState(S.WAIT, 120) then U.still(game, DIR .. "/01_route101_walk.png") end
  check(Popup.Rse.window and Popup.Rse.window.name == "ROUTE 101", "route 101 popup name")

  popupAt("route101", "EM_ROUTE101", 10, 10, "ROUTE 101", "wood", "02_route101")
  popupAt("petalburg woods", "EM_PETALBURG_WOODS", 12, 30, "PETALBURG WOODS", "wood", "03_petalburg_woods")
  popupAt("petalburg", "EM_PETALBURG_CITY", 20, 18, "PETALBURG CITY", "brick", "04_petalburg_city")
  popupAt("slateport", "EM_SLATEPORT_CITY", 19, 21, "SLATEPORT CITY", "marble", "05_slateport_city")
  popupAt("route 105", "EM_ROUTE105", 10, 20, "ROUTE 105", "underwater", "06_route105")
  local uw = popupAt("underwater 124", "EM_UNDERWATER_ROUTE124", 10, 10, "UNDERWATER", "stone2", "07_underwater_route124")
  local man = require("src.ui.game3.rse.mapsec").readLua("chrome/map_popup/manifest.lua")
  local Kit = require("src.ui.game3.rse.scene_kit")
  local want = Kit.color555(man.underwaterPalette[3])
  check(uw and math.abs(uw.colors.fg[1] - want[1]) < 1e-6 and math.abs(uw.colors.fg[3] - want[3]) < 1e-6,
    "underwater map uses sMapPopUp_Palette_Underwater (pokeemerald/src/map_name_popup.c:421)")

  Popup.dismiss()
  Flags.setFlag(Space.store, nil, C:flag("FLAG_HIDE_MAP_NAME_POPUP"), true)
  place("EM_ROUTE101", 10, 10, "down")
  check(Popup.Rse.task == nil, "FLAG_HIDE_MAP_NAME_POPUP suppresses the popup")
  Flags.setFlag(Space.store, nil, C:flag("FLAG_HIDE_MAP_NAME_POPUP"), false)

  place("EM_ROUTE101", 10, 10, "down")
  for _ = 1, 400 do
    if not Popup.Rse.task then break end
    U.wait(1)
  end
  check(Popup.Rse.task == nil, "popup slides out and ends")
  return finish()
end
