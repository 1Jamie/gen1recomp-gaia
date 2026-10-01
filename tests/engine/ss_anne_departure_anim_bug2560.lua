-- scripts/VermilionDock.asm:79, scripts/VermilionDock.asm:142, home/oam.asm:6

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check, eq = T.check, T.eq

T.fixtures.fresh()

local OW = require("src.world.OverworldController")
local TileRenderer = require("src.render.TileRenderer")

local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end

local game = { data = { field = {} }, save = {} }
setUpvalue(OW.drawShipAnim, "Game", game)

local WATER = 0x14
local drawnTiles = {}
local renderer = {
  rebuild = function() end,
  drawTile = function(_, tile) drawnTiles[#drawnTiles + 1] = tile end,
}
local map = {
  renderer = renderer,
  tileAt = function() return WATER end,
  setBlock = function() end,
}
local ow = setmetatable({ map = map }, { __index = OW })

check(type(OW.tickShipAnim) == "function", "the departure has its own tick")

local done = 0
ow:startSsAnneDeparture(function() done = done + 1 end)
local sa = ow.shipAnim

local seen, emitted, maxLive = {}, 0, 0
local births, lastX = {}, {}
local frames = 0
while not sa.gone and frames < 4000 do
  if OW.tickShipAnim then ow:tickShipAnim() end
  frames = frames + 1
  local live = {}
  if sa.puff then live[#live + 1] = sa.puff end
  for _, p in ipairs(sa.puffs or {}) do live[#live + 1] = p end
  if #live > maxLive then maxLive = #live end
  for _, p in ipairs(live) do
    if not seen[p] then
      seen[p] = true
      emitted = emitted + 1
      births[#births + 1] = p.x
    end
    lastX[p] = p.x
  end
  if frames == 1 then
    eq(#live, 0, "no puff before the first column shift")
  end
end

eq(frames, 128 * 8, "she sails 128px at 8 frames a pixel")
eq(emitted, 8, "eight puffs, one per column shift (ld e, $8)")
check(maxLive <= 1, ("at most one puff is ever live (saw %d)"):format(maxLive))
eq(done, 1, "the departure finishes once")
for i = 2, #births do
  eq(births[i - 1] - births[i], 16, "each puff is born 16px west of the last (sub 16)")
end

drawnTiles = {}
ow.shipAnim = { px = 0, py = 0, tiles = { { WATER, 0x50 }, { WATER, WATER } },
                off = 4, frames = 0 }
ow:drawShipAnim(0, 0)
eq(#drawnTiles, 4, "every snapshot tile goes through the renderer's live tile draw")

local origDraw = love.graphics.draw
local drawn = {}
love.graphics.draw = function(d) drawn[#drawn + 1] = d end
local fake = setmetatable({
  image = "atlas",
  quads = { [WATER] = "q14" },
  claimedBy = { [WATER] = { sequence = { 1, 2 }, period = 10,
                            textures = { "water_a", "water_b" } } },
}, { __index = TileRenderer })
check(type(TileRenderer.drawTile) == "function", "TileRenderer:drawTile exists")
if TileRenderer.drawTile then
  local function topTexture()
    drawn = {}
    fake:drawTile(WATER, 0, 0)
    return drawn[#drawn]
  end
  local a = topTexture()
  local changed = false
  for _ = 1, 20 do
    TileRenderer.tick()
    if topTexture() ~= a then changed = true end
  end
  check(changed, "water tile drawn through drawTile animates with the tile clock")
  drawn = {}
  fake:drawTile(0x50, 0, 0)
  eq(#drawn, 0, "a tile with no quad and no animation draws nothing")
end
love.graphics.draw = origDraw

T.finish("ss anne departure anim")
