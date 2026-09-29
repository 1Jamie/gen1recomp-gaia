-- engine/battle/core.asm:1052
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local function isChoice(top, battle)
    return top ~= battle and top ~= nil and top.index ~= nil and top.onChoose ~= nil
  end

  local lead = Pokemon.new(game.data, "CATERPIE", 3)
  lead.hp = 1
  game.save.party = { lead, Pokemon.new(game.data, "SQUIRTLE", 10) }
  U.teleport(game, "ROUTE_1", 5, 5, "down")

  local battle = BattleState.newWild(game, "RATTATA", 50)
  battle.onFinish = function() end
  game.overworld:pushBattle(battle)

  for _ = 1, 200 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(4)
  end
  U.tap(game, "a"); U.wait(8)
  U.tap(game, "a"); U.wait(8)

  local sawPrompt = false
  local up = false
  for _ = 1, 900 do
    local top = game.stack:top()
    local cur = battle.current
    local txt = cur and cur.text and tostring(cur.text) or ""
    if isChoice(top, battle) then up = true break end
    if top ~= battle then break end
    if txt:find("Use next") then
      sawPrompt = true
    else
      U.tap(game, "a")
    end
    U.wait(2)
  end
  U.log("use-next page seen:", sawPrompt)

  local top = game.stack:top()
  if not up then
    for _ = 1, 120 do
      U.wait(1)
      if isChoice(game.stack:top(), battle) then up = true break end
    end
  end
  U.log("PASS_USE_NEXT_YESNO_WITHOUT_A", up and sawPrompt)
  local boxOk = false
  if up then
    top = game.stack:top()
    boxOk = top.tx == 13 and top.ty == 9
    U.log("PASS_USE_NEXT_BOX_13_9", boxOk)
    U.wait(20)
    U.still(game, DIR .. "/2554_01_use_next_yesno_auto.png")
  end
  local ok = up and sawPrompt and boxOk
  U.log(ok and "RESULT PASS" or "RESULT FAIL")
  love.event.quit(ok and 0 or 1)
end
