local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_exchange_corner_purchase", "/tmp/em_exchange_corner_purchase")
local LABEL = "BattleFrontier_ExchangeServiceCorner_EventScript_DecorClerk1"

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    local Frontier = require("src.core.game3.rse.frontier.util")
    local DecorInv = require("src.core.game3.rse.decoration_inventory")
    local C = S.C()
    local poster = C:require("decorations", "DECOR_KISS_POSTER")
    Frontier.frontier(session).battlePoints = 100
    d.check(M.goTo(game, "EM_BATTLE_FRONTIER_EXCHANGE_SERVICE_CORNER", 3, 4, "right"),
      "Exchange Service Corner loaded beside the decoration clerk")
    local preview = require("src.ui.game3.screens").get("frontier_preview", session)
    local previewShown = false
    local done = M.talk(game, LABEL, {
      answers = { 0, "yes", 10 },
      onList = function()
        if not previewShown then
          previewShown = true
          d.check(preview.exchangeOpen, "Emerald exchange item preview opened for the list")
          d.shot(game, "01_exchange_corner_poster_preview")
        end
      end,
    })
    d.check(done, "Exchange Corner clerk script completed after purchase")
    d.check(previewShown, "Exchange Corner displayed the decoration chooser")
    d.check(DecorInv.has(poster, session), "Kiss Poster was added to decoration inventory")
    d.check(Frontier.frontier(session).battlePoints == 84, "purchase deducted 16 Battle Points")
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
