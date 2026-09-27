local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_mud_slope", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_mud_slope")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")

  S.check(F.goTo(game, "EM_GRANITE_CAVE_B1F", 9, 11, "up"), "Granite Cave B1F loads (" .. tostring(F.map()) .. ")")
  S.check(Collision.isMuddySlope(Collision.behavior(9, 10)) and Collision.isMuddySlope(Collision.behavior(9, 9)),
    "the slope is (9,9)-(9,10)")
  local minY, slid = Player.cellY, false
  F.holdKeys(game, { "up" }, 120, function(i)
    if Player.cellY < minY then minY = Player.cellY end
    if Player.moving and Player.moveDir == "down" and Player.facing == "up" and not slid then
      slid = true
      U.still(game, S.dir .. "/01_on_foot_slides.png")
    end
    return false
  end)
  U.wait(30)
  S.check(slid, "on foot the slope slides the player back down, facing up")
  S.check(minY >= 10 and Player.cellY >= 10, "on foot the player never gets past the slope (min y=" .. minY .. ")")

  local mach = F.give("ITEM_MACH_BIKE")
  F.goTo(game, "EM_GRANITE_CAVE_B1F", 9, 11, "up")
  F.useRegistered(game, mach)
  S.check(Player.biking and Player.bikeType == "mach", "on the Mach Bike")
  minY = Player.cellY
  F.holdKeys(game, { "up" }, 90, function() if Player.cellY < minY then minY = Player.cellY end end)
  U.wait(30)
  S.check(Player.cellY >= 10, "from a standing start the Mach Bike slides back (y=" .. Player.cellY .. ")")

  F.goTo(game, "EM_GRANITE_CAVE_B1F", 9, 13, "up")
  S.check(Player.biking, "still biking after the reload")
  local shot
  F.holdKeys(game, { "up" }, 90, function()
    if Player.targetY == 9 and Player.moving and not shot then
      shot = true
      U.still(game, S.dir .. "/02_mach_climbs.png")
    end
    return Player.cellY <= 8 and not Player.moving
  end)
  U.wait(20)
  S.check(Player.cellY <= 8, "with a run-up the Mach Bike climbs the slope (y=" .. Player.cellY .. ")")
  S.still(game, "03_top_of_slope.png")

  local acro = F.give("ITEM_ACRO_BIKE")
  F.useRegistered(game, acro)
  F.useRegistered(game, acro)
  F.goTo(game, "EM_GRANITE_CAVE_B1F", 9, 13, "up")
  S.check(Player.biking and Player.bikeType == "acro", "switched to the Acro Bike")
  F.holdKeys(game, { "up" }, 90)
  U.wait(30)
  S.check(Player.cellY >= 10, "the Acro Bike is too slow for the slope (y=" .. Player.cellY .. ")")
  S.finish()
end
