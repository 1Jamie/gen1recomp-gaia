package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local eq = T.eq

local Sem = require("src.core.game3.field_semantics")
local Flags = require("src.core.game3.scripting.flags")

-- pokefirered/include/constants/vars.h:47
local PRET = {
  repelSteps = "VAR_REPEL_STEP_COUNT",
  happinessSteps = "VAR_HAPPINESS_STEP_COUNTER",
  poisonSteps = "VAR_POISON_STEP_COUNTER",
  massageSteps = "VAR_MASSAGE_COOLDOWN_STEP_COUNTER",
}

for name, pret in pairs(PRET) do
  local want = Flags.VAR_IDS[pret]
  eq(Sem.FRLG_VARS[name], want, "FRLG " .. name .. " is " .. pret)
  eq(Sem.var({}, name), want, "profile-less session resolves " .. name .. " to " .. pret)
end

eq(Sem.FRLG_VARS.poisonSteps ~= Flags.VAR_IDS.VAR_MAGIKARP_SIZE_RECORD, true,
  "FRLG poison step counter does not alias VAR_MAGIKARP_SIZE_RECORD")

T.finish("game3_frlg_field_vars")
