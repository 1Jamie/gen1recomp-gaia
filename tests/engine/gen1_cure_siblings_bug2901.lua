-- engine/items/item_effects.asm:907
-- engine/items/item_effects.asm:1172
-- engine/battle/move_effects/heal.asm:13
-- engine/battle/move_effects/heal.asm:29
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Font = require("src.render.Font")
Font.load(Data)
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local MoveEffects = require("src.battle.MoveEffects")
local Damage = require("src.battle.Damage")
local Stats = require("src.pokemon.Stats")
local Status = require("src.battle.Status")
local TurnOrder = require("src.battle.TurnOrder")
local ItemEffects = require("src.inventory.ItemEffects")
local faithful = require("src.battle.rulesets.gen1_faithful")
local modern = require("src.battle.rulesets.modern_clean")

for _, id in ipairs({ "FULL_HEAL", "FULL_RESTORE", "PARLYZ_HEAL" }) do
  Data.items[id] = Data.items[id] or { id = id, name = id:gsub("_", " ") }
end

local function newBattle(ruleset)
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 40)
  battle.ruleset = ruleset or faithful
  return battle, save
end

local function textOf(msgs)
  local m = msgs and msgs[1]
  return type(m) == "table" and (m.text or "") or tostring(m or "")
end

local REST, RECOVER = { id = "REST" }, { id = "RECOVER" }

do
  local battle, save = newBattle()
  local p = battle.player
  local raw = p.mon.stats.speed
  p.badges = { SOULBADGE = true }
  p.stages.speed, p.stages.attack = 2, 1
  p.mon.status = "PAR"
  Status.bakePenalty(p)
  T.check(TurnOrder.effectiveSpeed(p) ~= raw, "staged, boosted, quartered before the cure")
  ItemEffects.use(Data, save, "PARLYZ_HEAL", p.mon, battle)
  T.eq(TurnOrder.effectiveSpeed(p), raw, "the cure leaves the raw party speed")
  T.eq(p.stages.speed, 2, "the stage counter itself survives")
  T.eq(Damage.stagedStat(p, "attack"), p.mon.stats.attack, "attack is raw too")
  MoveEffects.changeStage(battle, p, "attack", 1)
  T.eq(Damage.stagedStat(p, "attack"), Stats.applyStage(p.mon.stats.attack, 2),
    "a stage change recomputes that stat")
  T.eq(Damage.stagedStat(p, "speed"), raw, "and leaves the others raw")
end

do
  local battle, save = newBattle()
  local p = battle.player
  p.curStats = { hp = p.mon.stats.hp, attack = 1, defense = 1, speed = 1, special = 1 }
  p.mon.status = "PAR"
  ItemEffects.use(Data, save, "FULL_HEAL", p.mon, battle)
  T.eq(p.curStats.speed, p.mon.stats.speed, "a transformed mon gets its own party stats back")
end

do
  local battle, save = newBattle(modern)
  local p = battle.player
  p.stages.speed = 2
  p.mon.status = "PAR"
  ItemEffects.use(Data, save, "PARLYZ_HEAL", p.mon, battle)
  T.eq(TurnOrder.effectiveSpeed(p), Stats.applyStage(p.mon.stats.speed, 2),
    "modern_clean keeps the stages after a cure")
end

do
  local battle = newBattle()
  local p = battle.player
  p.mon.status, p.toxicCounter, p.mon.hp = "PSN", 3, 1
  MoveEffects.primary.HEAL_EFFECT(battle, p, battle.enemy, REST)
  T.eq(p.toxicCounter, 3, "REST keeps the toxic flag and counter")
end

do
  local battle, save = newBattle()
  local p = battle.player
  p.mon.status, p.toxicCounter, p.mon.hp = "PSN", 3, 1
  ItemEffects.use(Data, save, "FULL_RESTORE", p.mon, battle)
  T.eq(p.mon.status, nil, "FULL RESTORE on a hurt mon cures poison")
  T.eq(p.toxicCounter, 3, "but keeps the toxic flag")
end

do
  local battle, save = newBattle()
  local p = battle.player
  p.mon.status, p.toxicCounter = "PSN", 3
  ItemEffects.use(Data, save, "FULL_HEAL", p.mon, battle)
  T.eq(p.toxicCounter, nil, "FULL HEAL still clears the toxic flag")
end

local function healResult(move, missing, ruleset)
  local battle = newBattle(ruleset)
  local p = battle.player
  p.mon.stats.hp = 600
  p.mon.hp = 600 - missing
  local msgs = MoveEffects.primary.HEAL_EFFECT(battle, p, battle.enemy, move)
  return p.mon.hp, msgs
end

for _, missing in ipairs({ 255, 511 }) do
  for _, move in ipairs({ REST, RECOVER }) do
    local hp = healResult(move, missing)
    T.eq(hp, 600 - missing, move.id .. " fails at exactly " .. missing .. " missing HP")
  end
end
T.eq((healResult(RECOVER, 256)), 600, "RECOVER works at 256 missing HP")
T.eq((healResult(REST, 254)), 600, "REST works at 254 missing HP")
T.eq((healResult(RECOVER, 1)), 600, "RECOVER works at 1 missing HP")
T.eq((healResult(RECOVER, 0)), 600, "RECOVER at full HP fails without change")

do
  local battle = newBattle()
  local p = battle.player
  p.mon.status, p.mon.hp = "PAR", 1
  local msgs = MoveEffects.primary.HEAL_EFFECT(battle, p, battle.enemy, REST)
  T.check(textOf(msgs):find("became healthy", 1, true) ~= nil, "REST over a status: became healthy")
end

do
  local battle = newBattle()
  local p = battle.player
  p.mon.status, p.mon.hp = nil, 1
  local msgs = MoveEffects.primary.HEAL_EFFECT(battle, p, battle.enemy, REST)
  T.check(textOf(msgs):find("started sleeping", 1, true) ~= nil, "REST while healthy: started sleeping")
end

T.eq((healResult(RECOVER, 255, modern)), 600, "modern_clean RECOVER works at 255 missing HP")

do
  local battle = newBattle(modern)
  local p = battle.player
  p.mon.status, p.toxicCounter, p.mon.hp = "PSN", 3, 1
  MoveEffects.primary.HEAL_EFFECT(battle, p, battle.enemy, REST)
  T.eq(p.toxicCounter, nil, "modern_clean REST clears the toxic flag")
end

do
  local Growth = require("src.pokemon.Growth")
  local battle, save = newBattle()
  local p = battle.player
  local mon = save.party[1]
  mon.exp = Growth.expForLevel(Data.pokemon.FIXMON_A.growthRate, mon.level + 1,
                               Data.growth_rates) - 1
  battle.queue, battle.nextInsert = {}, 0
  battle.participants = { [mon] = true }
  p.hazeStatReset = true
  battle:awardExp()
  battle.queue[2].fn()
  T.eq(mon.level, 31, "the queued row writes the level")
  T.eq(p.hazeStatReset, nil, "a level-up after HAZE re-applies badge boosts")
end

T.finish("gen1 cure siblings of #2901")
