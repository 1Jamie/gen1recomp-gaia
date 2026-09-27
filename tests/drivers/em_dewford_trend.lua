local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_dewford_trend", "/tmp/em_dewford_trend")

local function wordByText(text)
  local groups = require("src.core.game3.easy_chat_text").groups()
  for gid = 1, 20 do
    for _, w in ipairs(groups[gid] and groups[gid].words or {}) do
      if w.text == text and gid ~= 18 and gid ~= 19 then return w.id end
    end
  end
  error("no easy chat word " .. text)
end

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    local Dewford = require("src.core.game3.rse.dewford_trend")
    local Town = require("src.core.game3.rse.town_common")
    local Rtc = require("src.core.game3.rtc")
    local G = Town.EC_GROUP
    d.check(M.goTo(game, "EM_DEWFORD_TOWN", 3, 7, "left"), "arrived in Dewford Town")
    local trends = Dewford.trends(session)
    d.check(#trends == 5, "five saved trends exist (InitDewfordTrend)")
    local oldPhrase = Dewford.phraseString(0, session)
    d.note("initial trendy phrase: " .. oldPhrase)
    d.shot(game, "01_dewford_town")

    -- pokeemerald/data/maps/DewfordTown/scripts.inc:581
    local phrase = { wordByText("COOL"), wordByText("CAMERA") }
    local mark = #M.msgs
    local done = M.talk(game, "DewfordTown_EventScript_TrendyPhraseBoy", {
      answers = { "no" },
      easyChat = function(st)
        d.check(st.type == 9, "easy chat opened as EASY_CHAT_TYPE_TRENDY_PHRASE (" .. tostring(st.type) .. ")")
        d.check(st.count == 2 and st.words[1] == trends[1].words[1], "trendy phrase screen starts from the current trend")
        d.shot(game, "02_trendy_phrase_screen")
        return { phrase[1], phrase[2] }
      end,
    })
    d.check(done, "trendy phrase boy script finished")
    d.check(M.saw(oldPhrase, mark), "boy quotes the current trend \"" .. oldPhrase .. "\"")
    local newPhrase = Dewford.phraseString(0, session)
    d.check(newPhrase == Town.word(phrase[1]) .. " " .. Town.word(phrase[2]), "new trend is COOL CAMERA (" .. newPhrase .. ")")
    d.check(S.flag("FLAG_SYS_CHANGED_DEWFORD_TREND"), "FLAG_SYS_CHANGED_DEWFORD_TREND set")
    d.check((session.gameStats and session.gameStats[2] or 0) == 1, "GAME_STAT_STARTED_TRENDS incremented")
    d.check(M.saw("COOL CAMERA", mark), "boy repeats \"COOL CAMERA\"")
    d.shot(game, "03_trend_set")

    mark = #M.msgs
    M.talk(game, "DewfordTown_EventScript_TrendyPhraseBoy", { answers = { "yes" } })
    d.check(M.saw("COOL CAMERA", mark), "boy now says COOL CAMERA is the biggest thing")

    -- pokeemerald/data/maps/DewfordTown_Hall/scripts.inc:4
    d.check(M.goTo(game, "EM_DEWFORD_TOWN_HALL", 5, 7, "up"), "entered Dewford Hall")
    mark = #M.msgs
    M.talk(game, "DewfordTown_Hall_EventScript_Girl", {})
    d.check(M.saw("COOL CAMERA", mark), "hall girl talks about COOL CAMERA")
    d.shot(game, "04_hall_girl")

    -- pokeemerald/data/maps/DewfordTown_Hall/scripts.inc:82
    local painting = { [0] = "Scream", "Smile", "Last", "Birth", "Scream", "Scream", "Last", "Last" }
    local idx = (phrase[1] + phrase[2]) % 8
    mark = #M.msgs
    if S.adjacentTo(game, 7, 1) then
      U.tap(game, "a")
      U.wait(4)
      M.pump(game, {})
    end
    d.check(M.saw("COOL CAMERA", mark), "painting title uses the trend (" .. painting[idx] .. " title, index " .. idx .. ")")
    d.shot(game, "05_hall_painting")

    -- pokeemerald/src/dewford_trend.c:91
    local before = {}
    for i, t in ipairs(Dewford.trends(session)) do before[i] = t.trendiness .. (t.gainingTrendiness and "+" or "-") end
    local days0 = S.var("VAR_DAYS")
    Rtc.advance(24 * 60 * 3)
    mark = #M.msgs
    M.talk(game, "DewfordTown_Hall_EventScript_Girl", {})
    local after = {}
    for i, t in ipairs(Dewford.trends(session)) do after[i] = t.trendiness .. (t.gainingTrendiness and "+" or "-") end
    d.note("trendiness before " .. table.concat(before, " ") .. " after 3 days " .. table.concat(after, " "))
    d.check(table.concat(before, ",") ~= table.concat(after, ","), "UpdateDewfordTrendPerDay ran through dotimebasedevents")
    d.check(S.var("VAR_DAYS") == days0 + 3, "VAR_DAYS advanced by 3 (" .. days0 .. " -> " .. S.var("VAR_DAYS") .. ")")
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
