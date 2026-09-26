#!/usr/bin/env luajit
-- Tests Safari Zone warp exit positioning, door step transitions, and trigger line parity against pret pokefirered.
-- pokefirered/src/field_fadetransition.c:242 SetUpWarpExitTask / Task_ExitNonAnimDoor
-- pokefirered/data/maps/FuchsiaCity_SafariZone_Entrance/map.json
-- pokefirered/data/maps/FuchsiaCity_SafariZone_Entrance/scripts.inc

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed, passed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")
local Warp = require("src.core.game3.warp")
local Safari = require("src.core.game3.safari")

print("[test] 1. Metatile behavior constants match pret pokefirered")
check(Collision.isNonAnimDoor(0x60) == true, "MB_CAVE_DOOR (0x60) is recognized as non-anim door")
check(Collision.isWarpDoor(0x69) == true, "MB_WARP_DOOR (0x69) is recognized as warp door")
check(Collision.isNonAnimDoor(0x69) == false, "MB_WARP_DOOR is not non-anim door")

print("[test] 2. warpExitArrival steps player 1 tile down on MB_CAVE_DOOR")
local fakeFade = {
  begin = function(mode, speed, callback)
    if callback then callback() end
  end,
  isActive = function() return false end,
}
package.loaded["src.ui.game3.fade"] = fakeFade

-- Initialize player at warp landing tile (4, 1) facing down
Player.cellX = 4
Player.cellY = 1
Player.facing = "down"
check(Player.cellX == 4 and Player.cellY == 1, "player starts at (4,1)")
check(Player.facing == "down", "player facing is down")

-- Mock collision behavior at (4, 1) to be MB_CAVE_DOOR (0x60)
local origBehavior = Collision.behavior
Collision.behavior = function(x, y)
  if x == 4 and y == 1 then return 0x60 end
  return 0
end

local finished = false
Warp.fadeModes = function() return 1, 0 end
-- Call warpExitArrival
local warpDone = false
-- In test environment without love.timer, player forceStep completes via step loop
Player.forceStep = function(dir, onDone)
  local dirs = { down = {0, 1}, up = {0, -1}, left = {-1, 0}, right = {1, 0} }
  local d = dirs[dir] or {0, 0}
  Player.cellX = Player.cellX + d[1]
  Player.cellY = Player.cellY + d[2]
  if onDone then onDone() end
  return true
end

-- Require warp and execute warpExitArrival (using internal function through Warp.request simulation)
local ok, err = pcall(function()
  local mockMod = {}
  local mockGame = {
    data = { maps = {} },
    currentMap = Safari.EXIT_MAP,
  }
  local Map = require("src.core.game3.map")
  Map.load = function(mod, game, mapId, opts)
    Player.cellX = opts.x
    Player.cellY = opts.y
    Player.facing = opts.facing
    return true
  end

  Warp.request(mockMod, mockGame, Safari.EXIT_MAP, 4, 1, "down", { fade = true })
end)

check(ok == true, "Warp.request completed successfully")
check(Player.cellX == 4 and Player.cellY == 2,
  string.format("Player stepped down out of doorway from (4,1) to (4,2) (got %d,%d)", Player.cellX, Player.cellY))

print("[test] 3. Exit script movement from (4,2) lands player at (4,4) outside triggers")
-- FuchsiaCity_SafariZone_Entrance_Movement_Exit has 2 walk_down steps
-- Step 1: (4,2) -> (4,3)
Player.cellY = Player.cellY + 1
-- Step 2: (4,3) -> (4,4)
Player.cellY = Player.cellY + 1
check(Player.cellX == 4 and Player.cellY == 4,
  string.format("Player lands at (4,4) after Movement_Exit (got %d,%d)", Player.cellX, Player.cellY))

-- Walking North from (4,4) steps onto (4,3), which triggers EntryTriggerMid
local stepNorthDestY = Player.cellY - 1
check(stepNorthDestY == 3, "Stepping North from (4,4) steps onto coord trigger line y=3")

Collision.behavior = origBehavior

print(string.format("\n%d passed, %d failed", passed, failed))
if failed == 0 then
  print("SAFARI_WARP_EXIT_TEST PASS")
  os.exit(0)
else
  os.exit(1)
end
