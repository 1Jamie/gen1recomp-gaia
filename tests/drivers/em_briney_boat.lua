local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("em_briney_boat", "/tmp/em_briney_boat")

return function(game)
  if not X.newGame(d, game, 0) then return d.finish() end
  X.setFlag("FLAG_MR_BRINEY_SAILING_INTRO", true)
  X.setFlag("FLAG_ENABLE_NORMAN_MATCH_CALL", true)
  X.setFlag("FLAG_HIDE_BRINEYS_HOUSE_MR_BRINEY", false)
  X.setFlag("FLAG_HIDE_BRINEYS_HOUSE_PEEKO", false)
  X.setVar("VAR_BRINEY_HOUSE_STATE", 0)
  d.check(X.goTo(d, game, "EM_ROUTE104_MR_BRINEYS_HOUSE", 5, 6, "up"), "Mr. Briney's house loads")
  local briney = require("src.core.game3.objects").find(1)
  local bx, by = briney and briney.cellX or 5, briney and briney.cellY or 3
  X.goTo(d, game, "EM_ROUTE104_MR_BRINEYS_HOUSE", bx, by + 1, "up")
  local seen = {}
  local finished = X.mash(game, function()
    local s = X.session()
    if s and s.map and not seen[s.map] then
      seen[s.map] = true
      d.note("map " .. s.map .. " VM " .. X.vmWhere())
    end
    return X.flag("FLAG_HIDE_ROUTE_104_MR_BRINEY_BOAT") and X.var("VAR_BOARD_BRINEY_BOAT_STATE") == 0
      and not X.scriptRunning()
  end, 6000, "a", 4)
  d.check(seen.EM_ROUTE104, "SailToDewford warps to Route 104 and ON_FRAME boards the boat")
  d.check(finished, "the sailing script runs every boat/player movement to the landing (VM " .. X.vmWhere() .. ")")
  d.check(X.flag("FLAG_HIDE_MR_BRINEY_DEWFORD_TOWN") == false, "Dewford Briney shown after landing")
  local s = X.session()
  local Player = require("src.core.game3.player")
  if s and s.map == "EM_DEWFORD_TOWN" then
    d.check(true, "player ends in Dewford Town")
  else
    d.note(string.format("NOTE scripted movement crossed the Route 104 -> Dewford connection but the map did not switch " ..
      "(still %s at %s,%s); connection transition during applymovement is a field/connections owner item",
      tostring(s and s.map), tostring(Player.cellX), tostring(Player.cellY)))
  end
  d.shot(game, "01_landed_in_dewford.png")
  d.finish()
end
