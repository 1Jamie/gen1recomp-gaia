local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_first_battle"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end
  local function finish()
    print(string.format("[driver] em_first_battle: %d failure(s)", fails))
    love.event.quit(fails == 0 and 0 or 1)
    U.wait(10)
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "NICK", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local ExpSeq = require("src.core.game3.battle.exp_seq")
  local BattleTransition = require("src.core.game3.battle_transition")
  local Audio = require("src.core.game3.audio")
  local Map = require("src.core.game3.map")
  local Field = require("src.core.game3.field")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  result(session ~= nil, "field session exists")
  if not session then return finish() end

  local ok, err = pcall(function() Map.load(nil, game, "EM_ROUTE101", { x = 7, y = 13, facing = "down" }) end)
  result(ok, "Route 101 loads " .. tostring(err or ""))
  U.wait(40)

  session.party = {}
  -- pokeemerald/src/battle_setup.c:923
  Party.giveMon(session, C.species.byName.SPECIES_TREECKO, 5, "TREECKO")
  local mon = session.party[1]
  result(mon ~= nil and mon.level == 5, "starter Treecko lv5 in the party")
  if not mon then return finish() end
  local exp0 = tonumber(mon.exp) or 0
  local moveNames = {}
  for i, m in ipairs(mon.moves or {}) do moveNames[i] = C:name("moves", m, "MOVE_") or tostring(m) end
  print("[driver] starter moves " .. table.concat(moveNames, ","))

  local outcome
  local started, serr = BattleBridge.startFirstBattle(Runtime._mod, game, {
    done = function(r) outcome = r end,
  })
  result(started == true, "first battle started " .. tostring(serr or ""))
  if not started then return finish() end
  local tid = BattleTransition._transitionId
  result(tid == C.battle.byName.B_TRANSITION_BLUR, "transition is B_TRANSITION_BLUR (" .. tostring(tid) .. ")")
  local song = Audio._currentSong and Audio._currentSong.id
  result(song == C.songs.byName.MUS_VS_WILD, "battle music MUS_VS_WILD (" .. tostring(song) .. ")")

  for _ = 1, 3000 do
    if Battle.isActive() then break end
    U.wait(1)
  end
  result(Battle.isActive(), "battle active after the transition")
  local st = Battle.getState()
  if not st then return finish() end
  local foe = st.enemy and st.enemy.mon
  result(foe and foe.species == C.species.byName.SPECIES_ZIGZAGOON and foe.level == 2, "foe is Zigzagoon lv2")
  result(st.wild and st.kinds and st.kinds.firstBattle == "birch", "battle kind firstBattle=birch")
  result(st.aiFlags == 0x80000000, "AI flags AI_SCRIPT_FIRST_BATTLE (" .. string.format("0x%X", st.aiFlags or 0) .. ")")
  result(not st.firstBattle, "Oak first-battle path stays off")

  local lastTap, f = 0, 0
  local function pump_text()
    f = f + 1
    if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
      lastTap = f
      U.tap(game, "a")
      return true
    end
    return false
  end
  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end
  local function wait_command(limit)
    for _ = 1, limit or 6000 do
      if at_command() or not Battle.isActive() then break end
      if not pump_text() then U.wait(1) end
    end
    return at_command()
  end
  local function logged(pattern)
    for _, t in ipairs(Ui.log()) do
      if type(t) == "string" and t:find(pattern) then return true end
    end
    return false
  end

  local introShot = false
  for _ = 1, 600 do
    if Ui.dialogPending and Ui.dialogPending() then
      U.wait(20)
      introShot = U.still(game, DIR .. "/01_intro_wild_zigzagoon.png")
      break
    end
    U.wait(1)
  end
  result(introShot, "intro shot")
  result(logged("ZIGZAGOON"), "intro text names Wild ZIGZAGOON")

  result(wait_command(), "reached the action menu")
  U.wait(20)
  result(U.still(game, DIR .. "/02_action_menu.png"), "action menu shot")

  U.tap(game, "right")
  U.wait(4)
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "a")
  U.wait(30)
  result(logged("Don't leave me"), "RUN is refused with STRINGID_DONTLEAVEBIRCH")
  result(U.still(game, DIR .. "/03_dont_leave_birch.png"), "run refused shot")
  result(wait_command(), "back at the action menu")
  U.tap(game, "up")
  U.wait(4)
  U.tap(game, "left")
  U.wait(4)

  local moveShot, faintShot, expShot = false, false, false
  local turns = 0
  local expSeen = false
  for _ = 1, 20 do
    if not Battle.isActive() then break end
    if not wait_command() then break end
    turns = turns + 1
    U.tap(game, "a")
    U.wait(20)
    if not moveShot and Ui._mode == "moves" then
      moveShot = U.still(game, DIR .. "/04_move_select.png")
    end
    U.tap(game, "a")
    for _ = 1, 4000 do
      if at_command() or not Battle.isActive() then break end
      local e = Battle.getState() and Battle.getState().enemy
      if not faintShot and e and e.mon and (tonumber(e.mon.hp) or 1) <= 0 then
        U.wait(24)
        faintShot = U.still(game, DIR .. "/05_zigzagoon_faints.png")
      end
      if not expShot and ExpSeq.busy() then
        expSeen = true
        U.wait(30)
        expShot = U.still(game, DIR .. "/06_exp_gain.png")
      end
      if Battle._phase == "awarding" then expSeen = true end
      if not pump_text() then U.wait(1) end
    end
  end
  print("[driver] turns " .. turns .. " outcome " .. tostring(outcome) .. " endReason " .. tostring(st.endReason))
  result(moveShot, "move select shot")
  result(faintShot, "faint shot")
  result(expSeen, "exp award sequence ran")
  result(expShot, "exp gain shot")
  result(logged("gained"), "STRINGID_PKMNGAINEDEXP printed")

  for _ = 1, 3000 do
    if outcome ~= nil then break end
    if not pump_text() then U.wait(1) end
  end
  result(outcome == "win", "battle outcome win (" .. tostring(outcome) .. ")")
  local exp1 = tonumber(session.party[1] and session.party[1].exp) or 0
  result(exp1 > exp0, string.format("starter exp %d -> %d", exp0, exp1))
  for _ = 1, 300 do
    if not Field.locked then break end
    U.wait(1)
  end
  U.wait(60)
  result(Map.current == "EM_ROUTE101", "back on the field at Route 101 (" .. tostring(Map.current) .. ")")
  result(not Battle.isActive(), "battle closed")
  result(U.still(game, DIR .. "/07_back_on_field.png"), "field shot")

  local Trainers = require("src.core.game3.scripting.trainers")
  local Prize = require("src.core.game3.battle.prize")
  local calvin = C.trainers.byName.TRAINER_CALVIN_1
  local foeRow = Trainers.foeFromId(calvin)
  result(foeRow ~= nil, "Calvin trainer row")
  if not foeRow then return finish() end
  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_GROVYLE, 30, "GROVYLE")
  session.money = 1000
  local want = Prize.calcRse(calvin, {})
  outcome = nil
  Ui._log = {}
  local ok2, err2 = BattleBridge.start(Runtime._mod, game, foeRow, {
    wild = false, trainerId = calvin, done = function(r) outcome = r end,
  })
  result(ok2 == true, "Calvin battle started " .. tostring(err2 or ""))
  for _ = 1, 3000 do
    if Battle.isActive() then break end
    U.wait(1)
  end
  local tsong = Audio._currentSong and Audio._currentSong.id
  result(tsong == C.songs.byName.MUS_VS_TRAINER, "trainer battle music MUS_VS_TRAINER (" .. tostring(tsong) .. ")")
  local victoryHeard = false
  for _ = 1, 20 do
    if not Battle.isActive() then break end
    if not wait_command() then break end
    U.tap(game, "a")
    U.wait(20)
    U.tap(game, "a")
    for _ = 1, 4000 do
      if at_command() or not Battle.isActive() then break end
      local s = Audio._currentSong and Audio._currentSong.id
      if s == C.songs.byName.MUS_VICTORY_TRAINER then victoryHeard = true end
      if not pump_text() then U.wait(1) end
    end
  end
  for _ = 1, 3000 do
    if outcome ~= nil then break end
    if not pump_text() then U.wait(1) end
  end
  result(outcome == "win", "Calvin battle won (" .. tostring(outcome) .. ")")
  result(victoryHeard, "MUS_VICTORY_TRAINER played on the win")
  result(session.money == 1000 + want, string.format("prize money %d (+%d from gTrainerMoneyTable)", session.money, want))
  result(logged("got %$" .. want) or logged(tostring(want)), "STRINGID_PLAYERGOTMONEY shows " .. want)
  U.wait(60)
  result(U.still(game, DIR .. "/08_after_calvin.png"), "after trainer battle shot")
  return finish()
end
