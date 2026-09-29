local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_easy_chat_player", "/tmp/em_easy_chat_player")

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    local Player = require("src.core.game3.rse.easy_chat_player")
    local Bag = require("src.core.game3.bag")
    local C = require("src.core.game3.constants").of("emerald")

    -- pokeemerald/data/scripts/profile_man.inc:28
    d.check(M.goTo(game, "EM_PETALBURG_CITY_POKEMON_CENTER_1F", 11, 3, "up"), "in Petalburg Pokemon Center")
    local profile = { Player.BERRY_MASTER_WIFE_PHRASES[1][1], Player.BERRY_MASTER_WIFE_PHRASES[1][2],
      Player.BERRY_MASTER_WIFE_PHRASES[5][1], Player.BERRY_MASTER_WIFE_PHRASES[5][2] }
    local mark = #M.msgs
    local done = M.talk(game, "ProfileMan_EventScript_Man", {
      answers = { 0 },
      easyChat = function(st)
        d.check(st.type == 0, "easy chat opened as EASY_CHAT_TYPE_PROFILE (" .. tostring(st.type) .. ")")
        d.check(st.words[1] == Player.DEFAULT_PROFILE[1], "profile screen starts from I AM A POKEMON FRIEND")
        d.shot(game, "01_profile_screen")
        return profile
      end,
    })
    d.check(done, "Profile Man script finished")
    d.check(session.easyChatProfile and session.easyChatProfile[4] == profile[4], "session.easyChatProfile holds the new words")
    d.check(S.flag("FLAG_SYS_CHAT_USED"), "FLAG_SYS_CHAT_USED set")
    d.check(M.saw("fantastic", mark) or M.saw("F-fantastic", mark), "Profile Man praises the profile (VAR_RESULT 1)")
    d.check(M.saw("GREAT BATTLE", mark), "ShowEasyChatProfile prints the new profile")
    d.shot(game, "02_profile_done")

    mark = #M.msgs
    M.talk(game, "ProfileMan_EventScript_Man", { answers = { 0 }, easyChat = function(st) return st.words end })
    d.check(M.saw("not into it", mark) or M.saw("NOT into it", mark) or M.saw("right now", mark),
      "an unchanged profile goes to the cancel branch")

    -- pokeemerald/data/maps/Route123_BerryMastersHouse/scripts.inc:43
    d.check(M.goTo(game, "EM_ROUTE123_BERRY_MASTERS_HOUSE", 7, 5, "up"), "in the Berry Master's house")
    local spelon = C:require("items", "ITEM_SPELON_BERRY")
    mark = #M.msgs
    done = M.talk(game, "Route123_BerryMastersHouse_EventScript_BerryMastersWife", {
      easyChat = function(st)
        d.check(st.type == 13, "easy chat opened as EASY_CHAT_TYPE_GOOD_SAYING (" .. tostring(st.type) .. ")")
        d.check(st.words[1] == 0xFFFF and st.words[2] == 0xFFFF, "good saying starts empty")
        d.shot(game, "03_good_saying_screen")
        return { Player.BERRY_MASTER_WIFE_PHRASES[1][1], Player.BERRY_MASTER_WIFE_PHRASES[1][2] }
      end,
    })
    d.check(done, "Berry Master's wife script finished")
    d.check(Bag.has(session.bag, spelon, 1), "GREAT BATTLE earns the SPELON BERRY")
    d.check(S.flag("FLAG_RECEIVED_SPELON_BERRY"), "FLAG_RECEIVED_SPELON_BERRY set")
    d.check(S.flag("FLAG_DAILY_BERRY_MASTERS_WIFE"), "daily flag set")
    d.shot(game, "04_berry_given")

    -- pokeemerald/data/maps/BattleFrontier_BattleTowerLobby/scripts.inc:442
    d.check(M.goTo(game, "EM_BATTLE_FRONTIER_BATTLE_TOWER_LOBBY", 23, 6, "up"), "in the Battle Tower lobby")
    local won = { 1, 2, 3, 4, 5, 6 }
    for i = 1, 6 do won[i] = Player.DEFAULT_BATTLE.easyChatBattleLost[7 - i] end
    mark = #M.msgs
    done = M.talk(game, "BattleFrontier_BattleTowerLobby_EventScript_FeelingsMan", {
      answers = { 1 },
      easyChat = function(st)
        d.check(st.type == 2, "easy chat opened as EASY_CHAT_TYPE_BATTLE_WON (" .. tostring(st.type) .. ")")
        d.check(st.words[5] == Player.DEFAULT_BATTLE.easyChatBattleWon[5], "battle won screen starts from the saved words")
        d.shot(game, "05_battle_won_screen")
        return won
      end,
    })
    d.check(done, "Feelings man script finished")
    d.check(session.easyChatBattleWon and session.easyChatBattleWon[1] == won[1], "session.easyChatBattleWon holds the new words")
    local Tower = require("src.core.game3.rse.frontier.tower")
    local okT = pcall(Tower.saveBattleTowerRecord, session)
    local f = session.frontier
    d.check(okT and f and f.towerPlayer and f.towerPlayer.speechWon[1] == won[1], "the Battle Tower record carries the new words")
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
