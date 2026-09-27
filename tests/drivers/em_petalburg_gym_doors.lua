local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("em_petalburg_gym_doors", "/tmp/em_petalburg_gym_doors")
local MAP = "EM_PETALBURG_CITY_GYM"

local function labels()
  local src = require("src.core.game3.dataset").cache():read("data/generated/gba/scripts/labels.lua")
  return assert(load(src, "labels", "t", {}))()
end

local function frameOf(mid)
  for f = 0, 4 do
    if mid == X.label("METATILE_PetalburgGym_SlidingDoor_Frame" .. f) then return f end
  end
  return nil
end

return function(game)
  if not X.newGame(d, game, 0) then return d.finish() end
  X.setVar("VAR_PETALBURG_GYM_STATE", 6)
  d.check(X.goTo(d, game, MAP, 4, 107, "up"), "Petalburg Gym loads with VAR_PETALBURG_GYM_STATE=6")
  X.settle(game)
  local f4 = X.label("METATILE_PetalburgGym_SlidingDoor_Frame4")
  d.check(X.metatile(1, 104) == f4 and X.metatile(7, 104) == f4,
    "ON_LOAD PetalburgGymUnlockRoomDoors opens the entrance room doors (" .. tostring(X.metatile(1, 104)) .. ")")
  d.check(X.metatile(1, 105) == f4 + 8, "lower door half is the next metatile row (METATILE_ROW_WIDTH)")
  d.check(X.metatile(6, 85) == X.label("METATILE_PetalburgGym_RoomEntrance_Left"),
    "entrance room exits get their RoomEntrance metatiles")
  d.note("speed room door before: frame " .. tostring(frameOf(X.metatile(1, 78))) .. " mid " .. tostring(X.metatile(1, 78)))
  X.goTo(d, game, MAP, 4, 80, "up")
  X.settle(game)
  d.shot(game, "01_speed_room_doors_closed.png")

  local L = labels()
  local key = L.PetalburgCity_Gym_EventScript_SlideOpenSpeedRoomDoors
  local Space = require("src.core.game3.scripting.space")
  local seen, last, frames = {}, nil, 0
  d.try("start SlideOpenSpeedRoomDoors", function() Space.vm:start(key) end)
  for _ = 1, 600 do
    local f = frameOf(X.metatile(1, 78))
    if f ~= last then
      seen[#seen + 1] = tostring(f) .. "@" .. frames
      last = f
    end
    if not X.scriptRunning() then break end
    frames = frames + 1
    U.wait(1)
  end
  d.note("door frames seen " .. table.concat(seen, " "))
  d.check(frameOf(X.metatile(1, 78)) == 4 and frameOf(X.metatile(7, 78)) == 4,
    "PetalburgGymSlideOpenRoomDoors ends on SlidingDoor_Frame4 for both speed room doors")
  d.check(#seen >= 2, "the doors animate through the sliding frames (" .. #seen .. " changes)")
  d.check(not X.scriptRunning(), "waitstate releases the script once the slide finishes")
  local Collision = require("src.core.game3.collision")
  d.check(not Collision.canEnter(game, 1, 78) and not Collision.canEnter(game, 1, 79),
    "open door cells are MAPGRID_IMPASSABLE like pret")
  d.shot(game, "02_speed_room_doors_open.png")
  d.finish()
end
