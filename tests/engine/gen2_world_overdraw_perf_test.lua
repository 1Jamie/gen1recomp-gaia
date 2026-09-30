-- Gen 2 overworld draw-path fixes and the caches that replaced per-frame work:
--   * Crystal ghost NPCs (neighbour-map objects) skip the grass composite,
--     as Gold/Silver already did -- their px/py are the neighbour's.
--   * bgOverQuads is one quad cache per atlas, not one shared by every atlas.
--   * the poison flash and the void-fill dissolve run on the logic clock.
--   * MapAttrGrid's numeric grid, the anim-cell index and the people cull.
--   luajit tests/engine/gen2_world_overdraw_perf_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local World = require("src.world.gen2.World")
local BorderFill = require("src.world.gen2.BorderFill")
local MapAttrGrid = require("src.world.gen2.MapAttrGrid")

local function crystalWorld(fields)
  local world = setmetatable(fields, { __index = World })
  function world:isCrystal() return true end
  return world
end

-- ------------------------------------------------ ghost grass (Crystal)
do
  local grass = 0
  local world = crystalWorld({})
  function world:drawGrassOver() grass = grass + 1 end
  function world:drawBgPriorityOver() end
  function world:drawGrassShake() end
  local rows = {}
  local function sprite(row) rows[#rows + 1] = row or "full" end
  local entity = { px = 0, py = 0, inGrass = true }

  world:drawEntityComposite(entity, 0, 0, 1, sprite, true, false)
  eq(grass, 1, "an on-map object in grass gets the grass composite")
  eq(rows[1], "bottom", "bottom OAM first")

  grass, rows = 0, {}
  world:drawEntityComposite(entity, 0, 0, 1, sprite, false, true)
  eq(grass, 0, "BUG FIX: a neighbour-map ghost never samples this map's grass")
  eq(#rows, 1, "the ghost draws once, whole")
  eq(rows[1], "full", "as a single full sprite")

  -- The old six-argument call (drawPipeline mods) keeps its behaviour.
  grass = 0
  world:drawEntityComposite(entity, 0, 0, 1, sprite, false)
  eq(grass, 1, "no offMap argument still composites")
end

-- drawPeople passes offMap for ghosts.
do
  local composites = {}
  local world = crystalWorld({
    player = { px = 0, py = 0, draw = function() end },
    npcs = {}, camera = { x = 0, y = 0 }, viewW = 160, viewH = 144,
  })
  local ghostNpc = { px = 16, py = 16, inGrass = true, draw = function() end }
  world.ghosts = { { npc = ghostNpc, ox = 320, oy = 0 } }
  world.camera.x = 300
  function world:flyHides() return false, false end
  function world:drawJumpShadow() end
  function world:drawEntityComposite(entity, _, _, _, _, withExtras, offMap)
    composites[#composites + 1] = { entity = entity, extras = withExtras,
      offMap = offMap }
  end
  function world:drawEmote() end
  function world:drawHealAnim() end
  function world:drawFlyAnim() end
  world:drawPeople(1)
  eq(#composites, 2, "player and ghost both drawn")
  local ghost
  for _, c in ipairs(composites) do
    if c.entity == ghostNpc then ghost = c end
  end
  check(ghost ~= nil, "the ghost reached the compositor")
  eq(ghost and ghost.offMap, true, "drawPeople flags the ghost as off-map")
  eq(ghost and ghost.extras, false, "and without the on-map extras")
end

-- ------------------------------------------------ people cull + reuse
do
  local drawn = {}
  local function person(name, px, py)
    return { name = name, px = px, py = py,
      draw = function(self) drawn[#drawn + 1] = self.name end }
  end
  local world = setmetatable({
    player = person("player", 5000, 5000),
    npcs = { person("near", 64, 32), person("far", 2000, 32),
      person("row", 80, 32) },
    ghosts = {}, camera = { x = 0, y = 0 }, viewW = 160, viewH = 144,
  }, { __index = World })
  function world:isCrystal() return false end
  function world:flyHides() return false, false end
  function world:drawJumpShadow() end
  function world:drawGrassShake() end
  function world:drawEmote() end
  function world:drawHealAnim() end
  function world:drawFlyAnim() end
  world:drawPeople(1)
  eq(#drawn, 3, "the far NPC is culled, the player never is")
  eq(drawn[1], "near", "equal rows draw in list order")
  eq(drawn[2], "row", "equal rows draw in list order (second)")
  eq(drawn[3], "player", "Y order holds")
  local list = world._peopleList
  drawn = {}
  world:drawPeople(1)
  eq(#drawn, 3, "a second frame draws the same people")
  check(world._peopleList == list, "and reuses the draw list")

  -- The billboard (TILT) path shows more than the view: no cull there.
  drawn = {}
  world:drawPeople(1, function(_, _, body) body() end)
  eq(#drawn, 4, "the tilt billboard pass keeps everyone")
end

-- ------------------------------------------------ bgOverQuads per atlas
do
  local world = crystalWorld({})
  local a = love.graphics.newImage("a.png")
  local b = love.graphics.newImage("b.png")
  local qa = world:bgOverQuadsFor(a)
  local qb = world:bgOverQuadsFor(b)
  check(qa ~= qb, "BUG FIX: two atlases get two quad caches")
  check(world:bgOverQuadsFor(a) == qa, "one atlas keeps its cache")
end

-- ------------------------------------------------ poison flash clock
do
  local world = setmetatable({}, { __index = World })
  world:poisonBGFlash()
  eq(world.poisonFlash, 4, "the flash arms four frames")
  for i = 3, 0, -1 do
    world:tickPoisonFlash()
    eq(world.poisonFlash, i, "one logic tick spends one frame")
  end
  world:tickPoisonFlash()
  eq(world.poisonFlash, 0, "and it stops at zero")

  -- Game2's fixed step drives both clocks through tickFrameClocks.
  world:poisonBGFlash()
  world:tickFrameClocks()
  eq(world.poisonFlash, 3, "tickFrameClocks spends a poison frame")
  eq(world.borderTicks, 1, "and banks one dissolve tick")
  for _ = 1, 100 do world:tickFrameClocks() end
  eq(world.borderTicks, BorderFill.CROSSFADE_FRAMES,
    "banked ticks cap at one whole dissolve")
end

-- ------------------------------------------------ void dissolve clock
do
  local owner = { borderTicks = 0 }
  BorderFill.crossfade(owner, "water", "A")
  local from, alpha = BorderFill.crossfade(owner, "trees", "B", 1)
  eq(from, "water", "a new fill dissolves from the old one")
  local a1 = alpha
  from, alpha = BorderFill.crossfade(owner, "trees", "B", 0)
  eq(alpha, a1, "BUG FIX: a render frame with no logic tick does not advance")
  from, alpha = BorderFill.crossfade(owner, "trees", "B", 2)
  check(alpha > a1, "two banked ticks advance two frames")

  -- Ticks banked before a swap do not skip the new dissolve.
  local o2 = {}
  BorderFill.crossfade(o2, "water", "A")
  local f2, al2 = BorderFill.crossfade(o2, "trees", "B", 15)
  eq(f2, "water", "a swap after a long gap still dissolves")
  check(al2 <= 1 / BorderFill.CROSSFADE_FRAMES + 1e-9,
    "from its first frame")
end

-- ------------------------------------------------ MapAttrGrid numeric
do
  local block = {}
  for i = 1, 16 do block[i] = i - 1 end
  block[16] = 0x85
  local tileset = { blocks = { block, block } }
  local map = { width = 2, height = 1, blocks = { 1, 0 }, borderBlock = 1 }
  local grid = MapAttrGrid.build(map, tileset)
  for my = 0, 31, 8 do
    for mx = 0, 63, 8 do
      local want = MapAttrGrid.cellAt(map, tileset, mx, my)
      local got = MapAttrGrid.lookup(grid, mx + 3, my + 5)
      eq(got and got.tileId, want.tileId, "lookup tile id at " .. mx .. "," .. my)
      eq(got and got.rawTileId, want.rawTileId, "raw id at " .. mx .. "," .. my)
      eq(got and got.attr.vramBank, want.attr.vramBank,
        "bank at " .. mx .. "," .. my)
    end
  end
  eq(MapAttrGrid.lookup(grid, -8, 0), nil, "left of the map is nothing")
  eq(MapAttrGrid.lookup(grid, 64, 0), nil, "right of the map does not wrap")
  eq(MapAttrGrid.lookup(grid, 0, 32), nil, "below the map is nothing")
  eq(MapAttrGrid.lookup(nil, 0, 0), nil, "no grid is nothing")
end

-- ------------------------------------------------ anim cell index
do
  local world = setmetatable({}, { __index = World })
  local water = { layer = {}, tile = 1, cells = { 0, 0, 8, 0, 32, 64 } }
  local flower = { layer = {}, tile = 2, cells = { 16, 8 } }
  local cells = { [1] = water, [2] = flower }
  eq(world:animListAt(cells, 8, 0), water, "indexed water cell")
  eq(world:animListAt(cells, 32, 64), water, "indexed far water cell")
  eq(world:animListAt(cells, 16, 8), flower, "indexed flower cell")
  eq(world:animListAt(cells, 8, 8), nil, "a plain cell is not animated")
  eq(world:animListAt(nil, 0, 0), nil, "no anim table")
  eq(world:animListAt(false, 0, 0), nil, "a map with no anims")
end

-- ------------------------------------------------ memoized keys
do
  local GbcPalette = require("src.render.GbcPalette")
  local fake = { daytime = "DAY", flickerPhase = 1 }
  local k1 = World.mapCacheKey(fake, "M")
  eq(k1, "M|DAY|" .. tostring(GbcPalette.mode) .. "|nil|1", "key format")
  check(World.mapCacheKey(fake, "M") == k1, "memoized")
  fake.daytime = "NITE"
  check(World.mapCacheKey(fake, "M") ~= k1, "a daytime change rebuilds it")
  fake.daytime = "DARK"
  local dark1 = World.mapCacheKey(fake, "M")
  fake.flickerPhase = 2
  check(World.mapCacheKey(fake, "M") ~= dark1, "a flicker change rebuilds it")

  BorderFill.setVoidFill("fade")
  local def = { id = "M", tileset = "TILESET_JOHTO", borderBlock = 5 }
  local w = setmetatable({}, { __index = World })
  eq(w:borderFillKey(def), BorderFill.fillKey(def), "fill key matches")
  BorderFill.setVoidFill("water")
  eq(w:borderFillKey(def), BorderFill.fillKey(def), "fill key follows mode")
  BorderFill.setVoidFill("fade")
end

T.finish("gen2 world overdraw perf")
