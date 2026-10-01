local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_quicksave_truck_bug2561"

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

return function(game)
  local finished = false
  local function finish()
    if finished then return end
    finished = true
    print((failures == 0 and "PASS" or "FAIL") .. " em_quicksave_truck_bug2561 failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
    U.wait(10)
  end

  local Rtc = require("src.core.game3.rtc")
  Rtc.reset()
  Rtc.setFixed("2005-06-01T09:30:00")

  local Vm = require("src.core.game3.scripting.vm")
  local started = {}
  local origStart = Vm.start
  Vm.start = function(self, key, facing)
    started[#started + 1] = key
    return origStart(self, key, facing)
  end

  local SaveData = require("src.core.SaveData")
  local writes = 0
  local origSave = SaveData.save
  SaveData.save = function(data, ...)
    writes = writes + 1
    return origSave(data, ...)
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
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Field = require("src.core.game3.field")
  local StartMenu = require("src.ui.game3.start_menu")
  local EM = Flags.forVersion("emerald")
  local VARS = EM.VAR_IDS

  local session = Runtime.getSession()
  if not check(okNew and session ~= nil and session.map == "EM_INSIDE_OF_TRUCK",
      "new game lands in the truck (" .. tostring(session and session.map) .. ")") then
    return finish()
  end

  local labels = Space.bundle and Space.bundle.labels or {}
  local function ran(name)
    local key = labels[name]
    for _, k in ipairs(started) do
      if k == key or k == name then return true end
    end
    return false
  end
  local function mapNow()
    local s = Runtime.getSession()
    return s and s.map
  end
  local function var(name) return tonumber(Flags.getVar(Space.store, nil, VARS[name])) or 0 end
  local function busy()
    return (Space.vm and Space.vm:isRunning()) or Warp.isBusy() or (Message.isOpen and Message.isOpen())
      or Field.locked or Space._pendingOnFrame
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
  local function step(dir, n)
    for _ = 1, n or 1 do
      U.hold(game, dir, 16)
      for _ = 1, 200 do
        if not Warp.isBusy() and not Player.moving then break end
        U.wait(1)
      end
    end
  end
  local function press(key)
    game:keypressed(key)
    U.wait(1)
    game:keyreleased(key)
  end
  local function where()
    local s = Runtime.getSession()
    return string.format("%s %s,%s", tostring(s and s.map), tostring(Player.cellX), tostring(Player.cellY))
  end

  -- pokeemerald/src/overworld.c:1542
  if not Truck.isRunning() then try("truck", function() Truck.execute() end) end
  for _ = 1, 4000 do
    if not Truck.isRunning() then break end
    U.wait(1)
  end
  check(not Truck.isRunning(), "truck sequence finished")
  U.wait(10)

  step("right", 1)
  settle(600)
  step("right", 2)
  settle(300, function() return mapNow() == "EM_LITTLEROOT_TOWN" end)
  if not check(mapNow() == "EM_LITTLEROOT_TOWN", "the truck exit reaches Littleroot") then return finish() end

  -- pokeemerald/data/maps/LittlerootTown/scripts.inc:195
  local landed = settle(1200, function()
    return mapNow() == "EM_LITTLEROOT_TOWN" and Space.vm and Space.vm:isRunning()
      and Player.cellX == 4 and Player.cellY == 10 and not Player.moving
  end)
  check(landed, "StepOffTruckMale jumps the player to (4,10) while the script still runs (" .. where() .. ")")
  check(var("VAR_LITTLEROOT_INTRO_STATE") == 1, "VAR_LITTLEROOT_INTRO_STATE still 1 mid-script ("
    .. var("VAR_LITTLEROOT_INTRO_STATE") .. ")")
  check(game:quickSaveAllowed() == false, "quickSaveAllowed refuses mid StepOffTruck")
  local beforeWrites = writes
  local beforeSave = SaveData.load()
  press("f1")
  local afterSave = SaveData.load()
  check(writes == beforeWrites, "F1 mid-script writes no save (" .. (writes - beforeWrites) .. " writes)")
  check((beforeSave == nil) == (afterSave == nil)
    and (afterSave == nil or (afterSave.map == beforeSave.map and afterSave.x == beforeSave.x)),
    "save on disk unchanged by the refused F1")
  check(game.phase == "field" and Space.vm:isRunning(), "the cutscene keeps running after the refused F1")
  U.still(game, DIR .. "/2561_01_littleroot_stepoff_f1_refused.png")

  -- pokeemerald/data/maps/LittlerootTown/scripts.inc:111
  local inHouse = settle(3000, function() return mapNow() == "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F" end)
  check(inHouse and ran("LittlerootTown_EventScript_StepOffTruckMale"), "Mom walks the player into Brendan's house ("
    .. where() .. ")")
  -- pokeemerald/data/scripts/players_house.inc:5
  settle(2400, function() return var("VAR_LITTLEROOT_INTRO_STATE") >= 4 and not busy() end)
  U.wait(30)
  check(var("VAR_LITTLEROOT_INTRO_STATE") == 4 and not busy(), "1F idle after EnterHouseMovingIn (state "
    .. var("VAR_LITTLEROOT_INTRO_STATE") .. ")")

  check(game:quickSaveAllowed() == true, "quickSaveAllowed on the idle field")
  U.tap(game, "start")
  settle(60, function() return StartMenu.isOpen() end)
  check(StartMenu.isOpen() and game:saveOffered(), "START menu still opens with SAVE on the idle field")
  U.tap(game, "b")
  settle(60, function() return not StartMenu.isOpen() end)
  U.wait(10)

  local home = { map = mapNow(), x = Player.cellX, y = Player.cellY }
  note("idle position " .. where())
  local stable = true
  for cycle = 1, 3 do
    local w0 = writes
    press("f1")
    if not check(writes == w0 + 1, "cycle " .. cycle .. ": F1 on the idle field writes a save") then stable = false end
    press("f2")
    U.wait(5)
    settle(1200, function() return game.phase == "field" and mapNow() ~= nil and not busy() end)
    U.wait(30)
    settle(600)
    local same = mapNow() == home.map and Player.cellX == home.x and Player.cellY == home.y
    if not check(same, "cycle " .. cycle .. ": F2 reload keeps the player at " .. home.map .. " " .. home.x .. ","
        .. home.y .. " (" .. where() .. ")") then
      stable = false
    end
  end
  check(stable, "3 save/load cycles do not move the player")
  U.still(game, DIR .. "/2561_02_house_1f_after_3_save_load_cycles.png")

  finish()
end
