-- home/overworld.asm:236, home/overworld.asm:1219

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check, eq = T.check, T.eq

local Data = T.fixtures.fresh()
local Collision = require("src.world.Collision")
local Player = require("src.world.Player")
local Sound = require("src.core.Sound")
local OW = require("src.world.OverworldController")

Collision.load(Data)
Data.field.playerSprites = { walk = "SPRITE_FIX_PLAYER" }
Data.field.ledges = {
  { tileset = "OVERWORLD", facing = "down", input = "down",
    standingTile = 1, ledgeTile = 2 },
}

local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end

local down = {}
local input = {
  wasPressed = function() return false end,
  isDown = function(_, k) return down[k] == true end,
}
local game = { input = input, data = Data, save = {} }
setUpvalue(OW.handleInput, "Game", game)
local GameMod = require("src.core.Game")
GameMod.input = input
GameMod.save = game.save

local sounds = {}
local origPlay = Sound.play
Sound.play = function(_, key) sounds[#sounds + 1] = key end

local W, H = 20, 20
local ledgeRow = 10

local function newMap()
  return {
    def = { tileset = "OVERWORLD" },
    inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < W and y < H end,
    isWalkableCell = function(_, _, y) return y ~= ledgeRow end,
    isWaterCell = function() return false end,
    cellTile = function(_, _, y) return y == ledgeRow and 2 or 1 end,
    warpAtCell = function() return nil end,
    connection = function(_, side) return side == "south" and { map = "SOUTH" } or nil end,
  }
end

local function newOw(cx, cy, facing)
  local ow = setmetatable({
    map = newMap(),
    entities = {},
    player = Player.new(Data, cx, cy, facing),
    dirHeld = function() return true end,
    canCollisionWarp = function() return false end,
    stopSurfingOntoLand = function() end,
    onSlopeMap = function() return false end,
    checkBoulderPush = function() return false end,
  }, { __index = OW })
  ow.crossed = {}
  ow.crossConnection = function(self, dir) self.crossed[#self.crossed + 1] = dir; return true end
  ow.hops = {}
  ow.scriptMove = function(self, _, dir, n) self.hops[#self.hops + 1] = { dir, n }; return true end
  return ow
end

local function clear(t) for i = #t, 1, -1 do t[i] = nil end end

local function hold(ow, dir)
  for k in pairs(down) do down[k] = nil end
  if dir then down[dir] = true end
  local r = ow:handleInput()
  ow.player:update()
  return r
end

local function has(list, key)
  for _, v in ipairs(list) do if v == key then return true end end
  return false
end

do
  local ow = newOw(5, H - 1, "up")
  ow.player.turnArmed = false
  clear(sounds)
  hold(ow, "down")
  check(not has(sounds, "Collision"), "gapless reversal at a seam plays no collision")
  eq(ow.crossed[1], "down", "and crosses the connection on the same poll")
  eq(ow.player.facing, "down", "with the new facing")
  check(not (ow.player.bumpFrames and ow.player.bumpFrames > 0), "and no wall-bonk walk in place")
end

do
  local ow = newOw(5, H - 1, "up")
  clear(sounds)
  eq(hold(ow, "down"), "turned", "an armed press still only turns in place at the seam")
  eq(#ow.crossed, 0, "and does not cross on the turn poll")
  check(not has(sounds, "Collision"), "nor bump")
end

do
  local ow = newOw(5, H - 1, "up")
  ow.player.turnArmed = false
  ow.player.turnTimer = 3
  clear(sounds)
  hold(ow, "down")
  eq(#ow.crossed, 0, "a running turn window still holds the crossing off")
end

do
  local ow = newOw(5, ledgeRow - 1, "left")
  ow.player.turnArmed = false
  clear(sounds)
  hold(ow, "down")
  check(not has(sounds, "Collision"), "gapless turn onto a ledge plays no collision")
  check(has(sounds, "Ledge"), "and hops at once")
  eq(ow.hops[1] and ow.hops[1][2], 2, "two cells")
end

do
  local ow = newOw(5, 5, "up")
  ow.player.turnArmed = false
  clear(sounds)
  eq(hold(ow, "down"), "moved", "open ground reversal still steps")
  check(not has(sounds, "Collision"), "without a bump")
end

Sound.play = origPlay
T.finish("seam reversal")
