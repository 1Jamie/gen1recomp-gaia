-- Yellow's three Kanto-starter side-quests, hand-ported from
-- scripts/CeruleanMelaniesHouse.asm, scripts/Route24.asm
-- (Route24CooltrainerM4Text) and scripts/VermilionCity_2.asm
-- (VermilionCityPrintOfficerJennyText).  Registered on top of the shared
-- Red map scripts by data/scripts/init.lua on a Yellow boot only, so the
-- table keys compose with story.lua / story4.lua's existing entries.

local M = {}

-- Melanie hands over her Bulbasaur once the starter Pikachu trusts you
-- (wPikachuHappiness >= 147).
M.CERULEAN_MELANIES_HOUSE = {
  talk = {
    TEXT_CERULEANMELANIESHOUSE_MELANIE = function(game, ow, npc, done)
      local rows = { { "face_player" } }
      if game.save.flags.EVENT_GOT_BULBASAUR_IN_CERULEAN then
        rows[#rows + 1] = { "show_text", "MelanieText4" }
      elseif (game.save.pikachuHappiness or 90) < 147 then
        rows[#rows + 1] = { "show_text", "MelanieText1" }
      else
        rows[#rows + 1] = { "show_text", "MelanieText1" }
        rows[#rows + 1] = { "ask", "MelanieText2" }
        rows[#rows + 1] = { "jump_if_false", "declined" }
        rows[#rows + 1] = { "give_pokemon", "BULBASAUR", 10 }
        rows[#rows + 1] = { "jump_if_false", "end" } -- party + box full
        rows[#rows + 1] = { "show_text", "MelanieText3" }
        rows[#rows + 1] = { "hide_object", "CERULEAN_MELANIES_HOUSE",
                            "CERULEANMELANIESHOUSE_BULBASAUR" }
        rows[#rows + 1] = { "set_flag", "EVENT_GOT_BULBASAUR_IN_CERULEAN" }
        rows[#rows + 1] = { "jump", "end" }
        rows[#rows + 1] = { "label", "declined" }
        rows[#rows + 1] = { "show_text", "MelanieText5" }
      end
      ow.runner:run(rows, { npc = npc, onDone = done })
    end,
    -- pet flavor: the text with the species' cry over it
    TEXT_CERULEANMELANIESHOUSE_BULBASAUR = {
      { "play_cry", "BULBASAUR" },
      { "show_text", "MelanieBulbasaurText" },
    },
    TEXT_CERULEANMELANIESHOUSE_ODDISH = {
      { "play_cry", "ODDISH" },
      { "show_text", "MelanieOddishText" },
    },
    TEXT_CERULEANMELANIESHOUSE_SANDSHREW = {
      { "play_cry", "SANDSHREW" },
      { "show_text", "MelanieSandshrewText" },
    },
  },
}

-- Damian gives away the Charmander he thinks is too weak (EVENT_54F).
M.ROUTE_24 = {
  talk = {
    TEXT_ROUTE24_COOLTRAINER_M4 = {
      { "face_player" },
      { "check_flag", "EVENT_54F" },
      { "jump_if_true", "after" },
      { "ask", "_Route24DamianText1" },
      { "jump_if_false", "declined" },
      { "give_pokemon", "CHARMANDER", 10 },
      { "jump_if_false", "end" },
      { "show_text", "_Route24DamianText2" },
      { "set_flag", "EVENT_54F" },
      { "jump", "end" },
      { "label", "declined" },
      { "show_text", "_Route24DamianText3" },
      { "jump", "end" },
      { "label", "after" },
      { "show_text", "_Route24DamianText4" },
    },
  },
}

-- Officer Jenny's Squirtle: kept until you carry the Thunder Badge.
M.VERMILION_CITY = {
  talk = {
    TEXT_VERMILIONCITY_OFFICER_JENNY = function(game, ow, npc, done)
      local rows = { { "face_player" } }
      if game.save.flags.EVENT_GOT_SQUIRTLE_FROM_OFFICER_JENNY then
        rows[#rows + 1] = { "show_text", "_OfficerJennyText5" }
      elseif not (game.save.inventory
                  and game.save.inventory.THUNDERBADGE) then
        rows[#rows + 1] = { "show_text", "_OfficerJennyText1" }
      else
        rows[#rows + 1] = { "ask", "_OfficerJennyText2" }
        rows[#rows + 1] = { "jump_if_false", "declined" }
        rows[#rows + 1] = { "give_pokemon", "SQUIRTLE", 10 }
        rows[#rows + 1] = { "jump_if_false", "end" }
        rows[#rows + 1] = { "show_text", "_OfficerJennyText3" }
        rows[#rows + 1] = { "set_flag",
                            "EVENT_GOT_SQUIRTLE_FROM_OFFICER_JENNY" }
        rows[#rows + 1] = { "jump", "end" }
        rows[#rows + 1] = { "label", "declined" }
        rows[#rows + 1] = { "show_text", "_OfficerJennyText4" }
      end
      ow.runner:run(rows, { npc = npc, onDone = done })
    end,
  },
}

return M
