local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_story_opening"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function note(msg)
  print("[driver] " .. msg)
end

local vmLogs = {}
local function captureLog(msg)
  msg = tostring(msg)
  if msg:find("skip unknown", 1, true) or msg:find("skip op", 1, true) or msg:find("not ported", 1, true)
      or msg:find("missing script", 1, true) or msg:find("runaway", 1, true) then
    vmLogs[#vmLogs + 1] = msg
  end
end

return function(game)
  local finished = false
  local function finish()
    if finished then return end
    finished = true
    check(#vmLogs == 0, "no unknown-op / unported-system VM logs on the opening path (" .. #vmLogs .. ")")
    for i = 1, math.min(#vmLogs, 10) do note("VM LOG " .. vmLogs[i]) end
    print((failures == 0 and "PASS" or "FAIL") .. " em_story_opening failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
    U.wait(10)
  end
  local function abort(label)
    check(false, label)
    finish()
  end

  local origPrint = print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    captureLog(table.concat(parts, "\t"))
    return origPrint(...)
  end

  check((os.getenv("POKEPORT_RTC") or "") ~= "", "fixed RTC from POKEPORT_RTC (" .. tostring(os.getenv("POKEPORT_RTC")) .. ")")

  local Vm = require("src.core.game3.scripting.vm")
  local started = {}
  local origNew = Vm.new
  Vm.new = function(opts)
    local vm = origNew(opts)
    local a = vm.adapters
    if a and a.log and not a._drvWrapped then
      local inner = a.log
      a.log = function(msg) captureLog(msg) return inner(msg) end
      a._drvWrapped = true
    end
    return vm
  end
  local origStart = Vm.start
  Vm.start = function(self, key, facing)
    started[#started + 1] = key
    return origStart(self, key, facing)
  end

  local function shot(name)
    U.still(game, DIR .. "/" .. name .. ".png")
  end

  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end

  if not check(waitFor(function() return game.phase == "boot" and game.boot ~= nil end, 900), "boot reached") then
    return finish()
  end
  local Boot = require("src.ui.game3.boot")
  local custom = game.boot.custom
  if not check(custom ~= nil, "Emerald boot modules drive the boot") then return finish() end
  check(waitFor(function() return custom.intro ~= nil end, 200), "copyright + intro start")
  U.wait(400)
  shot("01_intro")
  check(custom.intro ~= nil and custom.title == nil, "intro still running before the skip")
  for _ = 1, 400 do
    if custom.title then break end
    U.tap(game, "a")
    U.wait(8)
  end
  if not check(custom.title ~= nil, "A skips the intro to the title screen") then return finish() end
  U.wait(240)
  shot("02_title")

  for _ = 1, 600 do
    if custom.menu then break end
    U.tap(game, "start")
    U.wait(10)
  end
  if not check(custom.menu ~= nil, "START on the title opens the main menu") then return finish() end
  U.wait(60)
  shot("03_main_menu")
  local menu = custom.menu
  check(menu.items and menu.items[1] == "NEW_GAME", "no save: NEW GAME is the first row (" .. tostring(menu.items and menu.items[1]) .. ")")
  for _ = 1, 300 do
    if custom.newGame then break end
    U.tap(game, "a")
    U.wait(10)
  end
  local birch = custom.newGame
  if not check(birch ~= nil, "NEW GAME starts the Birch speech") then return finish() end
  U.wait(260)
  shot("04_birch")

  local function printerWaiting()
    local p = birch.printer
    return p and (p.state == "clear" or p.state == "scroll_start" or p.state == "wait") or false
  end
  local function birchUntil(pred, limit)
    for _ = 1, limit or 6000 do
      if pred() then return true end
      if printerWaiting() then U.tap(game, "a") U.wait(2) else U.wait(1) end
    end
    return pred()
  end
  if not check(birchUntil(function() return birch.main.func == "ChooseGender" end), "Birch asks boy or girl") then
    return finish()
  end
  U.wait(10)
  shot("05_gender_menu")
  U.tap(game, "a")
  if not check(birchUntil(function() return birch.main.func == "WaitPressBeforeNameChoice" end, 3000),
      "BOY chosen, Birch asks the name") then return finish() end
  U.tap(game, "a")
  if not check(waitFor(function() return birch.naming and birch.naming.stage == "input" end, 600), "naming screen open") then
    return finish()
  end
  U.wait(10)
  local preset = birch.playerName
  shot("06_naming_preset")
  U.tap(game, "start")
  U.wait(6)
  U.tap(game, "a")
  if not check(birchUntil(function() return birch.main.func == "ProcessNameYesNoMenu" end, 1200),
      "preset name " .. tostring(preset) .. " accepted, name YES/NO") then return finish() end
  shot("07_name_yes_no")
  U.tap(game, "a")
  if not check(birchUntil(function() return game.phase == "field" end, 6000), "Birch shrinks the player into the new game") then
    return finish()
  end

  local Runtime = require("src.core.game3.runtime")
  local Truck = require("src.core.game3.truck_sequence")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Field = require("src.core.game3.field")
  local Collision = require("src.core.game3.collision")
  local EM = Flags.forVersion("emerald")
  local VARS, IDS = EM.VAR_IDS, EM.IDS

  local session = Runtime.getSession()
  check(session and session.name == preset and session.gender == 0,
    "session keeps the Birch name and gender (" .. tostring(session and session.name) .. ")")
  check(session and session.map == "EM_INSIDE_OF_TRUCK", "new game starts inside the truck (" .. tostring(session and session.map) .. ")")
  check(Truck.isRunning(), "Game3 runs ExecuteTruckSequence")
  U.wait(300)
  shot("08_truck_ride")
  if not check(waitFor(function() return not Truck.isRunning() end, 4000), "truck stops and the door opens") then
    return finish()
  end
  U.wait(8)
  shot("09_truck_door_open")

  local function mapNow()
    local s = Runtime.getSession()
    return s and s.map
  end
  local function var(name) return tonumber(Flags.getVar(Space.store, nil, VARS[name])) or 0 end
  local function flag(name) return Flags.getFlag(Space.store, nil, IDS[name]) == true end
  local labels = Space.bundle and Space.bundle.labels or {}
  local function ran(name)
    local key = labels[name]
    for _, k in ipairs(started) do
      if k == key or k == name then return true end
    end
    return false
  end

  local function busy()
    return (Space.vm and Space.vm:isRunning()) or Warp.isBusy() or Message.isOpen() or Field.locked
      or Player.moving or Choice.isOpen()
  end

  local choiceAnswers = {}
  local function settle(limit, pred, onChoice)
    local n = 0
    for _ = 1, limit or 2400 do
      if pred and pred() then return true end
      if Choice.isOpen() then
        local answer = onChoice and onChoice() or "a"
        choiceAnswers[#choiceAnswers + 1] = answer
        if answer == "no" then U.tap(game, "down") U.wait(2) end
        U.tap(game, "a")
        U.wait(6)
      elseif Message.isOpen() then
        n = n + 1
        if n % 5 == 0 then U.tap(game, "a") else U.wait(1) end
      else
        U.wait(1)
      end
      if not pred and not busy() then
        U.wait(2)
        if not busy() then return true end
      end
    end
    if pred then return pred() and true or false end
    return not busy()
  end

  local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
  local function step(dir)
    local x0, y0, m0 = Player.cellX, Player.cellY, mapNow()
    for _ = 1, 3 do
      U.hold(game, dir, 2)
      for _ = 1, 60 do
        if not Player.moving and not Warp.isBusy() then break end
        U.wait(1)
      end
      if Player.cellX ~= x0 or Player.cellY ~= y0 or mapNow() ~= m0 or busy() then break end
    end
    for _ = 1, 400 do
      if not Player.moving and not Warp.isBusy() then break end
      U.wait(1)
    end
  end

  local function passable(fx, fy, tx, ty, dir)
    local ok = Collision.canEnter(game, tx, ty, {
      fromX = fx, fromY = fy, dir = dir, elevation = Player.currentElevation,
    })
    return ok
  end

  local function path(tx, ty)
    local sx, sy = Player.cellX, Player.cellY
    local key = function(x, y) return x .. "," .. y end
    local prev, q, head = { [key(sx, sy)] = false }, { { sx, sy } }, 1
    while head <= #q do
      local c = q[head]
      head = head + 1
      if c[1] == tx and c[2] == ty then break end
      for _, dir in ipairs({ "up", "down", "left", "right" }) do
        local d = DELTA[dir]
        local nx, ny = c[1] + d[1], c[2] + d[2]
        local k = key(nx, ny)
        if prev[k] == nil and #q < 4000 and passable(c[1], c[2], nx, ny, dir) then
          prev[k] = { c[1], c[2], dir }
          q[#q + 1] = { nx, ny }
        end
      end
    end
    if prev[key(tx, ty)] == nil then return nil end
    local out, k = {}, key(tx, ty)
    while prev[k] do
      local p = prev[k]
      table.insert(out, 1, p[3])
      k = key(p[1], p[2])
    end
    return out
  end

  local function goTo(tx, ty, limit)
    local m0 = mapNow()
    for _ = 1, limit or 12 do
      if Player.cellX == tx and Player.cellY == ty then return true end
      if mapNow() ~= m0 then return false end
      if busy() then settle(2400) end
      local p = path(tx, ty)
      if not p then
        note(string.format("no path on %s from %d,%d to %d,%d", tostring(mapNow()), Player.cellX, Player.cellY, tx, ty))
        U.wait(30)
      else
        for _, dir in ipairs(p) do
          local bx, by = Player.cellX, Player.cellY
          step(dir)
          if mapNow() ~= m0 or busy() then break end
          if Player.cellX == bx and Player.cellY == by then break end
        end
      end
    end
    return Player.cellX == tx and Player.cellY == ty
  end

  local function face(dir)
    if Player.facing ~= dir then
      U.tap(game, dir)
      U.wait(12)
    end
  end

  local function pushInto(dir, pred, tries)
    for _ = 1, tries or 4 do
      step(dir)
      if pred() then return true end
      settle(600, pred)
      if pred() then return true end
    end
    return pred()
  end

  -- pokeemerald/data/maps/InsideOfTruck/scripts.inc:16
  pushInto("right", function() return mapNow() == "EM_LITTLEROOT_TOWN" end, 6)
  check(ran("InsideOfTruck_EventScript_SetIntroFlags"), "truck coord event runs SetIntroFlags")
  if not check(mapNow() == "EM_LITTLEROOT_TOWN", "walking out of the truck reaches Littleroot (" .. tostring(mapNow()) .. ")") then
    return finish()
  end
  U.wait(30)
  shot("10_littleroot_arrival")

  -- pokeemerald/data/maps/LittlerootTown/scripts.inc:110
  local inHouse = settle(4000, function() return mapNow() == "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F" end)
  check(ran("LittlerootTown_EventScript_StepOffTruckMale"), "Mom greets the player (StepOffTruckMale)")
  if not check(inHouse, "Mom walks the player into the house (" .. tostring(mapNow()) .. ")") then return finish() end
  U.wait(40)
  shot("11_mom_house_1f")
  settle(4000, function() return var("VAR_LITTLEROOT_INTRO_STATE") >= 4 and not busy() end)
  if not check(var("VAR_LITTLEROOT_INTRO_STATE") == 4, "Mom sends the player upstairs (VAR_LITTLEROOT_INTRO_STATE="
      .. var("VAR_LITTLEROOT_INTRO_STATE") .. ")") then return finish() end

  -- pokeemerald/data/maps/LittlerootTown_BrendansHouse_1F/map.json
  goTo(8, 3)
  pushInto("up", function() return mapNow() == "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F" end)
  if not check(mapNow() == "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", "stairs lead to the bedroom (" .. tostring(mapNow()) .. ")") then
    return finish()
  end
  settle(600)
  U.wait(20)
  shot("12_bedroom")

  -- pokeemerald/data/scripts/players_house.inc:52
  local WallClock = require("src.ui.game3.rse.wall_clock")
  goTo(5, 2)
  face("up")
  U.tap(game, "a")
  local opened = settle(2400, function() return WallClock.isOpen() end)
  if not check(opened, "A on the wall clock opens StartWallClock") then return finish() end
  U.wait(60)
  shot("13_wall_clock")
  U.tap(game, "a")
  waitFor(function() local w = WallClock.active() return w and w.state == "confirm_input" end, 300)
  U.wait(10)
  shot("14_wall_clock_confirm")
  U.tap(game, "a")
  check(waitFor(function() return not WallClock.isOpen() end, 600), "clock set and closed")
  settle(4000, function() return var("VAR_LITTLEROOT_INTRO_STATE") == 6 and not busy() end)
  check(flag("FLAG_SET_WALL_CLOCK") and flag("FLAG_SYS_CLOCK_SET"), "FLAG_SET_WALL_CLOCK + FLAG_SYS_CLOCK_SET")
  if not check(var("VAR_LITTLEROOT_INTRO_STATE") == 6, "Mom comes upstairs after the clock (state "
      .. var("VAR_LITTLEROOT_INTRO_STATE") .. ")") then return finish() end
  U.wait(10)
  shot("15_mom_bedroom")

  -- pokeemerald/data/scripts/players_house.inc:136
  goTo(7, 2)
  pushInto("up", function() return mapNow() == "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F" end)
  if not check(mapNow() == "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F", "stairs back down to 1F") then return finish() end
  local tvShot = false
  local tvDone = settle(6000, function()
    if not tvShot and Message.isOpen() and ran("LittlerootTown_BrendansHouse_1F_EventScript_PetalburgGymReport") then
      local s = Runtime.getSession()
      if s and Field.metatileOverrides and Field.metatileOverrides["EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F"] then
        tvShot = true
        U.wait(20)
        shot("16_tv_scene")
      end
    end
    return var("VAR_LITTLEROOT_INTRO_STATE") == 7 and not busy()
  end)
  check(ran("LittlerootTown_BrendansHouse_1F_EventScript_PetalburgGymReport"), "TV scene runs (PetalburgGymReport)")
  if not check(tvDone and flag("FLAG_SYS_TV_HOME"), "TV scene completes (state " .. var("VAR_LITTLEROOT_INTRO_STATE") .. ")") then
    return finish()
  end
  if not tvShot then shot("16_tv_scene") end

  goTo(8, 7)
  pushInto("down", function() return mapNow() == "EM_LITTLEROOT_TOWN" end)
  if not check(mapNow() == "EM_LITTLEROOT_TOWN", "the player leaves the house (" .. tostring(mapNow()) .. ")") then
    return finish()
  end
  settle(600)
  U.wait(20)
  shot("17_leave_house")

  -- pokeemerald/data/maps/LittlerootTown_MaysHouse_1F/scripts.inc:86
  goTo(14, 9)
  pushInto("up", function() return mapNow() == "EM_LITTLEROOT_TOWN_MAYS_HOUSE_1F" end)
  if not check(mapNow() == "EM_LITTLEROOT_TOWN_MAYS_HOUSE_1F", "the door leads into the neighbor's house (" .. tostring(mapNow()) .. ")") then
    return finish()
  end
  settle(4000, function() return var("VAR_LITTLEROOT_HOUSES_STATE_BRENDAN") == 2 and not busy() end)
  check(flag("FLAG_MET_RIVAL_MOM"), "the rival's mom greets the player (YoureNewNeighbor)")
  U.wait(10)
  shot("18_rivals_mom")
  goTo(2, 3)
  pushInto("up", function() return mapNow() == "EM_LITTLEROOT_TOWN_MAYS_HOUSE_2F" end)
  if not check(mapNow() == "EM_LITTLEROOT_TOWN_MAYS_HOUSE_2F", "stairs to the rival's room") then return finish() end
  settle(600)
  check(var("VAR_LITTLEROOT_RIVAL_STATE") == 2, "rival room ON_TRANSITION readies MeetMay (state " .. var("VAR_LITTLEROOT_RIVAL_STATE") .. ")")

  -- pokeemerald/data/maps/LittlerootTown_MaysHouse_2F/scripts.inc:48
  goTo(5, 3)
  face("down")
  U.tap(game, "a")
  local mayShot = false
  local met = settle(4000, function()
    if not mayShot and Message.isOpen() and ran("LittlerootTown_MaysHouse_2F_EventScript_RivalsPokeBall") then
      mayShot = true
      U.wait(20)
      shot("19_meet_may")
    end
    return var("VAR_LITTLEROOT_TOWN_STATE") == 1 and not busy()
  end)
  if not check(met and var("VAR_LITTLEROOT_RIVAL_STATE") == 3, "May meets the player (VAR_LITTLEROOT_RIVAL_STATE="
      .. var("VAR_LITTLEROOT_RIVAL_STATE") .. ", TOWN_STATE " .. var("VAR_LITTLEROOT_TOWN_STATE") .. ")") then
    return finish()
  end
  if not mayShot then shot("19_meet_may") end

  goTo(1, 2)
  pushInto("up", function() return mapNow() == "EM_LITTLEROOT_TOWN_MAYS_HOUSE_1F" end)
  settle(1200)
  goTo(2, 7)
  pushInto("down", function() return mapNow() == "EM_LITTLEROOT_TOWN" end)
  if not check(mapNow() == "EM_LITTLEROOT_TOWN", "back outside in Littleroot") then return finish() end
  settle(600)

  -- pokeemerald/data/maps/LittlerootTown/scripts.inc:366
  goTo(11, 2)
  pushInto("up", function() return ran("LittlerootTown_EventScript_GoSaveBirchTrigger") end, 2)
  local saved = settle(4000, function() return var("VAR_LITTLEROOT_TOWN_STATE") == 2 and not busy() end)
  check(ran("LittlerootTown_EventScript_GoSaveBirchTrigger"), "the twin stops the player (GoSaveBirchTrigger)")
  if not check(saved, "the twin asks the player to save Birch (TOWN_STATE " .. var("VAR_LITTLEROOT_TOWN_STATE") .. ")") then
    return finish()
  end
  U.wait(10)
  shot("20_twin_save_birch")

  -- pokeemerald/data/maps/Route101/scripts.inc:19
  for _ = 1, 6 do
    if mapNow() == "EM_ROUTE101" then break end
    step("up")
  end
  if not check(mapNow() == "EM_ROUTE101", "north exit reaches Route 101 (" .. tostring(mapNow()) .. ")") then return finish() end
  for _ = 1, 4 do
    if ran("Route101_EventScript_StartBirchRescue") then break end
    step("up")
  end
  local chaseShot = false
  local chase = settle(6000, function()
    if not chaseShot and Message.isOpen() and ran("Route101_EventScript_StartBirchRescue") then
      chaseShot = true
      U.wait(10)
      shot("21_birch_chase")
    end
    return var("VAR_ROUTE101_STATE") == 2 and not busy()
  end)
  check(ran("Route101_EventScript_StartBirchRescue"), "Route 101 coord event starts the Birch chase")
  if not check(chase, "Birch chase scene ends (VAR_ROUTE101_STATE=" .. var("VAR_ROUTE101_STATE") .. ")") then
    return finish()
  end

  -- pokeemerald/data/maps/Route101/scripts.inc:214
  local StarterChoose = require("src.ui.game3.rse.starter_choose")
  goTo(7, 15)
  face("up")
  U.tap(game, "a")
  local open = settle(2400, function() return StarterChoose.isOpen() end)
  if not check(open, "A on Birch's bag runs ChooseStarter") then return finish() end
  local sc = StarterChoose.active()
  U.wait(40)
  shot("22_choose_starter")
  U.tap(game, "a")
  if not check(waitFor(function() return sc.confirm ~= nil end, 300), "the middle ball grows and asks YES/NO") then
    return finish()
  end
  U.wait(6)
  shot("23_starter_confirm")
  local Battle = require("src.core.game3.battle")
  U.tap(game, "a")
  local battled = settle(2400, function() return Battle.isActive() end)
  local mon = session.party and session.party[1]
  check(mon ~= nil and tonumber(mon.species) == StarterChoose.species(nil, 1) and tonumber(mon.level) == 5,
    "starter given at level 5 (species " .. tostring(mon and mon.species) .. ")")
  if not check(battled, "the first battle starts") then return finish() end

  -- pokeemerald/src/battle_setup.c:917
  local Ui = require("src.core.game3.battle.ui")
  local st = Battle.getState()
  local foe = st and st.enemy and st.enemy.mon
  check(foe and foe.level == 2, "wild Zigzagoon lv2 (species " .. tostring(foe and foe.species) .. ")")
  local lastTap, f = 0, 0
  local function pumpText()
    f = f + 1
    if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
      lastTap = f
      U.tap(game, "a")
      return true
    end
    return false
  end
  local function atCommand()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end
  local function waitCommand(limit)
    for _ = 1, limit or 6000 do
      if atCommand() or not Battle.isActive() then break end
      if not pumpText() then U.wait(1) end
    end
    return atCommand()
  end
  if waitCommand() then
    U.wait(20)
    shot("24_first_battle")
  end
  local turns = 0
  for _ = 1, 20 do
    if not Battle.isActive() then break end
    if not waitCommand() then break end
    turns = turns + 1
    U.tap(game, "a")
    U.wait(20)
    U.tap(game, "a")
    for _ = 1, 4000 do
      if atCommand() or not Battle.isActive() then break end
      if not pumpText() then U.wait(1) end
    end
  end
  local result = Battle.getResult and Battle.getResult()
  note("battle turns " .. turns .. " result " .. tostring(result or (st and st.result)))
  check(st and st.result == "win", "the first battle is won (" .. tostring(st and st.result) .. ")")

  -- pokeemerald/data/maps/LittlerootTown_ProfessorBirchsLab/scripts.inc:107
  local lab = settle(6000, function() return mapNow() == "EM_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB" end)
  if not check(lab, "Birch takes the player to his lab (" .. tostring(mapNow()) .. ")") then return finish() end
  U.wait(60)
  shot("25_birch_lab")
  local labShot = false
  local done = settle(8000, function()
    return var("VAR_BIRCH_LAB_STATE") == 3 and not busy()
  end, function()
    if not labShot then
      labShot = true
      shot("26_lab_nickname")
    end
    return #choiceAnswers == 0 and "no" or "a"
  end)
  check(ran("LittlerootTown_ProfessorBirchsLab_EventScript_GiveStarterEvent"), "lab ON_FRAME runs GiveStarterEvent")
  check(done, "Birch hands over the starter (VAR_BIRCH_LAB_STATE=" .. var("VAR_BIRCH_LAB_STATE") .. ")")
  U.wait(20)
  shot("27_lab_done")
  finish()
end
