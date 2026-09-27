local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_battle_visuals"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
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
  local Anim = require("src.core.game3.battle.anim")
  local BattleTransition = require("src.core.game3.battle_transition")
  local BattleBg = require("src.core.game3.battle.bg")
  local BattleChrome = require("src.ui.game3.battle_chrome")
  local Map = require("src.core.game3.map")
  local Trainers = require("src.core.game3.scripting.trainers")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  result(session ~= nil, "field session exists")
  if not session then love.event.quit(1) return end

  local function sp(name) return C.species.byName["SPECIES_" .. name] end
  local function mv(name) return C.moves.byName["MOVE_" .. name] end

  local function load_map(id, x, y)
    local ok, err = pcall(function() Map.load(nil, game, id, { x = x, y = y, facing = "down" }) end)
    result(ok, "load " .. id .. " " .. tostring(err or ""))
    U.wait(40)
  end

  local function set_party()
    session.party = {}
    Party.giveMon(session, sp("SALAMENCE"), 50, "SALAMENCE")
    local m = session.party[1]
    m.moves = { mv("HEADBUTT"), mv("EMBER"), mv("DRAGON_BREATH"), mv("FLY") }
    m.pp = { 15, 25, 20, 15 }
    m.maxPp = { 15, 25, 20, 15 }
    m.hp = m.maxHp or m.hp
  end

  local lastTap = 0
  local f = 0
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

  local function run_battle(tag, startFn, transitionFrames)
    local ok, err = startFn()
    result(ok == true, tag .. " battle started " .. tostring(err or ""))
    if not ok then return end
    local tid = BattleTransition._transitionId
    print("[driver] " .. tag .. " transition id " .. tostring(tid) .. " family " .. BattleTransition.family())
    local shotMid = false
    for _ = 1, 3000 do
      if BattleTransition._phase == "main" and BattleTransition._fx and not shotMid then
        U.wait(transitionFrames)
        shotMid = U.still(game, DIR .. "/" .. tag .. "_01_transition_mid.png")
      end
      if Battle.isActive() then break end
      U.wait(1)
    end
    result(shotMid, tag .. " transition mid-frame shot")
    result(Battle.isActive(), tag .. " battle active after transition")
    local slid = false
    for _ = 1, 600 do
      local s = Anim.stage()
      local bs = s and s.bgSlide
      if bs and bs.enemyOx and bs.enemyOx < -40 and bs.enemyOx > -200 then
        slid = U.still(game, DIR .. "/" .. tag .. "_02_intro_slide.png")
        break
      end
      U.wait(1)
    end
    result(slid, tag .. " intro slide shot")
    print("[driver] " .. tag .. " background " .. tostring(BattleBg.sheetKey(BattleBg.terrainId()))
      .. " terrain id " .. tostring(BattleBg.terrainId()) .. " env " .. tostring(Battle.getState() and Battle.getState().terrain))
    for _ = 1, 6000 do
      if at_command() then break end
      if not pump_text() then U.wait(1) end
    end
    result(at_command(), tag .. " reached command menu")
    U.wait(30)
    result(U.still(game, DIR .. "/" .. tag .. "_03_action_menu.png"), tag .. " action menu shot")
    U.tap(game, "a")
    U.wait(30)
    result(Ui._mode == "moves", tag .. " move menu open")
    result(U.still(game, DIR .. "/" .. tag .. "_04_move_menu.png"), tag .. " move menu shot")
    U.tap(game, "b")
    U.wait(10)
    Battle.abort("run")
    for _ = 1, 600 do
      if not Battle.isActive() then break end
      U.wait(1)
    end
    U.wait(60)
  end

  result(BattleChrome.isRse(), "Emerald chrome manifest is the rse layout")

  load_map("EM_ROUTE117", 32, 15)
  set_party()
  local Chrome = require("src.ui.game3.chrome")
  local frameType = Chrome._frameType
  Chrome.setFrameType(4)
  run_battle("route117_oddish", function()
    return BattleBridge.startWild(Runtime._mod, game, { species = sp("ODDISH"), level = 14 }, {})
  end, 24)

  Chrome.setFrameType(frameType)
  load_map("EM_ROUTE101", 10, 12)
  set_party()
  session.party[1].level = 5
  run_battle("route101_zigzagoon", function()
    return BattleBridge.startWild(Runtime._mod, game, { species = sp("ZIGZAGOON"), level = 2 }, {})
  end, 30)

  load_map("EM_ROUTE102", 20, 8)
  set_party()
  local calvin = C.trainers.byName.TRAINER_CALVIN_1
  run_battle("route102_calvin", function()
    local foe = Trainers.foeFromId(calvin)
    if not foe then return nil, "no trainer row" end
    return BattleBridge.start(Runtime._mod, game, foe, { wild = false, trainerId = calvin })
  end, 30)

  load_map("EM_PETALBURG_WOODS", 20, 30)
  set_party()
  local grunt = C.trainers.byName.TRAINER_GRUNT_PETALBURG_WOODS
  run_battle("petalburg_woods_aqua", function()
    local foe = Trainers.foeFromId(grunt)
    if not foe then return nil, "no trainer row" end
    return BattleBridge.start(Runtime._mod, game, foe, { wild = false, trainerId = grunt })
  end, 60)

  print(string.format("[driver] em_battle_visuals: %d failure(s)", fails))
  love.event.quit(fails == 0 and 0 or 1)
end
