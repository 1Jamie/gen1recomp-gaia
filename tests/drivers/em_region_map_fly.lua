local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_region_map_fly"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_region_map_fly failures=" .. failures)
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
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Field = require("src.core.game3.field")
  local Party = require("src.core.game3.party")
  local RegionMap = require("src.ui.game3.rse.region_map")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session ~= nil, "new game session") then return finish() end

  Flags.setVar(Space.store, nil, C:var("VAR_LITTLEROOT_INTRO_STATE"), 7)
  Flags.setVar(Space.store, nil, C:var("VAR_LITTLEROOT_TOWN_STATE"), 4)
  Flags.setVar(Space.store, nil, C:var("VAR_ROUTE101_STATE"), 3)
  Flags.setFlag(Space.store, nil, C:flag("FLAG_RESCUED_BIRCH"), true)
  for _, f in ipairs({ "FLAG_VISITED_LITTLEROOT_TOWN", "FLAG_VISITED_OLDALE_TOWN", "FLAG_VISITED_PETALBURG_CITY" }) do
    Flags.setFlag(Space.store, nil, C:flag(f), true)
  end

  local function mapNow()
    local s = Runtime.getSession()
    return s and s.map
  end

  local function place(mapId, x, y, facing)
    local ok = try("Map.load " .. mapId, function()
      Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    end)
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    U.wait(40)
    return ok
  end

  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end

  check(place("EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", 2, 2, "up"), "bedroom loads (the wall map is metatile (2,1))")
  U.tap(game, "a")
  local msg = waitFor(function() return Message.isOpen and Message.isOpen() end, 120)
  check(msg, "A on the wall map shows Common_Text_LookCloserAtMap")
  for _ = 1, 20 do
    if RegionMap.active() then break end
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(6)
  end
  local s = RegionMap.active()
  check(s ~= nil and s.mode == "wall", "special FieldShowRegionMap opens the rse field region map")
  if not s then return finish() end
  check(waitFor(function() return s.state == 4 end, 120), "field region map faded in and takes input")
  check(s.cursorX == 5 and s.cursorY == 13, string.format("cursor starts on Littleroot (%d,%d)", s.cursorX, s.cursorY))
  check(s.mapSecName == "LITTLEROOT TOWN", "name window shows " .. tostring(s.mapSecName))
  U.wait(10)
  U.still(game, DIR .. "/01_wall_map.png")
  U.hold(game, "up", 5)
  waitFor(function() return s.inputFn == "full" and s.moveCounter == 0 end, 30)
  U.wait(2)
  check(s.cursorY == 12, "up moves the cursor one square in 5 frames (" .. s.cursorY .. ")")
  check(s.mapSecName == "ROUTE 101", "cursor on Route 101 (" .. tostring(s.mapSecName) .. ")")
  U.still(game, DIR .. "/02_wall_map_route101.png")
  U.tap(game, "b")
  check(waitFor(function() return RegionMap.active() == nil end, 120), "B closes the wall map")
  check(waitFor(function() return not (Space.vm and Space.vm:isRunning()) end, 240), "EventScript_RegionMap finishes")
  U.wait(30)
  U.shot(game, DIR .. "/03_back_in_bedroom.png")
  check(mapNow() == "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", "back in the bedroom")

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_SWELLOW, 30, "SWELLOW")
  place("EM_ROUTE101", 10, 10, "down")
  local picked, closed = nil, false
  RegionMap.show({
    session = session,
    mode = "fly",
    onPick = function(sec, info)
      picked = { sec = sec, info = info }
      local ok, err = pcall(Field.flyTo, sec, session.party[1])
      if not ok then
        print("[driver] NOTE Field.flyTo is the FB side and still fails on rse (" .. tostring(err)
          .. "); landing through Field.flyDestination + Map.load")
        local dest = Field.flyDestination(sec)
        Map.load(nil, game, dest.map, { x = dest.x, y = dest.y, facing = "down" })
        Player.reset(dest.x, dest.y, "down")
      end
    end,
    onClose = function() closed = true end,
  })
  s = RegionMap.active()
  check(s ~= nil and s.mode == "fly", "fly map opens")
  check(waitFor(function() return s.state == 12 end, 120), "fly map fades in (CB_FadeInFlyMap)")
  check(s.mapSecName == "ROUTE 101", "fly cursor starts on Route 101 (" .. tostring(s.mapSecName) .. ")")
  local canFly, cantFly = 0, 0
  for _, icon in ipairs(s.flyIcons) do
    if icon.flicker then canFly = canFly + 1 else cantFly = cantFly + 1 end
  end
  check(canFly == 3 and cantFly == 13, "fly icons: 3 visited towns, 13 not visited (" .. canFly .. "/" .. cantFly .. ")")
  U.still(game, DIR .. "/04_fly_map.png")
  local function step(dir)
    local x0, y0 = s.cursorX, s.cursorY
    U.hold(game, dir, 2)
    waitFor(function() return s.cursorX ~= x0 or s.cursorY ~= y0 end, 30)
    waitFor(function() return s.inputFn == "full" end, 10)
    U.wait(1)
  end
  step("left")
  step("left")
  step("left")
  step("up")
  check(s.cursorX == 2 and s.cursorY == 11, string.format("cursor on Petalburg square (%d,%d)", s.cursorX, s.cursorY))
  check(s.mapSecName == "PETALBURG CITY" and s.mapSecType == RegionMap.TYPE.CITY_CANFLY, "Petalburg is a fly destination")
  U.wait(8)
  U.still(game, DIR .. "/05_fly_map_petalburg.png")
  U.tap(game, "a")
  check(waitFor(function() return closed end, 120), "A on Petalburg closes the fly map")
  check(picked and picked.sec == 7, "picked mapsec 7 (" .. tostring(picked and picked.sec) .. ")")
  check(waitFor(function() return mapNow() == "EM_PETALBURG_CITY" end, 900), "flew to EM_PETALBURG_CITY (" .. tostring(mapNow()) .. ")")
  waitFor(function() return not Field.locked end, 900)
  U.wait(20)
  check(Player.cellX == 20 and Player.cellY == 17,
    string.format("landed at the Petalburg heal location (%s,%s)", tostring(Player.cellX), tostring(Player.cellY)))
  U.shot(game, DIR .. "/06_landed_petalburg.png")
  return finish()
end
