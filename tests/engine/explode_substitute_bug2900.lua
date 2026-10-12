-- engine/battle/effects.asm:175
-- engine/battle/core.asm:4899
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Font = require("src.render.Font")
Font.load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

Data.moves.FIX_EXPLODE = {
  id = "FIX_EXPLODE", index = 96, name = "FIX EXPLODE",
  type = "NORMAL", power = 170, accuracy = 100, pp = 5,
  effect = "EXPLODE_EFFECT",
}

local function mkseq(vals)
  local i = 0
  return function(_, hi)
    i = i + 1
    return vals[i] ~= nil and vals[i] or hi
  end
end

local function newBattle()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 40)
  battle.rng = mkseq({ 0, 255, 255 })
  return battle
end

do
  local battle = newBattle()
  battle.enemy.substituteHP = 1
  local eStart = battle.enemy.mon.hp
  battle:performMove(battle.player, battle.enemy, { id = "FIX_EXPLODE", pp = 5 })
  T.eq(battle.enemy.substituteHP, nil, "the explosion breaks the substitute")
  T.eq(battle.enemy.mon.hp, eStart, "the target behind it takes nothing")
  T.check(battle.player.mon.hp > 0, "the user survives breaking the substitute")
  T.check(not battle.player.faintQueued, "and no faint is queued for it")
end

do
  local battle = newBattle()
  battle.enemy.substituteHP = 999
  battle:performMove(battle.player, battle.enemy, { id = "FIX_EXPLODE", pp = 5 })
  T.check(battle.enemy.substituteHP ~= nil, "a substitute that holds stays up")
  T.eq(battle.player.mon.hp, 0, "and the user still faints")
end

do
  local battle = newBattle()
  battle:performMove(battle.player, battle.enemy, { id = "FIX_EXPLODE", pp = 5 })
  T.eq(battle.player.mon.hp, 0, "no substitute: the user faints")
end

Data.moves.FIX_EXPLODE = nil
T.finish("explosion breaking a substitute spares the user (#2900)")
