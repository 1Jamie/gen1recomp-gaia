local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")
local Save = require("src.core.gen2.Save")

-- ../pokecrystal/data/maps/maps.asm:156
local MAP = "DARK_CAVE_VIOLET_ENTRANCE"

return function(game)
  local fails = 0
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print("[flash2863] " .. (cond and "PASS " or "FAIL ") .. line)
  end
  local function finish()
    print("[flash2863] " .. (fails == 0 and "ALL PASS" or (fails .. " FAILURES")))
    love.event.quit(fails == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map) then
    ok(false, "the crystal world booted")
    finish()
  end

  local lead = Mon.new(game.data, "HOOTHOOT", 20)
  lead.moves = { { id = "FLASH", pp = 20, maxPp = 20 } }
  game.save.party = { lead }
  game.save.player.badges = game.save.player.badges or {}
  game.save.player.badges.ZEPHYR = true

  world:warpToMapId(MAP, 3, 12, "up")
  U.wait(60)
  world.noWildEncounters = true
  ok(world.map and world.map.id == MAP, "arrived at " .. MAP)
  ok(world.daytime == "DARK", "the cave starts dark")

  local result = world:useFieldMove("FLASH", lead)
  ok(result and result.ok, "FLASH accepted")
  for _ = 1, 600 do
    if world.flashUsed and not world:busy() and not world.queuedFieldMove then break end
    U.tap(game, "a")
    U.wait(3)
  end
  U.wait(30)
  ok(world.flashUsed == true, "FLASH set STATUSFLAGS_FLASH_F")
  ok(world.daytime ~= "DARK", "the cave is lit")

  ok(game:writeSave() ~= false, "save written")
  game:returnToTitle()
  U.wait(10)
  local loaded = Save.load(game.save.version)
  ok(loaded ~= nil, "save read back")
  if not loaded then finish() end
  game:continueGame(loaded)
  for _ = 1, 600 do
    if game.world and game.world.map and not game.world:busy() then break end
    U.wait(1)
  end
  U.wait(60)
  local back = game.world
  ok(back and back.map and back.map.id == MAP, "continued in " .. MAP)
  ok(back and back.flashUsed == true, "STATUSFLAGS_FLASH_F survives CONTINUE")
  ok(back and back.daytime ~= "DARK", "the cave is still lit after CONTINUE")
  U.still(game, DIR .. "/2863_crystal_after_continue_lit.png")
  finish()
end
