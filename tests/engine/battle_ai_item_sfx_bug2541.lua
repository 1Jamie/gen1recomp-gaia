package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)

local BattleState = require("src.battle.BattleState")
local TrainerAI = require("src.battle.TrainerAI")
local SaveData = require("src.core.SaveData")
local Sound = require("src.core.Sound")
local Pokemon = require("src.pokemon.Pokemon")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

for _, item in ipairs({ "FULL_HEAL", "GUARD_SPEC" }) do
  T.eq(TrainerAI.playsRestoringSfx(item), true, item .. " plays AIPlayRestoringSFX")
end
for _, item in ipairs({ "X_ATTACK", "X_DEFEND", "X_SPEED", "X_SPECIAL",
                        "POTION", "SUPER_POTION", "HYPER_POTION", "FULL_RESTORE" }) do
  T.eq(TrainerAI.playsRestoringSfx(item), false, item .. " is silent")
end

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

local function sfxFor(item)
  local battle = BattleState.newWild(newGame(), "FIXMON_C", 10)
  battle.trainer = { name = "MISTY" }
  battle.queue, battle.nextInsert = {}, 0
  battle.aiUses = 1
  local played = {}
  local orig = Sound.play
  Sound.play = function(_, name) played[#played + 1] = name end
  local ok, err = pcall(battle.executeAction, battle, battle.enemy, battle.player,
    { special = "aiItem", item = item })
  Sound.play = orig
  T.check(ok, "executeAction ran for " .. item .. " " .. tostring(err))
  return played
end

T.eq(#sfxFor("X_DEFEND"), 0, "X DEFEND plays no restoring SFX")
T.eq(#sfxFor("POTION"), 0, "POTION plays no restoring SFX")
T.eq(#sfxFor("FULL_RESTORE"), 0, "FULL RESTORE plays no restoring SFX")
local guard = sfxFor("GUARD_SPEC")
T.eq(guard[1], "Heal_Ailment", "GUARD SPEC plays Heal_Ailment")

T.finish("battle_ai_item_sfx_bug2541")
