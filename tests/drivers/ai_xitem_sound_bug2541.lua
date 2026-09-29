-- engine/battle/trainer_ai.asm:459,690-725
--   tools/run_driver.sh red <identity> tests/drivers/ai_xitem_sound_bug2541.lua /tmp/shots2541
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots2541"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local Sound = require("src.core.Sound")

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

  game.save.options.animations = false
  game.save.party = { Pokemon.new(game.data, "PIDGEY", 5) }
  U.teleport(game, "CERULEAN_GYM", 5, 5, "up")
  U.wait(10)
  local ow = game.overworld
  check("the overworld is up", ow ~= nil)

  local battle = BattleState.newTrainer(game, "OPP_MISTY", 1)
  battle.onFinish = function() end
  if ow then ow:pushBattle(battle) end
  for _ = 1, 900 do
    if game.stack:top() == battle and (battle.introSlide or 0) == 0 then break end
    U.wait(1)
  end
  check("the trainer battle reached the screen", game.stack:top() == battle)
  check("battle animations are off", battle:animationsOn() == false)

  local played = {}
  local realPlay = Sound.play
  Sound.play = function(data, name, ...)
    played[#played + 1] = name
    return realPlay(data, name, ...)
  end
  battle.aiUses = 1
  battle.trainerAIAction = function(self)
    self.trainerAIAction = nil
    return { special = "aiItem", item = "X_DEFEND" }
  end

  local rose = false
  for _ = 1, 1500 do
    local cur = battle.current
    if cur and cur.text and cur.text:find("rose", 1, true) then
      rose = true
      break
    end
    U.tap(game, "a")
    U.wait(3)
  end
  check("the X DEFEND rose page came up", rose)
  for _ = 1, 200 do
    if battle.charIndex and battle.total and battle.charIndex >= battle.total then break end
    U.wait(1)
  end
  U.still(game, DIR .. "/2541_1_x_defend_rose_page.png")
  check("the enemy DEFENSE stage is +1", (battle.enemy.stages.defense or 0) == 1)
  local heal = false
  for _, n in ipairs(played) do
    if n == "Heal_Ailment" then heal = true end
  end
  check("Heal_Ailment never played for X DEFEND", not heal)

  Sound.play = realPlay
  finish()
end
