local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

return function(game)
  local fails = 0
  local function check(cond, label)
    if cond then
      print("PASS " .. label)
    else
      fails = fails + 1
      print("FAIL " .. label)
    end
    return cond
  end
  local function finish()
    if fails == 0 then
      print("PASS u8 learn move four-move paths")
      love.event.quit(0)
    else
      print("FAIL u8 learn move four-move paths")
      love.event.quit(1)
    end
  end

  U.wait(30)
  local Schema = require("src.core.game3.save_schema_firered")
  local Party = require("src.core.game3.party")
  local Experience = require("src.core.game3.battle.experience")
  local SummaryData = require("src.core.game3.summary_data")
  local Runtime = require("src.core.game3.runtime")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local LearnMove = require("src.core.game3.battle.learn_move")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")

  local session = Schema.newGame({ name = "RED", rivalName = "BLUE", gender = 0 })

  local function fresh_charmander()
    session.party = {}
    Party.giveMon(session, 4, 6)
    local mon = session.party[1]
    Experience.syncExpToLevel(mon)
    mon.exp = SummaryData.expForLevel(Experience.growthRate(mon), 7) - 3
    mon.moves = { 10, 45, 33, 39 }
    mon.pp = { 35, 40, 35, 30 }
    mon.maxPp = { 35, 40, 35, 30 }
    return mon
  end

  local function page()
    return (Message.isOpen() and Message.currentPage and Message.currentPage()) or ""
  end
  local function anyLine(needle)
    for _, t in ipairs(Ui.log() or {}) do
      if t:find(needle, 1, true) then return true end
    end
    return false
  end
  local function advanceUntil(pred, limit)
    for f = 1, limit do
      U.wait(1)
      if pred() then return true end
      if f % 6 == 0 and not Choice.active and not Message._stay then U.tap(game, "a") end
    end
    return false
  end
  local function promptUp(needle)
    return function()
      return Choice.active and Choice.kind == "yesno" and Message.isWaiting()
        and page():find(needle, 1, true) ~= nil
    end
  end
  local function start_wild()
    return BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 3 }, { fade = false })
  end

  fresh_charmander()
  session.map = "FR_ROUTE_1"
  session.x = 10
  session.y = 20
  session.flags = session.flags or {}
  game:_enterField(session, "new_game")
  U.wait(90)

  check(start_wild(), "u8 stop-path battle started")
  if not check(advanceUntil(promptUp("Should a move be deleted"), 6000), "u8 delete prompt shows with YES/NO") then
    U.shot(game, DIR .. "/u8_98_softlock_before_delete_prompt.png")
    return finish()
  end
  check(anyLine("wants to learn") and anyLine("four moves"), "u8 wants-to-learn and four-moves lines shown first")
  U.wait(20)
  U.shot(game, DIR .. "/u8_01_delete_prompt_yesno.png")
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "a")
  if not check(advanceUntil(promptUp("Stop trying"), 600), "u8 NO opens stop-trying prompt") then
    return finish()
  end
  U.wait(20)
  U.shot(game, DIR .. "/u8_02_stop_trying_prompt.png")
  U.tap(game, "a")
  local sawDidNot = advanceUntil(function()
    return Message.isWaiting() and page():find("did not learn", 1, true) ~= nil
  end, 600)
  if check(sawDidNot, "u8 YES to stop prints did-not-learn") then
    U.wait(10)
    U.shot(game, DIR .. "/u8_03_did_not_learn.png")
  end
  check(advanceUntil(function() return not Battle.isActive() end, 3000), "u8 stop-path battle ended")
  local m1 = session.party[1]
  check(m1 and table.concat(m1.moves, ",") == "10,45,33,39" and m1.level == 7, "u8 stop path kept moves at LV. 7")
  check(not LearnMove.busy(), "u8 LearnMove idle after stop path")
  U.wait(60)

  fresh_charmander()
  check(start_wild(), "u8 forget-path battle started")
  if not check(advanceUntil(promptUp("Should a move be deleted"), 6000), "u8 forget path reaches delete prompt") then
    return finish()
  end
  U.wait(10)
  U.tap(game, "a")
  if not check(advanceUntil(function() return Choice.active and Choice.kind == "multi" end, 600), "u8 YES opens forget list") then
    return finish()
  end
  U.wait(20)
  U.shot(game, DIR .. "/u8_04_forget_list.png")
  U.tap(game, "a")
  local sawLearned = advanceUntil(function()
    return Message.isWaiting() and page():find("learned", 1, true) ~= nil and anyLine("Poof")
  end, 900)
  if check(sawLearned, "u8 Poof chain reaches learned EMBER") then
    check(anyLine("forgot how to"), "u8 forgot-how-to line shown")
    U.wait(10)
    U.shot(game, DIR .. "/u8_05_learned_ember.png")
  end
  check(advanceUntil(function() return not Battle.isActive() end, 3000), "u8 forget-path battle ended")
  local m2 = session.party[1]
  check(m2 and m2.moves[1] == 52 and m2.level == 7, "u8 EMBER replaced SCRATCH at LV. 7")
  U.wait(60)
  U.shot(game, DIR .. "/u8_06_back_on_route1.png")
  finish()
end
