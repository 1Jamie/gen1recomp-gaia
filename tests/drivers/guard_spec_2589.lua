-- engine/battle/trainer_ai.asm:645
--   tools/run_driver.sh blue <identity> tests/drivers/guard_spec_2589.lua <shotdir>
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots2589"
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

  game.save.options.animations = false
  game.save.party = { Pokemon.new(game.data, "PIDGEY", 50) }
  U.teleport(game, "VIRIDIAN_GYM", 16, 8, "up")
  U.wait(10)
  local ow = game.overworld
  check("the overworld is up", ow ~= nil)

  local battle = BattleState.newTrainer(game, "OPP_GIOVANNI", 1)
  battle.onFinish = function() end
  if ow then ow:pushBattle(battle) end
  for _ = 1, 900 do
    if game.stack:top() == battle and (battle.introSlide or 0) == 0 then break end
    U.wait(1)
  end
  check("the trainer battle reached the screen", game.stack:top() == battle)

  battle.aiUses = 1
  battle.trainerAIAction = function(self)
    self.trainerAIAction = nil
    return { special = "aiItem", item = "GUARD_SPEC" }
  end

  local texts = {}
  local last
  local guardIdx
  local shot = false
  for _ = 1, 3000 do
    local cur = battle.current
    local t = cur and cur.text
    if t and t ~= last then
      texts[#texts + 1] = t
      last = t
      print("TEXT " .. t:gsub("\n", " "))
      if not guardIdx and t:find("GUARD", 1, true) then guardIdx = #texts end
    end
    if guardIdx and not shot and t == texts[guardIdx] then
      for _ = 1, 200 do
        if battle.charIndex and battle.total and battle.charIndex >= battle.total then break end
        U.wait(1)
      end
      U.still(game, DIR .. "/2589_01_giovanni_used_guard_spec.png")
      shot = true
    end
    if guardIdx and #texts >= guardIdx + 1 then break end
    U.tap(game, "a")
    U.wait(3)
  end

  check("the used GUARD SPEC line came up", guardIdx ~= nil)
  check("the used line names GIOVANNI", guardIdx ~= nil and texts[guardIdx]:find("GIOVANNI", 1, true) ~= nil)
  check("the enemy Mist bit is set", battle.enemy.mist == true)
  local nextText = guardIdx and texts[guardIdx + 1]
  check("a next battle line followed", nextText ~= nil)
  check("no protected against stat changes line after it",
    nextText ~= nil and not nextText:find("protected", 1, true) and not nextText:find("stat changes", 1, true))
  check("the battle proceeds to a move line", nextText ~= nil and nextText:find("used", 1, true) ~= nil)

  finish()
end
