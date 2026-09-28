local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_frontier_tutor_preview", "/tmp/em_frontier_tutor_preview")
local LABEL = "BattleFrontier_Lounge7_EventScript_LeftMoveTutor"

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    d.check(M.goTo(game, "EM_BATTLE_FRONTIER_LOUNGE7", 2, 6, "up"), "Battle Frontier Lounge 7 loaded")
    d.shot(game, "01_lounge7")
    local preview = require("src.ui.game3.screens").get("frontier_preview", session)
    local shown = false
    local hookWasOpen = false
    local done = M.talk(game, LABEL, {
      answers = { 10 },
      onList = function()
        if not shown then
          shown = true
          hookWasOpen = preview.tutorOpen
          d.shot(game, "02_tutor_move_description")
        end
      end,
    })
    d.check(done, "Frontier tutor script opened the move chooser and exited cleanly")
    d.check(shown and hookWasOpen, "RSE tutor preview hook was enabled for the move list")
    d.check(preview.tutorOpen == false, "CloseBattleFrontierTutorWindow reset the preview hook")
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
