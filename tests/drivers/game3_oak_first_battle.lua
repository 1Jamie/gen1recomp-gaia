local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_oak_first_battle"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Message = require("src.ui.game3.message")
  local Anim = require("src.core.game3.battle.anim")

  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 1, 5)

  -- pokefirered/data/maps/PalletTown_ProfessorOaksLab/scripts.inc:333
  local ok, err = BattleBridge.start(Runtime._mod, game, {
    species = 7, level = 5, trainerId = 326,
  }, {
    wild = false,
    fade = false,
    trainerId = 326,
    earlyRival = true,
    rivalFlags = 3,
    firstBattle = true,
    defeatText = "WHAT?\nUnbelievable!",
    victoryText = "RIVAL: Yeah!\nAm I great or what?",
  })
  result(ok == true, "tutorial rival battle started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end

  local st = Battle.getState()
  if not st then love.event.quit(1) return end
  result(st.firstBattle == true, "st.firstBattle set from the script operand")
  result(st.aiFlags == 7, "rival keeps aiFlags 7 (got " .. tostring(st.aiFlags) .. ")")

  local function page_text()
    if not (Message and Message.isOpen and Message.isOpen()) then return nil end
    local pages = Message._pages or {}
    return pages[Message._page or 1]
  end

  local function showing(needle)
    local p = page_text()
    return p ~= nil and tostring(p):find(needle, 1, true) ~= nil
  end

  local shots = {}
  local function want(needle, file, label)
    shots[#shots + 1] = { needle = needle, file = file, label = label, held = 0 }
  end

  local function poll_shots()
    for _, sh in ipairs(shots) do
      if not sh.taken then
        if showing(sh.needle) and Message.isWaiting and Message.isWaiting() then
          sh.held = sh.held + 1
          if sh.held >= 6 then
            sh.taken = true
            U.shot(game, DIR .. "/" .. sh.file)
            print("shot " .. sh.file)
          end
        else
          sh.held = 0
        end
      end
    end
  end

  local function shot_pending_here()
    for _, sh in ipairs(shots) do
      if not sh.taken and showing(sh.needle) then return true end
    end
    return false
  end

  local lastTap = 0
  local f = 0
  local function pump(frames, stop)
    for _ = 1, frames do
      f = f + 1
      poll_shots()
      if stop and stop() then return true end
      if shot_pending_here() then
        U.wait(1)
      elseif Ui.dialogPending and Ui.dialogPending() and not Anim.busy() and f - lastTap >= 16 then
        lastTap = f
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return false
  end

  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  want("for Pete's sake", "2310_01_oak_intro.png", "opening Oak speech")
  want("The TRAINER that makes", "2310_02_oak_trainer_that.png", "second opening page")
  pump(3000, at_command)
  result(at_command(), "reached the command menu after Oak's opening speech")

  -- pokefirered/src/battle_main.c:3053
  want("no running away", "2310_03_oak_no_running.png", "Oak's no-running line")
  Ui._menuIndex = 4
  U.tap(game, "a")
  pump(600, function() return shots[3].taken == true end)
  pump(300, at_command)
  result(shots[3].taken == true, "RUN in the tutorial battle prints Oak's no-running line")

  want("Inflicting damage on the foe", "2310_04_oak_inflicting_damage.png", "first-damage advice")
  st.player.mon.moves = { 33, 0, 0, 0 }
  st.player.mon.pp = { 35, 0, 0, 0 }
  Ui._pendingCommand = { kind = "move", move = 33, slot = 1, user = "player" }
  Ui._mode = "none"
  pump(3000, function() return shots[4].taken == true end)
  result(shots[4].taken == true, "first damage on the foe prints Oak's damage advice")
  pump(1200, at_command)

  want("Am I great or what?", "2310_05_rival_victory_text.png", "rival victory speech")
  want("How disappointing", "2310_06_oak_how_disappointing.png", "Oak's loss speech")
  st.player.mon.hp = 1
  st.player.hp = 1
  local pp = Anim.present("player")
  if pp then pp.displayHp = 1 end
  st.enemy.mon.moves = { 33, 0, 0, 0 }
  st.enemy.mon.pp = { 35, 0, 0, 0 }
  st.enemy.mon.level = 80
  for _ = 1, 8 do
    if not Battle.isActive() then break end
    if at_command() then
      st.player.mon.hp = 1
      if pp then pp.displayHp = 1 end
      Ui._pendingCommand = { kind = "move", move = 33, slot = 1, user = "player" }
      Ui._mode = "none"
    end
    pump(1500, function() return shots[6].taken == true or not Battle.isActive() end)
    if shots[6].taken then break end
  end
  pump(900, function() return not Battle.isActive() end)

  local sawWhiteout = false
  for _, t in ipairs(Ui.log() or {}) do
    if tostring(t):find("blacked out", 1, true) then sawWhiteout = true end
  end
  result(sawWhiteout == false, "no white-out pair on the tutorial loss")

  for _, sh in ipairs(shots) do
    result(sh.taken == true, "shot " .. sh.file .. " (" .. sh.label .. ")")
  end

  print("driver done fails=" .. tostring(fails))
  love.event.quit(fails == 0 and 0 or 1)
end
