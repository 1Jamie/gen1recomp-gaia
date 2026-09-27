local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_mauville_old_man", "/tmp/em_mauville_old_man")

local MAP = "EM_MAUVILLE_CITY_POKEMON_CENTER_1F"
local LABEL = "MauvilleCity_PokemonCenter_1F_EventScript_MauvilleOldMan"

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    local OldMan = require("src.core.game3.rse.old_man")
    local NativesOldMan = require("src.core.game3.scripting.natives_old_man")
    local Town = require("src.core.game3.rse.town_common")
    local Bard = require("src.core.game3.rse.bard_music")
    local Party = require("src.core.game3.party")
    Party.giveMonToPlayer(session, S.species("SPECIES_TORCHIC"), 20)

    local function oldMan(tid)
      session.trainerId = tid
      OldMan.set(session)
      d.check(M.goTo(game, MAP, 3, 5, "up"), "entered Mauville Pokemon Center 1F (old man " .. session.oldMan.id .. ")")
    end

    -- pokeemerald/data/scripts/mauville_man.inc:12
    oldMan(10)
    d.check(S.var("VAR_OBJ_GFX_ID_0") == S.C():require("event_objects", "OBJ_EVENT_GFX_BARD"),
      "SetMauvilleOldManObjEventGfx: VAR_OBJ_GFX_ID_0 = OBJ_EVENT_GFX_BARD")
    d.shot(game, "01_bard_in_center")
    local sawSong = false
    local mark = #M.msgs
    local done = M.talk(game, LABEL, {
      answers = { "yes", "no" },
      holdMessage = function() return NativesOldMan.singing == true end,
      onFrame = function()
        if NativesOldMan.singing and not sawSong then
          local info = NativesOldMan.lastBard
          if info and #info.texts >= 6 then
            sawSong = true
            d.shot(game, "02_bard_singing")
          end
        end
      end,
    })
    d.check(done, "bard script finished")
    local info = NativesOldMan.lastBard
    d.check(info ~= nil, "PlayBardSong rendered a song")
    if info then
      d.note(string.format("bard default song: %d samples (%.2fs) peak %.4f, %d phoneme starts, %d frames, bake %.3fs",
        info.samples, info.seconds, info.peak, info.phonemes, info.frames, info.bakeSeconds))
      d.check(info.samples > 44100 * 3 and info.peak > 0.01, "sample rendering is audible and > 3 s")
      d.check(info.phonemes >= 6, "at least one phoneme per lyric word (" .. info.phonemes .. ")")
      local joined = table.concat(info.texts, "|")
      d.check(joined:find("SHAKE IT\nDO", 1, true) ~= nil and joined:find("THE DIET\nDANCE", 1, true) ~= nil,
        "song text revealed as SHAKE IT / DO then THE DIET / DANCE")
      local sim = Bard.simulate(info.lyrics)
      local pcm = Bard.bake(sim)
      if M.wav(d.dir .. "/bard_default_song.wav", pcm) then d.note("wrote " .. d.dir .. "/bard_default_song.wav") end
    end
    d.check(sawSong, "song box captured mid-song")
    if not d.check(M.saw("write some", mark), "bard asks to write new lyrics after an unchanged song") then
      for i = mark + 1, #M.msgs do d.note("msg " .. i .. ": " .. M.msgs[i]:gsub("\n", "/")) end
    end

    -- pokeemerald/data/scripts/mauville_man.inc:43
    local newWords
    mark = #M.msgs
    NativesOldMan.lastBard = nil
    done = M.talk(game, LABEL, {
      answers = { "yes", "yes", "yes" },
      holdMessage = function() return NativesOldMan.singing == true end,
      easyChat = function(st)
        d.check(st.type == 6, "easy chat opened as EASY_CHAT_TYPE_BARD_SONG (" .. tostring(st.type) .. ")")
        d.check(st.count == 6, "bard lyrics screen has 6 slots (" .. tostring(st.count) .. ")")
        d.shot(game, "03_bard_lyrics_screen")
        local w = {}
        for i = 1, 6 do w[i] = st.words[i] end
        w[1], w[6] = w[6], w[1]
        newWords = w
        return w
      end,
    })
    d.check(done, "write-lyrics script finished")
    d.check(NativesOldMan.lastBard ~= nil and NativesOldMan.lastBard.lyrics[1] == newWords[1], "bard sang the new lyrics")
    d.check(session.oldMan.hasChangedSong == true and session.oldMan.songLyrics[1] == newWords[1],
      "SaveBardSongLyrics stored the new song")
    d.check(M.saw("sing this song", mark) or M.saw("this song for a while", mark), "bard promises to sing the new song")
    d.shot(game, "04_bard_saved")

    -- pokeemerald/data/scripts/mauville_man.inc:67
    oldMan(12)
    mark = #M.msgs
    done = M.talk(game, LABEL, {})
    d.check(done and S.flag("FLAG_UNLOCKED_TRENDY_SAYINGS"), "hipster sets FLAG_UNLOCKED_TRENDY_SAYINGS")
    d.check(session.oldMan.taughtWord == true, "hipster taught a word")
    local unlocked = 0
    for i = 0, OldMan.NUM_TRENDY_SAYINGS - 1 do if OldMan.isTrendySayingUnlocked(i, session) then unlocked = unlocked + 1 end end
    d.check(unlocked == 1, "one trendy saying unlocked (" .. unlocked .. ")")
    d.check(M.saw("HAVE YOU HEARD", mark) or M.saw("heard", mark) or M.saw("Heard", mark), "hipster names the word")
    d.shot(game, "05_hipster")
    done = M.talk(game, LABEL, {})
    d.check(M.saw("already", #M.msgs - 3), "hipster already taught you")

    -- pokeemerald/data/scripts/mauville_man.inc:872
    oldMan(18)
    mark = #M.msgs
    done = M.talk(game, LABEL, { answers = { "yes", "yes", "no", "yes", "no", "yes", "no", "yes", "no", "yes", "no", "yes" } })
    d.check(done, "giddy script finished")
    d.check(M.saw("Don't you agree?", mark) or M.saw("?", mark + 1), "giddy told a tale")
    d.check(M.saw("chat again", mark), "giddy ran out of tales")
    d.shot(game, "06_giddy")

    -- pokeemerald/data/scripts/mauville_man.inc:790
    oldMan(16)
    session.gameStats = session.gameStats or {}
    session.gameStats[9] = 57
    mark = #M.msgs
    done = M.talk(game, LABEL, { answers = { "yes", "yes" } })
    d.check(done and OldMan.freeStorySlot(session) == 1, "storyteller recorded a legend")
    d.check(M.saw("57", mark), "storyteller quotes the stat value 57")
    session.gameStats[9] = 60
    mark = #M.msgs
    done = M.talk(game, LABEL, { answers = { "yes", 0 } })
    d.check(done and session.oldMan.statValues[1] == 60, "retelling after a stat increase re-records 60")
    d.check(M.saw("This is a tale of a TRAINER", mark), "story text shown")
    d.shot(game, "07_storyteller")

    -- pokeemerald/data/scripts/mauville_man.inc:604
    oldMan(14)
    local Inv = require("src.core.game3.rse.decoration_inventory")
    local myDecor = S.C():require("decorations", "DECOR_PIKA_CUSHION")
    Inv.add(myDecor, session)
    local want = session.oldMan.decorations[1]
    mark = #M.msgs
    done = M.talk(game, LABEL, { answers = { "yes", 0, "yes", "yes" }, decor = { Inv.categoryOf(myDecor), 0 } })
    d.check(done, "trader script finished")
    d.check(Inv.has(want, session) and not Inv.has(myDecor, session), "traded for the trader's first decoration")
    d.check(session.oldMan.alreadyTraded == true and session.oldMan.decorations[1] == myDecor, "trader keeps the player's decoration")
    d.check(M.saw("send my decoration", mark) or M.saw("trade", mark), "trade completed message")
    d.shot(game, "08_trader")
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
