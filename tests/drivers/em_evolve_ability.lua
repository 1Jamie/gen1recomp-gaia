local U = require("tests.drivers.util")

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_evolve_ability failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Evolution = require("src.core.game3.evolution")
  local Pokemon = require("src.core.game3.pokemon")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session and session.version == "emerald", "emerald session") then return finish() end
  local TRUANT, VITAL_SPIRIT = 54, 72
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_SLAKOTH"), 18)
  local mon = session.party[1]
  check(Pokemon.abilityName(mon.ability) == "TRUANT", "Slakoth has Truant (" .. Pokemon.abilityName(mon.ability) .. ")")
  Evolution.apply(mon, C:require("species", "SPECIES_VIGOROTH"), session)
  check(mon.ability == VITAL_SPIRIT and mon.abilityId == VITAL_SPIRIT, "Vigoroth has Vital Spirit (" .. tostring(mon.ability) .. ")")
  Evolution.apply(mon, C:require("species", "SPECIES_SLAKING"), session)
  check(mon.ability == TRUANT, "Slaking has Truant (" .. tostring(mon.ability) .. ")")
  return finish()
end
