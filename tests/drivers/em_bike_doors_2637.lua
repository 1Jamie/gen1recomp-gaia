local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_bike_doors_2637", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_bike_doors_2637")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Player = require("src.core.game3.player")
  local Bike = require("src.core.game3.bike")
  local Warp = require("src.core.game3.warp")
  local Collision = require("src.core.game3.collision")
  local session = Runtime.getSession()
  if not S.check(session.version == "emerald", "driver runs Emerald") then return S.finish() end
  local function place(kind, x, y, facing)
    if Player.biking then Bike.rse(session).getOnOff(kind, session) end
    S.check(F.goTo(game, "EM_MAUVILLE_CITY", x, y, facing), "Mauville approach loaded")
    local item = F.give(kind == "mach" and "ITEM_MACH_BIKE" or "ITEM_ACRO_BIKE")
    F.useRegistered(game, item)
    S.check(Player.biking and Player.bikeType == kind, kind .. " mounted through registered item")
  end
  local function rideUntilLastFrame(dir, tx, ty)
    local ready = false
    F.holdKeys(game, { dir }, 180, function()
      ready = Player.moving and Player.targetX == tx and Player.targetY == ty
        and Player.progress >= Player.stepFrames - 1
      return ready
    end)
    return S.check(ready, "approach last frame " .. tx .. "," .. ty)
  end
  local function enterAndExit(kind, x, tag)
    local door = Collision.isDoorWarp(game, x, 5)
    if not S.check(door ~= nil, tag .. " has real animated door warp") then return false end
    F.holdKeys(game, { "up" }, 90, function() return F.map() ~= "EM_MAUVILLE_CITY" end)
    F.settle(game, 500)
    if not S.check(F.map() == door.destMap, tag .. " actual door enters destination") then return false end
    S.check(not Player.biking, tag .. " indoors dismounts " .. kind)
    S.check(S.still(game, tag .. "_inside.png"), tag .. " stable indoor screenshot")
    local def = game.data.maps[F.map()]
    local exit
    for _, w in ipairs(def.warps or {}) do
      if w.destMap == "EM_MAUVILLE_CITY" then exit = w break end
    end
    if not S.check(exit ~= nil, tag .. " has outdoor exit mat") then return false end
    F.holdKeys(game, { "down" }, 140, function() return F.map() == "EM_MAUVILLE_CITY" end)
    F.settle(game, 500)
    S.check(F.map() == "EM_MAUVILLE_CITY", tag .. " actual exit returns outdoors")
    return true
  end
  for _, kind in ipairs({ "mach", "acro" }) do
    for _, x in ipairs({ 22, 35 }) do
      local tag = kind .. "_" .. (x == 22 and "center" or "shop")
      place(kind, x - 1, 6, "right")
      if rideUntilLastFrame("right", x, 6) then
        F.holdKeys(game, { "up" }, 1)
        S.check(Player.cellX == x and Player.cellY == 6 and not Player.moving and not Warp.isBusy(),
          tag .. " changed heading blocks unclaimed door step")
        S.note(tag .. " facing=" .. Player.facing .. " running=" .. Bike.rse(session).state.running)
        U.wait(20)
        S.check(S.still(game, tag .. "_approach.png"), tag .. " stable approach screenshot")
        enterAndExit(kind, x, tag)
      end
      place(kind, x, 6, "up")
      enterAndExit(kind, x, tag .. "_straight")
    end
  end
  place("mach", 22, 8, "up")
  if rideUntilLastFrame("up", 22, 6) then
    U.wait(50)
    S.check(Player.cellY == 6 and not Player.moving and F.map() == "EM_MAUVILLE_CITY" and not Warp.isBusy(),
      "Mach coast stops south of Center without opening door")
    S.check(S.still(game, "mach_coast_stopped.png"), "Mach coast stable screenshot")
    enterAndExit("mach", 22, "mach_coast")
  end
  S.finish()
end
