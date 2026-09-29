local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_fan_club_interview", "/tmp/em_fan_club_interview")

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    local Party = require("src.core.game3.party")
    local Tv = require("src.core.game3.rse.tv")
    local EasyChat = require("src.ui.game3.easy_chat")
    Party.giveMon(session, S.species("SPECIES_ZIGZAGOON"), 10, "ZIGGY")
    d.check(require("src.core.game3.scripting.natives_tv") ~= nil, "natives_tv loaded")

    -- pokeemerald/data/scripts/interview.inc:94
    d.check(M.goTo(game, "EM_SLATEPORT_CITY_POKEMON_FAN_CLUB", 9, 6, "up"), "in the Slateport Fan Club")
    local opened, typed = {}, {}
    local done = M.talk(game, "SlateportCity_PokemonFanClub_EventScript_Reporter", {
      answers = { "yes" },
      onEasyChat = function(st)
        opened[#opened + 1] = st.type
        d.check(st.count == 1, "fan club screen has one word slot (" .. tostring(st.count) .. ")")
        d.shot(game, string.format("%02d_screen", #opened))
        U.tap(game, "a")
        U.wait(6)
        d.check(st.mode == "GROUP", "A on the slot opens the group list (" .. tostring(st.mode) .. ")")
        U.tap(game, "a")
        U.wait(6)
        d.check(st.mode == "WORD", "A on a group opens its words (" .. tostring(st.mode) .. ")")
        local g = st.groups[st.groupCursor]
        d.check(g and g.words and #g.words > 0, string.format("group %s lists words (%s)",
          tostring(g and g.id), tostring(g and g.words and #g.words)))        U.tap(game, "a")
        U.wait(6)
        typed[#typed + 1] = st.words[1]
        d.check(st.words[1] ~= 0xFFFF, "a word was entered into the slot (" .. tostring(st.words[1]) .. ")")
        d.shot(game, string.format("%02d_typed", #opened))
      end,
    })
    d.check(done, "reporter script finished")
    d.check(#opened == 2, "easy chat opened twice (" .. #opened .. ")")
    d.check(opened[1] == 7 and opened[2] == 7, "easy chat opened as EASY_CHAT_TYPE_FAN_CLUB")
    d.check(not EasyChat.isOpen(), "easy chat closed")
    local show
    for i = 0, Tv.NUM_NORMAL_TVSHOW_SLOTS - 1 do
      local s = session.tvShows[i]
      if s and s.kind == Tv.TVSHOW_PKMN_FAN_CLUB_OPINIONS then show = s end
    end
    d.check(show ~= nil, "fan club opinions show queued")
    d.check(show and show.words and show.words[1] == typed[1] and show.words[2] == typed[2],
      "show words hold the entered words")
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
