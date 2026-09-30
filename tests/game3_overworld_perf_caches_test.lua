-- Per-frame caches in the game3 overworld: OAM sort reuse, ghost pool sync /
-- camera-range ticking, one-cell collision patch, trainer id negative cache
-- and seamless tileset pair warming.
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end

-- OAM ---------------------------------------------------------------------
do
  local Oam = require("src.core.game3.oam")
  Oam.reset()
  local img = {}
  local function spawn(y, pri)
    local id, s = Oam.createSprite({ oam = { shape = 0, size = 1, priority = pri or 0 } }, 10, y, 0)
    s.image = img
    return id, s
  end
  local _, a = spawn(40)
  local _, b = spawn(20)
  local _, c = spawn(30, 1)
  Oam.resetFrame()
  check(#Oam._buffer == 0, "resetFrame empties the frame buffer")
  local buf = Oam.buildOamBuffer()
  check(#buf == 3 and buf[1] == b and buf[2] == a and buf[3] == c, "sorted by priority then y")
  local sorted = Oam._sorted
  Oam.resetFrame()
  check(Oam._buffer == buf and #buf == 0, "resetFrame clears in place")
  local buf2 = Oam.buildOamBuffer()
  check(buf2 == buf and Oam._sorted == sorted and buf2[1] == b and buf2[3] == c,
    "unchanged scene reuses the sorted cache")
  a.y = 0
  Oam.resetFrame()
  buf2 = Oam.buildOamBuffer()
  check(buf2[1] == a and buf2[2] == b and buf2[3] == c, "moved sprite re-sorts")
  a.invisible = true
  Oam.resetFrame()
  buf2 = Oam.buildOamBuffer()
  check(#buf2 == 2 and buf2[1] == b, "hidden sprite leaves the buffer")
  a.invisible = false
  c.image = nil
  local _, d = spawn(20)
  Oam.resetFrame()
  buf2 = Oam.buildOamBuffer()
  local seen = {}
  for _, s in ipairs(buf2) do seen[s] = true end
  check(#buf2 == 3 and seen[d] and seen[a] and seen[b] and not seen[c],
    "swapped sprite with equal count rebuilds the set")
  Oam.reset()
  check(Oam._sorted == nil, "reset drops the sort cache")
end

-- Ghosts ------------------------------------------------------------------
do
  local spawned, ticked = 0, {}
  local Objects = {
    spawnFromDefs = function(defs, def, id)
      spawned = spawned + 1
      return { order = {}, byId = {}, id = id }
    end,
    tickPool = function(pool) ticked[pool.id] = (ticked[pool.id] or 0) + 1 end,
    playerBlocks = function() return false end,
  }
  local Map = { world = {} }
  local Player = { cellX = 5, cellY = 5 }
  package.loaded["src.core.game3.objects"] = Objects
  package.loaded["src.core.game3.map"] = Map
  package.loaded["src.core.game3.player"] = Player
  package.loaded["src.core.game3.field_view"] = { _viewW = 240, _viewH = 160 }
  local Ghosts = require("src.core.game3.ghosts")
  local function entry(id, ox, oy)
    return { id = id, ox = ox, oy = oy,
      def = { objects = { {} }, midLayout = { width = 20, height = 20 } } }
  end
  Map.world = { entry("NEAR", 20, 0), entry("FAR", 200, 0), entry("NORTH", 0, -20) }
  Ghosts.sync()
  check(spawned == 3, "sync spawns a pool per world map")
  for _ = 1, 5 do Ghosts.sync() end
  check(spawned == 3, "sync with an unchanged world does not respawn")
  Ghosts._pools.NORTH = nil
  Ghosts.sync()
  check(spawned == 4 and Ghosts._pools.NORTH, "externally dropped pool is respawned")
  Ghosts._pools.EXTRA = { order = {}, byId = {} }
  Ghosts.sync()
  check(Ghosts._pools.EXTRA == nil, "pool outside the world is dropped")
  Map.world = { Map.world[1] }
  Ghosts.sync()
  check(Ghosts._pools.FAR == nil and Ghosts._pools.NEAR, "new world table resyncs")
  Map.world = { entry("NEAR", 20, 0), entry("FAR", 200, 0) }
  Ghosts.clear()
  Ghosts.sync()
  check(Ghosts._pools.NEAR and Ghosts._pools.FAR, "clear then sync respawns")
  Ghosts.update({})
  check(ticked.NEAR == 1 and ticked.FAR == nil, "only pools near the camera tick")
  Player.cellX = 190
  Ghosts.update({})
  check(ticked.FAR == 1, "a pool ticks again once the camera is back in range")
  Ghosts.clear()
  package.loaded["src.core.game3.objects"] = nil
  package.loaded["src.core.game3.map"] = nil
  package.loaded["src.core.game3.player"] = nil
  package.loaded["src.core.game3.field_view"] = nil
end

-- Collision.patchCell -----------------------------------------------------
do
  local Collision = require("src.core.game3.collision")
  local LayoutNative = require("src.core.game3.layout_native")
  local cells = {}
  for i = 1, 16 do cells[i] = { mid = 1, coll = 0, elev = 0 } end
  local layout = LayoutNative.fromDecoded({ width = 4, height = 4, cells = cells }, "T", "p")
  local def = { midLayout = layout, warps = { { x = 2, y = 2 } } }
  Collision.bindMap(nil, "T", def)
  local grid = Collision._grid
  layout:applyOverride(1, 1, 5, 0x07, 0)
  check(Collision.patchCell("T", def, 1, 1) and Collision._grid == grid and grid[1 * 4 + 1 + 1] == 0x07,
    "patchCell updates one grid entry in place")
  local full = layout:collArray()
  local same = true
  for i = 1, 16 do if full[i] ~= grid[i] then same = false end end
  check(same, "patched grid matches a full rebuild")
  check(not Collision.patchCell("T", def, 2, 2), "warp cell falls back to bindMap")
  check(not Collision.patchCell("OTHER", def, 1, 1), "other bound map falls back")
  check(not Collision.patchCell("T", def, 9, 1), "off-grid cell falls back")
end

-- TrainerSight negative cache ----------------------------------------------
do
  local Space = require("src.core.game3.scripting.space")
  local prevBundle = Space.bundle
  local list = { { op = "msgbox" } }
  Space.bundle = { scripts = { S = list } }
  local TrainerSight = require("src.core.game3.trainer_sight")
  local eo = { scriptKey = "S" }
  check(TrainerSight.getTrainerId(eo) == nil and eo._trainerIdMiss == list, "first scan misses")
  -- same list table: the cached miss stands without rescanning
  list[2] = { op = "trainerbattle", trainer = 3 }
  check(TrainerSight.getTrainerId(eo) == nil, "repeat lookups hit the negative cache")
  Space.bundle.scripts.S = { { op = "trainerbattle", trainer = 7 } }
  check(TrainerSight.getTrainerId(eo) == 7, "replaced script is rescanned")
  Space.bundle = prevBundle
end

-- Map warm queue ----------------------------------------------------------
do
  local loads = {}
  local Native = { _pairs = { loaded = {} } }
  function Native.ready() return true end
  function Native.get(pair) loads[#loads + 1] = pair; Native._pairs[pair] = {}; return {} end
  package.loaded["src.core.game3.tileset_native"] = Native
  local Map = require("src.core.game3.map")
  local function def(pair) return { pair = pair, midLayout = { pair = pair } } end
  Map.computeWorld = function()
    return { { id = "A", def = def("loaded") }, { id = "B", def = def("p1") },
      { id = "C", def = def("p2") }, { id = "D", def = def("p1") } }
  end
  Map.ensureMidLayout = function() end
  Map._warmPairs = nil
  Map._worldRoot = nil
  Map.refreshWorld({ data = { maps = {} } }, 10, 10, "ROOT")
  check(#loads == 0 and Map._warmQueue and #Map._warmQueue == 2, "seamless refresh queues unloaded pairs")
  Map.stepWarm()
  check(#loads == 1 and loads[1] == "p1", "stepWarm loads one pair per call")
  Map.stepWarm()
  check(#loads == 2 and loads[2] == "p2" and Map._warmQueue == nil, "queue drains")
  Map._warmPairs = true
  Map._worldRoot = nil
  Native._pairs = {}
  loads = {}
  Map.refreshWorld({ data = { maps = {} } }, 10, 10, "ROOT")
  check(#loads == 4 and Map._warmQueue == nil, "non-seamless load still warms synchronously")
  package.loaded["src.core.game3.tileset_native"] = nil
end

print(failures == 0 and "PASS game3_overworld_perf_caches_test"
  or ("FAIL game3_overworld_perf_caches_test failures=" .. failures))
os.exit(failures == 0 and 0 or 1)
