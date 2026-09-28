local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

return function(game)
  local d = S.new("em_battle_pyramid", "/tmp/em_battle_pyramid")
  local check, note = d.check, d.note
  local function shot(name) d.shot(game, name) end
  local function finish() return d.finish() end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end

  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local raw = love.filesystem.read("saves/emerald/slot1.lua")
  if not check(type(raw) == "string", "identity has the post-Hall-of-Fame save") then return finish() end
  local session = Schema.fromSaveTable(SaveData.decode(raw))
  require("src.core.game3.options").bind(session, game.options)
  game:adoptSave(session, true)
  game.sessionStartedAt = os.time()
  game:_enterField(session, "continue")
  U.wait(30)
  S.settle(game)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Natives = require("src.core.game3.scripting.natives")
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  local PartyMenu = require("src.ui.game3.party_menu")
  local SaveMenu = require("src.ui.game3.save_menu")
  local StartMenu = require("src.ui.game3.start_menu")
  local Message = require("src.ui.game3.message")
  session = Runtime.getSession()
  Natives.ensureBound(session)
  require("tests.drivers.em_f4_hooks").install()
  local Py = require("src.core.game3.rse.frontier.pyramid")
  local Util = require("src.core.game3.rse.frontier.util")
  local D = require("src.core.game3.rse.frontier.trainers")
  local C = S.C()
  check(Natives.handlerFor("CallBattlePyramidFunction") ~= nil, "CallBattlePyramidFunction bound on Emerald")
  session.repelSteps = 0

  local function tough(name, moves)
    local m = D.createMon(S.species(name), 50, 31, 0, tonumber(session.trainerId) or 0, { otName = session.name })
    local ms = {}
    for i, mv in ipairs(moves) do ms[i] = S.move(mv) end
    D.setMoves(m, ms)
    D.setEvs(m, { 252, 252, 6, 0, 0, 0 })
    m.otId, m.otName, m.ot = session.trainerId, session.name, session.name
    return m
  end
  session.party = {
    tough("SPECIES_METAGROSS", { "MOVE_METEOR_MASH", "MOVE_EARTHQUAKE", "MOVE_PSYCHIC", "MOVE_SHADOW_BALL" }),
    tough("SPECIES_SALAMENCE", { "MOVE_DRAGON_CLAW", "MOVE_EARTHQUAKE", "MOVE_FLAMETHROWER", "MOVE_AERIAL_ACE" }),
    tough("SPECIES_SWAMPERT", { "MOVE_SURF", "MOVE_EARTHQUAKE", "MOVE_ICE_BEAM", "MOVE_BRICK_BREAK" }),
  }

  local function teleport(mapId, x, y, facing)
    S.settle(game)
    local ok, err = pcall(function() Map.load(nil, game, mapId, { x = x, y = y, facing = facing }) end)
    if not ok then note("Map.load " .. mapId .. ": " .. tostring(err)) end
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    U.wait(30)
    S.settle(game)
    return ok
  end

  if not check(teleport("EM_BATTLE_FRONTIER_BATTLE_PYRAMID_LOBBY", 7, 14, "up"), "Battle Pyramid lobby loads") then
    return finish()
  end
  shot("01_pyramid_lobby")
  local f = Util.frontier(session)
  local partyOpened, savePrompted = false, false
  local function idleUi()
    if PartyMenu.isOpen() and PartyMenu.mode == "choose_multi" then
      if not partyOpened then
        partyOpened = true
        U.wait(10)
        shot("02_choose_three")
      end
      for _, slot in ipairs({ 1, 2, 3 }) do
        PartyMenu.enterChosenMon(slot)
        U.wait(4)
      end
      PartyMenu.confirmChosenMons()
      U.wait(10)
      return true
    end
    if SaveMenu.isOpen() then
      savePrompted = true
      U.tap(game, "a")
      U.wait(8)
      return true
    end
    return false
  end
  local attendant = S.objectByScript("BattleFrontier_BattlePyramidLobby_EventScript_Attendant")
  if not check(attendant ~= nil, "pyramid attendant present") then return finish() end
  S.talkTo(game, attendant)
  S.settle(game, { limit = 30000, until_ = function() return S.mapNow() == Py.FLOOR_MAP and not S.busy() end,
    choice = function() return "yes" end, onIdleUi = idleUi })
  check(partyOpened, "ChoosePartyForBattleFrontier picks three mons")
  check(savePrompted, "the challenge saves before entering")
  if not check(S.mapNow() == Py.FLOOR_MAP, "warped onto the first Pyramid floor (" .. tostring(S.mapNow()) .. ")") then
    return finish()
  end
  U.wait(60)
  S.settle(game)
  local def = Map._def
  check(def and def.midLayout and def.midLayout.width == 32 and def.midLayout.height == 32,
    "the floor layout is composed to 32x32 from four by four squares (battle_pyramid.c:1523)")
  local en, ex = Py.entranceAndExit(session)
  check(math.floor(Player.cellX / 8) + math.floor(Player.cellY / 8) * 4 == en,
    "the player arrives in the entrance square " .. en .. " at " .. Player.cellX .. "," .. Player.cellY)
  local tpl = Py.floorTemplate(session)
  local trainers, balls = 0, 0
  local ball = C:require("event_objects", "OBJ_EVENT_GFX_ITEM_BALL")
  for _, lid in ipairs(Objects._order or {}) do
    local eo = Objects.find(lid)
    if eo and not eo.hidden then
      if tonumber(eo.graphicsId) == ball then balls = balls + 1 else trainers = trainers + 1 end
    end
  end
  check(trainers == tpl.numTrainers and balls == tpl.numItems, "floor spawns " .. tpl.numTrainers .. " trainers and "
    .. tpl.numItems .. " item balls (" .. trainers .. "/" .. balls .. ")")
  check(f.pyramidLightRadius >= 32, "OnTransition sets the pyramid light radius (" .. tostring(f.pyramidLightRadius) .. ")")
  shot("03_floor1_arrival")
  check(Py.bagHas(session, S.item("ITEM_HYPER_POTION"), 1) and Py.bagHas(session, S.item("ITEM_ETHER"), 1),
    "the battle bag starts with a Hyper Potion and an Ether (battle_pyramid.c:1809)")

  local function nearestObject(isBall)
    local best, bd
    for _, lid in ipairs(Objects._order or {}) do
      local eo = Objects.find(lid)
      if eo and not eo.hidden and ((tonumber(eo.graphicsId) == ball) == isBall) and eo.cellX < 1000 then
        local dd = math.abs(eo.cellX - Player.cellX) + math.abs(eo.cellY - Player.cellY)
        if not bd or dd < bd then best, bd = eo, dd end
      end
    end
    return best
  end

  local battles, wild, trainerBattles = 0, 0, 0
  local battleBagProbe = "pending"
  local Battle = require("src.core.game3.battle")
  local BattleUi = require("src.core.game3.battle.ui")
  local PyramidBag = require("src.ui.game3.rse.pyramid_bag")
  local function onBattleFrame()
    if battleBagProbe == "pending" and Battle._phase == "command" and BattleUi._mode == "menu" then
      battleBagProbe = "opening"
      BattleUi._menuIndex = 2
      U.tap(game, "a")
    elseif battleBagProbe == "opening" and PyramidBag.isOpen() then
      battleBagProbe = "opened"
      check(PyramidBag._st and PyramidBag._st.location == "battle",
        "the active battle opens the dedicated Pyramid bag in battle mode")
      shot("04_pyramid_battle_bag")
      U.wait(30)
      U.tap(game, "b")
    elseif battleBagProbe == "opened" and not PyramidBag.isOpen() then
      battleBagProbe = "closed"
    end
  end
  local function onBattleStart(st)
    battles = battles + 1
    if st.wild or st.kinds and st.kinds.wild then wild = wild + 1 else trainerBattles = trainerBattles + 1 end
    if battles == 1 then S.pendingBattleShot = "04_pyramid_battle" end
  end

  local bagBefore = 0
  for _, id in ipairs(Py.bagLists(session)) do if id ~= 0 then bagBefore = bagBefore + 1 end end
  local itemBall = nearestObject(true)
  if check(itemBall ~= nil, "an item ball is on the floor") then
    local itemsLeft = Py.remainingItems(session)
    S.talkTo(game, itemBall, { settle = { onBattleStart = onBattleStart, onBattleFrame = onBattleFrame } })
    S.settle(game, { limit = 6000, onBattleStart = onBattleStart, onBattleFrame = onBattleFrame })
    check(Py.remainingItems(session) == itemsLeft - 1, "pyramid_hideitem removes the picked ball (" ..
      Py.remainingItems(session) .. ")")
    local bagAfter = 0
    for _, id in ipairs(Py.bagLists(session)) do if id ~= 0 then bagAfter = bagAfter + 1 end end
    check(bagAfter >= bagBefore, "the found item goes into the pyramid bag")
  end

  local foe = nearestObject(false)
  if check(foe ~= nil, "a pyramid trainer is on the floor") then
    local lid = foe.localId
    local left = Py.remainingTrainers(session)
    local sawHint = false
    S.talkTo(game, foe, { settle = { onBattleStart = onBattleStart, onBattleFrame = onBattleFrame } })
    S.settle(game, { limit = 30000, onBattleStart = onBattleStart, onBattleFrame = onBattleFrame, watch = function()
      if not sawHint and Message.isOpen() and trainerBattles > 0 and not require("src.core.game3.battle").isActive() then
        sawHint = true
        U.wait(20)
        shot("05_post_battle_hint")
      end
    end })
    check(trainerBattles >= 1, "BattlePyramid_TrainerBattle starts a one-mon frontier battle")
    check(Py.trainerFlag(session, lid), "the trainer is marked battled (battle_pyramid.c:1394)")
    check(Py.remainingTrainers(session) == left - 1, "one fewer trainer remains")
    check(sawHint, "pyramid_showhint prints a post-battle hint")
    check(f.pyramidLightRadius > 32, "winning widens the light radius (" .. tostring(f.pyramidLightRadius) .. ")")
  end
  check(battleBagProbe == "closed", "B closes the Pyramid bag back to the battle command menu")

  U.tap(game, "start")
  U.wait(20)
  local bagIdx
  for i, e in ipairs(StartMenu.ENTRIES or {}) do if e.id == "pyramid_bag" then bagIdx = i end end
  if check(StartMenu.isOpen() and bagIdx ~= nil, "the pyramid start menu lists BATTLE BAG") then
    shot("06_pyramid_start_menu")
    for _ = 1, 10 do
      if StartMenu.cursor == bagIdx then break end
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    local PBag = require("src.ui.game3.rse.pyramid_bag")
    for _ = 1, 120 do
      if PBag.isOpen() then break end
      U.wait(1)
    end
    U.wait(30)
    check(PBag.isOpen(), "the pyramid bag screen opens")
    shot("07_pyramid_bag")
    U.tap(game, "a")
    U.wait(20)
    check(PBag._st.mode == "action", "A on an item opens USE/GIVE/TOSS/CANCEL")
    shot("08_pyramid_bag_actions")
    U.tap(game, "b")
    U.wait(10)
    U.tap(game, "b")
    for _ = 1, 120 do
      if not PBag.isOpen() then break end
      U.wait(1)
    end
    check(not PBag.isOpen(), "B closes the pyramid bag")
    for _ = 1, 20 do
      if not StartMenu.isOpen() then break end
      U.tap(game, "b")
      U.wait(10)
    end
  end

  local exitMid = C:require("metatile_labels", "METATILE_BattlePyramid_Exit")
  local exitX, exitY
  local L = Map._def and Map._def.midLayout
  for y = 0, 31 do
    for x = 0, 31 do
      if L and L:midAt(x, y) == exitMid then exitX, exitY = x, y end
    end
  end
  if check(exitX ~= nil, "the floor has one exit tile in square " .. ex) then
    local floorBefore = tonumber(f.curChallengeBattleNum) or 0
    local streakBefore = Util.get1(f.pyramidWinStreaks, f.lvlMode)
    S.goTo(game, { exitX, exitY }, { settle = { onBattleStart = onBattleStart } })
    local Collision = require("src.core.game3.collision")
    note(string.format("exit at %d,%d player %d,%d beh %s want %s", exitX, exitY, Player.cellX, Player.cellY,
      tostring(Collision.behavior(exitX, exitY)), tostring(require("src.core.game3.mb").id("BATTLE_PYRAMID_WARP"))))
    note("warp script key " .. tostring(Py.scriptKey("BattlePyramid_WarpToNextFloor")) .. " floor " .. tostring(f.curChallengeBattleNum)
      .. " busy " .. tostring(S.busy()) .. " vm " .. S.vmWhere())
    S.settle(game, { limit = 30000, onBattleStart = onBattleStart,
      until_ = function() return (tonumber(f.curChallengeBattleNum) or 0) > floorBefore and not S.busy() end })
    check((tonumber(f.curChallengeBattleNum) or 0) == floorBefore + 1, "stepping on the exit runs BattlePyramid_WarpToNextFloor")
    check(Util.get1(f.pyramidWinStreaks, f.lvlMode) == streakBefore + 1, "clearing a floor adds a win")
    check(S.mapNow() == Py.FLOOR_MAP, "the next floor is generated")
    U.wait(60)
    shot("09_floor2")
  end
  note(string.format("battles %d (wild %d, trainer %d)", battles, wild, trainerBattles))

  U.tap(game, "start")
  U.wait(20)
  local retIdx
  for i, e in ipairs(StartMenu.ENTRIES or {}) do if e.id == "retire_frontier" then retIdx = i end end
  if check(StartMenu.isOpen() and retIdx ~= nil, "the pyramid start menu lists RETIRE") then
    for _ = 1, 10 do
      if StartMenu.cursor == retIdx then break end
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    S.settle(game, { limit = 30000, choice = function() return 1 end,
      until_ = function() return S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_PYRAMID_LOBBY" and not S.busy() end })
    check(S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_PYRAMID_LOBBY", "retiring warps back to the lobby")
    S.settle(game, { limit = 20000 })
    check(#session.party >= 3, "LoadPlayerParty restores the party")
    shot("10_back_in_lobby")
  end
  finish()
end
