local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_route113_ash", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_route113_ash")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Ctx = require("src.core.game3.scripting.ctx")
  local Steps = require("src.core.game3.step_callbacks_rse")
  local C = require("src.core.game3.constants").of("emerald")
  local ASH = C:require("metatile_labels", "METATILE_Fallarbor_AshGrass")
  local MOWED = C:require("metatile_labels", "METATILE_Fallarbor_NormalGrass")

  F.give("ITEM_SOOT_SACK")
  F.setVar("VAR_ASH_GATHER_COUNT", 0)
  S.check(F.goTo(game, "EM_ROUTE113", 34, 6, "right"), "Route 113 loads (" .. tostring(F.map()) .. ")")
  S.check(Ctx.stepCallback("EM_ROUTE113") == "ash", "Route113_OnResume set STEP_CB_ASH ("
    .. tostring(Ctx.stepCallback("EM_ROUTE113")) .. ")")
  local wasAsh, ashCells = {}, 0
  for x = 35, 44 do
    wasAsh[x] = Steps.metatileAt(x, 6) == ASH
    if wasAsh[x] then ashCells = ashCells + 1 end
  end
  S.check(ashCells >= 6, "ash grass east of (34,6) (" .. ashCells .. " cells)")
  S.still(game, "01_route113_ash.png")

  local mid
  F.holdKeys(game, { "right" }, 8 * 16 + 8, function()
    if Player.cellX == 38 and not mid then
      mid = true
      U.still(game, S.dir .. "/02_walking_through_ash.png")
    end
    return Player.cellX >= 42 and not Player.moving
  end)
  U.wait(10)
  local walked, mowed = 0, 0
  for x = 35, Player.cellX do
    if wasAsh[x] then walked = walked + 1 end
    if wasAsh[x] and Steps.metatileAt(x, 6) == MOWED then mowed = mowed + 1 end
  end
  S.check(Player.cellX >= 42, "walked to (" .. Player.cellX .. ",6)")
  S.check(mowed == walked and walked >= 6, "every ash cell walked over is plain grass now (" .. mowed .. "/" .. walked .. ")")
  S.check(F.var("VAR_ASH_GATHER_COUNT") == walked, "the Soot Sack counted " .. F.var("VAR_ASH_GATHER_COUNT") .. " ash")
  S.check(Steps.metatileAt(Player.cellX + 1, 6) == ASH, "the cell ahead still has its ash")
  S.still(game, "03_ash_swept.png")

  local sack = C:require("items", "ITEM_SOOT_SACK")
  require("src.core.game3.bag").remove(require("src.core.game3.runtime").getSession().bag, sack, 1)
  local before = F.var("VAR_ASH_GATHER_COUNT")
  F.holdKeys(game, { "down" }, 20)
  F.holdKeys(game, { "left" }, 16 * 3, function() return not Player.moving and Player.cellX <= 39 end)
  U.wait(10)
  local y = Player.cellY
  S.check(Steps.metatileAt(Player.cellX, y) ~= ASH, "the row below was swept too")
  S.check(F.var("VAR_ASH_GATHER_COUNT") == before, "without the Soot Sack nothing is gathered")
  S.finish()
end
