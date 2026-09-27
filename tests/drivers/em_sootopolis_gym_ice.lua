local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_sootopolis_gym_ice", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_sootopolis_gym_ice")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Ctx = require("src.core.game3.scripting.ctx")
  local Steps = require("src.core.game3.step_callbacks_rse")
  local C = require("src.core.game3.constants").of("emerald")
  local CRACKED = C:require("metatile_labels", "METATILE_SootopolisGym_Ice_Cracked")
  local BROKEN = C:require("metatile_labels", "METATILE_SootopolisGym_Ice_Broken")

  S.check(F.goTo(game, "EM_SOOTOPOLIS_CITY_GYM_1F", 8, 20, "up"), "Sootopolis Gym 1F loads (" .. tostring(F.map()) .. ")")
  S.check(Ctx.stepCallback("EM_SOOTOPOLIS_CITY_GYM_1F") == "sootopolisIce",
    "OnResume set STEP_CB_SOOTOPOLIS_ICE (" .. tostring(Ctx.stepCallback("EM_SOOTOPOLIS_CITY_GYM_1F")) .. ")")
  S.check(F.var("VAR_ICE_STEP_COUNT") == 1, "OnTransition set VAR_ICE_STEP_COUNT 1 (" .. F.var("VAR_ICE_STEP_COUNT") .. ")")
  S.check(Collision.isThinIce(Collision.behavior(8, 19)), "(8,19) is thin ice")
  S.still(game, "01_gym_ice.png")

  F.holdKeys(game, { "up" }, 16 * 4, function() return Player.targetY <= 17 end)
  U.wait(24)
  S.check(Player.cellY == 17, "walked up over three ice tiles (y=" .. Player.cellY .. ")")
  local cracked = 0
  for y = 17, 19 do
    if Steps.metatileAt(8, y) == CRACKED then cracked = cracked + 1 end
  end
  S.check(cracked == 3, "each thin ice tile cracked (" .. cracked .. ")")
  S.check(F.var("VAR_ICE_STEP_COUNT") == 4, "VAR_ICE_STEP_COUNT counted the steps (" .. F.var("VAR_ICE_STEP_COUNT") .. ")")
  S.check(Steps.isIceVisited(8, 17) and Steps.isIceVisited(8, 19), "row vars mark the cracked tiles")
  S.check(Collision.isSlideSouth(Collision.behavior(8, 16)), "the stairs at (8,16) are still a south slide")
  S.still(game, "02_cracked_trail.png")

  F.holdKeys(game, { "down" }, 30, function() return Player.targetY >= 18 end)
  U.wait(24)
  S.check(Steps.metatileAt(8, 18) == BROKEN, "stepping back onto cracked ice breaks it")
  S.still(game, "03_ice_breaks.png")
  for _ = 1, 400 do
    if F.map() == "EM_SOOTOPOLIS_CITY_GYM_B1F" then break end
    U.wait(1)
  end
  S.check(F.map() == "EM_SOOTOPOLIS_CITY_GYM_B1F", "the player falls through to B1F (" .. tostring(F.map()) .. ")")
  F.settle(game, 200)
  S.still(game, "04_gym_b1f.png")

  F.goTo(game, "EM_SOOTOPOLIS_CITY_GYM_1F", 8, 20, "up")
  local Natives = require("src.core.game3.scripting.natives")
  if not Natives.handlerFor("SetSootopolisGymCrackedIceMetatiles") then
    S.note("NOTE SetSootopolisGymCrackedIceMetatiles is not bound yet (crossfile W3a-FA natives_field_rse)")
    return S.finish()
  end
  local afterWarp = 0
  for y = 17, 19 do
    if Steps.metatileAt(8, y) == CRACKED then afterWarp = afterWarp + 1 end
  end
  S.check(afterWarp == 0, "a warp back in clears the temp row vars, so no cracks (" .. afterWarp .. ")")
  F.holdKeys(game, { "up" }, 16 * 4, function() return Player.targetY <= 17 end)
  U.wait(24)
  local Space = require("src.core.game3.scripting.space")
  local Map = require("src.core.game3.map")
  require("src.core.game3.field").clearMetatiles(Map._def and Map._def.midLayout)
  local cleared = 0
  for y = 17, 19 do
    if Steps.metatileAt(8, y) == CRACKED then cleared = cleared + 1 end
  end
  Space.runOnLoad("EM_SOOTOPOLIS_CITY_GYM_1F")
  local restored = 0
  for y = 17, 19 do
    if Steps.metatileAt(8, y) == CRACKED then restored = restored + 1 end
  end
  S.check(cleared == 0 and restored == 3,
    "ON_LOAD SetSootopolisGymCrackedIceMetatiles redraws the visited cracks (" .. cleared .. " -> " .. restored .. ")")
  S.still(game, "05_reload_cracks.png")
  S.finish()
end
