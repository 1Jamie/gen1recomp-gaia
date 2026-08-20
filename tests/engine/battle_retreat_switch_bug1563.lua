-- SwitchPlayerMon (core.asm:2419-2423), AnimateRetreatingPlayerMon (:1769-1796)
-- (#1563); pokeyellow core.asm:1862-1866 (#1545); core.asm:1471-1488 (#1608)
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local function newBattle()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 40), Pokemon.new(Data, "FIXMON_A", 40) }
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 40)
  battle.rng = function(a) if a then return a end return 0 end
  return battle
end

-- ---------------------------------------------------------------------
-- the shrink stages and their frame budget
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.queue, battle.nextInsert = {}, 0
  battle:queueRetreatAnim()
  T.eq(#battle.queue, 2, "the retreat queues its start act plus the hold")
  T.eq(battle.queue[2].wait, 7, "4 frames at 5x5 then Delay3 at 3x3")
  T.check(battle:shrinkOutScale(battle.player) == nil, "nothing shrinks yet")
  battle.queue[1].fn()
  T.eq(battle.shrinkOut.battler, battle.player, "the outgoing pic is the one drawn")
  T.eq(battle:shrinkOutScale(battle.player), 5 / 7, "wDownscaledMonSize 0 -> 5x5")
  battle.shrinkOut.frame = 3
  T.eq(battle:shrinkOutScale(battle.player), 5 / 7, "for four frames")
  battle.shrinkOut.frame = 4
  T.eq(battle:shrinkOutScale(battle.player), 3 / 7, "wDownscaledMonSize 1 -> 3x3")
  battle.shrinkOut.frame = 6
  T.eq(battle:shrinkOutScale(battle.player), 3 / 7, "through Delay3")
  T.check(battle:shrinkOutScale(battle.enemy) == nil,
    "AnimateRetreatingPlayerMon is player-side only")
end

-- ---------------------------------------------------------------------
-- the Yellow starter slides off instead of shrinking
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.starterPikachuSendOut = function() return true end
  battle.queue, battle.nextInsert = {}, 0
  battle:queueRetreatAnim()
  T.eq(#battle.queue, 3, "start act, the slide's hold, then the slot clear")
  battle.queue[1].fn()
  local slide = battle.picOff and battle.picOff.playerMon
  T.check(slide ~= nil, "the back pic slot is sliding")
  T.eq(slide.to, -64, "8 tiles off the left edge")
  T.eq(slide.hold, 3, "wSlideMonDelay 3 V-blanks per tile")
  T.eq(battle.queue[2].wait, 24, "8 tiles x 3 frames")
  T.check(battle:shrinkOutScale(battle.player) == nil, "and no downscale stage")
  battle.queue[3].fn()
  T.check((battle.picOff or {}).playerMon == nil, "the slot clears afterwards")
end

-- ---------------------------------------------------------------------
-- resolveSwitch runs the retreat between the withdraw text and the swap
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.queue, battle.nextInsert = {}, 0
  local outgoing = battle.player.mon
  battle:resolveSwitch(battle.game.save.party[2])
  local withdraw = table.remove(battle.queue, 1)
  battle.nextInsert = 0
  withdraw.fn()
  T.check(battle.queue[1] and battle.queue[1].text ~= nil, "RetreatMon text first")
  T.check(battle.queue[2] and battle.queue[2].fn ~= nil, "then the retreat start")
  T.eq(battle.queue[3] and battle.queue[3].wait, 7, "then its hold")
  T.eq(battle.player.mon, outgoing, "the party slot has not been swapped yet")
end

-- ---------------------------------------------------------------------
-- a fainted pick reopens the party list (#1608)
-- ---------------------------------------------------------------------
do
  local battle = newBattle()
  battle.queue, battle.nextInsert = {}, 0
  battle.buildScreen = function(_, _, opts) return opts end
  battle:openParty()
  local opts = battle.queue[1].ui()
  battle.queue, battle.nextInsert = {}, 0
  battle.game.save.party[2].hp = 0
  opts.onSwitch(battle.game.save.party[2])
  T.check(battle.queue[1] and battle.queue[1].text
          and battle.queue[1].text:find("no will", 1, true) ~= nil,
    "HasMonFainted prints NoWillText")
  T.check(battle.queue[2] and battle.queue[2].fn ~= nil, "and queues the reprompt")
  battle.queue[2].fn()
  T.check(battle.queue[3] and battle.queue[3].ui ~= nil,
    "GoBackToPartyMenu puts the list back up")

  battle.queue, battle.nextInsert = {}, 0
  opts.onSwitch(battle.player.mon)
  T.check(battle.queue[1] and battle.queue[1].text
          and battle.queue[1].text:find("already out", 1, true) ~= nil,
    "AlreadyOutText for the mon that is already out")
  T.check(battle.queue[2] and battle.queue[2].fn ~= nil, "which also reprompts")
end

T.finish("retreat animation and switch reprompt (#1563, #1545, #1608)")
