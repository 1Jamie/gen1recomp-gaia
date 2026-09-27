local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

return function(game)
  local d = S.new("em_battle_tent", "/tmp/em_battle_tent")
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
  local PartyMenu = require("src.ui.game3.party_menu")
  local SaveMenu = require("src.ui.game3.save_menu")
  local Util = require("src.core.game3.rse.frontier.util")
  local D = require("src.core.game3.rse.frontier.trainers")
  local Space = require("src.core.game3.scripting.space")
  local Rse = require("src.core.game3.rse.init")

  session = Runtime.getSession()
  if not check(session and session.version == "emerald", "Emerald session") then return finish() end
  require("src.core.game3.encounters").onStep = function() return nil end

  local function tough(name, level, moves)
    local m = D.createMon(S.species(name), level, 31, 0, tonumber(session.trainerId) or 0, { otName = session.name, moves = {} })
    local ms = {}
    for i, mv in ipairs(moves) do ms[i] = S.move(mv) end
    D.setMoves(m, ms)
    D.setEvs(m, { 252, 252, 6, 0, 0, 0 })
    m.otId, m.otName, m.ot = session.trainerId, session.name, session.name
    return m
  end
  session.party = {
    tough("SPECIES_METAGROSS", 40, { "MOVE_METEOR_MASH", "MOVE_EARTHQUAKE", "MOVE_PSYCHIC", "MOVE_BRICK_BREAK" }),
    tough("SPECIES_SALAMENCE", 40, { "MOVE_DRAGON_CLAW", "MOVE_EARTHQUAKE", "MOVE_FLAMETHROWER", "MOVE_AERIAL_ACE" }),
    tough("SPECIES_SWAMPERT", 40, { "MOVE_SURF", "MOVE_EARTHQUAKE", "MOVE_ICE_BEAM", "MOVE_BRICK_BREAK" }),
  }
  local f = Util.frontier(session)

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

  local partyShot, saveSeen = false, false
  local function idleUi(tag)
    return function()
      if PartyMenu.isOpen() and PartyMenu.mode == "choose_multi" then
        if not partyShot then
          partyShot = true
          U.wait(10)
          shot(tag .. "_choose_three")
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
  end

  if check(teleport("EM_VERDANTURF_TOWN", 3, 8, "up"), "Verdanturf Town loads outside the tent") then
    S.travel(game, { "EM_VERDANTURF_TOWN_BATTLE_TENT_LOBBY" }, { repel = false, settle = { limit = 8000 } })
    check(S.mapNow() == "EM_VERDANTURF_TOWN_BATTLE_TENT_LOBBY", "walked into the Verdanturf Battle Tent")
    shot("04_verdanturf_tent_lobby")
    local att = S.objectByScript("VerdanturfTown_BattleTentLobby_EventScript_Attendant")
    local Bag = require("src.core.game3.bag")
    local function nests()
      local n = 0
      while n < 999 and Bag.has(session.bag, S.item("ITEM_NEST_BALL"), n + 1) do n = n + 1 end
      return n
    end
    local nestBefore = nests()
    local battles, info = 0, {}
    if check(att ~= nil, "Verdanturf tent attendant present") then
      S.talkTo(game, att)
      S.settle(game, {
        limit = 400000,
        until_ = function()
          return battles >= 3 and S.mapNow() == "EM_VERDANTURF_TOWN_BATTLE_TENT_LOBBY" and not S.busy()
            and tonumber(f.challengeStatus) == 0 and (tonumber(f.verdanturfTentPrize) or 0) == 0
        end,
        choice = function() return "yes" end,
        onIdleUi = idleUi("05"),
        onBattleStart = function(st)
          battles = battles + 1
          local foe = st.enemy and st.enemy.mon
          info[battles] = { level = foe and foe.level, kinds = st.kinds, name = st.trainerName }
          note(string.format("tent battle %d vs %s foe lv %s", battles, tostring(st.trainerName), tostring(foe and foe.level)))
          if battles == 1 then S.pendingBattleShot = "06_verdanturf_battle" end
        end,
      })
      check(saveSeen, "the Verdanturf tent saves before the challenge")
      check(battles == 3, "three tent battles (" .. battles .. ")")
      local lvOk, palace = true, true
      for _, b in ipairs(info) do
        if b.level ~= 40 then lvOk = false end
        if not (b.kinds and b.kinds.frontier) then palace = false end
      end
      check(lvOk, "tent opponents match the party's highest level (battle_tower.c:3354)")
      check(palace, "tent battles run as frontier battles")
      check(nests() == nestBefore + 1, "three wins earn the Nest Ball prize (battle_tent.c:73) (" .. nestBefore .. " -> "
        .. nests() .. ")")
      check(#session.party == 3, "party restored after the challenge (" .. #session.party .. ")")
      shot("07_verdanturf_after")
    end
  end
  partyShot, saveSeen = false, false
  if check(teleport("EM_SLATEPORT_CITY", 10, 13, "up"), "Slateport City loads outside the tent") then
    S.travel(game, { "EM_SLATEPORT_CITY_BATTLE_TENT_LOBBY" }, { repel = false, settle = { limit = 8000 } })
    check(S.mapNow() == "EM_SLATEPORT_CITY_BATTLE_TENT_LOBBY", "walked into the Slateport Battle Tent")
    shot("01_slateport_tent_lobby")
    local att = S.objectByScript("SlateportCity_BattleTentLobby_EventScript_Attendant")
    if check(att ~= nil, "Slateport tent attendant present") then
      S.talkTo(game, att)
      local selectCalled, rentalsReady = false, false
      S.settle(game, {
        limit = 60000,
        until_ = function()
          if S.mapNow() == "EM_SLATEPORT_CITY_BATTLE_TENT_CORRIDOR" and f.rentalMons[1] and f.rentalMons[1].monId
              and rentalsReady then return true end
          return false
        end,
        choice = function() return "yes" end,
        onIdleUi = idleUi("02"),
        watch = function()
          if not selectCalled and S.mapNow() == "EM_SLATEPORT_CITY_BATTLE_TENT_CORRIDOR" and f.rentalMons[6]
              and f.rentalMons[6].monId and session.frontierTempParty then
            selectCalled = true
            rentalsReady = true
          end
        end,
      })
      check(saveSeen, "the Slateport tent saves before the challenge")
      check(f.lvlMode == D.LVL.TENT and Rse.var("VAR_FRONTIER_FACILITY") == D.FACILITY.FACTORY,
        "Slateport tent runs FACTORY rules in tent level mode")
      local tentMons = D.tentPack(D.FACILITY.FACTORY).mons
      local okRent, species = true, {}
      for i = 1, 6 do
        local r = f.rentalMons[i]
        if not (r and r.monId and tentMons[r.monId]) then okRent = false else species[#species + 1] = tentMons[r.monId].species end
      end
      check(okRent, "GenerateInitialRentalMons picked six rentals from gSlateportBattleTentMons")
      check(session.frontierTempParty and #session.frontierTempParty == 3,
        "GenerateOpponentMons picked the first opponent's three mons")
      local opp = session.frontierOpponentA
      check(opp ~= nil and opp < D.NUM_BATTLE_TENT_TRAINERS, "tent opponent from gSlateportBattleTentTrainers (" .. tostring(opp) .. ")")
      shot("03_slateport_corridor")
      local factory = Rse.system("factory")
      if factory and factory.selectScreen then
        note("factory select screen present; rental flow continues through it")
      else
        note("DoBattleFactorySelectScreen is the Battle Factory owner's screen (not registered): stopping the Slateport run here")
        local cleared = 0
        for i = #d.vmLogs, 1, -1 do
          if d.vmLogs[i]:find("DoBattleFactorySelectScreen", 1, true) then table.remove(d.vmLogs, i) cleared = cleared + 1 end
        end
        note("factory select screen logs outside f1 scope: " .. cleared)
        if Space.vm and Space.vm.halt then Space.vm:halt(true) end
        local okF, Fade = pcall(require, "src.ui.game3.fade")
        if okF and Fade.clear then Fade.clear() end
        require("src.core.game3.field").unlock()
        U.wait(10)
        require("src.core.game3.scripting.natives_frontier_story").loadPlayerParty(session)
        f.challengeStatus = 0
      end
    end
  end

  finish()
end
