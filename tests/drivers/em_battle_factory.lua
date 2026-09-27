local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

return function(game)
  local d = S.new("em_battle_factory", "/tmp/em_battle_factory")
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
  local SaveMenu = require("src.ui.game3.save_menu")
  local Util = require("src.core.game3.rse.frontier.util")
  local D = require("src.core.game3.rse.frontier.trainers")
  local Natives = require("src.core.game3.scripting.natives")
  local Select = require("src.ui.game3.rse.factory_select")
  local Swap = require("src.ui.game3.rse.factory_swap")
  local SummaryMenu = require("src.ui.game3.summary_menu")

  session = Runtime.getSession()
  if not check(session and session.version == "emerald" and S.flag("FLAG_SYS_GAME_CLEAR"),
      "post-game Emerald session") then return finish() end
  Natives.ensureBound(session)
  check(Natives.handlerFor("CallBattleFactoryFunction") ~= nil, "CallBattleFactoryFunction bound on Emerald")
  session.repelSteps = 0
  require("src.core.game3.encounters").onStep = function() return nil end

  local original = {}
  for i, m in ipairs(session.party) do original[i] = m.species end

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

  if not check(teleport("EM_BATTLE_FRONTIER_BATTLE_FACTORY_LOBBY", 9, 10, "up"), "Battle Factory lobby loads") then
    return finish()
  end
  shot("01_factory_lobby")
  local f = Util.frontier(session)

  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end

  local sel = { opened = false, picks = {}, invalid = 0, summary = false, done = false }
  -- pokeemerald/src/battle_factory_screen.c:1671
  local function driveSelect()
    local st = Select._st
    if not waitFor(function() return st.phase == "choose" end, 300) then return end
    if not sel.opened then
      sel.opened = true
      U.wait(8)
      shot("03_select_screen")
    end
    local target = 1
    while Select.isOpen() and st.selectingState <= 3 and target <= 6 do
      while st.cursor ~= target do
        U.tap(game, "right")
        U.wait(3)
      end
      U.tap(game, "a")
      waitFor(function() return st.phase == "menu" end, 200)
      if #sel.picks == 0 and not sel.summary then
        U.wait(4)
        shot("04_select_menu")
        sel.summary = true
        U.tap(game, "a")
        waitFor(function() return SummaryMenu.isOpen() end, 200)
        U.wait(20)
        shot("05_rental_summary")
        U.tap(game, "b")
        waitFor(function() return st.phase == "menu" and not SummaryMenu.isOpen() end, 400)
      end
      U.tap(game, "down")
      U.wait(3)
      U.tap(game, "a")
      waitFor(function() return st.phase ~= "menu" end, 200)
      if st.phase == "invalid" then
        sel.invalid = sel.invalid + 1
        U.wait(4)
        U.tap(game, "a")
        waitFor(function() return st.phase == "choose" end, 200)
      else
        sel.picks[#sel.picks + 1] = target
      end
      target = target + 1
      waitFor(function() return st.phase == "choose" or st.phase == "yesno" end, 300)
    end
    if waitFor(function() return st.phase == "yesno" end, 300) then
      U.wait(4)
      shot("06_select_confirm_three")
      U.tap(game, "a")
      waitFor(function() return not Select.isOpen() end, 400)
      sel.done = true
    end
  end

  local swap = { opened = false, did = false, enemyMon = nil, playerMon = nil, same = 0 }
  -- pokeemerald/src/battle_factory_screen.c:2634
  local function driveSwap()
    local st = Swap._st
    if not waitFor(function() return st.phase == "choose" end, 300) then
      local Stack = require("src.ui.game3.stack")
      local top = Stack.top()
      note("SWAP stuck phase=" .. tostring(st.phase) .. " top=" .. tostring(top and top.id) .. " depth=" .. Stack.depth()
        .. " fade=" .. tostring(st.pal and st.pal:fadeActive()))
      return
    end
    if not swap.opened then
      swap.opened = true
      U.wait(6)
      shot("08_swap_player_screen")
    end
    U.tap(game, "a")
    waitFor(function() return st.phase == "menu" end, 300)
    U.wait(4)
    shot("09_swap_menu")
    swap.playerMon = st.party[st.cursor + 1] and st.party[st.cursor + 1].species
    U.tap(game, "down")
    U.wait(3)
    U.tap(game, "a")
    waitFor(function() return st.phase == "choose" and st.inEnemyScreen end, 600)
    U.wait(6)
    shot("10_swap_enemy_screen")
    for pick = 0, 2 do
      while st.cursor ~= pick do
        U.tap(game, "right")
        U.wait(3)
      end
      U.tap(game, "a")
      waitFor(function() return st.phase == "yesno" or st.phase == "same_species" end, 400)
      if st.phase == "same_species" then
        swap.same = swap.same + 1
        U.wait(10)
        U.tap(game, "a")
        waitFor(function() return st.phase == "choose" end, 300)
      else
        U.wait(4)
        shot("11_swap_accept")
        swap.enemyMon = st.enemy[st.cursor + 1] and st.enemy[st.cursor + 1].species
        U.tap(game, "a")
        waitFor(function() return not Swap.isOpen() end, 400)
        swap.did = true
        return
      end
    end
    U.tap(game, "b")
    waitFor(function() return st.phase == "yesno" end, 300)
    U.tap(game, "a")
    waitFor(function() return not Swap.isOpen() end, 400)
  end

  local saveSeen = false
  local function idleUi()
    if Select.isOpen() then
      driveSelect()
      return true
    end
    if Swap.isOpen() then
      driveSwap()
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

  local att = S.objectByScript("BattleFrontier_BattleFactoryLobby_EventScript_SinglesAttendant")
  if not check(att ~= nil, "singles attendant present") then return finish() end
  require("src.core.game3.rng").SeedRng(tonumber(os.getenv("EM_F3_SEED") or "") or 0xF3)
  local total, allInfo, challenges = 0, {}, 0
  local lvOk, fOk, threeOk, rentalRoomOk, recordOk, bpOk = true, true, true, true, true, true
  local swapVerified = nil
  for attempt = 1, 4 do
    challenges = attempt
    local battles, results, info = 0, {}, {}
    local rentalAtFirst
    local wantSwap = true
    local streakBefore = Util.get2(f.factoryWinStreaks, 0, 0)
    local bpStart = tonumber(f.battlePoints) or 0
    sel.opened, sel.done, sel.picks, sel.summary = sel.opened, false, {}, sel.summary
    S.talkTo(game, att)
    S.settle(game, {
      limit = 600000,
      until_ = function()
        return battles >= 1 and S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_FACTORY_LOBBY" and not S.busy()
          and tonumber(f.challengeStatus) == 0
      end,
      choice = function()
        local Message = require("src.ui.game3.message")
        local page = tostring(Message.currentPage and Message.currentPage() or "")
        if page:upper():find("RECORD", 1, true) then return "no" end
        if page:upper():find("SWAP A POK", 1, true) then
          if wantSwap then
            wantSwap = false
            return "yes"
          end
          return "no"
        end
        return "yes"
      end,
      onIdleUi = idleUi,
      watch = function()
        if not rentalAtFirst and S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_FACTORY_BATTLE_ROOM" then
          rentalAtFirst = {}
          for i, m in ipairs(session.party) do rentalAtFirst[i] = m.species end
        end
      end,
      onBattleStart = function(st)
        battles = battles + 1
        total = total + 1
        local foe = st.enemy and st.enemy.mon
        local lv, sp = {}, {}
        for i, m in ipairs(session.party) do lv[i], sp[i] = m.level, m.species end
        info[battles] = { level = foe and foe.level, kinds = st.kinds, partyLevels = lv, party = #session.party,
          species = sp }
        allInfo[#allInfo + 1] = info[battles]
        note(string.format("challenge %d battle %d vs %s foe %s lv %s", attempt, battles, tostring(st.trainerName),
          tostring(foe and foe.species), tostring(foe and foe.level)))
        if total == 1 then S.pendingBattleShot = "07_factory_battle" end
      end,
      onBattleEnd = function(result)
        results[battles] = result
        note("challenge " .. attempt .. " battle " .. battles .. " -> " .. tostring(result))
      end,
    })
    if not (sel.done and #sel.picks == 3) then threeOk = false end
    if not (rentalAtFirst and #rentalAtFirst == 3) then rentalRoomOk = false end
    local won = 0
    for i = 1, battles do if results[i] == "win" then won = won + 1 end end
    note("challenge " .. attempt .. ": won " .. won .. " of " .. battles)
    if Util.get2(f.factoryRecordWinStreaks, 0, 0) < math.min(streakBefore + won, 7) then recordOk = false end
    if won >= 7 and not ((tonumber(f.battlePoints) or 0) > bpStart) then bpOk = false end
    if swap.did and swapVerified == nil and info[2] then
      swapVerified = false
      for _, sp in ipairs(info[2].species or {}) do if sp == swap.enemyMon then swapVerified = true end end
    end
    if swap.opened then break end
  end
  check(saveSeen, "the challenge saves before entering (Common_EventScript_SaveGame)")
  check(sel.opened, "factory_rentmons opened the rental select screen (DoBattleFactorySelectScreen)")
  check(threeOk, "three rentals chosen through RENT in every challenge")
  check(rentalRoomOk, "the battle room party is the three rentals")
  check(total >= 1, "factory battles fought (" .. total .. " over " .. challenges .. " challenges)")
  for _, b in ipairs(allInfo) do
    if b.level ~= 50 then lvOk = false end
    if not (b.kinds and b.kinds.frontier) then fOk = false end
    if b.party ~= 3 then threeOk = false end
    for _, l in ipairs(b.partyLevels) do if l ~= 50 then lvOk = false end end
  end
  check(lvOk, "rentals and opponents are level 50")
  check(fOk, "factory battles run as frontier battles")
  check(threeOk, "three rentals battle")
  check(swap.opened, "factory_swapmons opened the swap screen after a win (DoBattleFactorySwapScreen)")
  check(swap.did or swap.same > 0, "a swap was made (or refused for a same-species clash)")
  if swap.did then
    check(swapVerified == true, "the accepted opponent mon battles in the next round (CopySwappedMonData)")
  end
  check(bpOk, "seven wins award battle points")
  check(S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_FACTORY_LOBBY", "back in the factory lobby")
  check(tonumber(f.challengeStatus) == 0, "factory_save 0 clears the challenge status")
  local restored = #session.party == #original
  for i, sp in ipairs(original) do if session.party[i] and session.party[i].species ~= sp then restored = false end end
  check(restored, "LoadPlayerParty restored the player's own party")
  check(recordOk, "record streak saved (" .. Util.get2(f.factoryRecordWinStreaks, 0, 0) .. ")")
  shot("12_back_in_lobby")
  return finish()
end
