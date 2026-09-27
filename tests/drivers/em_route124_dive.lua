local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_route124_dive"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_route124_dive failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Party = require("src.core.game3.party")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Collision = require("src.core.game3.collision")
  local Dive = require("src.core.game3.dive")
  local ShowMon = require("src.core.game3.field_move_show_mon")
  local Weather = require("src.core.game3.weather")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field session exists") then return finish() end
  local IDS = Flags.forVersion("emerald").IDS

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_WAILMER, 40, "WAILMER")
  local m = session.party[1]
  m.moves = { C.moves.byName.MOVE_DIVE, C.moves.byName.MOVE_SURF, C.moves.byName.MOVE_WATER_GUN, C.moves.byName.MOVE_REST }
  m.pp = { 10, 15, 25, 10 }

  local function mapNow() local s = Runtime.getSession(); return s and s.map end

  local function pump(pred, frames, label)
    local seen = {}
    for _ = 1, frames or 900 do
      if pred() then return true, seen end
      if Choice.isOpen and Choice.isOpen() then
        seen.choice = true
        U.tap(game, "a")
      elseif Message.isOpen and Message.isOpen() then
        seen.message = true
        U.tap(game, "a")
        U.wait(3)
      else
        U.wait(1)
      end
      if ShowMon.isActive() then seen.showMon = true end
      if Warp.isBusy() then seen.warp = true end
    end
    if label then print("[driver] pump timeout: " .. label) end
    return pred(), seen
  end

  local function place(mapId, x, y, facing, surfing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    local s = Runtime.getSession()
    s.x, s.y, s.facing = x, y, facing
    Player.surfing = surfing == true
    require("src.core.game3.field").unlock()
    U.wait(20)
  end

  place("EM_ROUTE124", 10, 3, "down", true)
  local MB = require("src.core.game3.mb")
  check(Collision.behavior(10, 3) == MB.id("DEEP_WATER"), "Route 124 (10,3) is diveable deep water")

  Flags.setFlag(Space.store, nil, IDS.FLAG_BADGE07_GET, false)
  U.tap(game, "a")
  U.wait(10)
  check(not (Space.vm and Space.vm:isRunning()), "without the Mind Badge A on deep water starts nothing")

  Flags.setFlag(Space.store, nil, IDS.FLAG_BADGE05_GET, true)
  Flags.setFlag(Space.store, nil, IDS.FLAG_BADGE07_GET, true)
  local code, dest = Dive.trySetDiveWarp(session)
  check(code == 2 and dest and dest.map == "EM_UNDERWATER_ROUTE124" and dest.x == 10 and dest.y == 3,
    string.format("TrySetDiveWarp -> 2 to %s (%s,%s)", tostring(dest and dest.map), tostring(dest and dest.x), tostring(dest and dest.y)))
  U.shot(game, DIR .. "/01_route124_surfing.png")
  U.tap(game, "a")
  U.wait(4)
  local key = Space.vm and Space.vm._scriptKey
  check(key == Space.scriptKey("EventScript_UseDive"), "A on deep water with the badge runs EventScript_UseDive (" .. tostring(key) .. ")")
  for _ = 1, 120 do
    if Message.isOpen and Message.isOpen() then break end
    U.wait(1)
  end
  U.wait(30)
  U.shot(game, DIR .. "/02_want_to_dive.png")
  local dived, seen = pump(function() return mapNow() == "EM_UNDERWATER_ROUTE124" and not Warp.isBusy() end, 1500, "dive")
  check(seen.choice == true, "the dive prompt asks YES/NO")
  check(seen.showMon == true, "FLDEFF_USE_DIVE shows the field move mon")
  check(dived, "dive warps to EM_UNDERWATER_ROUTE124 (" .. tostring(mapNow()) .. ")")
  check(Player.cellX == 10 and Player.cellY == 3, string.format("underwater at the same cell (%d,%d)", Player.cellX, Player.cellY))
  U.wait(30)
  check(Player.underwater == true and not Player.surfing, "avatar is UNDERWATER, not surfing")
  check(Weather.get() == Weather.UNDERWATER_BUBBLES, "underwater map runs bubbles weather (" .. tostring(Weather.get()) .. ")")
  local OwSprites = require("src.core.game3.ow_sprites")
  check(OwSprites.avatarState(Player) == "UNDERWATER", "OW sprite state UNDERWATER")
  U.shot(game, DIR .. "/03_underwater_route124.png")

  local function waterClass(bh)
    return bh == MB.id("SEAWEED_NO_SURFACING") or bh == MB.id("NO_SURFACING") or bh == MB.id("SEAWEED")
  end
  local sx, sy = nil, nil
  for yy = 1, 78 do
    for xx = 1, 78 do
      if not sx and Collision.isWalkable(xx, yy) and not Collision.isWater(xx, yy) then
        for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
          if waterClass(Collision.behavior(xx + d[1], yy + d[2])) then sx, sy = xx, yy end
        end
      end
    end
  end
  if sx then
    place("EM_UNDERWATER_ROUTE124", sx, sy, "down")
    U.wait(5)
  end
  local waterCell = nil
  for _, d in ipairs({ { "right", 1, 0 }, { "left", -1, 0 }, { "down", 0, 1 }, { "up", 0, -1 } }) do
    local b = Collision.behavior(Player.cellX + d[2], Player.cellY + d[3])
    if b == MB.id("SEAWEED_NO_SURFACING") or b == MB.id("NO_SURFACING") or b == MB.id("SEAWEED") then
      waterCell = d
      break
    end
  end
  check(waterCell ~= nil, "an underwater (no-surfacing / seaweed) cell borders the dive spot")
  local entered = false
  if waterCell then
    local tx, ty = Player.cellX + waterCell[2], Player.cellY + waterCell[3]
    U.hold(game, waterCell[1], 20)
    for _ = 1, 40 do if not Player.moving then break end U.wait(1) end
    entered = Player.cellX == tx and Player.cellY == ty
    print(string.format("[driver] %s -> (%d,%d) beh=%s", waterCell[1], Player.cellX, Player.cellY,
      tostring(MB.nameOf(Collision.behavior(Player.cellX, Player.cellY)))))
  end
  check(entered and Player.underwater == true, "the player swims onto the underwater seaweed / no-surfacing cell")
  U.shot(game, DIR .. "/04_underwater_seaweed.png")

  place("EM_UNDERWATER_ROUTE124", 10, 3, "down")
  Player.underwater = true
  U.wait(10)
  check(Dive.trySetDiveWarp(session) == 1, "TrySetDiveWarp -> 1 (emerge) under open water")
  U.tap(game, "b")
  U.wait(4)
  key = Space.vm and Space.vm._scriptKey
  check(key == Space.scriptKey("EventScript_UseDiveUnderwater"), "B underwater runs EventScript_UseDiveUnderwater (" .. tostring(key) .. ")")
  local up = pump(function() return mapNow() == "EM_ROUTE124" and not Warp.isBusy() end, 1500, "emerge")
  check(up, "emerging returns to EM_ROUTE124 (" .. tostring(mapNow()) .. ")")
  U.wait(20)
  check(Player.surfing == true and not Player.underwater, "surfaced avatar is SURFING")
  check(Player.cellX == 10 and Player.cellY == 3, string.format("surfaced at the same cell (%d,%d)", Player.cellX, Player.cellY))
  U.shot(game, DIR .. "/05_route124_surfaced.png")

  place("EM_UNDERWATER_ROUTE124", 13, 4, "down")
  Player.underwater = true
  U.wait(10)
  check(Dive.isUnableToEmerge(Collision.behavior(13, 4)), "(13,4) is NO_SURFACING")
  check(Dive.trySetDiveWarp(session) == 0, "no dive warp from a NO_SURFACING tile")

  finish()
end
