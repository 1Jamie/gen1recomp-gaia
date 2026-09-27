local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_acro_route119_rails", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_acro_route119_rails")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local BikeRse = require("src.core.game3.bike.rse")

  S.check(F.goTo(game, "EM_ROUTE119", 7, 5, "right"), "Route 119 loads (" .. tostring(F.map()) .. ")")
  S.check(Collision.isHorizontalRail(Collision.behavior(8, 5)), "(8,5) is a horizontal rail")
  F.holdKeys(game, { "right" }, 40)
  S.check(Player.cellX == 7, "on foot the rail is a wall (x=" .. Player.cellX .. ")")

  local acro = F.give("ITEM_ACRO_BIKE")
  F.useRegistered(game, acro)
  S.check(Player.biking and Player.bikeType == "acro", "SELECT mounts the Acro Bike")
  S.still(game, "01_acro_mounted.png")

  local frames = {}
  F.holdKeys(game, { "right" }, 60, function()
    if Player.moving and Player.progress == 1 then frames[#frames + 1] = Player.stepFrames end
    if #frames == 2 and Player.progress == 3 then U.still(game, S.dir .. "/02_acro_on_rail.png") end
    return Player.cellX >= 10 and not Player.moving
  end)
  S.note("Acro rail step frames: " .. table.concat(frames, ","))
  S.check(frames[1] == 6, "the Acro Bike rides at MOVE_SPEED_FAST_2 (6 frames)")
  S.check(Player.cellX == 10 and Player.cellY == 5, "rode the rail to (10,5) (" .. Player.cellX .. "," .. Player.cellY .. ")")
  U.wait(20)

  F.holdKeys(game, { "down" }, 20)
  S.check(Player.cellY == 5, "DOWN alone on a horizontal rail does nothing")
  U.wait(10)

  local sawHop
  F.holdKeys(game, { "down", "b" }, 30, function()
    if Player.jumping and Player.jumpType == "normal" and not sawHop then
      sawHop = Player.progress
      if Player.progress >= 1 then U.still(game, S.dir .. "/03_side_jump.png") end
    end
    return false
  end)
  U.wait(10)
  S.check(sawHop ~= nil, "DOWN + B together side jumps")
  S.check(Player.cellY == 6 and Collision.isIsolatedHorizontalRail(Collision.behavior(Player.cellX, Player.cellY)),
    "landed on the isolated rail (" .. Player.cellX .. "," .. Player.cellY .. ")")
  F.holdKeys(game, { "down", "b" }, 30)
  U.wait(10)
  S.check(Player.cellY == 7, "a second side jump reaches the lower rail (y=" .. Player.cellY .. ")")
  F.holdKeys(game, { "right" }, 200, function() return Player.cellX >= 19 and not Player.moving end)
  S.check(Player.cellX >= 19, "rode the lower rail off its east end (x=" .. Player.cellX .. ")")
  S.still(game, "04_rail_end.png")

  F.goTo(game, "EM_ROUTE119", 4, 13, "right")
  S.check(Player.biking and Player.bikeType == "acro", "still on the Acro Bike after the reload")
  local popped, hopped = false, false
  F.holdKeys(game, { "b" }, 70, function(i)
    if Player.acroAnim and Player.acroAnim.kind == "back" and not popped then popped = true end
    if i == 20 then U.still(game, S.dir .. "/05_wheelie.png") end
    if Player.action and Player.action.jump == "low" and not hopped then
      hopped = true
    end
    if hopped and Player.action and Player.action.t == 6 then
      U.still(game, S.dir .. "/06_bunny_hop.png")
      return true
    end
    return false
  end)
  S.check(popped, "B from a standstill pops a wheelie")
  S.check(hopped, "holding B 40 frames bunny hops")
  S.check(BikeRse.state.acroState == BikeRse.ACRO.BUNNY_HOP, "ACRO_STATE_BUNNY_HOP")
  local x0 = Player.cellX
  F.holdKeys(game, { "b", "right" }, 60)
  S.check(Player.cellX > x0, "hopping with RIGHT hops forward (" .. x0 .. " -> " .. Player.cellX .. ")")
  U.wait(40)
  S.check(BikeRse.state.acroState == BikeRse.ACRO.NORMAL, "releasing B lowers the wheelie")
  S.finish()
end
