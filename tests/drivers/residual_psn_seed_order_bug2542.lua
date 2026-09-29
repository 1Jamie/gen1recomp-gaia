-- engine/battle/core.asm:470-530
--   tools/run_driver.sh red <identity> tests/drivers/residual_psn_seed_order_bug2542.lua /tmp/shots2542
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots2542"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local failed = false
  local function check(label, ok)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
    return ok
  end
  local function finish()
    love.event.quit(failed and 1 or 0)
    while true do coroutine.yield() end
  end

  local mon = Pokemon.new(game.data, "BULBASAUR", 40)
  mon.hp = mon.stats.hp - 30
  mon.moves = { { id = "GROWL", pp = 40 } }
  game.save.party = { mon }
  U.teleport(game, "ROUTE_3", 13, 6, "left")
  U.wait(10)
  local ow = game.overworld
  check("the overworld is up", ow ~= nil)

  local battle = BattleState.newWild(game, "SNORLAX", 50)
  battle.onFinish = function() end
  if ow then ow:pushBattle(battle) end
  for _ = 1, 900 do
    if game.stack:top() == battle and (battle.introSlide or 0) == 0 then break end
    U.wait(1)
  end
  check("the wild battle reached the screen", game.stack:top() == battle)

  local enemy, player = battle.enemy, battle.player
  battle.enemyAction = function() return { id = "SPLASH", pp = 40 } end
  enemy.mon.status = "PSN"
  enemy.leechSeeded = true
  local startEnemy, startPlayer = enemy.mon.hp, player.mon.hp
  local tick = math.max(1, math.floor(enemy.mon.stats.hp / 16))

  local sawPoison, sawSeed = false, false
  local order = {}
  for i = 1, 4000 do
    local text = battle.current and battle.current.text
    if text and text:find("poison", 1, true) and not sawPoison then
      sawPoison = true
      order[#order + 1] = "poison"
      check("poison text shows before the bar moves", enemy.shownHP == startEnemy)
      check("only the status damage is in the model",
            enemy.mon.hp == startEnemy - tick)
      for _ = 1, 200 do
        if battle.charIndex and battle.total and battle.charIndex >= battle.total then break end
        U.wait(1)
      end
      U.wait(10)
      U.still(game, DIR .. "/2542_1_poison_text_bar_full.png")
    elseif text and text:find("LEECH SEED", 1, true) and not sawSeed then
      sawSeed = true
      order[#order + 1] = "seed"
      check("the seed text shows after both bars moved",
            enemy.shownHP == enemy.mon.hp and player.shownHP == player.mon.hp)
      check("the seed drain came off the poison total",
            enemy.mon.hp == startEnemy - 2 * tick)
      check("the seeder was healed", player.mon.hp == startPlayer + tick
            or player.mon.hp > startPlayer)
      for _ = 1, 200 do
        if battle.charIndex and battle.total and battle.charIndex >= battle.total then break end
        U.wait(1)
      end
      U.wait(10)
      U.still(game, DIR .. "/2542_2_seed_text_after_drain.png")
      break
    end
    if i % 5 == 0 then U.tap(game, "a") end
    U.wait(1)
  end
  check("the poison page appeared", sawPoison)
  check("the seed page appeared", sawSeed)
  check("poison came before the seed", order[1] == "poison" and order[2] == "seed")
  finish()
end
