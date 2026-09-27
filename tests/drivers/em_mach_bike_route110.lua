local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_mach_bike_route110", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_mach_bike_route110")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Constants = require("src.core.game3.constants")
  local C = Constants.of("emerald")

  F.noTrainerSight()
  S.check(F.goTo(game, "EM_ROUTE110", 27, 20, "up"), "Route 110 loads (" .. tostring(F.map()) .. ")")
  local runX, runY
  for y = 29, 12, -1 do
    for x = 26, 28 do
      local free = true
      for i = 0, 10 do
        if not Collision.canEnter(game, x, y - i, {}) then free = false break end
      end
      if free then runX, runY = x, y break end
    end
    if runX then break end
  end
  if not S.check(runX ~= nil, "a clear ten-cell run north on the Seaside Cycling Road (" .. tostring(runX) .. "," .. tostring(runY) .. ")") then
    return S.finish()
  end
  F.goTo(game, "EM_ROUTE110", runX, runY, "up")
  local mach = F.give("ITEM_MACH_BIKE")
  local mapSong = F.songId()
  F.useRegistered(game, mach)
  S.check(Player.biking and Player.bikeType == "mach", "SELECT on the registered Mach Bike mounts it")
  S.check(F.songId() == C:require("songs", "MUS_CYCLING"),
    "MUS_CYCLING plays (" .. tostring(F.songId()) .. ", map song " .. tostring(mapSong) .. ")")
  S.still(game, "01_mach_mounted.png")

  local frames = {}
  local lastY = Player.cellY
  F.holdKeys(game, { "up" }, 90, function()
    if Player.moving and Player.progress == 1 then frames[#frames + 1] = Player.stepFrames end
    if #frames == 4 and Player.progress == 2 then
      U.still(game, S.dir .. "/02_mach_full_speed.png")
    end
    return #frames >= 6
  end)
  S.note("Mach step frames: " .. table.concat(frames, ","))
  S.check(frames[1] == 16 and frames[2] == 8 and frames[3] == 4, "speed tiers 16/8/4 frames (sMachBikeSpeeds)")
  S.check(frames[5] == 4 and frames[6] == 4, "full speed holds 4 frames a cell")
  S.check(Player.cellY < lastY - 3, "rode north (" .. lastY .. " -> " .. Player.cellY .. ")")

  local coastStart = Player.cellY
  for _ = 1, 60 do U.wait(1) end
  S.check(Player.moving == false and Player.cellY < coastStart, "releasing the D-pad coasts, then stops ("
    .. coastStart .. " -> " .. Player.cellY .. ")")
  S.still(game, "03_mach_stopped.png")

  F.holdKeys(game, { "right" }, 2)
  U.wait(12)
  S.check(Player.facing == "right" and Player.cellY <= coastStart, "a standing turn faces without moving")

  F.useRegistered(game, mach)
  S.check(not Player.biking, "SELECT again dismounts")
  local Audio = require("src.core.game3.audio")
  S.check(Audio._savedSong == nil and Audio.specialMapSong() == mapSong,
    "dismounting clears the saved MUS_CYCLING and targets the map song (" .. tostring(Audio.specialMapSong()) .. ")")
  S.still(game, "04_dismounted.png")

  F.goTo(game, "EM_ROUTE110_SEASIDE_CYCLING_ROAD_SOUTH_ENTRANCE", 5, 5, "up")
  F.useRegistered(game, mach)
  S.check(Player.biking, "the cycling road gate house allows cycling (" .. tostring(F.map()) .. ")")
  F.useRegistered(game, mach)
  F.goTo(game, "EM_PETALBURG_CITY_MART", 4, 6, "up")
  F.useRegistered(game, mach)
  S.check(not Player.biking, "a mart has allowCycling=0: no bike (" .. tostring(F.map()) .. ")")
  local Message = require("src.ui.game3.message")
  U.wait(20)
  S.check(Message.isOpen and Message.isOpen(), "Dad's advice message opens")
  S.still(game, "05_dads_advice.png")
  F.settle(game, 200)
  S.finish()
end
