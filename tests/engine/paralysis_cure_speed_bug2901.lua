-- engine/battle/move_effects/heal.asm:35
-- engine/battle/trainer_ai.asm:625
-- engine/items/item_effects.asm:907
-- engine/items/item_effects.asm:1172
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
local Status = require("src.battle.Status")
local StatusRegistry = require("src.battle.StatusRegistry")
local TurnOrder = require("src.battle.TurnOrder")
local TrainerAI = require("src.battle.TrainerAI")
local ItemEffects = require("src.inventory.ItemEffects")
local faithful = require("src.battle.rulesets.gen1_faithful")
local modern = require("src.battle.rulesets.modern_clean")

for _, id in ipairs({ "FULL_HEAL", "FULL_RESTORE", "PARLYZ_HEAL", "AWAKENING" }) do
  Data.items[id] = Data.items[id] or { id = id, name = id:gsub("_", " ") }
end

local function mon(status)
  return {
    name = "MON", stages = {},
    curStats = { speed = 100, attack = 100, defense = 50, special = 50, hp = 100 },
    curTypes = { "NORMAL" },
    mon = { status = status, level = 50, hp = 50, stats = { hp = 100 } },
  }
end

local function arena(ruleset, player, enemy)
  return { data = Data, ruleset = ruleset, player = player, enemy = enemy,
           rng = function(lo) return lo end, trainer = { name = "LASS" } }
end

local REST = { id = "REST" }

do
  local p, e = mon("PAR"), mon(nil)
  MoveEffects.primary.HEAL_EFFECT(arena(faithful, p, e), p, e, REST)
  T.eq(p.mon.status, "SLP", "REST swaps paralysis for sleep")
  T.eq(TurnOrder.effectiveSpeed(p), 25, "REST keeps the quartered speed")
end

do
  local p, e = mon("BRN"), mon(nil)
  MoveEffects.primary.HEAL_EFFECT(arena(faithful, p, e), p, e, REST)
  T.eq(Status.applyPenalty(p, "attack", 100), 50, "REST keeps the halved attack")
end

do
  local p, e = mon("PAR"), mon(nil)
  local B = arena(faithful, p, e)
  MoveEffects.primary.HEAL_EFFECT(B, p, e, REST)
  p.mon.status = nil
  StatusRegistry.inflict(B, p, "PAR", {})
  T.eq(TurnOrder.effectiveSpeed(p), 6, "a second paralysis quarters the stale quarter")
end

do
  local p, e = mon("PAR"), mon(nil)
  local B = arena(faithful, p, e)
  MoveEffects.primary.HEAL_EFFECT(B, p, e, REST)
  MoveEffects.primary.SPEED_UP2_EFFECT(B, p, e)
  T.eq(TurnOrder.effectiveSpeed(p), 200, "a speed stage change recomputes the stat")
end

do
  local p, e = mon("PAR"), mon(nil)
  MoveEffects.primary.HEAL_EFFECT(arena(modern, p, e), p, e, REST)
  T.eq(TurnOrder.effectiveSpeed(p), 100, "modern_clean drops the penalty with the status")
end

for _, item in ipairs({ "FULL_HEAL", "FULL_RESTORE" }) do
  local p, e = mon(nil), mon("PAR")
  TrainerAI.useItem(arena(faithful, p, e), item)
  T.eq(e.mon.status, nil, "the AI's " .. item .. " cures paralysis")
  T.eq(TurnOrder.effectiveSpeed(e), 25, "the AI's " .. item .. " keeps the quartered speed")
end

local function newBattle()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 40)
  battle.ruleset = faithful
  return battle, save
end

local function paralyzed(battle)
  local p = battle.player
  p.mon.status = "PAR"
  Status.bakePenalty(p)
  return p, p.mon.stats.speed
end

for _, item in ipairs({ "PARLYZ_HEAL", "FULL_HEAL" }) do
  local battle, save = newBattle()
  local p, raw = paralyzed(battle)
  local result = ItemEffects.use(Data, save, item, p.mon, battle)
  T.eq(result, "consumed", item .. " is used")
  T.eq(TurnOrder.effectiveSpeed(p), raw, "the player's " .. item .. " restores speed")
end

do
  local battle, save = newBattle()
  local p, raw = paralyzed(battle)
  p.mon.hp = p.mon.stats.hp
  ItemEffects.use(Data, save, "FULL_RESTORE", p.mon, battle)
  T.eq(TurnOrder.effectiveSpeed(p), raw, "FULL RESTORE at full HP acts as FULL HEAL")
end

do
  local battle, save = newBattle()
  local p, raw = paralyzed(battle)
  p.mon.hp = 1
  ItemEffects.use(Data, save, "FULL_RESTORE", p.mon, battle)
  T.eq(p.mon.status, nil, "FULL RESTORE on a hurt mon cures paralysis")
  T.eq(TurnOrder.effectiveSpeed(p), math.max(1, math.floor(raw / 4)),
    "but keeps the quartered speed")
end

do
  local battle, save = newBattle()
  local p, raw = paralyzed(battle)
  p.mon.hp = 1
  MoveEffects.primary.HEAL_EFFECT(battle, p, battle.enemy, REST)
  T.eq(TurnOrder.effectiveSpeed(p), math.max(1, math.floor(raw / 4)), "the player's REST keeps the quarter")
  ItemEffects.use(Data, save, "AWAKENING", p.mon, battle)
  T.eq(TurnOrder.effectiveSpeed(p), raw, "an AWAKENING after REST recopies the party stats")
end

T.finish("curing paralysis keeps the quartered speed where the cart does (#2901)")
