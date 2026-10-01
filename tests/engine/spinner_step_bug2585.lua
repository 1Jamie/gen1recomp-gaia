-- engine/overworld/spinners.asm:23-49, home/copy2.asm:62-91

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check, eq = T.check, T.eq

local Data = T.fixtures.fresh()
local Player = require("src.world.Player")
local TileRenderer = require("src.render.TileRenderer")
local Game = require("src.core.Game")
Game.save = {}

Data.field.playerSprites = { walk = "SPRITE_FIX_PLAYER" }

eq(Player.SPIN_ITER_FRAMES, 6, "a spinning OverworldLoop pass costs 2 + 4 frames")

local p = Player.new(Data, 5, 5, "down")
eq(p:stepLength("left"), 16, "a plain walking step is 16 frames")
p.spinning = true
eq(p:stepLength("left"), 48, "a spinner tile is 8 passes of 6 frames")

p.spinFrames = 32
eq(p:stepLength("left"), 16, "the warp arrival spin keeps its own timing")
p.spinFrames = nil

p.bikeStepFrames = 8
Game.save.onBike = true
eq(p:stepLength("left"), 24, "on the bike the four passes still cost 6 frames each")
Game.save.onBike = nil

p.spinTimer = 0
local facings = {}
for _ = 1, 48 do
  p:update()
  local _, _, _, facing = p:pose()
  facings[#facings + 1] = facing
end
local runs, run = {}, 1
for i = 2, #facings do
  if facings[i] == facings[i - 1] then run = run + 1
  else runs[#runs + 1] = run; run = 1 end
end
local sixes = 0
for i = 2, #runs do if runs[i] == 6 then sixes = sixes + 1 end end
eq(sixes, #runs - 1, "every whole facing run lasts 6 frames")
check(#runs >= 6, "eight quarter turns per spinner tile")

TileRenderer.setSpinning(true, 5)
local a = TileRenderer.spinBlurActive()
for _ = 1, 48 do TileRenderer.tick() end
eq(TileRenderer.spinBlurActive(), a, "arrow graphic holds through one spinner tile")
TileRenderer.setSpinning(true, 4)
check(TileRenderer.spinBlurActive() ~= a, "and flips on the next tile")
TileRenderer.setSpinning(false)

local OW = require("src.world.OverworldController")
local ow = setmetatable({
  player = Player.new(Data, 5, 5, "down"),
  entities = {},
  scriptMoves = {},
  map = {},
  onStepComplete = function() end,
}, { __index = OW })
local moves = { { dir = "left", count = 2 }, { dir = "up", count = 1 } }
ow:runSpinnerMoves(moves, 1)
eq(ow.spinnerLeft, 2, "the seed is the index after the first tile's dec (home/overworld.asm:1844-1846)")
TileRenderer.setSpinning(ow.spinnerSliding, ow.spinnerLeft)
local firstBlur = TileRenderer.spinBlurActive()
ow:updateScriptMoves()
eq(ow.spinnerLeft, 2, "starting the first tile does not count it twice")
TileRenderer.setSpinning(ow.spinnerSliding, ow.spinnerLeft)
eq(TileRenderer.spinBlurActive(), firstBlur, "the first drawn frame already shows the first tile's graphic")
local function finishTile()
  while ow.player.moving do ow.player:update() end
  ow:updateScriptMoves()
end
finishTile()
eq(ow.spinnerLeft, 1, "the second tile decrements the index")
finishTile()
eq(ow.spinnerLeft, 0, "the third tile decrements again")
finishTile()
eq(ow.spinnerLeft, nil, "the index clears once the slide ends")
eq(ow.spinnerSliding, nil, "and so does the sliding flag")
eq(ow.player.spinning, false, "the player stops spinning")

T.finish("spinner step")
