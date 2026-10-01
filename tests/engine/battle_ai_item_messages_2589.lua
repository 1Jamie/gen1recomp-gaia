package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)

local BattleState = require("src.battle.BattleState")
local TrainerAI = require("src.battle.TrainerAI")
local SaveData = require("src.core.SaveData")
local Pokemon = require("src.pokemon.Pokemon")
local TypeChart = require("src.battle.TypeChart")
local romText = require("src.core.RomText")
TypeChart.load(Data)

local function newGame()
  local save = SaveData.newGame()
  save.player.name = "RED"
  save.party = { Pokemon.new(Data, "FIXMON_A", 10, function(_, b) return b end) }
  return {
    data = Data, save = save,
    stack = { top = function() return nil end, push = function() end },
    input = { wasPressed = function() return false end,
              isDown = function() return false end },
  }
end

local function newBattle()
  local battle = BattleState.newWild(newGame(), "FIXMON_C", 10)
  battle.trainer = { name = "MISTY" }
  battle.aiUses = 1
  return battle
end

local function strings(msgs)
  local out = {}
  for _, m in ipairs(msgs) do
    if type(m) == "string" then out[#out + 1] = m end
  end
  return out
end

local function usedLine(battle, item)
  local itemName = Data.items[item] and Data.items[item].name or item
  return romText(Data, "_AIBattleUseItemText", "%s\nused %s!", "MISTY", itemName, battle.enemy.name)
end

do
  local battle = newBattle()
  battle.enemy.mist = nil
  local msgs = TrainerAI.useItem(battle, "GUARD_SPEC")
  T.eq(#msgs, 1, "GUARD SPEC prints exactly one message")
  T.eq(msgs[1], usedLine(battle, "GUARD_SPEC"), "GUARD SPEC prints only the used line")
  T.eq(battle.enemy.mist, true, "GUARD SPEC sets the enemy Mist bit")
end

for _, item in ipairs({ "FULL_HEAL", "POTION", "SUPER_POTION", "HYPER_POTION", "FULL_RESTORE" }) do
  local battle = newBattle()
  local msgs = TrainerAI.useItem(battle, item)
  T.eq(#msgs, 1, item .. " prints exactly one message")
  T.eq(msgs[1], usedLine(battle, item), item .. " prints only the used line")
end

for _, item in ipairs({ "X_ATTACK", "X_DEFEND", "X_SPEED", "X_SPECIAL" }) do
  local battle = newBattle()
  local msgs = TrainerAI.useItem(battle, item)
  T.eq(#msgs, 3, item .. " yields used line, anim, rose line")
  T.eq(msgs[1], usedLine(battle, item), item .. " used line first")
  T.eq(type(msgs[2]) == "table" and msgs[2].anim, "XSTATITEM_DUPLICATE_ANIM", item .. " plays the stat anim")
  T.check(type(msgs[3]) == "string" and msgs[3]:find("rose!", 1, true) ~= nil, item .. " prints the rose line")
end

do
  local battle = newBattle()
  battle.enemy.stages.attack = 6
  local msgs = TrainerAI.useItem(battle, "X_ATTACK")
  local s = strings(msgs)
  T.eq(#msgs, 2, "X ATTACK at +6 prints used line and one more, no anim")
  T.eq(s[2], romText(Data, "_NothingHappenedText", "Nothing happened!"), "X ATTACK at +6 prints Nothing happened")
  T.eq(battle.enemy.stages.attack, 6, "X ATTACK at +6 leaves the stage at +6")
end

T.finish("battle_ai_item_messages_2589")
