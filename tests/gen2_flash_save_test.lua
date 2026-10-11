package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local S = require("tests.harness").suite("gen2 flash save")
local check, eq = S.check, S.eq

local World = require("src.world.gen2.World")
local Game2 = require("src.core.Game2")

local world = World.new({ save = {} })
world:loadPlayerData({ flashUsed = true })
eq(world.flashUsed, true, "a save with STATUSFLAGS_FLASH_F comes back flashed")

world = World.new({ save = {} })
world.flashUsed = true
world:loadPlayerData({})
eq(world.flashUsed, false, "a save without it comes back dark")

local function snapshot(flashUsed)
  local live = World.new({ save = {} })
  live:loadPlayerData({})
  live.flashUsed = flashUsed
  live.map = { id = "DARK_CAVE_VIOLET_ENTRANCE", def = { objects = {} } }
  live.player = { cellX = 3, cellY = 4, facing = "down" }
  local game = { world = live, save = {}, data = {}, options = {} }
  return Game2.snapshotSave(game)
end
eq(snapshot(true).flashUsed, true, "snapshotSave carries STATUSFLAGS_FLASH_F")
eq(snapshot(false).flashUsed, nil, "and leaves it off when FLASH was not used")

local reloaded = World.new({ save = {} })
reloaded:loadPlayerData(snapshot(true))
check(reloaded.flashUsed, "save then CONTINUE keeps the cave lit")

S.finish()
