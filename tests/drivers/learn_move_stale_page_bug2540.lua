-- engine/pokemon/learn_move.asm:87-95, engine/battle/experience.asm:242-256
--   tools/run_driver.sh red <identity> tests/drivers/learn_move_stale_page_bug2540.lua /tmp/shots2540
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots2540"
  local Pokemon = require("src.pokemon.Pokemon")
  local Growth = require("src.pokemon.Growth")
  local BattleState = require("src.battle.BattleState")
  local Font = require("src.render.Font")

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
  local function codes(text)
    local out = {}
    for chunk in (text .. "\n"):gmatch("([^\n\v]*)[\n\v]") do
      out[#out + 1] = table.concat(Font.encode(chunk), ",")
    end
    return out
  end

  local mon = Pokemon.new(game.data, "BULBASAUR", 19)
  mon.moves = {
    { id = "TACKLE", pp = 35 }, { id = "GROWL", pp = 40 },
    { id = "LEECH_SEED", pp = 10 }, { id = "VINE_WHIP", pp = 10 },
  }
  local rate = game.data.pokemon.BULBASAUR.growthRate
  mon.exp = Growth.expForLevel(rate, 20, game.data.growth_rates) - 1
  game.save.party = { mon }
  U.teleport(game, "ROUTE_3", 13, 6, "left")
  U.wait(10)
  local ow = game.overworld
  check("the overworld is up", ow ~= nil)

  local battle = BattleState.newTrainer(game, "OPP_SWIMMER", 1)
  battle.onFinish = function() end
  if ow then ow:pushBattle(battle) end
  for _ = 1, 1200 do
    if game.stack:top() == battle and (battle.introSlide or 0) == 0 then break end
    U.tap(game, "a")
    U.wait(2)
  end
  check("the trainer battle reached the screen", game.stack:top() == battle)
  battle.enemy.mon.hp = 1
  check("the trainer has a second mon", #battle.enemyParty >= 2)

  local seenLearn, checked = false, false
  for i = 1, 6000 do
    local top = game.stack:top()
    if top ~= battle then
      if top and top.newMoveId then seenLearn = true end
      if i % 4 == 0 then U.tap(game, "a") end
    elseif seenLearn and battle.current == nil and (battle.waitFrames or 0) > 0
        and not checked then
      checked = true
      local name = mon.nickname or game.data.pokemon.BULBASAUR.name
      local mdef = game.data.moves.POISONPOWDER
      local shown = {}
      for j, line in ipairs(battle.shown or {}) do shown[j] = table.concat(line, ",") end
      local grew = codes(name .. " grew\nto level 20!")
      check("the held page is not the grew-to-level page",
            not (shown[1] == grew[1] and shown[2] == grew[2]))
      local learned = codes(name .. " learned\n" .. mdef.name .. "!")
      check("the held page is the learned page",
            shown[1] == learned[1] and shown[2] == learned[2])
      U.still(game, DIR .. "/2540_1_learned_page_held_over_ball_row.png")
      break
    elseif battle.current or battle.phase ~= "messages" then
      if i % 4 == 0 then U.tap(game, "a") end
    end
    U.wait(1)
  end
  check("the forget-a-move flow ran", seenLearn)
  check("the held-page moment was reached", checked)
  finish()
end
