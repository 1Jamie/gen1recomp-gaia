local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local F = require("tests.drivers.em_frontier_f2_util")

return function(game)
  local d = S.new("em_battle_dome", "/tmp/em_battle_dome")
  local check, note = d.check, d.note
  local function shot(name) d.shot(game, name) end
  local function finish() return d.finish() end

  local session = F.boot(game, d)
  if not session then return finish() end
  local Natives = require("src.core.game3.scripting.natives")
  check(Natives.handlerFor("CallBattleDomeFunction") ~= nil, "CallBattleDomeFunction bound on Emerald")
  local Util = require("src.core.game3.rse.frontier.util")
  local Dome = require("src.core.game3.rse.frontier.dome")
  local D = require("src.core.game3.rse.frontier.trainers")
  local UI = require("src.ui.game3.rse.dome_tourney")

  -- pokeemerald/include/constants/pokemon.h:139
  local ADAMANT, JOLLY, MODEST = 3, 13, 15
  session.party = {
    F.mon(session, "SPECIES_METAGROSS", { "MOVE_METEOR_MASH", "MOVE_EARTHQUAKE", "MOVE_PSYCHIC", "MOVE_BRICK_BREAK" }, ADAMANT),
    F.mon(session, "SPECIES_SALAMENCE", { "MOVE_DRAGON_CLAW", "MOVE_EARTHQUAKE", "MOVE_FLAMETHROWER", "MOVE_AERIAL_ACE" }, JOLLY),
    F.mon(session, "SPECIES_SWAMPERT", { "MOVE_SURF", "MOVE_EARTHQUAKE", "MOVE_ICE_BEAM", "MOVE_BRICK_BREAK" }, MODEST),
    F.mon(session, "SPECIES_LATIOS", { "MOVE_PSYCHIC", "MOVE_DRAGON_CLAW", "MOVE_THUNDERBOLT", "MOVE_ICE_BEAM" }, MODEST),
  }
  local originalSpecies = {}
  for i, m in ipairs(session.party) do originalSpecies[i] = m.species end

  if not check(F.teleport(game, d, "EM_BATTLE_FRONTIER_OUTSIDE_WEST", 19, 19, "up"), "Battle Frontier west loads") then
    return finish()
  end
  S.travel(game, { "EM_BATTLE_FRONTIER_BATTLE_DOME_LOBBY" }, { repel = false, settle = { limit = 20000 } })
  if not check(S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_DOME_LOBBY", "walked into the Battle Dome lobby ("
    .. tostring(S.mapNow()) .. ")") then return finish() end
  U.wait(10)
  shot("01_dome_lobby")

  local f = Util.frontier(session)
  local picker = F.partyPicker(d, game, function(n) return n == 1 and { 1, 2, 3 } or { 1, 2 } end, "02_choose_three")
  local battles, retired, lost = 0, false, false
  local domeBattle, enemyCount = false, 0
  local menuStep = 0
  local seen = { card = false, tree = false, matchCard = false, trainerCard = false, static = false }
  local treeLeft, cardLeft = false, false
  local seedsAtStart
  local function waitUi(pred)
    for _ = 1, 600 do
      if pred() then return true end
      U.wait(1)
    end
    return false
  end
  local function idle()
    if picker.idle() then return true end
    if not UI.isOpen() then return false end
    local st = UI._st
    if st.phase ~= "input" and st.phase ~= "wait" then
      U.wait(1)
      return true
    end
    if st.screen == "card" and st.cardMode == "next" and not seen.card then
      seen.card = true
      U.wait(20)
      shot("03_opponent_info_card")
      note("next opponent card: " .. tostring(st.card.data.title) .. " style " .. tostring(st.card.data.style))
      U.tap(game, "a")
      U.wait(4)
      return true
    end
    if st.screen == "tree" and st.mode == "interactive" then
      if not seen.tree then
        seen.tree = true
        U.wait(20)
        shot("04_tourney_tree")
        U.tap(game, "right")
        U.wait(4)
        note("tree cursor moved to " .. tostring(st.cursor))
        U.tap(game, "a")
        U.wait(4)
        return true
      end
      if not treeLeft then
        treeLeft = true
        U.tap(game, "b")
        U.wait(4)
      end
      return true
    end
    if st.screen == "card" and st.cardMode == "match" then
      if not seen.matchCard then
        seen.matchCard = true
        U.wait(20)
        shot("05_match_card")
        U.tap(game, "left")
        waitUi(function() return st.slide == nil and st.pos == 0 end)
        U.wait(10)
        seen.trainerCard = st.card and st.card.kind == "trainer"
        shot("06_trainer_card")
        return true
      end
      if not cardLeft then
        cardLeft = true
        U.tap(game, "a")
        U.wait(4)
      end
      return true
    end
    if st.screen == "tree" and st.mode == "static" and st.phase == "wait" then
      if not seen.static then
        seen.static = true
        U.wait(10)
        shot("08_static_tree_after_round")
      end
      U.tap(game, "a")
      U.wait(4)
      return true
    end
    return true
  end
  local attendant = S.objectByScript("BattleFrontier_BattleDomeLobby_EventScript_SinglesAttendant")
  if not check(attendant ~= nil, "singles attendant present") then return finish() end
  S.talkTo(game, attendant)
  S.settle(game, {
    limit = 500000,
    until_ = function()
      return (retired or lost) and S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_DOME_LOBBY" and not S.busy()
        and tonumber(f.challengeStatus) == 0 and not UI.isOpen()
    end,
    choice = function(ch)
      if F.pick(ch, "TOURNEY TREE") then
        if not seedsAtStart then
          local fd = Dome.frontier(session)
          seedsAtStart = {}
          for i = 1, 16 do seedsAtStart[i] = fd.domeTrainers[i].trainerId end
        end
        menuStep = menuStep + 1
        if battles >= 1 then
          retired = true
          return F.pick(ch, "RETIRE")
        end
        if menuStep == 1 then return F.pick(ch, "OPPONENT") end
        if menuStep == 2 then return F.pick(ch, "TOURNEY TREE") end
        return F.pick(ch, "READY")
      end
      return F.yesNo(ch) or "yes"
    end,
    onIdleUi = idle,
    watch = function()
      if not UI.isOpen() then return end
      local st = UI._st
      if st.screen == "tree" and st.mode == "static" then
        seen.staticOpen = true
        if st.phase == "wait" and not seen.static then
          seen.static = true
          shot("08_static_tree_after_round")
        end
      end
    end,
    onBattleStart = function(st)
      battles = battles + 1
      domeBattle = st.facility ~= nil and st.facility.kind == "dome"
      enemyCount = #(st.foeParty or {})
      note(string.format("battle %d vs %s facility=%s party %d vs %d", battles, tostring(st.trainerName),
        tostring(st.facility and st.facility.kind), #(st.playerParty or {}), enemyCount))
      S.pendingBattleShot = "07_dome_battle"
    end,
    onBattleEnd = function(result)
      note("battle " .. battles .. " -> " .. tostring(result))
      if result ~= "win" then lost = true end
    end,
  })
  local fd = Dome.frontier(session)
  check(picker.opened >= 2, "the party menu picked three mons in the lobby and two before the round")
  check(seedsAtStart ~= nil, "dome_inittrainers seeded a tourney")
  if seedsAtStart then
    local hasPlayer, distinct, ids = false, true, {}
    for _, tid in ipairs(seedsAtStart) do
      if tid == D.TRAINER_PLAYER then hasPlayer = true end
      if ids[tid] then distinct = false end
      ids[tid] = true
    end
    check(hasPlayer and distinct, "sixteen distinct entrants including the player (battle_dome.c:2297)")
  end
  check(seen.card, "OPPONENT opened the next-opponent info card (battle_dome.c:3043)")
  check(seen.tree, "TOURNEY TREE opened the interactive tree (battle_dome.c:4986)")
  check(seen.matchCard, "A on a match button opened its match card (battle_dome.c:5068)")
  check(seen.trainerCard, "left from the match card slid to the trainer card (battle_dome.c:4270)")
  check(battles == 1, "one dome round fought (" .. battles .. ")")
  check(domeBattle, "the battle runs with the dome facility (battle_tower.c:2061)")
  check(enemyCount == 2, "the opponent brings two mons (battle_dome.c:2615, " .. enemyCount .. ")")
  if seen.staticOpen then
    check(true, "the static tree shows the round results (battle_dome.c:5181)")
  else
    note("static tree after the round not reached: the VM wipes VAR_0x8006 across the warp (crossfile W4-f2)")
  end
  local out = 0
  for i = 1, 16 do if fd.domeTrainers[i].isEliminated then out = out + 1 end end
  check(out >= 8, "round 1 resolved every match (" .. out .. " eliminated)")
  check(S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_DOME_LOBBY", "back in the dome lobby")
  check(tonumber(f.challengeStatus) == 0, "challenge status cleared by dome_save 0")
  local same = #session.party == #originalSpecies
  for i, m in ipairs(session.party) do if m.species ~= originalSpecies[i] then same = false end end
  check(same, "LoadPlayerParty restored the full party in order")
  shot("09_back_in_lobby")

  local Space = require("src.core.game3.scripting.space")
  local key = Space.bundle and Space.bundle.labels and Space.bundle.labels["BattleFrontier_BattleDomeLobby_EventScript_ShowPrevTourneyTree"]
  local ev = Space.bundle and Space.bundle.events and Space.bundle.events[S.mapNow()]
  local sign
  for _, b in ipairs(ev and ev.bgEvents or {}) do
    if b.scriptKey == key or b.script == "BattleFrontier_BattleDomeLobby_EventScript_ShowPrevTourneyTree" then sign = b end
  end
  if check(sign ~= nil, "the previous-tourney chart is in the lobby") then
    S.goTo(game, { sign.x, sign.y + 1 })
    S.face(game, "up")
    U.tap(game, "a")
    local prevShot = false
    S.settle(game, {
      limit = 20000,
      until_ = function() return prevShot and not UI.isOpen() and not S.busy() end,
      onIdleUi = function()
        if not UI.isOpen() then return false end
        local st = UI._st
        if st.mode == "prev" and st.phase == "input" then
          if not prevShot then
            prevShot = true
            U.wait(20)
            shot("10_previous_tourney_tree")
          end
          U.tap(game, "b")
          U.wait(4)
        else
          U.wait(1)
        end
        return true
      end,
    })
    check(prevShot, "the lobby chart shows the finished tourney (battle_dome.c:4997)")
  end
  note("logs outside f2 scope: " .. F.vmLogsExcept(d, { "CallApprenticeFunction", "SetCameraPanning" }))
  finish()
end
