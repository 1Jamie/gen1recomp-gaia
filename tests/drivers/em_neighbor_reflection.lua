local U = require("tests.drivers.util")

local DIR = os.getenv("POKEPORT_SHOT_DIR") or "shots"

local function fail(msg)
  print("FAIL " .. msg)
  love.event.quit(1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)
  local Map = require("src.core.game3.map")
  local FxRse = require("src.core.game3.field_effects_rse")
  local Ghosts = require("src.core.game3.ghosts")
  local Objects = require("src.core.game3.objects")
  local r104 = game.data.maps["EM_ROUTE104"]
  if not r104 then return fail("EM_ROUTE104 missing") end

  Map.load(nil, game, "EM_ROUTE104", { x = 28, y = 1, facing = "down" })
  U.wait(60)
  U.still(game, DIR .. "/em_control_player_on_own_map_reflects.png")
  if (FxRse.lastReflections or 0) < 1 then return fail("control player has no reflection") end

  Map.load(nil, game, "EM_RUSTBORO_CITY", { x = 28, y = 57, facing = "down" })
  U.wait(60)
  U.still(game, DIR .. "/em_rustboro_view_route104_no_npc.png")

  local defs = { { localId = 1, index = 1, x = 28, y = 1, graphicsId = 5, movementType = 8, elevation = 3, flag = 0 } }
  Ghosts._pools["EM_ROUTE104"] = Objects.spawnFromDefs(defs, r104, "EM_ROUTE104")
  U.wait(30)
  U.still(game, DIR .. "/em_rustboro_view_route104_ghost_npc_on_shore.png")
  local n = FxRse.lastReflections or 0
  print("GHOST_VIEW_REFL", n)
  if n < 1 then return fail("neighbor NPC has no reflection") end
  print("PASS")
  love.event.quit(0)
end
