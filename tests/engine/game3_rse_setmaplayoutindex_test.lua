-- pokeemerald/src/scrcmd.c:732, pokeemerald/src/overworld.c:993, data/maps/ShoalCave_LowTideEntranceRoom/scripts.inc:5

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
require("src.core.GameVersion").set("emerald")

local Ops = require("src.core.game3.scripting.ops_a")
local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local NativePack = require("src.import.gba.native_pack")
local Dataset = require("src.core.game3.dataset")
local Extract = require("src.import.gba.extract_island1")
local AltLayouts = require("src.import.gba.alt_layouts")

local W, H = 4, 2
local ROOM = "EM_SHOAL_CAVE_LOW_TIDE_ENTRANCE_ROOM"
local HIGH = "EM_SHOAL_CAVE_HIGH_TIDE_ENTRANCE_ROOM"
local LAYOUT_HIGH = 168

local function blobOf(mid)
  local cells = {}
  for i = 1, W * H do cells[i] = { mid = mid, coll = 0, elev = 3 } end
  return NativePack.encodeMidLayout({ width = W, height = H, cells = cells })
end

local root = Extract.NATIVE_ROOT or ((Extract.CACHE_ROOT or "data/generated/gba") .. "/native")
local files = {
  [root .. "/layouts/" .. HIGH .. ".mid"] = blobOf(0x2A0),
  [root .. "/layout_files.lua"] = ("return { [%d] = %q, [164] = %q }\n"):format(LAYOUT_HIGH, HIGH, ROOM),
}
Dataset.cache = function()
  return { read = function(_, path) return files[path] end }
end

local cells = {}
for i = 1, W * H do cells[i] = { mid = 0x111, coll = 0, elev = 3 } end
local layout = { width = W, height = H }
function layout:cellAt(x, y) return cells[y * W + x + 1] end
function layout:applyOverride(x, y, mid, coll, elev)
  cells[y * W + x + 1] = { mid = mid, coll = coll, elev = elev }
end

local session = { version = "emerald", map = ROOM }
package.loaded["src.core.game3.runtime"] = {
  _game = { data = { maps = { [ROOM] = { id = ROOM, midLayout = layout } } } },
  getSession = function() return session end,
}
package.loaded["src.core.game3.collision"] = { bindMap = function() end }

local c = Ctx.new({})
c.mode, c.status = "bytecode", "running"
local logs = {}
local vm = {
  ctx = c,
  store = Flags.newStore(),
  adapters = { log = function(s) logs[#logs + 1] = s end },
  setPc = function() end,
}

eq(Ops.dispatch(vm, { op = "setmaplayoutindex", [1] = LAYOUT_HIGH }), false, "setmaplayoutindex does not yield")
eq(layout:cellAt(0, 0).mid, 0x2A0, "a layout another map header owns is applied (high tide entrance room)")
eq(layout:cellAt(W - 1, H - 1).mid, 0x2A0, "every cell takes the target layout")
eq(#logs, 0, "no missing-layout log")

local census = { maps = {
  { engineId = ROOM, layout = { layoutOff = 0x100 } },
  { engineId = HIGH, layout = { layoutOff = 0x200 } },
} }
local fakeRom = {
  ptrOffset = function(_, p) return p end,
  u32 = function(_, off) return ({ [0] = 0x100, [4] = 0x200 })[off] end,
}
local Versions = require("src.import.gba.versions")
local savedCount = Versions.NUM_MAP_LAYOUTS
Versions.NUM_MAP_LAYOUTS = 2
local okBuild, added, _, map = pcall(AltLayouts.buildUnreferenced, fakeRom, { g_map_layouts = 0 },
  { [ROOM] = {}, [HIGH] = {} }, {}, nil, census)
Versions.NUM_MAP_LAYOUTS = savedCount
check(okBuild, "buildUnreferenced runs over referenced layouts")
eq(okBuild and #added, 0, "referenced layouts bake no alt_ copy")
eq(type(map) == "table" and map[1], ROOM, "layout id 1 resolves to the map that owns it")
eq(type(map) == "table" and map[2], HIGH, "layout id 2 resolves to the high tide map file")

T.finish("game3_rse_setmaplayoutindex_test")
