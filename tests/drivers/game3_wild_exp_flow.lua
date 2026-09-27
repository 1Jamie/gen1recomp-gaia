local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_wild_exp_flow"

return function(game)
  io.stdout:setvbuf("line")
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    print(string.format("[driver] game3_wild_exp_flow: %d failure(s)", fails))
    love.event.quit(fails == 0 and 0 or 1)
    U.wait(10)
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Message = require("src.ui.game3.message")
  local StatGrowth = require("src.ui.game3.stat_growth")
  local Anim = require("src.core.game3.battle.anim")
  local Audio = require("src.core.game3.audio")
  local Map = require("src.core.game3.map")
  local Encounters = require("src.core.game3.encounters")
  local Pokemon = require("src.core.game3.pokemon")
  local Experience = require("src.core.game3.battle.experience")
  local Constants = require("src.core.game3.constants")
  local session = Runtime.getSession()
  if not result(session ~= nil, "field session exists") then return finish() end
  local C = Constants.of(Constants.versionOf(session))
  print("[driver] version " .. tostring(C.game))
  Encounters.onStep = function() return nil end
  if C.game == "emerald" then
    Map.load(nil, game, "EM_ROUTE101", { x = 7, y = 13, facing = "down" })
  else
    Map.load(nil, game, "FR_ROUTE1", { x = 10, y = 20, facing = "down" })
  end
  U.wait(40)

  local MUDKIP = C.species.byName.SPECIES_MUDKIP
  local learnLv, learnMove
  for lv = 6, 40 do
    local mv = Pokemon.movesLearnedAt(MUDKIP, lv)
    if mv and #mv > 0 then learnLv, learnMove = lv, mv[1] break end
  end
  if not result(learnLv ~= nil, "Mudkip learnset has a move between LV6 and LV40 (" .. tostring(learnLv) .. ")") then
    return finish()
  end
  session.party = {}
  Party.giveMon(session, MUDKIP, learnLv - 1, "")
  local mon = session.party[1]
  local mv = function(n) return C.moves.byName["MOVE_" .. n] end
  mon.moves = {}
  for _, n in ipairs({ "TACKLE", "GROWL", "PROTECT", "WATER_GUN", "SCRATCH" }) do
    if mv(n) ~= learnMove and #mon.moves < 4 then mon.moves[#mon.moves + 1] = mv(n) end
  end
  mon.pp = { 35, 40, 10, 10 }
  mon.maxPp = { 35, 40, 10, 10 }
  mon.exp = Experience.expForLevel(mon, learnLv) - 1
  print(string.format("[driver] Mudkip LV%d exp %d, learns %s at LV%d", mon.level, mon.exp,
    tostring(C:name("moves", learnMove, "MOVE_")), learnLv))

  local VS_WILD = C.songs.byName.MUS_VS_WILD
  local VICTORY_WILD = C.songs.byName.MUS_VICTORY_WILD
  local outcome
  local ok = BattleBridge.startWild(Runtime._mod, game,
    { species = C.species.byName.SPECIES_ZIGZAGOON, level = 5 }, { done = function(r) outcome = r end })
  if not result(ok == true, "wild Zigzagoon battle started") then return finish() end
  for _ = 1, 3000 do
    if Battle.isActive() then break end
    U.wait(1)
  end
  if not result(Battle.isActive(), "battle active") then return finish() end

  local f = 0
  local ev = {}
  local function mark(name)
    if not ev[name] then
      ev[name] = f
      print(string.format("[driver] f=%d %s song=%s", f, name, tostring(Audio._currentSong and Audio._currentSong.id)))
    end
  end
  local songAt = {}
  local waitF = 0
  local statShot, expShot, learnShot = false, false, false
  local gainedOpenFrames, gainedPrinted = 0, false
  local endedWhileGained = false
  local foeLowered = false
  while (Battle.isActive() or outcome == nil) and f < 30000 do
    f = f + 1
    local song = Audio._currentSong and Audio._currentSong.id
    local page = Message.isOpen() and Message.currentPage() or ""
    local phase = Battle._phase
    if song == VICTORY_WILD then mark("victory_song") end
    if page:find("fainted") then
      mark("fainted_open")
      songAt.fainted = songAt.fainted or song
      if Message.isWaiting() then mark("fainted_waiting") end
    end
    if page:find("EXP%. Points") then
      mark("gained_open")
      songAt.gained = songAt.gained or song
      gainedOpenFrames = gainedOpenFrames + 1
      if Message.isWaiting() then
        gainedPrinted = true
        mark("gained_printed")
        if not expShot then
          expShot = U.still(game, DIR .. "/01_gained_exp.png")
        end
      end
      if phase == "ending" or phase == "fade_out" then endedWhileGained = true end
    elseif ev.gained_open and not ev.gained_closed then
      mark("gained_closed")
    end
    if page:find("grew to") then mark("grew_open") end
    if page:find("trying to") or page:find("learn") then mark("learn_text") end
    if phase == "ending" or phase == "fade_out" then mark("battle_ending") end

    if StatGrowth.isOpen() then
      mark("stat_box")
      if not statShot then
        U.wait(20)
        statShot = U.still(game, DIR .. "/02_level_up_box.png")
      end
      U.wait(30)
      U.tap(game, "a")
    elseif Ui.choiceActive() then
      mark("learn_prompt")
      if not learnShot then
        U.wait(10)
        learnShot = U.still(game, DIR .. "/03_learn_prompt.png")
      end
      U.wait(20)
      local lg = Ui.log()
      local last = tostring(lg[#lg] or "")
      U.tap(game, last:find("Stop") and "a" or "b")
    elseif phase == "command" and Ui._mode == "menu" and not Anim.busy() then
      local st = Battle.getState()
      if st and st.enemy and st.enemy.mon and not foeLowered then
        st.enemy.mon.hp = 1
        foeLowered = true
      end
      U.wait(10) U.tap(game, "a") U.wait(10) U.tap(game, "a") U.wait(4)
    elseif Message.isWaiting() and Ui.dialogPending() then
      waitF = waitF + 1
      if waitF >= 90 then
        waitF = 0
        U.tap(game, "a")
      else
        U.wait(1)
      end
    else
      waitF = 0
      U.wait(1)
    end
  end

  result(outcome == "win", "battle outcome win (" .. tostring(outcome) .. ")")
  result(ev.fainted_waiting ~= nil and ev.gained_open ~= nil and ev.gained_open - ev.fainted_waiting >= 90,
    "fainted!\\p waits for a button press before getexp (" .. tostring(ev.fainted_waiting) .. " -> " .. tostring(ev.gained_open) .. ")")
  result(songAt.fainted == VS_WILD, "MUS_VS_WILD still playing on the fainted message (" .. tostring(songAt.fainted) .. ")")
  result(ev.victory_song ~= nil and ev.gained_open ~= nil and ev.victory_song <= ev.gained_open,
    "MUS_VICTORY_WILD starts before the gained EXP text (" .. tostring(ev.victory_song) .. " <= " .. tostring(ev.gained_open) .. ")")
  result(songAt.gained == VICTORY_WILD, "MUS_VICTORY_WILD playing under the gained EXP text")
  result(gainedPrinted, "gained EXP text printed in full")
  result(gainedOpenFrames >= 60, "gained EXP text on screen " .. gainedOpenFrames .. " frames")
  result(not endedWhileGained, "battle did not start ending while the gained EXP text was up")
  result(ev.grew_open ~= nil and ev.grew_open > (ev.gained_open or math.huge), "grew to LV text after the gained EXP text")
  result(ev.stat_box ~= nil and ev.stat_box >= (ev.grew_open or math.huge), "level-up stat box shown after grew to LV")
  result(ev.learn_prompt ~= nil and ev.learn_prompt > (ev.stat_box or math.huge), "move-learn prompt after the level-up box")
  result(ev.battle_ending ~= nil and ev.battle_ending > (ev.learn_prompt or math.huge)
    and ev.battle_ending > (ev.gained_closed or math.huge), "battle ends after the EXP / level / learn flow")
  result(expShot and statShot and learnShot, "gained / level-up / learn prompt shots")
  local m = session.party[1]
  result(m and m.level == learnLv, "Mudkip reached LV" .. learnLv .. " (" .. tostring(m and m.level) .. ")")
  return finish()
end
