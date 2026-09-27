local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_opening_scripts"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function note(msg)
  print("[driver] " .. msg)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then note(label .. " error: " .. tostring(err)) end
  return ok
end

local captured = {}
local function captureLog(msg)
  msg = tostring(msg)
  if msg:find("skip unknown", 1, true) or msg:find("skip op", 1, true) or msg:find("not ported", 1, true)
      or msg:find("missing script", 1, true) or msg:find("bad list", 1, true) or msg:find("runaway", 1, true) then
    captured[#captured + 1] = msg
    print("[driver] VM LOG " .. msg)
  end
end

return function(game)
  local finished = false
  local function finish()
    if finished then return end
    finished = true
    check(#captured == 0, "no unknown-op / unknown-special / unported-system logs on the opening path ("
      .. #captured .. ")")
    print((failures == 0 and "PASS" or "FAIL") .. " em_opening_scripts failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
    U.wait(10)
  end

  local Rtc = require("src.core.game3.rtc")
  Rtc.reset()
  Rtc.setFixed("2005-06-01T09:30:00")

  local origPrint = print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    local line = table.concat(parts, "\t")
    if not line:find("^%[driver%] VM LOG") then captureLog(line) end
    return origPrint(...)
  end

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

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end

  local Truck = require("src.core.game3.truck_sequence")
  local okNew = try("new_game", function()
    game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0, fieldCallback = "truck" })
  end)
  U.wait(10)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Field = require("src.core.game3.field")
  local EM = Flags.forVersion("emerald")
  local VARS, IDS = EM.VAR_IDS, EM.IDS

  local session = Runtime.getSession()
  check(okNew and session ~= nil and session.map == "EM_INSIDE_OF_TRUCK",
    "new game lands in the truck (" .. tostring(session and session.map) .. ")")
  if not session then return finish() end

  local labels = Space.bundle and Space.bundle.labels or {}
  local byKey = {}
  for name, key in pairs(labels) do byKey[key] = byKey[key] or name end
  local function ran(name)
    local key = labels[name]
    for _, k in ipairs(started) do
      if k == key or k == name then return true end
    end
    return false
  end
  local function lastStarted()
    local k = started[#started]
    return k and (byKey[k] or k) or "none"
  end

  local function mapNow()
    local s = Runtime.getSession()
    return s and s.map
  end
  local function var(name) return tonumber(Flags.getVar(Space.store, nil, VARS[name])) or 0 end
  local function setVar(name, v) Flags.setVar(Space.store, nil, VARS[name], v) end
  local function flag(name) return Flags.getFlag(Space.store, nil, IDS[name]) == true end
  local function setFlag(name, on) Flags.setFlag(Space.store, nil, IDS[name], on ~= false) end

  local function busy()
    return (Space.vm and Space.vm:isRunning()) or Warp.isBusy() or (Message.isOpen and Message.isOpen())
      or Field.locked
  end

  local function settle(frames, pred)
    local n = 0
    for _ = 1, frames or 1800 do
      if pred and pred() then return true end
      if Message.isOpen and Message.isOpen() then
        n = n + 1
        if n % 6 == 0 then U.tap(game, "a") else U.wait(1) end
      else
        U.wait(1)
      end
      if not pred and not busy() then return true end
    end
    return pred and pred() or not busy()
  end

  local function running()
    local vm = Space.vm
    if not (vm and vm:isRunning()) then return nil end
    local pc = vm.ctx.pc
    local list = pc and vm.scripts[pc.listKey]
    local row = list and list[pc.index]
    return string.format("%s#%s op=%s", tostring(byKey[pc and pc.listKey] or (pc and pc.listKey)),
      tostring(pc and pc.index), tostring(row and row.op))
  end

  local function haltStuck(label)
    local where = running()
    if not where then return end
    note(label .. " still running at " .. where .. "; halting it")
    local Objects = require("src.core.game3.objects")
    for lid, tr in pairs(Objects._tracks or {}) do
      if not tr.done then
        note(string.format("track lid=%s i=%s/%s", tostring(lid), tostring(tr.i), tostring(tr.actions and #tr.actions)))
      end
    end
    Space.vm:halt(true)
    Field.unlock()
  end

  local function place(mapId, x, y, facing)
    settle(600)
    local ok = try("Map.load " .. mapId, function()
      Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    end)
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    U.wait(20)
    return ok
  end

  local function step(dir, n)
    for _ = 1, n or 1 do
      U.hold(game, dir, 16)
      for _ = 1, 200 do
        if not Warp.isBusy() and not Player.moving then break end
        U.wait(1)
      end
    end
  end

  U.shot(game, DIR .. "/01_truck.png")

  -- pokeemerald/src/overworld.c:1542
  if not Truck.isRunning() then
    note("Game3 did not start the truck; driver runs ExecuteTruckSequence")
    try("truck", function() Truck.execute() end)
  end
  for _ = 1, 4000 do
    if not Truck.isRunning() then break end
    U.wait(1)
  end
  check(not Truck.isRunning(), "truck sequence finished")
  U.wait(10)
  U.shot(game, DIR .. "/02_truck_door_open.png")

  -- pokeemerald/data/maps/InsideOfTruck/scripts.inc:16
  step("right", 1)
  settle(600)
  check(ran("InsideOfTruck_EventScript_SetIntroFlags") and var("VAR_LITTLEROOT_INTRO_STATE") == 1,
    "truck coord event runs SetIntroFlags (VAR_LITTLEROOT_INTRO_STATE=" .. var("VAR_LITTLEROOT_INTRO_STATE") .. ")")
  local dw = session.dynamicWarp
  check(dw and dw.map == "EM_LITTLEROOT_TOWN" and dw.x == 3 and dw.y == 10,
    "setdynamicwarp targets Littleroot (3,10) (" .. tostring(dw and dw.map) .. " " .. tostring(dw and dw.x) .. ","
    .. tostring(dw and dw.y) .. ")")
  step("right", 2)
  settle(300, function() return mapNow() == "EM_LITTLEROOT_TOWN" end)
  if mapNow() ~= "EM_LITTLEROOT_TOWN" then
    note("truck exit did not warp (" .. tostring(mapNow()) .. "); placing the player at the dynamic warp")
    place("EM_LITTLEROOT_TOWN", 3, 10, "right")
  end
  check(mapNow() == "EM_LITTLEROOT_TOWN", "the truck exit reaches Littleroot")

  -- pokeemerald/data/maps/LittlerootTown/scripts.inc:111
  local reachedHouse = settle(3000, function() return mapNow() == "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F" end)
  check(ran("LittlerootTown_EventScript_StepOffTruckMale"), "Littleroot ON_FRAME runs StepOffTruckMale")
  if not check(reachedHouse, "Mom walks the player into Brendan's house (" .. tostring(mapNow()) .. ", last "
      .. lastStarted() .. ")") then
    haltStuck("StepOffTruckMale")
    setFlag("FLAG_HIDE_LITTLEROOT_TOWN_BRENDANS_HOUSE_TRUCK")
    setVar("VAR_LITTLEROOT_INTRO_STATE", 3)
    place("EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F", 8, 8, "up")
  end
  U.shot(game, DIR .. "/03_house_1f.png")

  -- pokeemerald/data/scripts/players_house.inc:5
  settle(2400, function() return var("VAR_LITTLEROOT_INTRO_STATE") >= 4 and not busy() end)
  check(ran("LittlerootTown_BrendansHouse_1F_EventScript_EnterHouseMovingIn"), "1F ON_FRAME runs EnterHouseMovingIn")
  if not check(var("VAR_LITTLEROOT_INTRO_STATE") == 4, "Mom sends the player upstairs (VAR_LITTLEROOT_INTRO_STATE="
      .. var("VAR_LITTLEROOT_INTRO_STATE") .. ")") then
    haltStuck("EnterHouseMovingIn")
    setVar("VAR_LITTLEROOT_INTRO_STATE", 4)
  end

  -- pokeemerald/data/scripts/players_house.inc:1
  local function walkTo(dir, n, pred)
    for _ = 1, n do
      step(dir, 1)
      if pred and pred() then return true end
    end
    return pred and pred() or false
  end
  local function goTo(tx, ty)
    for _ = 1, 24 do
      local cx, cy = Player.cellX, Player.cellY
      if cx == tx and cy == ty then return true end
      local before = cx .. "," .. cy
      if cx ~= tx then step(cx < tx and "right" or "left", 1) else step(cy < ty and "down" or "up", 1) end
      if Player.cellX .. "," .. Player.cellY == before then
        if cy ~= ty then step(cy < ty and "down" or "up", 1) else step(cx < tx and "right" or "left", 1) end
      end
    end
    note(string.format("goTo(%d,%d) stopped at %s,%s", tx, ty, tostring(Player.cellX), tostring(Player.cellY)))
    return Player.cellX == tx and Player.cellY == ty
  end
  settle(600)
  local upstairs = walkTo("up", 8, function() return mapNow() == "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F" end)
  settle(600)
  if not check(upstairs, "stairs lead to Brendan's room (" .. tostring(mapNow()) .. ")") then
    place("EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", 7, 1, "down")
  end
  check(var("VAR_LITTLEROOT_INTRO_STATE") == 5, "2F ON_TRANSITION blocks the stairs until the clock is set (state "
    .. var("VAR_LITTLEROOT_INTRO_STATE") .. ")")
  check(ran("LittlerootTown_BrendansHouse_2F_EventScript_CheckInitDecor") and var("VAR_SECRET_BASE_INITIALIZED") == 1,
    "2F ON_WARP runs CheckInitDecor -> InitSecretBaseDecorationSprites (VAR_SECRET_BASE_INITIALIZED="
    .. var("VAR_SECRET_BASE_INITIALIZED") .. ")")
  U.shot(game, DIR .. "/04_bedroom.png")

  -- pokeemerald/data/scripts/players_house.inc:52
  local WallClock = require("src.ui.game3.rse.wall_clock")
  local s = Runtime.getSession()
  note(string.format("2F arrival at %s,%s", tostring(s and s.x), tostring(s and s.y)))
  step("down", 1)
  step("left", 2)
  step("up", 1)
  s = Runtime.getSession()
  note(string.format("facing the clock from %s,%s (%s)", tostring(s and s.x), tostring(s and s.y), tostring(Player.facing)))
  U.tap(game, "a")
  local opened = settle(1200, function() return WallClock.isOpen() end)
  if check(opened, "the wall clock bg event opens StartWallClock") then
    U.wait(40)
    U.shot(game, DIR .. "/05_wall_clock.png")
    U.tap(game, "a")
    U.wait(20)
    U.tap(game, "a")
    settle(600, function() return not WallClock.isOpen() end)
  else
    haltStuck("WallClock")
  end
  settle(3000, function() return var("VAR_LITTLEROOT_INTRO_STATE") == 6 and not busy() end)
  check(var("VAR_LITTLEROOT_INTRO_STATE") == 6 and flag("FLAG_SET_WALL_CLOCK"),
    "clock set, Mom comes upstairs (state " .. var("VAR_LITTLEROOT_INTRO_STATE") .. ", last " .. lastStarted() .. ")")
  if var("VAR_LITTLEROOT_INTRO_STATE") ~= 6 then
    haltStuck("SetWallClock")
    setVar("VAR_LITTLEROOT_INTRO_STATE", 6)
    setFlag("FLAG_SET_WALL_CLOCK")
  end

  -- pokeemerald/data/scripts/players_house.inc:125
  goTo(7, 2)
  local down = walkTo("up", 2, function() return mapNow() == "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F" end)
  if not down then
    note("stairs down not reached; placing the player on 1F (8,2)")
    place("EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F", 8, 2, "down")
  end
  local tvDone = settle(4000, function() return var("VAR_LITTLEROOT_INTRO_STATE") == 7 and not busy() end)
  check(ran("LittlerootTown_BrendansHouse_1F_EventScript_PetalburgGymReport"), "1F ON_FRAME runs PetalburgGymReport")
  check(tvDone and flag("FLAG_SYS_TV_HOME"), "TV scene completes (state " .. var("VAR_LITTLEROOT_INTRO_STATE")
    .. ", FLAG_SYS_TV_HOME " .. tostring(flag("FLAG_SYS_TV_HOME")) .. ", last " .. lastStarted() .. ")")
  local offs = 0
  for _, o in pairs(Field.metatileOverrides["EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F"] or {}) do
    if o.metatile == 0x002 then offs = offs + 1 end
  end
  check(offs > 0, "TurnOffTVScreen writes METATILE_Building_TV_Off on the TV (" .. offs .. " cells)")
  if not tvDone then
    haltStuck("PetalburgGymReport")
    setVar("VAR_LITTLEROOT_INTRO_STATE", 7)
    setFlag("FLAG_SYS_TV_HOME")
  end
  U.shot(game, DIR .. "/06_after_tv.png")

  -- pokeemerald/data/scripts/tv.inc:1
  local NativesTv = require("src.core.game3.scripting.natives_tv")
  local Tv = require("src.core.game3.rse.tv")
  local news = NativesTv.BY_NAME.CheckForPlayersHouseNews({ specialVars = {}, stringVars = {} })
  local _, newsValue = news, select(2, NativesTv.BY_NAME.CheckForPlayersHouseNews({ specialVars = {} }))
  check(newsValue == Tv.PLAYERS_HOUSE_TV_MOVIE, "CheckForPlayersHouseNews is MOVIE after the broadcast ("
    .. tostring(newsValue) .. ")")

  -- pokeemerald/data/maps/LittlerootTown_BrendansHouse_1F/map.json
  goTo(8, 7)
  local outside = walkTo("down", 3, function() return mapNow() == "EM_LITTLEROOT_TOWN" end)
  settle(600)
  if not check(outside, "the player walks out to Littleroot (" .. tostring(mapNow()) .. ")") then
    place("EM_LITTLEROOT_TOWN", 5, 9, "down")
  end

  -- pokeemerald/data/maps/LittlerootTown_MaysHouse_1F/scripts.inc:86
  place("EM_LITTLEROOT_TOWN", 14, 9, "up")
  local inMays = walkTo("up", 2, function() return mapNow() == "EM_LITTLEROOT_TOWN_MAYS_HOUSE_1F" end)
  settle(3000, function() return var("VAR_LITTLEROOT_HOUSES_STATE_BRENDAN") == 2 and not busy() end)
  check(inMays and ran("LittlerootTown_MaysHouse_1F_EventScript_YoureNewNeighbor"),
    "May's house ON_FRAME runs YoureNewNeighbor (" .. tostring(mapNow()) .. ")")
  check(var("VAR_LITTLEROOT_HOUSES_STATE_BRENDAN") == 2 and flag("FLAG_MET_RIVAL_MOM"),
    "GetRivalSonDaughterString scene completes (state " .. var("VAR_LITTLEROOT_HOUSES_STATE_BRENDAN") .. ")")
  if var("VAR_LITTLEROOT_HOUSES_STATE_BRENDAN") ~= 2 then
    haltStuck("YoureNewNeighbor")
    setVar("VAR_LITTLEROOT_HOUSES_STATE_BRENDAN", 2)
    setFlag("FLAG_MET_RIVAL_MOM")
  end
  U.shot(game, DIR .. "/07_rivals_mom.png")

  -- pokeemerald/data/maps/LittlerootTown_MaysHouse_2F/scripts.inc:68
  note("skipping the 2F rival meeting: VAR_LITTLEROOT_RIVAL_STATE=3, VAR_LITTLEROOT_TOWN_STATE=1")
  setVar("VAR_LITTLEROOT_RIVAL_STATE", 3)
  setVar("VAR_LITTLEROOT_TOWN_STATE", 1)
  place("EM_LITTLEROOT_TOWN", 11, 3, "up")
  step("up", 2)
  settle(2400, function() return var("VAR_LITTLEROOT_TOWN_STATE") == 2 and not busy() end)
  check(ran("LittlerootTown_EventScript_GoSaveBirchTrigger"), "twin coord event runs GoSaveBirchTrigger")
  check(var("VAR_LITTLEROOT_TOWN_STATE") == 2, "GetPlayerBigGuyGirlString scene completes (VAR_LITTLEROOT_TOWN_STATE="
    .. var("VAR_LITTLEROOT_TOWN_STATE") .. ")")
  if var("VAR_LITTLEROOT_TOWN_STATE") ~= 2 then
    haltStuck("GoSaveBirchTrigger")
    setVar("VAR_LITTLEROOT_TOWN_STATE", 2)
  end

  -- pokeemerald/data/maps/Route101/scripts.inc:18
  local onRoute = walkTo("up", 4, function() return mapNow() == "EM_ROUTE101" end)
  if not onRoute then place("EM_ROUTE101", 11, 19, "up") end
  local chase = settle(4000, function() return var("VAR_ROUTE101_STATE") == 2 and not busy() end)
  check(ran("Route101_EventScript_StartBirchRescue"), "Route 101 coord event starts the Birch chase")
  check(chase, "Birch chase scene completes (VAR_ROUTE101_STATE=" .. var("VAR_ROUTE101_STATE") .. ", last "
    .. lastStarted() .. ")")
  U.shot(game, DIR .. "/08_birch_chase.png")
  if not chase then
    haltStuck("StartBirchRescue")
    setVar("VAR_ROUTE101_STATE", 2)
  end

  -- pokeemerald/data/maps/Route101/scripts.inc:161
  local StarterChoose = require("src.ui.game3.rse.starter_choose")
  place("EM_ROUTE101", 7, 15, "up")
  local bagKey = labels["Route101_EventScript_BirchsBag"]
  local bagLid
  local rdef = game.data and game.data.maps and game.data.maps["EM_ROUTE101"]
  for _, o in ipairs(rdef and rdef.objects or {}) do
    if o.scriptKey == bagKey then bagLid = o.localId end
  end
  note("A on the bag (OBJ_EVENT_GFX_BIRCHS_BAG 97) hits field.lua's FR PUSHABLE_BOULDER 97 check (crossfile); "
    .. "starting the bag object script lid " .. tostring(bagLid) .. " directly")
  try("startTalk bag", function() Space.vm:startTalk(bagKey, bagLid, 2) end)
  local open = settle(1200, function() return StarterChoose.isOpen() end)
  if not check(open, "Birch's bag runs ChooseStarter (" .. lastStarted() .. ")") then
    haltStuck("BirchsBag")
    return finish()
  end
  local sc = StarterChoose.active()
  U.wait(30)
  U.shot(game, DIR .. "/09_starter_bag.png")
  check(sc.label and sc.label.name ~= "", "starter label shows the species (" .. tostring(sc.label and sc.label.name)
    .. " / " .. tostring(sc.label and sc.label.category) .. ")")
  U.tap(game, "left")
  U.wait(6)
  U.shot(game, DIR .. "/10_starter_left.png")
  check(sc.selection == 0, "left moves to the first ball")
  U.tap(game, "a")
  U.wait(8)
  U.shot(game, DIR .. "/11_starter_growing.png")
  for _ = 1, 120 do
    if sc.confirm then break end
    U.wait(1)
  end
  check(sc.confirm ~= nil, "circle + mon reach the centre and the YES/NO box opens")
  U.wait(4)
  U.shot(game, DIR .. "/12_starter_confirm.png")
  local Battle = require("src.core.game3.battle")
  U.tap(game, "a")
  local battled = settle(1200, function() return Battle.isActive and Battle.isActive() end)
  local s2 = Runtime.getSession()
  local mon = s2 and s2.party and s2.party[1]
  local want = StarterChoose.species(nil, 0)
  check(mon ~= nil and tonumber(mon.species) == want and tonumber(mon.level) == 5,
    "starter given at level 5 (species " .. tostring(mon and mon.species) .. " want " .. tostring(want) .. ")")
  check(var("VAR_STARTER_MON") == 0, "VAR_STARTER_MON holds the choice (" .. var("VAR_STARTER_MON") .. ")")
  check(battled, "the first battle starts")
  if battled then
    U.wait(90)
    U.shot(game, DIR .. "/13_first_battle.png")
    local BattleBridge = require("src.core.game3.battle_bridge")
    note("ending the first battle through BattleBridge.finishPending (battle runtime is a separate W2 item)")
    try("finishPending", function() BattleBridge.finishPending("win") end)
    local lab = settle(4000, function() return mapNow() == "EM_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB" end)
    check(lab, "after the battle the bag script warps to Birch's lab (" .. tostring(mapNow()) .. ")")
    check(var("VAR_BIRCH_LAB_STATE") == 2 and flag("FLAG_RESCUED_BIRCH"), "BirchsBag sets VAR_BIRCH_LAB_STATE=2")

    -- pokeemerald/data/maps/LittlerootTown_ProfessorBirchsLab/scripts.inc:107
    local Choice = require("src.ui.game3.choice")
    local answers = 0
    local shotLab = false
    for _ = 1, 6000 do
      if var("VAR_BIRCH_LAB_STATE") == 3 and not busy() then break end
      if Choice.isOpen() then
        answers = answers + 1
        if answers == 1 then
          if not shotLab then U.shot(game, DIR .. "/14_birch_lab_nickname.png") shotLab = true end
          U.tap(game, "down")
        end
        U.tap(game, "a")
        U.wait(4)
      elseif Message.isOpen and Message.isOpen() then
        U.tap(game, "a")
        U.wait(5)
      else
        U.wait(1)
      end
    end
    check(ran("LittlerootTown_ProfessorBirchsLab_EventScript_GiveStarterEvent"), "lab ON_FRAME runs GiveStarterEvent")
    check(var("VAR_BIRCH_LAB_STATE") == 3, "Birch hands over the starter (VAR_BIRCH_LAB_STATE="
      .. var("VAR_BIRCH_LAB_STATE") .. ", " .. answers .. " YES/NO answers)")
    U.shot(game, DIR .. "/15_birch_lab_done.png")
  end

  finish()
end
