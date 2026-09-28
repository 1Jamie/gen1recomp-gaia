local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_pokecenter_heal"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "NICK", gender = 0 })
  U.wait(240)

  local GAME = require("src.core.GameVersion").get()
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of(GAME)
  local Map = require("src.core.game3.map")
  local Heal = require("src.core.game3.pokecenter_heal")
  local P = require("src.core.game3.player")
  local session = Runtime.getSession()
  local prefix = GAME == "emerald" and "EM_OLDALE_TOWN" or "FR_VIRIDIAN_CITY"
  local mons = GAME == "emerald" and { "TREECKO", "ZIGZAGOON", "WURMPLE" } or { "BULBASAUR", "PIDGEY", "RATTATA" }
  session.party = session.party or {}
  for _, name in ipairs(mons) do
    if Party.size(session.party) < 3 then Party.giveMon(session, C.species.byName["SPECIES_" .. name], 5, "") end
  end
  for _, m in ipairs(session.party) do m.hp = 1 end

  Map.load(nil, game, prefix .. "_POKEMON_CENTER_1F", { x = 7, y = 4, facing = "up" })
  session.x, session.y, session.facing = 7, 4, "up"
  U.wait(60)
  print(("party=%d player=%s,%s facing=%s"):format(Party.size(session.party), tostring(P.cellX), tostring(P.cellY), tostring(P.facing)))

  local maxBalls, sawGlow, sawMonitor, gfx, n, frames = 0, false, false, false, 0, 0
  for _ = 1, 40 do
    if Heal.isActive() then break end
    U.tap(game, "a")
    U.wait(20)
  end
  result(Heal.isActive(), "heal effect started")
  while Heal.isActive() and frames < 900 do
    local fx = Heal._fx
    maxBalls = math.max(maxBalls, #fx.balls)
    if fx.state == 2 or fx.state == 3 then sawGlow = true end
    if fx.monitorVisible then sawMonitor = true end
    if Heal._ballIdx and Heal._monImg then gfx = true end
    if frames % 6 == 0 and n < 60 then
      n = n + 1
      U.still(game, ("%s/heal_%03d.png"):format(DIR, frames))
    end
    U.wait(1)
    frames = frames + 1
  end
  result(maxBalls == 3, "three balls placed (" .. maxBalls .. ")")
  result(sawGlow, "ball glow phase ran")
  result(gfx, "ball + monitor graphics loaded")
  result(sawMonitor, "monitor flashed")
  for _ = 1, 30 do U.tap(game, "a") U.wait(20) end
  result((session.party[1].hp or 0) > 1, "party healed")
  print((fails == 0 and "PASS" or "FAIL") .. " em_pokecenter_heal")
  love.event.quit(fails == 0 and 0 or 1)
  U.wait(10)
end
