package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local check, eq = T.check, T.eq
love = require("tests.love_stub")
local worker = {}
love.thread = {
  newChannel = function()
    local ch = { q = {} }
    function ch:push(v) self.q[#self.q + 1] = v end
    function ch:pop() return table.remove(self.q, 1) end
    function ch:clear() self.q = {} end
    function ch:getCount() return #self.q end
    return ch
  end,
  newThread = function()
    function worker:start(input, output) self.input, self.output = input, output end
    function worker:getError() return nil end
    function worker:wait() end
    return worker
  end,
}
require("src.core.GameVersion").set("firered")
local Stream = require("src.core.game3.asset_stream")
local ObjectPrepare = require("src.core.game3.object_prepare")
local Cells = require("src.core.game3.field_cell_prepare")
local Objects = require("src.core.game3.objects")
local state = { gid = 17, hidden = false }
package.loaded["src.core.game3.scripting.space"] = {
  resolveObjectGraphicsId = function(def) return def.graphicsId == 240 and state.gid or def.graphicsId end,
  objectVisible = function(def) return not (def.flag == 1 and state.hidden) end,
}
package.loaded["src.core.game3.collision"] = { elevationAt = function() return 3 end }
local function finishJobs()
  for _ = 1, 20 do
    Stream.poll()
    local req = worker.input and worker.input:pop()
    if not req then break end
    local data = req.kind == "objects" and ObjectPrepare.objects(req.spec.payload) or Cells.cells(req.spec.payload)
    worker.output:push({ id = req.id, data = data, seconds = .001 })
    Stream.poll()
  end
end
local def = { objects = {
  { localId = 1, x = 3, y = 4, graphicsId = 240, movementType = 2, flag = 1 },
  { localId = 2, x = 5, y = 6, graphicsId = 16, movementType = 7 },
} }
Objects.prefetchMap("WORKER_MAP", def, 0); finishJobs()
state.gid, state.hidden = 25, true
Objects.loadMap({}, "WORKER_MAP", def)
eq(Objects._lastPreparationRoute, "worker", "map adopts worker-built instances")
local eo = Objects._byId[1]
eq(eo.graphicsId, 25, "variable graphics resolve against live state after preparation")
check(eo.hidden and not eo.visible, "hide flags resolve against live state after preparation")
eq(eo.elevation, 3, "elevation binds against the authoritative collision grid")
check(eo.def ~= def.objects[1], "prepared instances own their template copy")
local workerEo = ObjectPrepare.freeze(eo)
check(not pcall(ObjectPrepare.objects, { defs = def.objects }, function() return true end), "stale object preparation stops cooperatively")
Objects.loadMap({}, "WORKER_MAP", def)
check(ObjectPrepare.matches(workerEo, Objects._byId[1]), "worker and synchronous instance fields agree")
Objects.prefetchMap("WORKER_MAP", def); finishJobs()
def.objects[1].x = 9
Objects.loadMap({}, "WORKER_MAP", def)
eq(Objects._lastPreparationRoute, "sync", "changed definitions reject stale instances")
eq(Objects._byId[1].cellX, 9, "changed template position is applied immediately")
check(ObjectPrepare.freeze({ callback = function() end }) == nil, "custom functions keep the synchronous path")
Objects.prefetchMap("STALE_MAP", def); Stream.poll()
Objects.reset(); finishJobs()
Objects.loadMap({}, "STALE_MAP", def)
eq(Objects._lastPreparationRoute, "sync", "reset discards late object preparation")

local Layout = require("src.core.game3.layout_native")
local Pack = require("src.import.gba.native_pack")
local decoded = { width = 4, height = 4, trueWidth = 3, trueHeight = 3, borderWidth = 2, borderHeight = 2,
  borderMids = { 11, 12, 13, 14 }, cells = {} }
for i = 1, 16 do decoded.cells[i] = { mid = i, coll = 0, elev = 0 } end
local blob = Pack.encodeMidLayout(decoded)
local layout = Layout.fromDecoded(decoded, "PLAN", "general__test", blob)
layout:applyOverride(1, 1, 90, 0, 3)
local p = layout:workerPacked()
check(p ~= nil, "native grid snapshots use immutable packed bytes")
local s = { x0 = -5, y0 = -5, cols = 15, rows = 15, mode = "map", neighbors = {}, world = {},
  layouts = { { x0 = -5, y0 = -5, w = 15, h = 15, width = 4, height = 4, pair = layout.pair, packed = p } } }
local plan = Cells.cells(s)
local equal = true
for y = -5, 9 do for x = -5, 9 do
  local mid, pair, void, skip = Cells.cell(plan, x, y)
  equal = equal and mid == layout:midAt(x, y) and pair == layout.pair
    and void == (x < 0 or y < 0 or x >= 4 or y >= 4) and not skip
end end
check(equal, "packed worker sampling matches borders padding and metatile overrides")
s.mode = "black"; plan = Cells.cells(s)
local _, _, void, skip = Cells.cell(plan, -2, -3)
check(void and skip, "black void skips only off-map cells")
s.mode, s.fill = "trees", { w = 2, h = 2, mids = { 40, 41, 42, 43 } }
plan = Cells.cells(s)
eq(Cells.cell(plan, -1, -1), 43, "patterned void wraps negative coordinates identically")
check(not pcall(Cells.cells, s, function() return true end), "stale cell preparation stops cooperatively")
local Assets = require("src.render.Assets")
Assets.loader = { overrideOrder = function() return { {} } end }
check(layout:workerPacked() == nil, "modded layouts use sampled snapshots")
Assets.loader = nil

local Map = require("src.core.game3.map")
local Plan = require("src.core.game3.field_plan")
local mapDef = { pair = layout.pair, midLayout = layout, connections = {} }
local game = { data = { maps = { PLAN = mapDef } } }
Map.current, Map._worldRoot, Map._def, Map.neighborList = "PLAN", "PLAN", mapDef, {}
Map.world = { { id = "PLAN", def = mapDef, ox = 0, oy = 0 } }
package.loaded["src.core.game3.field_view"] = { _viewW = 64, _viewH = 64 }
package.loaded["src.core.game3.player"] = { px = 16, py = 16, cellX = 1, cellY = 1 }
package.loaded["src.core.game3.tileset_native"] = { hasMid = function() return true end }
require("src.core.game3.void_fill").mode = "map"
Plan.prefetch(game); finishJobs()
check(Plan.get(mapDef, -2, -2, 7, 7, "map") ~= nil, "completed cell windows are consumed without waiting")
local oldBorder = layout.borderMids[1]
layout.borderMids[1] = 99
check(Plan.get(mapDef, -2, -2, 7, 7, "map") == nil, "border edits reject stale cell windows")
layout.borderMids[1] = oldBorder
layout:applyOverride(2, 2, 91)
check(Plan.get(mapDef, -2, -2, 7, 7, "map") == nil, "layout edits reject stale cell windows")
Plan.prefetch(game); finishJobs()
Map.world[2] = { id = "OTHER", def = mapDef, ox = 4, oy = 0 }
check(Plan.get(mapDef, -2, -2, 7, 7, "map") == nil, "world topology changes reject stale cell windows")
Map.world[2] = nil
Plan.invalidate()
check(Plan.get(mapDef, -2, -2, 7, 7, "map") == nil, "context reset clears prepared cell windows")

local nextDef = { pair = layout.pair, midLayout = Layout.fromDecoded(decoded, "NEXT", layout.pair, blob),
  connections = { { direction = "west", map = "PLAN", offset = 0 } } }
mapDef.connections = { { direction = "east", map = "NEXT", offset = 0 } }
game.data.maps.NEXT = nextDef
Map.neighborList = { { dir = "east", offset = 0, def = nextDef } }
Map.world = Map.computeWorld(game.data.maps, "PLAN", 2, 4, 4)
Plan.prefetch(game); finishJobs()
Map.current, Map._def, Map._worldRoot = "NEXT", nextDef, nil
Map.neighborList = { { dir = "west", offset = 0, def = mapDef } }
local player = package.loaded["src.core.game3.player"]
player.px, player.cellX = -48, -3
-- The old world graph survives Map.load until the first draw refreshes it.
Plan.prefetch(game)
Map.world, Map._worldRoot = Map.computeWorld(game.data.maps, "NEXT", 2, 4, 4), "NEXT"
check(Plan.get(nextDef, -6, -2, 7, 7, "map") ~= nil, "seam forecast survives stale world between load and first draw")
local Ghosts = require("src.core.game3.ghosts")
Ghosts.clear()
player.px, player.cellX = 16, 1
local ghostDef = { midLayout = layout, objects = { { localId = 1, x = 2, y = 2, graphicsId = 17 } } }
Map.world = { { id = "WORKER_GHOST", def = ghostDef, ox = 5, oy = 0 } }
Ghosts.sync()
check(Ghosts._pools.WORKER_GHOST == nil and Objects._preparationPending("WORKER_GHOST"), "offscreen nearby ghosts wait for worker preparation")
finishJobs(); Ghosts.sync()
check(Ghosts._pools.WORKER_GHOST ~= nil and Objects._lastPreparationRoute == "worker", "completed ghost preparation adopts on main thread")
Map.world = { { id = "COLLISION_GHOST", def = ghostDef, ox = 5, oy = 0 } }
Ghosts.sync()
check(Ghosts.blocksOn("COLLISION_GHOST", ghostDef, 2, 2), "collision remains authoritative while ghost work is pending")
Map.world = { { id = "FAR_GHOST", def = ghostDef, ox = 100, oy = 0 } }
Ghosts.sync()
check(Ghosts._pools.FAR_GHOST == nil and not Objects._preparationPending("FAR_GHOST"), "far ghosts do not preload indiscriminately")
Stream.workerFailed = true; Ghosts.sync()
check(Ghosts._pools.FAR_GHOST ~= nil, "unavailable worker retains synchronous ghost fallback")
Stream.workerFailed = false
Plan.invalidate()
Map.current, Map._worldRoot, Map._def = "PLAN", "PLAN", mapDef
Map.world = Map.computeWorld(game.data.maps, "PLAN", 2, 4, 4)
Map.neighborList = { { dir = "east", offset = 0, def = nextDef } }
local Native = package.loaded["src.core.game3.tileset_native"]
local Void = require("src.core.game3.void_fill")
local calls, savedBorder = 0, Void.borderFor
Void.mode, Void.borderFor = "trees", function() return { w = 1, h = 1, mids = { 40 } } end
Native.hasMid = function(atlas) calls = calls + 1; return type(atlas) == "table" end
Plan.prefetch(game); finishJobs()
check(calls == 0, "forecasting a cold patterned pair never demand-loads a graphics atlas")
Native._pairs = { [layout.pair] = {} }
Plan.prefetch(game); finishJobs()
local trees = Plan.get(mapDef, -2, -2, 7, 7, "trees")
check(trees and Plan.cell(trees, -2, -2) == 40 and calls > 0, "pattern validation consumes the warmed atlas without bypassing upload budgets")
Void.mode, Void.borderFor = "map", savedBorder
Plan.invalidate()
local shared = { width = 4, height = 4, midAt = function() return 77 end }
local a, b = { midLayout = shared, pair = "pair_a" }, { midLayout = shared, pair = "pair_b" }
game.data.maps.A, game.data.maps.B = a, b
mapDef.connections = { { dir = "east", map = "A", offset = 0 }, { dir = "east", map = "B", offset = 0 } }
Map.world = Map.computeWorld(game.data.maps, "PLAN", 2, 4, 4)
Map.neighborList = { { dir = "east", offset = 0, def = a }, { dir = "east", offset = 0, def = b } }
Plan.prefetch(game); finishJobs()
local aliases = Plan.get(mapDef, -2, -2, 7, 7, "map")
local mid, pair
if aliases then mid, pair = Plan.cell(aliases, 4, 0) end
check(mid == 77 and pair == "pair_b", "shared mod layouts retain each map's pair and reverse connection priority")
Stream.shutdown()
-- Exercise the production worker's result envelope, including a cancelled
-- job, rather than just the Channel transport double above.
for _, name in ipairs({ "filesystem", "image", "data", "timer" }) do package.loaded["love." .. name] = {} end
local workerInput, workerOutput = love.thread.newChannel(), love.thread.newChannel()
function workerInput:demand() return self:pop() end
workerInput:push({ id = 1, kind = "objects", spec = { task = true,
  payload = { defs = { { localId = 1 } }, version = "firered" } }, cancelSignal = { getCount = function() return 0 end } })
workerInput:push({ id = 2, kind = "objects", spec = { task = true,
  payload = { defs = { { localId = 1 } }, version = "firered" } }, cancelSignal = { getCount = function() return 1 end } })
workerInput:push({ stop = true })
assert(loadfile("src/core/game3/asset_worker.lua"))(workerInput, workerOutput)
local success, cancelled = workerOutput:pop(), workerOutput:pop()
check(success and success.data and success.data[1].localId == 1, "production worker returns prepared objects")
check(success and success.error == nil, "successful production worker replies have no error")
check(cancelled and cancelled.data == nil and cancelled.error:find("cancelled"), "cancelled production worker replies return an error without data")
T.finish("game3_field_prepare_worker_test")
