local U = require("tests.drivers.util")
local BC = require("src.core.gen2.BugContest")
local Swarm = require("src.core.gen2.Roamers").Swarm
local Save = require("src.core.gen2.Save")

return function(game)
  local deadline = love.timer.getTime() + 25
  local ok, err = xpcall(function()
    local identity = os.getenv("POKEPORT_IDENTITY") or ""
    assert(identity ~= "" and identity ~= "pokemon-love2d", "isolated READY identity required")
    local out = assert(os.getenv("POKEPORT_SHOT_DIR"), "shot directory required")
    local world, save = assert(game.world), assert(game.save)
    local version = save.version
    local function wait(n)
      for _ = 1, n do
        assert(love.timer.getTime() < deadline, "H11 driver deadline")
        U.wait(1)
      end
    end
    local function ready(map)
      for _ = 1, 1600 do
        if world.map and (not map or world.map.id == map) and not game.stack:top() and world:acceptsMenuInput() then return end
        wait(1)
      end
      error("world did not settle: " .. tostring(map))
    end
    local function shot(name)
      ready()
      wait(4)
      assert(U.still(game, out .. "/" .. version .. "-" .. name .. ".png"), "capture failed")
      assert(love.timer.getTime() < deadline, "capture deadline")
    end
    local today = BC.now().day
    local yesterday = (today + BC.DAY_WRAP - 1) % BC.DAY_WRAP
    ready()
    save.dailyReset = { day = today, remaining = 1 }
    if version ~= "crystal" then
      assert(version == "gold" or version == "silver", "Gen2 driver only")
      world:setSwarm(3, 78, 0)
      assert(save.dailyFlags.swarm and Swarm.active(save), "Gold/Silver producer missing shared flag")
      save.dailyReset.day = yesterday
      world:checkTimeEvents()
      assert(not Swarm.active(save) and not save.swarmMap and not save.swarmMaps.DUNSPARCE, "Gold/Silver daily cleanup failed")
      shot("01-gold-silver-daily-control")
      print("PASS H11 " .. version .. " shared swarm daily cleanup control")
      return
    end
    local function run(key)
      assert(world.vm:start(key), "source script did not start: " .. key)
      for _ = 1, 2400 do
        if not world.vm:running() then break end
        U.tap(game, "a")
        wait(2)
      end
      assert(not world.vm:running(), "source script did not finish: " .. key)
      ready()
    end
    local function flag(name, id) return world:engineFlag(world:engineFlagId(name, id)) end
    for _, pair in ipairs({ { "ENGINE_GOLDENROD_DEPT_STORE_SALE_IS_ON", 97 }, { "ENGINE_DUNSPARCE_SWARM", 160 },
      { "ENGINE_YANMA_SWARM", 161 }, { "ENGINE_QWILFISH_SWARM", 82 } }) do
      world:setEngineFlag(world:engineFlagId(pair[1], pair[2]), false)
    end
    run("2f:573c")
    assert(flag("ENGINE_GOLDENROD_DEPT_STORE_SALE_IS_ON", 97), "Todd source sale producer failed")
    world:warpToMapId("GOLDENROD_DEPT_STORE_ROOF", 6, 5, "left")
    ready("GOLDENROD_DEPT_STORE_ROOF")
    shot("01-todd-rooftop-sale")
    run("2f:56a6"); run("2f:5887"); run("2f:5544")
    run("2f:5699"); run("2f:5172")
    local resolve = world:engineFlagResolver()
    assert(Swarm.onMap(save, "DARK_CAVE_VIOLET_ENTRANCE", resolve) == "DUNSPARCE"
      and Swarm.onMap(save, "ROUTE_35", resolve) == "YANMA", "Anthony/Arnie source swarms missing")
    assert(flag("ENGINE_QWILFISH_SWARM", 82) and Swarm.fishing(save, resolve) == 1
      and not save.dailyFlags.swarm, "Ralph source fishing state failed")
    assert(flag("ENGINE_ANTHONY_READY_FOR_REMATCH", 111) and flag("ENGINE_ANTHONY_FRIDAY_NIGHT", 145)
      and flag("ENGINE_BEVERLY_HAS_NUGGET", 125), "source phone-array producers missing")
    save.crystal.kenjiBreak = 2
    world:checkTimeEvents()
    assert(flag("ENGINE_GOLDENROD_DEPT_STORE_SALE_IS_ON", 97) and world:readVar(0x1a) == 2, "same-day poll changed daily state")
    save.dailyReset.day = yesterday
    world:checkTimeEvents()
    for _, pair in ipairs({ { "ENGINE_GOLDENROD_DEPT_STORE_SALE_IS_ON", 97 }, { "ENGINE_DUNSPARCE_SWARM", 160 },
      { "ENGINE_YANMA_SWARM", 161 }, { "ENGINE_QWILFISH_SWARM", 82 }, { "ENGINE_ANTHONY_READY_FOR_REMATCH", 111 },
      { "ENGINE_ANTHONY_FRIDAY_NIGHT", 145 }, { "ENGINE_BEVERLY_HAS_NUGGET", 125 } }) do
      assert(not flag(pair[1], pair[2]), "daily expiry retained " .. pair[1])
    end
    assert(world:readVar(0x1a) == 1 and save.swarmMaps.YANMA == "ROUTE_35"
      and save.swarmMaps.DUNSPARCE == "DARK_CAVE_VIOLET_ENTRANCE" and save.dailyFlags.fishingSwarm == 1,
      "Kenji countdown or inactive stored bytes failed")
    world:warpToMapId("GOLDENROD_CITY", 12, 20, "down"); ready("GOLDENROD_CITY")
    world:warpToMapId("GOLDENROD_DEPT_STORE_ROOF", 6, 5, "left"); ready("GOLDENROD_DEPT_STORE_ROOF")
    shot("02-next-day-rooftop-sale-ended")
    assert(game:writeSave() ~= false, "isolated native save failed")
    local restored = assert(Save.load("crystal"))
    assert(restored.crystal.kenjiBreak == 1 and restored.swarmMaps.YANMA == "ROUTE_35"
      and not restored.engineFlags[world:engineFlagId("ENGINE_GOLDENROD_DEPT_STORE_SALE_IS_ON", 97)], "native save/load lost expiry state")
    run("2f:56a6"); run("2f:5887")
    assert(flag("ENGINE_DUNSPARCE_SWARM", 160) and flag("ENGINE_YANMA_SWARM", 161), "phone source could not start new swarms")
    print("PASS H11 Crystal source phone/roof, daily World reset, independent grass/fishing, phone arrays, Kenji, native save/load, new calls")
  end, debug.traceback)
  if not ok then print("FAIL H11 " .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
