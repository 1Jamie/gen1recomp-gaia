-- Parity test: trainer next-mon after an AI switch must skip fainted slots.
--
-- Agatha (and any switchChance / switch AI) can withdraw mon 1, send mon 2,
-- then later return to mon 1.  If mon 2 was KO'd in between, enemyMonFainted
-- used to do enemyIndex+1 and send the already-fainted Golbat back out.
-- The FIGHT menu reappears with an empty enemy HP bar; executeAction then
-- returns immediately on target.mon.hp <= 0 -- a softlock.
--
-- pokered's EnemySendOutFirstMon / AnyEnemyPokemonAliveCheck scan the party
-- for the first mon with HP remaining (core.asm), not "current index + 1".
--
-- Self-contained; run via `luajit tests/parity_ai_switch_faint.lua`.
-- Also picked up by tests/run_tests.lua's parity_* glob.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.pokemon and Data.pokemon.RATTATA) then Data:load() end
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
local S = require("tests.harness").suite("parity ai switch faint")
local check, eq = S.check, S.eq

-- Minimal game stub matching what BattleState.newTrainer / enemyMonFainted
-- touch.  SET style skips the SHIFT "change POKéMON?" ChoiceBox.
local function freshGame()
  return {
    data = Data,
    save = {
      party = { Pokemon.new(Data, "BULBASAUR", 50) },
      player = { name = "RED" },
      inventory = {},
      options = { battleStyle = "set" },
      pokedex = { seen = {}, owned = {} },
      flags = {},
      money = 0,
    },
    stack = { push = function() end, pop = function() end, top = function() end },
  }
end

-- Drain act/say rows until the enemy swap act runs (or the queue empties).
local function pumpUntilSwap(b, limit)
  limit = limit or 200
  local n = 0
  while #b.queue > 0 and n < limit do
    n = n + 1
    local item = table.remove(b.queue, 1)
    if item.fn then
      b.nextInsert = 0
      item.fn()
      -- the send-out act replaces self.enemy; stop once a living mon is in
      if b.enemy and b.enemy.mon and b.enemy.mon.hp > 0 then
        return true
      end
    end
  end
  return b.enemy and b.enemy.mon and b.enemy.mon.hp > 0
end

-- #143: after AI-switch reorder, do not send a fainted slot.
do
  local Game = freshGame()
  local b = BattleState.newTrainer(Game, "OPP_AGATHA", 1)
  check(#b.enemyParty >= 3, "Agatha has enough party slots for the scenario")

  -- Simulate: switched to slot 2, KO'd it, switched back to slot 1, KO slot 1.
  b.enemyParty[1].hp = 0
  b.enemyParty[2].hp = 0
  -- slots 3+ stay at full HP from construction
  b.enemyIndex = 1
  b.enemy.mon = b.enemyParty[1]
  b.participants = { [Game.save.party[1]] = true }

  b:enemyMonFainted()
  check(pumpUntilSwap(b), "a living reserve is sent out after the KO")
  eq(b.enemyIndex, 3, "next index is the first living mon, not fainted slot 2")
  check(b.enemy.mon.hp > 0, "sent-out mon has HP (no empty-bar softlock)")
  check(b.enemy.mon == b.enemyParty[3], "sent-out battler is party slot 3")
  check(b.result ~= "win", "battle continues while reserves remain")
end

-- Sequential KOs (no AI switch) still advance one slot at a time.
do
  local Game = freshGame()
  local b = BattleState.newTrainer(Game, "OPP_YOUNGSTER", 1)
  b.enemyParty[1].hp = 0
  b.enemyIndex = 1
  b.enemy.mon = b.enemyParty[1]
  b.participants = { [Game.save.party[1]] = true }
  b:enemyMonFainted()
  check(pumpUntilSwap(b), "youngster still sends the second mon")
  eq(b.enemyIndex, 2, "without AI switch, first living mon is still index 2")
  check(b.enemy.mon.hp > 0, "second mon is healthy")
end

-- No living reserves: victory even if enemyIndex is mid-party (AI left
-- earlier slots dead and the active one was not the last index).
do
  local Game = freshGame()
  local b = BattleState.newTrainer(Game, "OPP_AGATHA", 1)
  for _, mon in ipairs(b.enemyParty) do mon.hp = 0 end
  b.enemyIndex = 2
  b.enemy.mon = b.enemyParty[2]
  b.participants = { [Game.save.party[1]] = true }
  b:enemyMonFainted()
  eq(b.result, "win", "all-fainted party ends the trainer battle")
  eq(b.afterQueue, "finish", "victory finishes after the queue")
end

S.finish()
