local U = require("tests.drivers.util")
local L = require("tests.drivers.em_battle_loop")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_match_call_rematch"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_match_call_rematch failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Field = require("src.core.game3.field")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Party = require("src.core.game3.party")
  local Battle = require("src.core.game3.battle")
  local Rng = require("src.core.game3.rng")
  local Rtc = require("src.core.game3.rtc")
  local Encounters = require("src.core.game3.encounters")
  local Trainers = require("src.core.game3.scripting.trainers")
  local StepEvents = require("src.core.game3.step_events")
  local Rematch = require("src.core.game3.rse.rematch")
  local MatchCall = require("src.core.game3.rse.match_call")
  local CallWindow = require("src.ui.game3.rse.pokenav.call_window")
  local C = require("src.core.game3.constants").of("emerald")
  local T = Flags.forVersion("emerald")
  local session = Runtime.getSession()
  if not check(session ~= nil, "session after new game") then return finish() end
  Encounters.onStep = function() return nil end

  local function flag(name) return Flags.getFlag(Space.store, nil, T.IDS[name]) == true end
  local function setFlag(name, on) Flags.setFlag(Space.store, nil, T.IDS[name], on ~= false) end
  local function mapNow() local s = Runtime.getSession() return s and s.map end
  local function still(name) U.still(game, DIR .. "/" .. name .. ".png") end
  local function busy()
    return (Space.vm and Space.vm:isRunning()) or Warp.isBusy() or Message.isOpen() or Field.locked
      or Player.moving or Choice.isOpen() or Battle.isActive() or CallWindow.isOpen() or StepEvents.busy()
  end
  local function goTo(mapId, x, y, facing)
    for _ = 1, 600 do
      if not busy() then break end
      if Message.isOpen() then U.tap(game, "b") end
      U.wait(1)
    end
    local ok = try("Map.load " .. mapId, function() Map.load(nil, game, mapId, { x = x, y = y, facing = facing }) end)
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    U.wait(20)
    return ok
  end
  local function mash(pred, limit)
    local n = 0
    for _ = 1, limit or 3000 do
      if pred() then return true end
      if Battle.isActive() then return pred() end
      if Message.isOpen() or Choice.isOpen() or CallWindow.isOpen() then
        n = n + 1
        if n % 4 == 0 then U.tap(game, "a") else U.wait(1) end
      else
        U.wait(1)
      end
    end
    return pred()
  end
  local battles = {}
  local function fight(label)
    for _ = 1, 600 do if Battle.isActive() then break end if Message.isOpen() then U.tap(game, "a") end U.wait(1) end
    if not check(Battle.isActive(), label .. " starts") then return false end
    local st0 = Battle._st
    local foeMon = st0 and st0.foeParty and st0.foeParty[1]
    battles[#battles + 1] = { trainerId = st0 and st0.trainerId, species = foeMon and foeMon.species }
    local ok = L.run(game, {})
    local st = Battle._st
    check(ok and st and st.result == "win", label .. " won (" .. tostring(st and st.result) .. ")")
    for _ = 1, 1200 do
      if not Battle.isActive() and not busy() then break end
      if Message.isOpen() or Choice.isOpen() then U.tap(game, "a") end
      U.wait(2)
    end
    return true
  end

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_SWAMPERT, 70, "SWAMPERT")
  setFlag("FLAG_SYS_POKENAV_GET")
  setFlag("FLAG_RECEIVED_POKENAV")
  setFlag("FLAG_HAS_MATCH_CALL")
  setFlag("FLAG_ADDED_MATCH_CALL_TO_POKENAV")

  local CINDY = C.trainers.byName.TRAINER_CINDY_1
  local CINDY_3 = C.trainers.byName.TRAINER_CINDY_3
  local idx = Rematch.firstBattleTableId(CINDY)
  check(idx == 10 and Rematch.trainerIds(idx)[2] == CINDY_3, "gRematchTable[REMATCH_CINDY] = { CINDY_1, CINDY_3, ... }")

  -- pokeemerald/data/maps/Route104/scripts.inc:924
  check(goTo("EM_ROUTE104", 11, 43, "down"), "Route 104 loads next to Cindy")
  U.tap(game, "a")
  if not fight("first battle with Cindy") then return finish() end
  mash(function() return not busy() end, 3000)
  check(Flags.getFlag(Space.store, nil, Flags.trainerFlagId(CINDY)), "TRAINER_CINDY_1 flag set after the win")
  check(Rematch.flag(session, Rematch.registeredFlagId(session, idx)), "register_matchcall registered Cindy (SetMatchCallRegisteredFlag)")
  still("01_cindy_registered")

  for i = 1, 5 do setFlag(string.format("FLAG_BADGE%02d_GET", i)) end
  local before = MatchCall.stepHookCalls or 0
  check(goTo("EM_PETALBURG_CITY", 15, 12, "left"), "Petalburg City loads (outdoor, not Cindy's route)")
  local Collision = require("src.core.game3.collision")
  local function open(x, y)
    local function can(fx, fy, tx, ty, dir)
      return Collision.canEnter(game, tx, ty, { fromX = fx, fromY = fy, dir = dir, elevation = Player.currentElevation })
    end
    return can(x, y, x - 1, y, "left") and can(x - 1, y, x, y, "right")
  end
  local spot
  for y = 8, 24 do
    for x = 6, 26 do
      if not spot and open(x, y) and open(x + 1, y) then spot = { x + 1, y } end
    end
  end
  if spot then goTo("EM_PETALBURG_CITY", spot[1], spot[2], "left") end
  print("[driver] walking spot " .. tostring(spot and (spot[1] .. "," .. spot[2])))
  Rng.SeedRng(0x2468)
  MatchCall.initCounters(session)
  local called, steps = false, 0
  local dirs = { "left", "right" }
  for i = 1, 200 do
    -- pokeemerald/src/match_call.c:1041
    if i % 10 == 9 then Rtc.advance(10) end
    local dir = dirs[(i % 2) + 1]
    U.hold(game, dir, 16)
    for _ = 1, 40 do if not Player.moving then break end U.wait(1) end
    steps = steps + 1
    if i == 1 then
      check((MatchCall.stepHookCalls or 0) > before, "step_events drives the match call step counter")
    end
    if CallWindow.isOpen() or StepEvents.busy() then called = true break end
    if i % 25 == 0 then
      local st = MatchCall._state or {}
      local def = MatchCall.currentDef() or {}
      print(string.format("[driver] step %d cell=%s,%s map=%s mc.steps=%s mc.minutes=%s now=%s allows=%s reg=%d type=%s sec=%s",
        i, tostring(Player.cellX), tostring(Player.cellY), tostring(mapNow()), tostring(st.stepCounter), tostring(st.minutes),
        tostring(MatchCall.totalMinutes(session)), tostring(MatchCall.mapAllowsMatchCall(session)),
        MatchCall.numRegisteredTrainers(session), tostring(def.mapType), tostring(def.regionMapSectionId)))
    end
  end
  for _ = 1, 60 do if CallWindow.isOpen() then break end U.wait(1) end
  check(called and CallWindow.isOpen(), "a match call rings within " .. steps .. " steps (seed 0x2468)")
  local last = MatchCall.lastCall
  check(last and last.trainerId == CINDY, "Cindy is the caller (" .. tostring(last and last.trainerId) .. ")")
  U.wait(12)
  still("02_call_window_slide_in")
  local cw = CallWindow.active()
  if not cw then return finish() end
  for _ = 1, 600 do
    if cw.state >= 6 then break end
    if cw.printer and cw.printer.state ~= "char" then U.tap(game, "a") end
    U.wait(1)
  end
  U.wait(40)
  still("03_call_message")
  local sel = cw.selected
  check(sel and sel.key and sel.key:find("DifferentRouteBattleRequest") ~= nil,
    "five badges: Cindy asks for a rematch (" .. tostring(sel and sel.key) .. ")")
  check(sel and sel.newRematchRequest == true, "the call is a new rematch request")
  for _ = 1, 1200 do
    if not CallWindow.isOpen() then break end
    if cw.printer and cw.printer.state ~= "char" then U.tap(game, "a") elseif cw.state == 6 then U.tap(game, "a") end
    U.wait(1)
  end
  check(not CallWindow.isOpen(), "the call hangs up")
  check(Rematch.get(session, idx) == 1, "trainerRematches[REMATCH_CINDY] = 1 after UpdateRematchIfDefeated")
  check(goTo("EM_ROUTE104", 11, 43, "down"), "back on Route 104")
  battles = {}
  U.tap(game, "a")
  if not fight("rematch with Cindy") then return finish() end
  local b = battles[#battles]
  check(b and b.trainerId == CINDY_3, "rematch battle uses the next party TRAINER_CINDY_3 (" .. tostring(b and b.trainerId) .. ")")
  local want = Trainers.get(CINDY_3)
  check(b and want and b.species == (want.party[1] and want.party[1].species), "foe lead is CINDY_3's first mon")
  mash(function() return not busy() end, 3000)
  check(Flags.getFlag(Space.store, nil, Flags.trainerFlagId(CINDY_3)), "TRAINER_CINDY_3 flag set after the rematch")
  check(Rematch.get(session, idx) == 0, "trainerRematches[REMATCH_CINDY] cleared after the rematch")
  still("04_after_rematch")

  -- pokeemerald/src/field_specials.c:353
  setFlag("FLAG_ENABLE_FIRST_WALLY_POKENAV_CALL")
  Flags.setVar(Space.store, nil, T.VAR_IDS.VAR_WALLY_CALL_STEP_COUNTER, 247)
  check(goTo("EM_PETALBURG_CITY", spot and spot[1] or 15, spot and spot[2] or 12, "left"), "back in Petalburg for Wally's call")
  local wallyWindow = false
  for i = 1, 6 do
    U.hold(game, dirs[(i % 2) + 1], 16)
    for _ = 1, 60 do
      if CallWindow.isOpen() then wallyWindow = true break end
      U.wait(1)
    end
    if wallyWindow then break end
  end
  check(wallyWindow, "VAR_WALLY_CALL_STEP_COUNTER reaching 250 starts MauvilleCity_EventScript_RegisterWallyCall")
  local wcw = CallWindow.active()
  check(wcw and wcw.text ~= nil, "pokenavcall opens the PokeNav call window with the script text")
  for _ = 1, 400 do
    if wcw and wcw.state >= 6 and not (wcw.printer and wcw.printer:isActive()) then break end
    if wcw and wcw.printer and wcw.printer.state ~= "char" then U.tap(game, "a") end
    U.wait(1)
  end
  still("05_wally_pokenavcall")
  local registered = mash(function() return flag("FLAG_ENABLE_WALLY_MATCH_CALL") and not busy() end, 4000)
  check(registered and not flag("FLAG_ENABLE_FIRST_WALLY_POKENAV_CALL"), "Wally's call registers him (FLAG_ENABLE_WALLY_MATCH_CALL)")
  still("06_after_wally_call")
  finish()
end
