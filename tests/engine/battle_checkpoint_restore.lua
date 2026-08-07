-- A battle checkpoint reconstructs a new controller from data, rather than
-- retaining the original table/closure, and restores gameplay RNG exactly.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("battle checkpoint restore")
local Fixtures = require("tests.modkit").fixtures
local BattleState = require("src.battle.BattleState")
local Checkpoint = require("src.core.Checkpoint")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")

local Data = Fixtures.fresh()
local oldRandom = love.math.random
local oldGet, oldSet = love.math.getRandomState, love.math.setRandomState
local rng = 12345
love.math.getRandomState = function() return tostring(rng) end
love.math.setRandomState = function(state) rng = assert(tonumber(state)) end
love.math.random = function(a, b)
  rng = (rng * 1103515245 + 12345) % 2147483648
  local unit = rng / 2147483648
  if a == nil then return unit end
  if b == nil then return math.floor(unit * a) + 1 end
  return a + math.floor(unit * (b - a + 1))
end

local function makeGame(kind)
  local save = SaveData.newGame()
  save.meta.playthroughId = "battle-playthrough"
  save.player.map, save.player.x, save.player.y = "FIX_TOWN", 2, 3
  save.player.facing, save.player.surfing = "left", false
  save.party = {
    Pokemon.new(Data, "FIXMON_A", 20),
    Pokemon.new(Data, "FIXMON_C", 15),
  }
  -- Strip new-game defaults that are intentionally absent from the tiny
  -- fixture registry, then place the sanitized save on a fixture map.
  SaveData.validate(save, Data)
  save.player.map, save.player.x, save.player.y = "FIX_TOWN", 2, 3
  save.player.facing, save.player.surfing = "left", false
  local stack = setmetatable({ states = {} }, { __index = StateStack })
  local overworld = {
    map = { id = "FIX_TOWN" },
    player = { cellX = 2, cellY = 3, facing = "left", surfing = false },
    runner = { isRunning = function() return false end },
    parallelRunners = {}, pendingScripts = {}, parallelQueue = {}, scriptMoves = {},
  }
  function overworld:captureSave(target)
    target.player.map = self.map.id
    target.player.x, target.player.y = self.player.cellX, self.player.cellY
    target.player.facing = self.player.facing
    target.player.surfing = self.player.surfing and true or false
  end
  function overworld:restoreBattleContinuation(battle, origin)
    battle.onFinish = function(result)
      self.lastRestoredFinish = { result = result, origin = origin.kind }
    end
    return true
  end
  local game = { data = Data, save = save, stack = stack, overworld = overworld }
  function game:restoreCheckpointSave(loaded)
    self.save = loaded
    self.overworld.map = { id = loaded.player.map }
    self.overworld.player = {
      cellX = loaded.player.x, cellY = loaded.player.y,
      facing = loaded.player.facing,
      surfing = loaded.player.surfing and true or false,
    }
    self.overworld.runner = { isRunning = function() return false end }
    self.overworld.parallelRunners, self.overworld.pendingScripts = {}, {}
    self.overworld.parallelQueue, self.overworld.scriptMoves = {}, {}
    self.stack.states = { self.overworld }
  end
  function game:restoreCheckpointBattle(battle)
    self.stack.states[#self.stack.states + 1] = battle
  end
  stack.states[1] = overworld
  local battle
  if kind == "trainer" then
    battle = BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
    battle.checkpointOrigin = {
      kind = "trainer_encounter", map = "FIX_TOWN", npc = "TRAINER_1",
      event = "EVENT_BEAT_TRAINER_1",
    }
  else
    battle = BattleState.newWild(game, "FIXMON_B", 12)
    battle.checkpointOrigin = { kind = "wild_encounter", map = "FIX_TOWN" }
  end
  battle.phase, battle.queue = "menu", {}
  battle.onFinish = function() end
  stack.states[2] = battle
  return game, battle
end

local function settleOverworld(game)
  game.stack.states = { game.overworld }
  game.save.money = 999999
  game.save.party[1].hp = 1
  game.overworld.player.cellX = 8
  game.overworld.player.facing = "up"
end

local game, originalBattle = makeGame("wild")
originalBattle.turnCount = 4
originalBattle.runAttempts = 1
originalBattle.player.stages.speed = 3
originalBattle.enemy.mon.hp = originalBattle.enemy.mon.hp - 5
originalBattle.enemy.shownHP = originalBattle.enemy.mon.hp
originalBattle.enemy.disabledSlot = 1
originalBattle.enemy.disabledTurns = 2
originalBattle.participants = { [game.save.party[1]] = true }
local checkpoint = assert(Checkpoint.capture(game))
local expectedNext = love.math.random(1, 1000000)

settleOverworld(game)
rng = 777
local restored, code, message = Checkpoint.restore(game, checkpoint)
T.check(restored == true, "battle checkpoint restores: " .. tostring(message or code))
local rebuilt = restored and game.stack:top()
if restored then
  T.check(rebuilt ~= originalBattle, "restore creates a new battle controller")
  T.eq(getmetatable(rebuilt), BattleState, "restored stack top is a BattleState")
  T.eq(rebuilt.phase, "menu", "restored battle resumes at the decision menu")
  T.eq(#rebuilt.queue, 0, "restored battle has no stale action queue")
  T.eq(rebuilt.turnCount, 4, "turn count roundtrips")
  T.eq(rebuilt.runAttempts, 1, "escape state roundtrips")
  T.eq(rebuilt.player.stages.speed, 3, "player stages roundtrip")
  T.eq(rebuilt.enemy.disabledSlot, 1, "enemy volatile state roundtrips")
  T.eq(rebuilt.enemy.disabledTurns, 2, "enemy volatile duration roundtrips")
  T.eq(rebuilt.enemy.mon.hp, checkpoint.runtime.battle.enemyMon.hp,
    "enemy Pokemon model roundtrips")
  T.eq(game.save.money, checkpoint.save.money, "persistent progress roundtrips")
  T.eq(game.save.party[1].hp, checkpoint.save.party[1].hp,
    "party model roundtrips")
  T.same(Checkpoint.capture(game), checkpoint,
    "capture A, discard, restore A, capture A2 yields normalized A == A2")
  T.eq(love.math.random(1, 1000000), expectedNext,
    "the exact next gameplay RNG result repeats after reload")
  rebuilt.onFinish("run")
  T.same(game.overworld.lastRestoredFinish,
    { result = "run", origin = "wild_encounter" },
    "restored battle receives a reconstructed semantic continuation")
end

local trainerGame, trainerOriginal = makeGame("trainer")
trainerOriginal.turnCount = 6
trainerOriginal.enemy.mon.hp = trainerOriginal.enemy.mon.hp - 3
trainerOriginal.enemy.shownHP = trainerOriginal.enemy.mon.hp
trainerOriginal.aiUses = 1
trainerOriginal.participants = { [trainerGame.save.party[1]] = true,
                                 [trainerGame.save.party[2]] = true }
local trainerCheckpoint = assert(Checkpoint.capture(trainerGame))
settleOverworld(trainerGame)
restored, code, message = Checkpoint.restore(trainerGame, trainerCheckpoint)
T.check(restored == true, "trainer checkpoint restores: " .. tostring(message or code))
local trainerRebuilt = trainerGame.stack:top()
if restored then
  T.check(trainerRebuilt ~= trainerOriginal,
    "trainer restore is independent of the original controller")
  T.eq(trainerRebuilt.oppClass, "OPP_FIX_YOUNGSTER", "trainer class roundtrips")
  T.eq(trainerRebuilt.enemyIndex, 1, "enemy roster index roundtrips")
  T.eq(trainerRebuilt.aiUses, 1, "trainer AI item budget roundtrips")
  T.same(Checkpoint.capture(trainerGame), trainerCheckpoint,
    "trainer differential recapture is exact")
end

love.math.random = oldRandom
love.math.getRandomState, love.math.setRandomState = oldGet, oldSet
T.finish()
