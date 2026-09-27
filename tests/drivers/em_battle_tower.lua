local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

return function(game)
  local d = S.new("em_battle_tower", "/tmp/em_battle_tower")
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
  local Player = require("src.core.game3.player")
  local Battle = require("src.core.game3.battle")
  local PartyMenu = require("src.ui.game3.party_menu")
  local SaveMenu = require("src.ui.game3.save_menu")
  local Choice = require("src.ui.game3.choice")
  local Stack = require("src.ui.game3.stack")
  local Util = require("src.core.game3.rse.frontier.util")
  local D = require("src.core.game3.rse.frontier.trainers")
  local Records = require("src.ui.game3.rse.frontier_records")
  local Natives = require("src.core.game3.scripting.natives")
  local C = S.C()

  session = Runtime.getSession()
  if not check(session and session.version == "emerald" and S.flag("FLAG_SYS_GAME_CLEAR"),
      "post-game Emerald session (" .. tostring(session and session.name) .. ")") then return finish() end
  Natives.ensureBound(session)
  check(Natives.handlerFor("CallBattleTowerFunc") ~= nil and Natives.handlerFor("CallFrontierUtilFunc") ~= nil,
    "CallBattleTowerFunc / CallFrontierUtilFunc bound on Emerald")
  session.repelSteps = 0
  require("src.core.game3.encounters").onStep = function() return nil end

  local function tough(name, moves)
    local m = D.createMon(S.species(name), 50, 31, 0, tonumber(session.trainerId) or 0,
      { otName = session.name, moves = {} })
    local ms = {}
    for i, mv in ipairs(moves) do ms[i] = S.move(mv) end
    D.setMoves(m, ms)
    D.setEvs(m, { 252, 252, 6, 0, 0, 0 })
    m.otId, m.otName, m.ot = session.trainerId, session.name, session.name
    return m
  end
  session.party = {
    tough("SPECIES_METAGROSS", { "MOVE_METEOR_MASH", "MOVE_EARTHQUAKE", "MOVE_PSYCHIC", "MOVE_BRICK_BREAK" }),
    tough("SPECIES_SALAMENCE", { "MOVE_DRAGON_CLAW", "MOVE_EARTHQUAKE", "MOVE_FLAMETHROWER", "MOVE_AERIAL_ACE" }),
    tough("SPECIES_SWAMPERT", { "MOVE_SURF", "MOVE_EARTHQUAKE", "MOVE_ICE_BEAM", "MOVE_BRICK_BREAK" }),
    tough("SPECIES_LATIOS", { "MOVE_PSYCHIC", "MOVE_DRAGON_CLAW", "MOVE_THUNDERBOLT", "MOVE_ICE_BEAM" }),
  }
  local originalSpecies = {}
  for i, m in ipairs(session.party) do originalSpecies[i] = m.species end
  if not S.hasItem("ITEM_SS_TICKET") then S.giveItem("ITEM_SS_TICKET", 1) end
  S.setFlag("FLAG_MET_SCOTT_ON_SS_TIDAL", true)

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

  if not check(teleport("EM_LILYCOVE_CITY_HARBOR", 8, 12, "up"), "Lilycove harbor loads") then return finish() end
  local attendant = S.objectByScript("LilycoveCity_Harbor_EventScript_FerryAttendant")
  if not check(attendant ~= nil, "ferry attendant present") then return finish() end
  S.talkTo(game, attendant)
  local sawTidal = false
  S.settle(game, { limit = 20000, until_ = function() return S.mapNow() == "EM_BATTLE_FRONTIER_OUTSIDE_WEST" end,
    choice = function(ch)
      local opts = ch.options or {}
      for i, o in ipairs(opts) do
        local t = tostring(type(o) == "table" and (o.text or o.label or o[1]) or o)
        if t:upper():find("FRONTIER", 1, true) then
          if not sawTidal then
            sawTidal = true
            U.wait(4)
            shot("01_ss_tidal_destinations")
          end
          return i
        end
      end
      return "yes"
    end })
  check(sawTidal, "ScriptMenu_CreateLilycoveSSTidalMultichoice lists BATTLE FRONTIER after meeting Scott")
  if not check(S.mapNow() == "EM_BATTLE_FRONTIER_OUTSIDE_WEST", "the S.S. Tidal lands at the Battle Frontier ("
    .. tostring(S.mapNow()) .. ")") then return finish() end
  shot("02_frontier_arrival")

  S.travel(game, { "EM_BATTLE_FRONTIER_RECEPTION_GATE" }, { repel = false, settle = { limit = 20000 } })
  S.settle(game, { limit = 20000 })
  check(S.flag("FLAG_SYS_FRONTIER_PASS"), "the reception gate issues the FRONTIER PASS")
  S.travel(game, { { "EM_BATTLE_FRONTIER_OUTSIDE_WEST", arrive = { 26, 61 } }, "EM_BATTLE_FRONTIER_OUTSIDE_EAST",
    "EM_BATTLE_FRONTIER_BATTLE_TOWER_LOBBY" }, { repel = false, settle = { limit = 20000 } })
  if not check(S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_TOWER_LOBBY", "walked into the Battle Tower lobby ("
    .. tostring(S.mapNow()) .. ")") then return finish() end
  shot("03_tower_lobby")

  local f = Util.frontier(session)
  local bpBefore = tonumber(f.battlePoints) or 0
  local savedParty, partyOpened, savePrompted = false, false, false
  local battles = 0
  local battleInfo = {}
  local function idleUi()
    if PartyMenu.isOpen() and PartyMenu.mode == "choose_multi" then
      if not partyOpened then
        partyOpened = true
        U.wait(10)
        shot("04_choose_three")
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
      if not savePrompted then
        savePrompted = true
        shot("05_save_before_challenge")
      end
      U.tap(game, "a")
      U.wait(8)
      return true
    end
    return false
  end
  local attendantS = S.objectByScript("BattleFrontier_BattleTowerLobby_EventScript_SinglesAttendant")
  if not check(attendantS ~= nil, "singles attendant present") then return finish() end
  S.talkTo(game, attendantS)
  local shotBattle = false
  S.settle(game, {
    limit = 400000,
    until_ = function()
      return battles >= 7 and S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_TOWER_LOBBY" and not S.busy()
        and tonumber(f.challengeStatus) == 0 and Util.get2(f.towerRecordWinStreaks, 0, 0) > 0
    end,
    choice = function() return "yes" end,
    onIdleUi = idleUi,
    onBattleStart = function(st)
      battles = battles + 1
      local foe = st.enemy and st.enemy.mon
      battleInfo[battles] = { trainer = st.trainerName, level = foe and foe.level, kinds = st.kinds,
        streak = Util.get2(f.towerWinStreaks, 0, 0), transition = st.transitionId }
      note(string.format("battle %d vs %s (%s) foe lv %s", battles, tostring(st.trainerName),
        tostring(st.trainerClassName or st.trainerClass), tostring(foe and foe.level)))
      if not shotBattle then
        shotBattle = true
        S.pendingBattleShot = "06_tower_battle"
      end
    end,
    onBattleEnd = function(result)
      note("battle " .. battles .. " -> " .. tostring(result))
      if battles == 1 then shot("07_after_first_battle") end
    end,
  })
  check(partyOpened, "ChoosePartyForBattleFrontier opened the party menu for three mons")
  check(savePrompted, "the challenge saves the game before the elevator (SaveGame special)")
  check(battles == 7, "seven tower battles fought (" .. battles .. ")")
  local allL50, allFrontier = true, true
  for i, b in ipairs(battleInfo) do
    if b.level ~= 50 then allL50 = false end
    if not (b.kinds and b.kinds.frontier) then allFrontier = false end
    if b.streak ~= i - 1 then note("battle " .. i .. " started at streak " .. tostring(b.streak)) end
  end
  check(allL50, "every opponent mon is level 50")
  check(allFrontier, "every battle runs as a frontier battle")
  check(Util.get2(f.towerWinStreaks, 0, 0) == 7, "win streak is 7 (" .. Util.get2(f.towerWinStreaks, 0, 0) .. ")")
  check(Util.get2(f.towerRecordWinStreaks, 0, 0) == 7, "record streak saved as 7")
  check((tonumber(f.battlePoints) or 0) == bpBefore + 1, "7 wins in lv50 singles award 1 BP ("
    .. tostring(bpBefore) .. " -> " .. tostring(f.battlePoints) .. ")")
  check(#session.party == 4, "LoadPlayerParty restored the full party (" .. #session.party .. ")")
  local same = true
  for i, m in ipairs(session.party) do if m.species ~= originalSpecies[i] then same = false end end
  check(same, "party order unchanged after the challenge")
  check(S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_TOWER_LOBBY", "back in the lobby")
  check(tonumber(f.challengeStatus) == 0, "challenge status cleared by tower_save 0")
  shot("08_back_in_lobby")

  local persisted = love.filesystem.read("saves/emerald/slot1.lua")
  local ok, back = pcall(function() return SaveData.decode(persisted) end)
  local listed = false
  for _, e in ipairs(require("src.core.game3.profile").of("emerald").save.sections or {}) do
    local n = type(e) == "table" and e.name or e
    if n == "frontier" then listed = true end
  end
  if listed then
    local pf = ok and back and back.frontier
    check(pf and Util.get2(pf.towerRecordWinStreaks, 0, 0) == 7, "the tower record is in the saved file")
  else
    note("save section 'frontier' is not listed in profiles/emerald/save.lua yet (crossfile); session record = "
      .. Util.get2(f.towerRecordWinStreaks, 0, 0))
  end

  local Space = require("src.core.game3.scripting.space")
  local key = Space.bundle and Space.bundle.labels and Space.bundle.labels["BattleFrontier_BattleTowerLobby_EventScript_ShowSinglesResults"]
  local ev = Space.bundle and Space.bundle.events and Space.bundle.events[S.mapNow()]
  local bg
  for _, b in ipairs(ev and ev.bgEvents or {}) do
    if b.scriptKey == key then bg = b end
  end
  if check(bg ~= nil, "singles results sign found in the lobby") then
    S.goTo(game, { bg.x, bg.y + 1 })
    S.face(game, "up")
    U.tap(game, "a")
    for _ = 1, 120 do
      if Records.isOpen() then break end
      U.wait(1)
    end
    U.wait(10)
    check(Records.isOpen(), "the singles results board opens the records window")
    shot("09_singles_results")
    for _ = 1, 20 do
      if not Records.isOpen() then break end
      U.tap(game, "a")
      U.wait(10)
    end
    S.settle(game, { limit = 2000 })
    check(not Records.isOpen(), "A dismisses the board and RemoveRecordsWindow closes it")
  end
  local StartMenu = require("src.ui.game3.start_menu")
  local Pass = require("src.ui.game3.rse.frontier_pass")
  S.settle(game)
  U.tap(game, "start")
  U.wait(20)
  local idx
  for i, e in ipairs(StartMenu.ENTRIES or {}) do if e.id == "trainer" then idx = i end end
  if check(StartMenu.isOpen() and idx ~= nil, "start menu open with the player entry") then
    for _ = 1, 10 do
      if StartMenu.cursor == idx then break end
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    for _ = 1, 120 do
      if Pass.isOpen() and Pass._st.phase == "input" then break end
      U.wait(1)
    end
    check(Pass.isOpen(), "the PLAYER entry opens the FRONTIER PASS once FLAG_SYS_FRONTIER_PASS is set")
    check(Pass._st.battlePoints == tonumber(f.battlePoints), "the pass shows the Battle Points (" .. tostring(Pass._st.battlePoints) .. ")")
    check(Pass._st.cursorArea == Pass.AREA.MAP, "inside the frontier the cursor starts on the map (frontier_pass.c:634)")
    U.wait(10)
    shot("10_frontier_pass")
    U.tap(game, "a")
    for _ = 1, 200 do
      if Pass.Map.active and Pass.Map.state == "input" then break end
      U.wait(1)
    end
    check(Pass.Map.active, "A on the map area opens the Frontier map")
    U.tap(game, "down")
    U.wait(20)
    check(Pass.Map.pos == 1, "down moves the facility cursor to the Battle Dome")
    shot("11_frontier_map")
    U.tap(game, "b")
    for _ = 1, 200 do
      if not Pass.Map.active and Pass._st.phase == "input" then break end
      U.wait(1)
    end
    check(not Pass.Map.active and Pass._st.phase == "input", "B returns from the map to the pass")
    U.tap(game, "b")
    for _ = 1, 200 do
      if not Pass.isOpen() then break end
      U.wait(1)
    end
    check(not Pass.isOpen(), "B puts the pass away")
    for _ = 1, 20 do
      if not StartMenu.isOpen() then break end
      U.tap(game, "b")
      U.wait(10)
    end
  end

  local kept, apprentice = {}, 0
  for _, l in ipairs(d.vmLogs) do
    if l:find("CallApprenticeFunction", 1, true) then apprentice = apprentice + 1 else kept[#kept + 1] = l end
  end
  d.vmLogs = kept
  note("apprentice special logs outside f1 scope: " .. apprentice)
  finish()
end
