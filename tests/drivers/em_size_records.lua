local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_size_records", "/tmp/em_size_records")

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    local C = S.C()
    local Party = require("src.core.game3.party")
    local lotad = C:require("species", "SPECIES_LOTAD")
    local seedot = C:require("species", "SPECIES_SEEDOT")
    Party.giveMonToPlayer(session, seedot, 20)
    Party.giveMonToPlayer(session, lotad, 20)
    local lotadMon, seedotMon = session.party[2], session.party[1]
    lotadMon.personality, lotadMon.ivHp, lotadMon.ivAtk = 0xFFFFFFFF, 15, 15
    lotadMon.ivDef, lotadMon.ivSpd, lotadMon.ivSpAtk, lotadMon.ivSpDef = 0, 15, 15, 0
    seedotMon.personality, seedotMon.ivHp, seedotMon.ivAtk = 0xEEEEEEEE, 15, 15
    seedotMon.ivDef, seedotMon.ivSpd, seedotMon.ivSpAtk, seedotMon.ivSpDef = 0, 15, 15, 0
    d.check(M.goTo(game, "EM_SOOTOPOLIS_CITY_LOTAD_AND_SEEDOT_HOUSE", 4, 4, "up"), "Lotad and Seedot house loaded")
    d.shot(game, "01_house")

    local done = M.talk(game, "SootopolisCity_LotadAndSeedotHouse_EventScript_SeedotBrother", {
      answers = { "yes", 0 },
      partySlot = 1,
      onList = function() d.shot(game, "02_seedot_party_select") end,
    })
    d.check(done, "Seedot record script completed through ChoosePartyMon and CompareSeedotSize")
    d.check(S.var("VAR_SEEDOT_SIZE_RECORD") > 0, "Seedot record stored in its Emerald variable")
    d.shot(game, "03_seedot_record")

    done = M.talk(game, "SootopolisCity_LotadAndSeedotHouse_EventScript_LotadBrother", {
      answers = { "yes", 1 },
      partySlot = 2,
      onList = function() d.shot(game, "04_lotad_party_select") end,
    })
    d.check(done, "Lotad record script completed through ChoosePartyMon and CompareLotadSize")
    d.check(S.var("VAR_LOTAD_SIZE_RECORD") > 0, "Lotad record stored in its Emerald variable")
    d.shot(game, "05_lotad_record")
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
