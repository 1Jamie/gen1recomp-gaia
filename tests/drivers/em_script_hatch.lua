local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_script_hatch", "/tmp/em_script_hatch")

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    local C = S.C()
    local Party = require("src.core.game3.party")
    local Natives = require("src.core.game3.scripting.natives")
    Party.giveMonToPlayer(session, C:require("species", "SPECIES_TORCHIC"), 1)
    local egg = session.party[1]
    egg.isEgg, egg.egg, egg.eggCycles = true, true, 1
    egg.nickname, egg.name = "", "TORCHIC"
    d.check(M.goTo(game, "EM_ROUTE114", 14, 8, "up"), "Route 114 loaded for the script hatch")
    d.shot(game, "01_route114_before_hatch")
    local ctx = { session = session, specialVars = { [0x8004] = 0 }, stringVars = {} }
    local _, _, known = Natives.special(ctx, C:special("ScriptHatchMon"), {})
    d.check(known, "ScriptHatchMon resolved through Emerald's runtime special table")
    d.check(egg.isEgg == false and egg.egg == false, "ScriptHatchMon converted the party egg into a Pokémon")
    d.check(egg.level == require("src.core.game3.breeding").EGG_HATCH_LEVEL and egg.friendship == 120,
      "hatched mon received the cart egg level and friendship")
    d.shot(game, "02_route114_after_hatch")
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
