package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Rse = require("src.core.game3.rse.init")
local SecretBase = require("src.core.game3.rse.secret_base")
local Trainers = require("src.core.game3.rse.frontier.trainers")
local BattleBridge = require("src.core.game3.battle_bridge")
local secretBaseKindForwarded = false
for _, kind in ipairs(BattleBridge.EXTRA_KINDS) do
  if kind == "secretBase" then secretBaseKindForwarded = true end
end
check(secretBaseKindForwarded, "battle bridge forwards the Secret Base battle kind")
local old = {
  manifest = SecretBase.manifest,
  var = Rse.var,
  setSpecialVar = Rse.setSpecialVar,
  random = Trainers.rng,
  shiny = Trainers.isShiny,
  createMon = Trainers.createMon,
  setEvs = Trainers.setEvs,
  setHeldItem = Trainers.setHeldItem,
  trainerInfo = Trainers.secretBaseTrainerInfo,
  className = Trainers.className,
}

SecretBase.manifest = function() return { facilityClasses = { 11, 12, 13, 14, 15, 21, 22, 23, 24, 25 } } end
Trainers.rng = function() return { Random32 = function() return 0x12345678 end } end
Trainers.isShiny = function() return false end
Trainers.createMon = function(species, level, iv, personality, otId, opts)
  return { species = species, level = level, fixedIV = iv, personality = personality, otId = otId,
    otName = opts.otName, otGender = opts.otGender, moves = opts.moves }
end
Trainers.setEvs = function(mon, evs) mon.evs = evs end
Trainers.setHeldItem = function(mon, item) mon.item = item end
Trainers.secretBaseTrainerInfo = function(fc) return fc + 100, fc + 200 end
Trainers.className = function(_, classId) return "CLASS " .. tostring(classId) end

local session = {
  version = "emerald",
  name = "BRENDA",
  party = { { species = 1, level = 30 } },
  secretBases = {
    [1] = {
      trainerName = "MISTY", gender = 1, trainerId = { 7, 0, 0, 0 },
      party = { species = { 25, 0 }, levels = { 28 }, personality = { 99 }, heldItems = { 2 }, EVs = { 14 },
        moves = { 33, 45, 86, 0 } },
    },
  },
}
local foe = SecretBase.battleFoe(0, session)
check(foe ~= nil, "saved Secret Base owner with a party produces a battle foe")
eq(foe.trainerName, "MISTY", "foe uses the saved owner name")
eq(foe.trainerClass, 123, "female owner class uses gender row and trainer-id class index")
eq(foe.trainerPicId, 223, "trainer picture follows the facility class")
eq(foe.party[1].fixedIV, 15, "secret-base Pokémon use the source fixed IV")
eq(foe.party[1].item, 2, "secret-base held item is restored")
eq(foe.party[1].evs[6], 14, "stored average EV is assigned to every stat")
eq(foe.party[1].moves[1], 33, "stored move set is restored")

local oldRuntime = package.loaded["src.core.game3.runtime"]
local oldNatives = package.loaded["src.core.game3.scripting.natives"]
local oldBridge = package.loaded["src.core.game3.battle_bridge"]
local oldTransition = package.loaded["src.core.game3.battle_transition_ids_rse"]
local oldSpace = package.loaded["src.core.game3.scripting.space"]
local oldBattleFoe = SecretBase.battleFoe
local savedVars, battleOpts, doneResult = {}, nil, nil
SecretBase.battleFoe = function() return { trainerId = 1024, trainerName = "MISTY", trainerClass = 121,
  trainerClassName = "CLASS 121", trainerPicId = 221, party = { { level = 28 } } } end
Rse.var = function(name) return name == "VAR_CURRENT_SECRET_BASE" and 0 or 0 end
Rse.setSpecialVar = function(_, id, value) savedVars[id] = value end
package.loaded["src.core.game3.runtime"] = { _mod = {}, _game = {}, getSession = function() return session end }
package.loaded["src.core.game3.scripting.natives"] = {
  outcome_to_code = function(result) return result == "lose" and 2 or 1 end,
  yieldHost = function(_, _, run) run(function() end); return false end,
}
package.loaded["src.core.game3.battle_bridge"] = { start = function(_, _, foeArg, opts)
  battleOpts = opts
  opts.done("lose")
  return true
end }
package.loaded["src.core.game3.battle_transition_ids_rse"] = { pickSpecial = function(group)
  eq(group, "secret_base", "battle uses Secret Base transition group")
  return 77
end }
package.loaded["src.core.game3.scripting.space"] = { vm = { tick = function() end } }
SecretBase.doSpecialBattle({}, {}, session, SecretBase.SPECIAL_BATTLE_SECRET_BASE)
check(battleOpts ~= nil, "special starts the battle bridge")
eq(battleOpts.secretBase, true, "battle receives secret-base battle kind")
eq(battleOpts.trainerId, 1024, "battle uses TRAINER_SECRET_BASE")
eq(battleOpts.noWhiteout, true, "losing returns to the script without whiteout")
eq(battleOpts.deferHeal, true, "script controls the source-order party heal")
eq(battleOpts.transitionId, 77, "special transition is forwarded")
eq(savedVars[0x800D], 2, "battle result is written to VAR_RESULT")

SecretBase.battleFoe = oldBattleFoe
Rse.var, Rse.setSpecialVar = old.var, old.setSpecialVar
package.loaded["src.core.game3.runtime"] = oldRuntime
package.loaded["src.core.game3.scripting.natives"] = oldNatives
package.loaded["src.core.game3.battle_bridge"] = oldBridge
package.loaded["src.core.game3.battle_transition_ids_rse"] = oldTransition
package.loaded["src.core.game3.scripting.space"] = oldSpace
SecretBase.manifest = old.manifest
Trainers.rng, Trainers.isShiny = old.random, old.shiny
Trainers.createMon, Trainers.setEvs, Trainers.setHeldItem = old.createMon, old.setEvs, old.setHeldItem
Trainers.secretBaseTrainerInfo, Trainers.className = old.trainerInfo, old.className
T.finish("emerald_secret_base_battle_test")
