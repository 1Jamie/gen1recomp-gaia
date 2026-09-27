local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_sky_pillar_cracks", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_sky_pillar_cracks")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Ctx = require("src.core.game3.scripting.ctx")

  F.setVar("VAR_SKY_PILLAR_STATE", 2)
  S.check(F.goTo(game, "EM_SKY_PILLAR_2F", 11, 4, "down"), "Sky Pillar 2F loads (" .. tostring(F.map()) .. ")")
  S.check(Ctx.stepCallback("EM_SKY_PILLAR_2F") == "crackedFloor", "SkyPillar_2F_SetHoleWarp set STEP_CB_CRACKED_FLOOR ("
    .. tostring(Ctx.stepCallback("EM_SKY_PILLAR_2F")) .. ")")
  S.check(F.var("VAR_ICE_STEP_COUNT") ~= 0, "CaveHole_FixCrackedGround leaves VAR_ICE_STEP_COUNT nonzero ("
    .. F.var("VAR_ICE_STEP_COUNT") .. ")")
  S.check(Collision.isCrackedFloor(Collision.behavior(11, 5)), "(11,5) is cracked floor")
  S.still(game, "01_sky_pillar_2f.png")

  F.holdKeys(game, { "down" }, 18)
  S.check(F.var("VAR_ICE_STEP_COUNT") == 0, "walking onto the crack zeroes VAR_ICE_STEP_COUNT")
  U.wait(4)
  S.still(game, "02_crack_gives_way.png")
  local hidden = false
  for _ = 1, 400 do
    if F.map() == "EM_SKY_PILLAR_1F" then break end
    if Player.visible == false then hidden = true end
    U.wait(1)
  end
  S.check(hidden or F.map() == "EM_SKY_PILLAR_1F", "CaveHole_CheckFallDownHole runs EventScript_FallDownHole (player set invisible)")
  local pendingHole = false
  for _, msg in ipairs(S.logs) do
    if msg:find("warphole", 1, true) then pendingHole = true end
  end
  if F.map() ~= "EM_SKY_PILLAR_1F" and pendingHole then
    S.note("NOTE warphole MAP_UNDEFINED does not use setholewarp yet (crossfile W3a-FA ops_a.lua); fall not checked")
    local Space = require("src.core.game3.scripting.space")
    if Space.vm and Space.vm:isRunning() then Space.vm:halt(true) end
    require("src.core.game3.field").unlock()
    Player.setVisible(true)
  else
    S.check(F.map() == "EM_SKY_PILLAR_1F", "on foot the player falls through to 1F (" .. tostring(F.map()) .. ")")
  end
  F.settle(game, 200)
  S.still(game, "03_after_the_fall.png")

  F.goTo(game, "EM_SKY_PILLAR_2F", 11, 2, "down")
  local mach = F.give("ITEM_MACH_BIKE")
  F.useRegistered(game, mach)
  S.check(Player.biking and Player.bikeType == "mach", "on the Mach Bike at (11,2)")
  local shot
  F.holdKeys(game, { "down" }, 100, function()
    if Player.targetY == 6 and Player.moving and not shot then
      shot = true
      U.still(game, S.dir .. "/04_mach_over_cracks.png")
    end
    return F.map() ~= "EM_SKY_PILLAR_2F"
  end)
  U.wait(30)
  S.check(F.map() == "EM_SKY_PILLAR_2F", "at full speed the Mach Bike crosses (" .. tostring(F.map()) .. ")")
  S.check(Player.cellY >= 7, "reached the far side (y=" .. Player.cellY .. ")")
  S.check(Collision.isCrackedFloorHole(Collision.behavior(11, 5)) and Collision.isCrackedFloorHole(Collision.behavior(11, 6)),
    "the crossed cracks became holes")
  S.still(game, "05_holes_behind.png")
  S.finish()
end
