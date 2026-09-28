local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_diploma", "/tmp/em_diploma")
local LABEL = "LilycoveCity_CoveLilyMotel_2F_EventScript_GameDesigner"

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    S.setFlag("FLAG_HIDE_LILYCOVE_MOTEL_GAME_DESIGNERS", false)
    d.check(M.goTo(game, "EM_LILYCOVE_CITY_COVE_LILY_MOTEL_2F", 4, 7, "up"), "Cove Lily Motel 2F loaded")
    S.setFlag("FLAG_TEMP_2", true)
    local Diploma = require("src.ui.game3.diploma")
    local Audio = require("src.core.game3.audio")
    local captured = false
    local done = M.talk(game, LABEL, {
      onFrame = function()
        if Diploma.isOpen() then
          if not captured and Diploma.phase() == "wait" then
            captured = true
            d.check(Diploma._player == "" and Diploma._gameFreak == ""
              and Diploma._body:match("^PLAYER:") ~= nil
              and Diploma._body:find("GAME FREAK", 1, true) ~= nil,
              "Emerald diploma renders its single, complete certificate string")
            U.wait(120)
            d.shot(game, "01_emerald_hoenn_diploma")
          end
          if Diploma.phase() == "wait" then U.tap(game, "a") end
        end
      end,
    })
    d.check(done, "game designer script completed after Special_ShowDiploma")
    d.check(captured, "Special_ShowDiploma opened the Emerald diploma")
    d.check(Diploma.isNational() == false, "incomplete regional dex selected the Hoenn diploma")
    d.check(Audio.isFanfareFinished(), "diploma waited for its fanfare")
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
