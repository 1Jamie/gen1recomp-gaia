local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

return function(game)
  local d = S.new("em_battle_pike", "/tmp/em_battle_pike")
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
  local Field = require("src.core.game3.field")
  local PartyMenu = require("src.ui.game3.party_menu")
  local SaveMenu = require("src.ui.game3.save_menu")
  local Stack = require("src.ui.game3.stack")
  local Message = require("src.ui.game3.message")
  local Util = require("src.core.game3.rse.frontier.util")
  local D = require("src.core.game3.rse.frontier.trainers")
  local Pike = require("src.core.game3.rse.frontier.pike")
  local Natives = require("src.core.game3.scripting.natives")
  local Rng = require("src.core.game3.rng")
  local C = S.C()

  session = Runtime.getSession()
  if not check(session and session.version == "emerald" and S.flag("FLAG_SYS_GAME_CLEAR"),
      "post-game Emerald session") then return finish() end
  Natives.ensureBound(session)
  check(Natives.handlerFor("CallBattlePikeFunction") ~= nil and Natives.handlerFor("CloseBattlePikeCurtain") ~= nil,
    "CallBattlePikeFunction / CloseBattlePikeCurtain bound on Emerald")
  session.repelSteps = 0

  local function tough(name, moves, item)
    local m = D.createMon(S.species(name), 50, 31, 0, tonumber(session.trainerId) or 0,
      { otName = session.name, moves = {} })
    local ms = {}
    for i, mv in ipairs(moves) do ms[i] = S.move(mv) end
    D.setMoves(m, ms)
    D.setEvs(m, { 252, 252, 6, 0, 0, 0 })
    D.setHeldItem(m, item and S.item(item) or 0)
    m.otId, m.otName, m.ot = session.trainerId, session.name, session.name
    return m
  end
  session.party = {
    tough("SPECIES_METAGROSS", { "MOVE_METEOR_MASH", "MOVE_EARTHQUAKE", "MOVE_PSYCHIC", "MOVE_BRICK_BREAK" }, "ITEM_LEFTOVERS"),
    tough("SPECIES_SALAMENCE", { "MOVE_DRAGON_CLAW", "MOVE_EARTHQUAKE", "MOVE_FLAMETHROWER", "MOVE_AERIAL_ACE" }),
    tough("SPECIES_SWAMPERT", { "MOVE_SURF", "MOVE_EARTHQUAKE", "MOVE_ICE_BEAM", "MOVE_BRICK_BREAK" }, "ITEM_SHELL_BELL"),
    tough("SPECIES_LATIOS", { "MOVE_PSYCHIC", "MOVE_DRAGON_CLAW", "MOVE_THUNDERBOLT", "MOVE_ICE_BEAM" }),
  }
  local original = {}
  for i, m in ipairs(session.party) do original[i] = { species = m.species, item = tonumber(m.heldItem) or 0 } end

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

  if not check(teleport("EM_BATTLE_FRONTIER_BATTLE_PIKE_LOBBY", 5, 10, "up"), "Battle Pike lobby loads") then
    return finish()
  end
  shot("01_pike_lobby")
  local f = Util.frontier(session)

  local curtainStart = C:require("metatile_labels", "METATILE_BattlePike_CurtainFrames_Start")
  local curtainSeen, flashSeen = {}, false
  local function watch()
    local bucket = Field.metatileOverrides[S.mapNow()]
    if bucket then
      for _, o in pairs(bucket) do
        local off = (tonumber(o.metatile) or 0) - curtainStart
        if off >= 0 and off < 3 * 4 * 8 then curtainSeen[S.mapNow()] = true end
      end
    end
    if Stack.has("rse_pike_status_flash") and not flashSeen then
      flashSeen = true
      shot("06_status_flash")
    end
  end

  local partyShot, saveSeen = false, false
  local function idleUi()
    if PartyMenu.isOpen() and PartyMenu.mode == "choose_multi" then
      if not partyShot then
        partyShot = true
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
      saveSeen = true
      U.tap(game, "a")
      U.wait(8)
      return true
    end
    return false
  end

  local battles = {}
  local function onBattleStart(st)
    local foe = st.enemy and st.enemy.mon
    local rec = { map = S.mapNow(), wild = st.wild, double = st.double, kinds = st.kinds, species = foe and foe.species,
      trainerB = st.trainerB,
      level = foe and foe.level, moves = foe and foe.moves and #foe.moves or 0, room = Pike.rt(session).roomType,
      foeCount = st.enemyParty and #st.enemyParty }
    battles[#battles + 1] = rec
    note(string.format("pike battle %d (%s) wild=%s double=%s foe %s lv %s", #battles, tostring(rec.room),
      tostring(rec.wild), tostring(rec.double), tostring(rec.species), tostring(rec.level)))
  end
  local function choiceFor(answers)
    return function()
      local page = tostring(Message.currentPage and Message.currentPage() or ""):upper()
      for key, ans in pairs(answers) do
        if page:find(key, 1, true) then return ans end
      end
      return "yes"
    end
  end

  local att = S.objectByScript("BattleFrontier_BattlePikeLobby_EventScript_Attendant")
  if not check(att ~= nil, "pike attendant present") then return finish() end
  Rng.SeedRng(tonumber(os.getenv("EM_F3_SEED") or "") or 0x71)
  S.talkTo(game, att)
  S.settle(game, {
    limit = 200000,
    until_ = function() return S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_PIKE_THREE_PATH_ROOM" and not S.busy() end,
    choice = choiceFor({}),
    onIdleUi = idleUi,
    watch = watch,
    onBattleStart = onBattleStart,
  })
  check(partyShot, "ChoosePartyForBattleFrontier picked three mons")
  check(saveSeen, "the Pike saves before the challenge")
  check(curtainSeen.EM_BATTLE_FRONTIER_BATTLE_PIKE_LOBBY or curtainSeen.EM_BATTLE_FRONTIER_BATTLE_PIKE_CORRIDOR,
    "CloseBattlePikeCurtain swaps in the curtain metatiles (field_specials.c:3841)")
  if not check(S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_PIKE_THREE_PATH_ROOM", "reached the three-path room ("
      .. tostring(S.mapNow()) .. ")") then return finish() end
  check(#session.party == 3, "the challenge runs with the three chosen mons")
  check(tonumber(f.curChallengeBattleNum) == 1, "the corridor starts at room 1 (" .. tostring(f.curChallengeBattleNum) .. ")")
  shot("03_three_path_room")

  local R = Pike.ROOM
  local plan = { R.SINGLE_BATTLE, R.STATUS, R.WILD_MONS, R.HEAL_FULL, R.DOUBLE_BATTLE, R.HARD_BATTLE }
  local visited = {}
  local statusAfter, healedAfter = nil, nil
  local wildBattles = 0
  local streak0 = Util.get1(f.pikeWinStreaks, 0)
  for i, roomType in ipairs(plan) do
    S.settle(game)
    local pf = Pike.frontier(session)
    pf.pikeHintedRoomType = roomType
    pf.pikeHintedRoomIndex = Pike.PATH.CENTER
    if roomType == R.STATUS then
      for _, m in ipairs(session.party) do m.status, m.sleep = nil, nil end
    end
    S.goTo(game, { 6, 3 }, { settle = { choice = choiceFor({}), onBattleStart = onBattleStart, watch = watch } })
    S.settle(game, { limit = 60000, choice = choiceFor({}), onBattleStart = onBattleStart, watch = watch, onIdleUi = idleUi })
    local mapNow = S.mapNow()
    visited[i] = { type = Pike.rt(session).roomType, map = mapNow }
    note("room " .. i .. " type " .. tostring(Pike.rt(session).roomType) .. " on " .. tostring(mapNow))
    if i == 1 then shot("04_pike_room") end
    if roomType == R.STATUS then
      statusAfter = 0
      for _, m in ipairs(session.party) do if Pike.hasAilment(m) then statusAfter = statusAfter + 1 end end
      shot("07_status_room_after")
    elseif roomType == R.HEAL_FULL then
      healedAfter = Pike.isPartyFullHealed(session)
    elseif roomType == R.WILD_MONS then
      shot("08_wild_room")
      local steps = 0
      for trip = 1, 12 do
        if wildBattles > 0 or S.mapNow() ~= Pike.WILD_ROOM then break end
        local target = (trip % 2 == 1) and { 4, 9 } or { 4, 17 }
        S.goTo(game, target, { settle = { choice = choiceFor({}), onBattleStart = onBattleStart, watch = watch } })
        S.settle(game, { limit = 60000, onBattleStart = onBattleStart, choice = choiceFor({}) })
        steps = steps + 8
        wildBattles = 0
        for _, b in ipairs(battles) do if b.wild and b.map == Pike.WILD_ROOM then wildBattles = wildBattles + 1 end end
      end
      note("wild room: " .. steps .. " steps, " .. wildBattles .. " wild battles")
    end
    if S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_PIKE_LOBBY" then
      note("challenge ended in room " .. i)
      break
    end
    local exitOk = S.goTo(game, { 4, 3 }, { settle = { choice = choiceFor({}), onBattleStart = onBattleStart, watch = watch },
      tries = 40 })
    S.settle(game, { limit = 60000, choice = choiceFor({}), onBattleStart = onBattleStart, watch = watch })
    note("room " .. i .. " exit -> " .. tostring(S.mapNow()) .. " (" .. tostring(exitOk) .. ")")
    if S.mapNow() ~= "EM_BATTLE_FRONTIER_BATTLE_PIKE_THREE_PATH_ROOM" then break end
  end
  local rooms = 0
  for i, v in ipairs(visited) do
    if v.type == plan[i] then rooms = rooms + 1 end
  end
  check(rooms >= 3, "the hinted path leads into the hinted room type (" .. rooms .. " of " .. #visited .. ")")
  local single, double = nil, nil
  for _, b in ipairs(battles) do
    if b.room == R.SINGLE_BATTLE and not b.wild then single = b end
    if b.room == R.DOUBLE_BATTLE and not b.wild then double = b end
  end
  check(single ~= nil and single.level == 50 and single.kinds and single.kinds.frontier,
    "single battle room: a level-50 frontier trainer battle (battle_tower.c:2101)")
  if statusAfter ~= nil then
    check(statusAfter >= 1, "status room inflicts a status on the party (" .. statusAfter .. ")")
    check(flashSeen, "pike_flashscreen runs the status screen flash (battle_pike.c:1242)")
  end
  wildBattles = 0
  for _, b in ipairs(battles) do if b.wild and b.map == Pike.WILD_ROOM then wildBattles = wildBattles + 1 end end
  check(wildBattles >= 1, "the wild room starts pike wild battles (wild_encounter.c:563) (" .. wildBattles .. ")")
  local wildOk = false
  for _, b in ipairs(battles) do
    if b.wild and (b.species == S.species("SPECIES_SEVIPER") or b.species == S.species("SPECIES_MILOTIC")
        or b.species == S.species("SPECIES_DUSCLOPS")) and (b.level == 45 or b.level == 46) and b.moves == 4 then
      wildOk = true
    end
  end
  check(wildOk, "pike wild mons are gBattlePike_1 species at 50 - levelDelta with fixed moves (battle_pike.c:1135)")
  if healedAfter ~= nil then check(healedAfter, "full-heal room restores the party (battle_pike.c:1551)") end
  local hard = nil
  for _, b in ipairs(battles) do if b.room == R.HARD_BATTLE and not b.wild then hard = b end end
  if hard then check(hard.level == 50, "hard battle room fights a level-50 trainer (battle_pike.c:1387)") end
  check(double ~= nil and double.double == true, "double battle room starts a double battle")
  check(double ~= nil and double.trainerB ~= nil and (double.trainerB.name or "") ~= "",
    "the double battle room pairs two frontier trainers (battle_tower.c:1620)")
  check(Util.get1(f.pikeWinStreaks, 0) > streak0, "each room advances the pike streak ("
    .. streak0 .. " -> " .. Util.get1(f.pikeWinStreaks, 0) .. ")")

  if S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_PIKE_THREE_PATH_ROOM" then
    local attendant = S.objectByScript("BattleFrontier_BattlePikeThreePathRoom_EventScript_Attendant")
    if check(attendant ~= nil, "three-path attendant present") then
      S.talkTo(game, attendant)
      S.settle(game, {
        limit = 200000,
        until_ = function() return S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_PIKE_LOBBY" and not S.busy()
          and tonumber(f.challengeStatus) == 0 end,
        choice = choiceFor({ ["CONTINUE"] = "no", ["SAVE"] = "no", ["RETIRE"] = 1 }),
        onIdleUi = idleUi,
      })
    end
  end
  check(S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_PIKE_LOBBY", "back in the Pike lobby")
  check(tonumber(f.challengeStatus) == 0, "pike_save 0 clears the challenge status")
  local restored = #session.party == #original
  for i, o in ipairs(original) do
    local m = session.party[i]
    if not m or m.species ~= o.species or (tonumber(m.heldItem) or 0) ~= o.item then restored = false end
  end
  check(restored, "LoadPlayerParty + pike_resethelditems restore the party and items (battle_pike.c:1602)")
  check(Util.get1(f.pikeRecordStreaks, 0) >= 1, "record streak saved (" .. Util.get1(f.pikeRecordStreaks, 0) .. ")")
  shot("09_back_in_lobby")
  return finish()
end
