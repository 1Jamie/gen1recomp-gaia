local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_cycling_fly_bug2564"
local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  print((failures == 0 and "PASS " or "FAIL ") .. "cycling_fly_bug2564")
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "cycling Fly boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  if not check(session ~= nil, "cycling Fly field reached") then return finish() end
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")
  local Fade = require("src.ui.game3.fade")
  local ItemUse = require("src.core.game3.item_use")
  local Bag = require("src.core.game3.bag")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of(session.version)
  local rse = session.version == "emerald"
  local defs = Flags.forVersion(session.version)
  local road = assert(defs.IDS[rse and "FLAG_SYS_CYCLING_ROAD" or "FLAG_SYS_ON_CYCLING_ROAD"])
  local scene = not rse and assert(defs.VAR_IDS.VAR_MAP_SCENE_ROUTE16)
  local bike = C:require("items", rse and "ITEM_MACH_BIKE" or "ITEM_BICYCLE")
  Bag.add(session.bag, bike, 1)
  if not rse then Flags.setFlag(Space.store, nil, assert(defs.IDS.FLAG_GOT_BICYCLE), true) end
  local function waitFor(pred, limit)
    for _ = 1, limit do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end
  local function settle()
    return waitFor(function()
      if Message.isOpen() then
        if Message.isTyping() then Message.skipReveal() end
        table.insert(game.input.pressQueue, "a")
      end
      return not Field.locked and not Fade.active and not Player.moving
        and not Message.isOpen() and not (Space.vm and Space.vm:isRunning())
    end, 600)
  end
  local function holdUntil(dir, pred, limit)
    local reached = false
    for _ = 1, limit do
      if pred() then reached = true break end
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      U.wait(1)
    end
    game.input.state[dir] = false
    return reached or pred()
  end
  local gate = rse and "EM_ROUTE110_SEASIDE_CYCLING_ROAD_NORTH_ENTRANCE"
    or "FR_ROUTE_16_NORTH_ENTRANCE_1F"
  Map.load(nil, game, gate, { x = rse and 6 or 3, y = rse and 4 or 12,
    facing = rse and "right" or "left" })
  if not check(settle(), "cycling gate scripts settle") then return finish() end
  check(game.data.maps[gate].bikingAllowed == 1, "cycling gate permits riding indoors")
  check(ItemUse.useBike(session, bike) and Player.biking, "cycling gate bike mounts")
  U.still(game, DIR .. "/cycling_gate_bike.png")
  if rse then
    if not check(holdUntil("right", function()
        return Player.targetX == 12 and Player.targetY == 4
      end, 240), "Emerald gate crosses BikeCheck and reaches east exit column") then return finish() end
  end
  if not check(holdUntil(rse and "down" or "left", function() return session.map ~= gate end, 600),
      "cycling gate enters road through coordinate script and warp") then return finish() end
  if not check(settle(), "cycling road arrival settles") then return finish() end
  check(Flags.getFlag(Space.store, nil, road), "cycling road flag armed by real gate scripts")
  if scene then check(Flags.getVar(Space.store, nil, scene) == 1, "Route 16 scene armed") end
  check(Player.biking, "cycling road requires bike before Fly")
  for _, eo in ipairs(require("src.core.game3.objects").forDraw()) do eo.sight = 0 end
  session.party = {}
  Party.giveMon(session, C:require("species", rse and "SPECIES_SWELLOW" or "SPECIES_CHARIZARD"), 40)
  local section = rse and "MAPSEC_MAUVILLE_CITY" or "MAPSEC_CELADON_CITY"
  local dest = assert(Field.flyDestination(section))
  check(Field.flyTo(section, session.party[1]), "cycling road Fly starts")
  if not check(waitFor(function()
      return session.map == dest.map and not Field._flyLanding and not Field.locked and not Fade.active
    end, 2400), "cycling Fly landing finishes") then return finish() end
  check(not Flags.getFlag(Space.store, nil, road), "Fly clears cycling flag")
  if scene then check(Flags.getVar(Space.store, nil, scene) == 0, "Fly clears Route 16 scene") end
  check(not Player.biking and not session.biking and not game.save.biking, "Fly lands on foot in every state mirror")
  U.still(game, DIR .. "/fly_city_on_foot.png")
  local center = rse and "EM_MAUVILLE_CITY_POKEMON_CENTER_1F" or "FR_CELADON_CITY_POKEMON_CENTER_1F"
  if not check(holdUntil("up", function() return session.map == center end, 300),
      "walking north enters real Center door") then return finish() end
  if not check(settle(), "Center warp finishes") then return finish() end
  check(game.data.maps[center].bikingAllowed == 0 and not Player.biking and not session.biking,
    "Center remains on foot after cycling road Fly")
  U.still(game, DIR .. "/center_on_foot.png")
  if not check(holdUntil("down", function() return session.map == dest.map end, 300),
      "Center exit returns to city") then return finish() end
  if not check(settle(), "Center exit settles") then return finish() end
  check(ItemUse.useBike(session, bike) and Player.biking, "city bike mounts after cycling road Fly")
  U.still(game, DIR .. "/city_bike_toggle.png")
  check(ItemUse.useBike(session, bike) and not Player.biking, "city bike dismounts after cycling road Fly")
  if rse then
    local acro = C:require("items", "ITEM_ACRO_BIKE")
    check(ItemUse.useBike(session, acro) and Player.biking and Player.bikeType == "acro", "city Acro Bike mounts")
    check(ItemUse.useBike(session, acro) and not Player.biking, "city Acro Bike dismounts")
  end
  finish()
end
