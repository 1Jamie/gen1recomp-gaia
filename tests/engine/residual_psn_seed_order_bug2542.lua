package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local Status = require("src.battle.Status")
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local function newBattle(status)
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  local game = { data = Data, save = save,
               stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 30)
  battle.queue, battle.nextInsert = {}, 0
  battle.enemy.mon.status = status
  battle.enemy.leechSeeded = true
  battle.player.mon.hp = math.max(1, battle.player.mon.stats.hp - 20)
  return battle
end

local function walk(battle)
  local rows = {}
  for _ = 1, 100 do
    local item = table.remove(battle.queue, 1)
    if not item then break end
    if item.text then
      rows[#rows + 1] = { kind = "text", text = item.text }
    elseif item.anim then
      rows[#rows + 1] = { kind = "anim", anim = item.anim }
    elseif item.drain then
      rows[#rows + 1] = { kind = "drain", enemyHP = battle.enemy.mon.hp,
                          playerHP = battle.player.mon.hp }
    elseif item.wait then
      rows[#rows + 1] = { kind = "wait", frames = item.wait }
    elseif item.fn then
      battle.nextInsert = 0
      item.fn()
    end
  end
  return rows
end

for _, status in ipairs({ "PSN", "BRN" }) do
  local battle = newBattle(status)
  local enemy, player = battle.enemy, battle.player
  local startEnemy, startPlayer = enemy.mon.hp, player.mon.hp
  local tick = math.max(1, math.floor(enemy.mon.stats.hp / 16))
  battle:residualFor(enemy, player)
  local rows = walk(battle)

  local kinds = {}
  for _, r in ipairs(rows) do kinds[#kinds + 1] = r.kind end
  T.eq(table.concat(kinds, ","), "text,anim,drain,anim,drain,text",
    status .. " + seed: text, anim, bar, anim, bar, seed text")
  T.eq(rows[2].anim, "BURN_PSN_ANIM", status .. " tick animation first")
  T.eq(rows[4].anim, "ABSORB", "then the leech seed animation")
  T.check(rows[6].text:find("LEECH SEED", 1, true) ~= nil,
    "the seed text is printed after the seed bar moves")
  T.eq(rows[3].enemyHP, startEnemy - tick,
    "the first bar stops at the status damage only")
  T.eq(rows[3].playerHP, startPlayer, "the seeder is not healed yet")
  T.eq(rows[5].enemyHP, startEnemy - 2 * tick, "the seed drain lands second")
  T.eq(rows[5].playerHP, startPlayer + tick, "and heals the seeder")
end

do
  local battle = newBattle(nil)
  battle:residualFor(battle.enemy, battle.player)
  local kinds = {}
  for _, r in ipairs(walk(battle)) do kinds[#kinds + 1] = r.kind end
  T.eq(table.concat(kinds, ","), "anim,drain,text", "seed alone: anim, bar, text")
end

do
  local battle = newBattle("PSN")
  local msgs = Status.residual(battle.enemy, battle.player, battle)
  T.eq(#msgs, 2, "Status.residual still returns both halves flat")
end

do
  local battle = newBattle("PSN")
  battle.enemy.mon.hp = 1
  battle:residualFor(battle.enemy, battle.player)
  local rows = walk(battle)
  local last = rows[#rows]
  T.check(battle.enemy.mon.hp == 0, "poison faints the seeded mon")
  T.check(last ~= nil, "the queue carries the faint beats")
end

T.finish("residual_psn_seed_order_bug2542")
