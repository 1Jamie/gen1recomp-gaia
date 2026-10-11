local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_field_poison_2865"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. "poison2865 " .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  print((failures == 0 and "PASS " or "FAIL ") .. "poison2865 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local ROUTES = { firered = "Route1", leafgreen = "Route1", ruby = "Route101", sapphire = "Route101", emerald = "Route101" }
local TOWNS = { firered = "PalletTown", leafgreen = "PalletTown" }

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.phase == "boot" and game.boot ~= nil, "boot_ready") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "PSN", gender = 0 })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Space = require("src.core.game3.scripting.space")
  local StepEvents = require("src.core.game3.step_events")
  local MapCatalog = require("src.import.gba.map_catalog")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field_session_ready") then return finish() end
  if Space.vm and Space.vm:isRunning() then Space.vm:halt(true) end
  require("src.core.game3.field").unlock()
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").check = function() return false end

  local version = session.version
  local isRse = require("src.core.game3.profile").family(session) == "rse"
  local C = require("src.core.game3.constants").of(version)
  session.party = {}
  Party.giveMon(session, C:require("species", isRse and "SPECIES_ZIGZAGOON" or "SPECIES_RATTATA"), 50)
  local mon = session.party[1]
  mon.status, mon.statusNum = "PSN", 8

  local mapId = MapCatalog.pretToEngine(TOWNS[version] or ROUTES[version])
  Map.load(nil, game, mapId, { x = 0, y = 0, facing = "down" })
  U.wait(30)
  local L = Map.currentDef().midLayout
  local sx, sy
  for y = 2, L.height - 12 do
    for x = 2, L.width - 3 do
      local ok = true
      for dy = 0, 6 do
        if not Collision.isWalkable(x, y + dy) or Collision.isGrass(x, y + dy) then ok = false break end
      end
      if ok then sx, sy = x, y break end
    end
    if sx then break end
  end
  if not check(sx ~= nil, "open_column_found_on_" .. tostring(mapId)) then return finish() end
  Map.load(nil, game, mapId, { x = sx, y = sy, facing = "down" })
  U.wait(40)
  if Space.vm and Space.vm:isRunning() then Space.vm:halt(true) end
  require("src.core.game3.field").unlock()

  local hp0 = mon.hp
  local seq, peak, shot = {}, 0, false
  local want = isRse and 10 or 5
  for _ = 1, 16 * 8 do
    table.insert(game.input.pressQueue, "down")
    game.input.state.down = true
    coroutine.yield()
    local m = StepEvents.bgMosaic()
    if m > 0 or #seq > 0 then seq[#seq + 1] = m end
    if m > peak then peak = m end
    if m == want and not shot then
      game.input.state.down = false
      shot = U.still(game, DIR .. "/2865_" .. version .. "_poison_mosaic_peak.png")
    end
    if #seq > 0 and m == 0 then break end
  end
  game.input.state.down = false
  print("poison2865 mosaic sequence: " .. table.concat(seq, ","))
  check(mon.hp < hp0, "poison step damaged the mon (" .. tostring(hp0) .. " -> " .. tostring(mon.hp) .. ")")
  check(peak == want, "mosaic peaks at " .. want .. " (got " .. peak .. ")")
  local expect = isRse and "2,4,6,8,10,8,6,4,2,0" or "1,2,3,4,5,4,3,2,1,0"
  check(table.concat(seq, ",") == expect, "mosaic follows Task_FieldPoisonEffect " .. expect)
  check(shot, "peak screenshot captured")
  U.wait(20)
  check(StepEvents.bgMosaic() == 0 and not StepEvents.poisonEffectActive(), "effect task ended")
  finish()
end
