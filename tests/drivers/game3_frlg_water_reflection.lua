local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_frlg_water_reflection"
local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  if failures == 0 then
    print("PASS game3_frlg_water_reflection")
    love.event.quit(0)
  else
    print("FAIL game3_frlg_water_reflection failures=" .. failures)
    love.event.quit(1)
  end
end
return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local FieldEffects = require("src.core.game3.field_effects")
  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the FireRed field") then return finish() end
  local maps = { "FR_CERULEAN_CITY", "FR_VIRIDIAN_CITY", "FR_PALLET_TOWN", "FR_ROUTE_21", "FR_ROUTE_1" }
  local mapId, px, py
  for _, candidate in ipairs(maps) do
    Map.load(nil, game, candidate, { x = 8, y = 8, facing = "down" })
    local C = require("src.core.game3.collision")
    for y = 0, 80 do
      for x = 0, 80 do
        if C.inBounds(x, y) and C.isWalkable(x, y)
            and FieldEffects.isFrlgReflective(C.behavior(x, y + 1)) then
          mapId, px, py = candidate, x, y
          break
        end
      end
      if mapId then break end
    end
    if mapId then break end
  end
  if not result(mapId ~= nil, "found a walkable FireRed shoreline cell") then return finish() end
  Map.load(nil, game, mapId, { x = px, y = py, facing = "down" })
  Player.moving, Player.progress = false, 0
  Player.cellX, Player.cellY = px, py
  Player.px, Player.py = px * 16, py * 16
  Player.targetX, Player.targetY = px, py
  Player.facing = "down"
  if game.session then game.session.x, game.session.y, game.session.facing = px, py, "down" end
  U.wait(45)
  result(FieldEffects.frlgReflectionType(px, py, px, py, 16, 32,
    function(x, y) return Collision.behavior(x, y) end), "water below the player is reflective")
  U.still(game, DIR .. "/frlg_water_reflection.png")
  result((FieldEffects.lastFrlgReflections or 0) >= 1,
    "the FireRed field renderer draws a water reflection")
  finish()
end
