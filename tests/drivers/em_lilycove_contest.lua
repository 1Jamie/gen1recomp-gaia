local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_lilycove_contest", "/tmp/em_lilycove_contest")

local LOBBY = "EM_LILYCOVE_CITY_CONTEST_LOBBY"
local MUSEUM_2F = "EM_LILYCOVE_CITY_LILYCOVE_MUSEUM_2F"

local function mod(name) return require(name) end
local function Stack() return mod("src.ui.game3.stack") end

local shots = {}
local function shotOnce(game, name)
  if shots[name] then return end
  shots[name] = true
  d.shot(game, name)
end

local function stageTask(screen, name)
  return screen.m.tasks:isActive(screen:func(name))
end

-- pokeemerald/src/contest.c:1556
local function playStage(game, schedule, tag)
  local Stage = mod("src.ui.game3.rse.contest")
  local screen = Stage.active()
  local selects, frames = 0, 0
  while screen and not screen.done and frames < 60000 do
    frames = frames + 1
    local c = screen.c
    if stageTask(screen, "taskHandleMoveSelectInput") then
      if not shots[tag .. "_03_move_select_r" .. (c.contest.appealNumber + 1)] then
        U.wait(4)
        shotOnce(game, tag .. "_03_move_select_r" .. (c.contest.appealNumber + 1))
      end
      local want = schedule[c.contest.appealNumber + 1] or 0
      if c.contest.playerMoveChoice ~= want then
        U.tap(game, "down")
        U.wait(2)
      else
        U.tap(game, "a")
        selects = selects + 1
        U.wait(2)
      end
    else
      if stageTask(screen, "taskTryShowMoveSelectScreen") then
        shotOnce(game, tag .. "_02_appeal_prompt_r" .. (c.contest.appealNumber + 1))
      end
      if stageTask(screen, "taskPrintRoundResultText") and screen:task(screen.mainTaskId).data[0] == 1
          and not screen:textActive() then
        shotOnce(game, tag .. "_05_round_result")
      end
      local t = screen.turn
      local ms = t and t.monSpriteId and screen:sprite(t.monSpriteId)
      if ms and ms.slidDone and screen:textActive() and not shots[tag .. "_04_appeal"] then
        U.wait(12)
        shotOnce(game, tag .. "_04_appeal")
      end
      if frames % 6 == 0 then U.tap(game, "a") else U.wait(1) end
    end
    screen = Stage.active()
  end
  return selects
end

-- pokeemerald/src/contest_util.c:978
local function playResults(game, tag)
  local Results = mod("src.ui.game3.rse.contest_results")
  local screen = Results.active()
  local frames = 0
  while screen and not screen.done and frames < 40000 do
    frames = frames + 1
    if stageTask(screen, "taskShowPreliminaryResults") then shotOnce(game, tag .. "_06_results_prelim") end
    if stageTask(screen, "taskShowWinnerMonBanner") and screen:task(screen.d.showResultsTaskId).data[0] == 3 then
      shotOnce(game, tag .. "_07_results_winner")
    end
    if stageTask(screen, "taskSetSeenWinnerMon") then
      shotOnce(game, tag .. "_08_results_final")
      U.tap(game, "a")
    else
      U.wait(1)
    end
    screen = Results.active()
  end
  return frames
end

local function driveContest(game, rankChoice, schedule, tag)
  local PartyMenu = mod("src.ui.game3.party_menu")
  local Choice = mod("src.ui.game3.choice")
  local Message = mod("src.ui.game3.message")
  local Hud = mod("src.ui.game3.hud")
  local Stage = mod("src.ui.game3.rse.contest")
  local Results = mod("src.ui.game3.rse.contest_results")
  if not M.goTo(game, LOBBY, 14, 4, "up") then return false, "goto lobby" end
  S.face(game, "up")
  U.tap(game, "a")
  U.wait(4)
  local answers = { 0, rankChoice, 0 }
  local ai, sawStage, sawResults, idle = 1, false, false, 0
  for _ = 1, 40000 do
    if Stage.active() then
      sawStage = true
      U.wait(40)
      shotOnce(game, tag .. "_01_curtain")
      playStage(game, schedule, tag)
    elseif Results.active() then
      sawResults = true
      playResults(game, tag)
    elseif mod("src.ui.game3.rse.contest_entry_pic").active and not shots[tag .. "_00b_entry_pic"] then
      U.wait(30)
      shotOnce(game, tag .. "_00b_entry_pic")
    elseif PartyMenu.isOpen and PartyMenu.isOpen() then
      shotOnce(game, tag .. "_00_choose_mon")
      U.wait(10)
      U.tap(game, "a")
      U.wait(10)
    elseif Choice.isOpen() then
      local ans = answers[ai]
      ai = ai + 1
      local want = (ans or 0) + 1
      U.wait(6)
      for _ = 1, 16 do
        if Choice.cursor == want then break end
        U.tap(game, Choice.cursor < want and "down" or "up")
        U.wait(3)
      end
      d.note(string.format("%s choice %d: %d options, cursor %d (want %d)", tag, ai - 1, #(Choice.options or {}),
        Choice.cursor, want))
      U.tap(game, "a")
      U.wait(6)
    elseif Message.isOpen() then
      if Message.isTyping() then
        Message.skipReveal()
        U.wait(2)
      elseif (Message._page or 1) < #(Message._pages or {}) or Hud._waitButton or not Message._stay then
        U.tap(game, "a")
        U.wait(2)
      else
        U.wait(1)
      end
    elseif Hud._waitButton then
      U.tap(game, "a")
      U.wait(2)
    else
      U.wait(1)
    end
    if sawResults and not S.busy() and S.mapNow() == LOBBY and not Stage.active() and not Results.active() then
      idle = idle + 1
      if idle > 30 then break end
    else
      idle = 0
    end
  end
  return sawStage and sawResults, "stage=" .. tostring(sawStage) .. " results=" .. tostring(sawResults)
end

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    local Ribbons = mod("src.core.game3.rse.ribbons")
    local Pokeblock = mod("src.core.game3.rse.pokeblock")
    local Util = mod("src.core.game3.rse.contest_util")
    S.setFlag("FLAG_RECEIVED_POKEBLOCK_CASE", true)
    S.setFlag("FLAG_HIDE_LILYCOVE_MUSEUM_CURATOR", true)
    local mon = S.giveMon("SPECIES_SALAMENCE", 60, { "MOVE_HI_JUMP_KICK", "MOVE_SUBMISSION", "MOVE_JUMP_KICK", "MOVE_MEGA_KICK" })
    local cond = Pokeblock.contest(mon)
    cond.cool, cond.tough, cond.beauty, cond.cute, cond.smart, cond.sheen = 220, 160, 160, 40, 40, 200
    local Rng = mod("src.core.game3.rng")

    local won = false
    for attempt = 1, 6 do
      local before = Ribbons.get(mon, "cool")
      Rng.SeedRng(0x0C1B + attempt)
      local okC, why = driveContest(game, 0, { 0, 1, 2, 0, 1 }, "normal" .. attempt)
      d.check(okC, "Normal Cool contest " .. attempt .. " ran through the stage and results screens (" .. tostring(why) .. ")")
      if not okC then return end
      local c = Util.current()
      d.note(string.format("normal attempt %d totals %d %d %d %d place %d", attempt, c.totals[0], c.totals[1], c.totals[2],
        c.totals[3], c:playerPlace() + 1))
      if c:playerPlace() == 0 then
        d.check(Ribbons.get(mon, "cool") == before + 1, "the lobby gave the Normal Cool ribbon")
        d.check(S.flag("FLAG_SYS_RIBBON_GET"), "FLAG_SYS_RIBBON_GET set")
        won = true
        break
      end
    end
    d.check(won, "won a Normal Cool contest")
    d.check(S.mapNow() == LOBBY, "back in the contest lobby after the hall")

    -- pokeemerald/src/contest_util.c:2003
    cond.cool, cond.tough, cond.beauty, cond.sheen = 245, 230, 230, 230
    for rank, label in ipairs({ "Super", "Hyper" }) do
      local rankWon = false
      for attempt = 1, 8 do
        local before = Ribbons.get(mon, "cool")
        Rng.SeedRng(0x0C1B00 + rank * 16 + attempt)
        local okC, why = driveContest(game, rank, { 0, 1, 2, 0, 1 }, label:lower() .. attempt)
        d.check(okC, label .. " Cool contest " .. attempt .. " ran (" .. tostring(why) .. ")")
        if not okC then return end
        local c = Util.current()
        d.note(string.format("%s attempt %d totals %d %d %d %d place %d", label:lower(), attempt, c.totals[0], c.totals[1],
          c.totals[2], c.totals[3], c:playerPlace() + 1))
        if c:playerPlace() == 0 then
          d.check(Ribbons.get(mon, "cool") == before + 1, "the lobby gave the " .. label .. " Cool ribbon (" .. (before + 1) .. ")")
          rankWon = true
          break
        end
      end
      d.check(rankWon, "won a " .. label .. " Cool contest")
    end

    Ribbons.set(mon, "cool", 3)
    cond.cool, cond.tough, cond.beauty, cond.sheen = 255, 255, 255, 255
    local artist = false
    for attempt = 1, 8 do
      Rng.SeedRng(0x0C1B0 + attempt)
      local okC, why = driveContest(game, 3, { 0, 1, 2, 0, 1 }, "master" .. attempt)
      d.check(okC, "Master Cool contest " .. attempt .. " ran (" .. tostring(why) .. ")")
      if not okC then return end
      local c = Util.current()
      d.note(string.format("master attempt %d totals %d %d %d %d place %d", attempt, c.totals[0], c.totals[1], c.totals[2],
        c.totals[3], c:playerPlace() + 1))
      if Util.shouldReadyContestArtist(c) then
        artist = true
        break
      end
    end
    d.check(artist, "a Master Cool win with 800+ points readies the contest artist")
    if not artist then return end

    local Painting = mod("src.ui.game3.rse.contest_painting")
    local sawPainting = false
    M.pump(game, {
      limit = 4000,
      answers = { "yes" },
      onFrame = function()
        if Painting.isOpen() then
          sawPainting = true
          U.wait(40)
          d.shot(game, "master_09_artist_painting")
          U.tap(game, "a")
          U.wait(40)
        end
      end,
    })
    d.check(sawPainting, "the artist showed the Master contest painting")
    d.check(S.var("VAR_LILYCOVE_CONTEST_LOBBY_STATE") == 0, "artist scene finished")
    d.check(S.flag("FLAG_COOL_PAINTING_MADE"), "FLAG_COOL_PAINTING_MADE set by the lobby script")
    d.check(Ribbons.get(mon, "artist") == 1, "Artist ribbon awarded")
    local w = session.contestWinners and session.contestWinners[Util.WINNER.MUSEUM_COOL]
    d.check(w ~= nil and w.species == mon.species, "museum cool slot holds the player's Salamence")
    d.check(Util.countPlayerMuseumPaintings(session) == 1, "one museum painting")

    S.setVar("VAR_LILYCOVE_MUSEUM_2F_STATE", 1)
    d.check(M.goTo(game, MUSEUM_2F, 10, 7, "up"), "entered the museum exhibit hall")
    d.shot(game, "museum_01_hall")
    S.face(game, "up")
    U.tap(game, "a")
    U.wait(4)
    local sawMuseum = false
    M.pump(game, {
      limit = 3000,
      onFrame = function()
        if Painting.isOpen() then
          sawMuseum = true
          U.wait(40)
          d.shot(game, "museum_02_cool_painting")
          U.tap(game, "a")
          U.wait(40)
        end
      end,
    })
    d.check(sawMuseum, "the museum shows the cool painting")
    d.shot(game, "museum_03_after")

    -- pokeemerald/data/maps/LilycoveCity_ContestLobby/scripts.inc:478
    for _, spot in ipairs({ { 3, "HALL_1" }, { 7, "HALL_3" } }) do
      d.check(M.goTo(game, LOBBY, spot[1], 2, "up"), "back in the lobby under the " .. spot[2] .. " painting")
      S.face(game, "up")
      U.tap(game, "a")
      U.wait(4)
      local saw = false
      M.pump(game, {
        limit = 3000,
        onFrame = function()
          if Painting.isOpen() then
            saw = true
            U.wait(40)
            d.shot(game, "lobby_" .. spot[2]:lower())
            U.tap(game, "a")
            U.wait(40)
          end
        end,
      })
      d.check(saw, "lobby shows the " .. spot[2] .. " winner painting")
    end
    local hall1 = session.contestWinners[Util.WINNER.HALL_1]
    d.check(hall1 and hall1.species == mon.species and hall1.contestRank == 3, "HALL_1 holds the Master Cool winner")
    local hall3 = session.contestWinners[Util.WINNER.HALL_3]
    d.check(hall3 and (hall3.species or 0) ~= 0, "HALL_3 still shows a default winner (new_game.c:176)")
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
