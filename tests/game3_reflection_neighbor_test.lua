package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(ok, msg)
  if not ok then
    failed = failed + 1
    print("FAIL " .. msg)
  end
end

love = love or {}
local draws = 0
love.graphics = love.graphics or {}
love.graphics.setColor = function() end
love.graphics.newQuad = function() return { setViewport = function() end } end
love.graphics.draw = function() draws = draws + 1 end

local okMap, Map = pcall(require, "src.core.game3.map")
if not okMap then
  print("[skip] map needs runtime: " .. tostring(Map))
  os.exit(0)
end
local Collision = require("src.core.game3.collision")
local Scripts = require("src.core.game3.scripting.interaction_scripts")
local MB = require("src.core.game3.mb")
local FxRse = require("src.core.game3.field_effects_rse")

local WATER = MB.id("POND_WATER")
local function layout(pair, mid)
  return { width = 4, height = 4, pair = pair, midAt = function() return mid end }
end

local host = { midLayout = layout("test_host", 1), pair = "test_host" }
local south = { midLayout = layout("test_south", 7), pair = "test_south" }
Scripts.behaviors.test_host = {}
Scripts.behaviors.test_south = { [7] = WATER }

Collision._mapDef = host
Map.neighborList = { { dir = "south", offset = 0, def = south } }
Map.world = {
  { id = "HOST", def = host, ox = 0, oy = 0 },
  { id = "SOUTH", def = south, ox = 0, oy = 4 },
}

check(Collision.behavior(1, 5) == nil, "gameplay behavior stays bounded to the current map")
check(Collision.worldBehavior and Collision.worldBehavior(1, 5) == WATER,
  "worldBehavior resolves a neighbor cell across the seam")
check(Collision.worldBehavior and Collision.worldBehavior(1, 1) == nil,
  "worldBehavior keeps current-map cells")

local spr = {
  width = 16, height = 32, frameCount = 1, quads = { [0] = true },
  image = { getDimensions = function() return 16, 32 end },
}
package.loaded["src.core.game3.ow_sprites"] = {
  getDraw = function() return spr end,
  pose = function() return 0, false end,
}
FxRse._fc = { gfx = {}, palTagNone = 0x11FF }

local ghost = { cellX = 1, cellY = 0, px = 16, py = 0, moving = false }
draws = 0
check(FxRse.drawReflection(ghost, 5, 0, false, 0, 0, 0, 0, 0, 4) == true,
  "ghost object on a neighbor map reflects off neighbor water")
check(draws > 0, "ghost reflection draws quads")

local near = { cellX = 1, cellY = 2, px = 16, py = 32, moving = false }
draws = 0
check(FxRse.drawReflection(near, 5, 0, false, 0, 0, 0, 0) == true,
  "current-map object next to the seam reflects off neighbor water")

local dry = { cellX = 1, cellY = 0, px = 16, py = 0, moving = false }
check(FxRse.drawReflection(dry, 5, 0, false, 0, 0, 0, 0) == false,
  "object with no water below does not reflect")

if failed > 0 then os.exit(1) end
print("game3_reflection_neighbor_test ok")
