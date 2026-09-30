package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Objects = require("src.core.game3.objects")
local Ghosts = require("src.core.game3.ghosts")
local Player = require("src.core.game3.player")
local Map = require("src.core.game3.map")
local Runtime = require("src.core.game3.runtime")
local Space = require("src.core.game3.scripting.space")
Space.bundle = { events = {} }
local game = { data = { maps = {} } }
Runtime.session = { version = "firered", map = "TEST_A", flags = {}, vars = {} }
Runtime._game = game
local layout = { width = 64, height = 64, collAt = function() return 0 end }
local first = { midLayout = layout, objects = {
  { localId = 7, x = 10, y = 10 },
  { localId = 8, x = 12, y = 10 },
  { localId = 9, x = 15, y = 10 },
} }
local empty = { midLayout = layout, objects = {} }
Objects.clear()
Ghosts.clear()
Objects.loadMap(game, "TEST_A", first)
Player.reset(10, 9, "down")
local boat, actor, npc = Objects.find(7), Objects.find(8), Objects.find(9)
local callbacks = { boat = 0, actor = 0, player = 0 }
local actions = {
  { kind = "step", dir = "down", fast = true },
  { kind = "step", dir = "down", fast = true },
  { kind = "step", dir = "down", fast = true },
}
Objects.startTrack(7, actions, function() callbacks.boat = callbacks.boat + 1 end)
Objects.startTrack(8, actions, function() callbacks.actor = callbacks.actor + 1 end)
Objects.startTrack(255, actions, function() callbacks.player = callbacks.player + 1 end)
npc.moving, npc.targetX, npc.targetY = true, npc.cellX, npc.cellY + 1
npc.progress, npc.animClock, npc.stepFrames = 0, 0, 16
npc.scriptBusy, npc.frozen = true, true

local function shiftPlayer(dx, dy)
  Player.cellX, Player.cellY = Player.cellX + dx, Player.cellY + dy
  Player.targetX, Player.targetY = Player.targetX + dx, Player.targetY + dy
  Player.px, Player.py = Player.px + dx * 16, Player.py + dy * 16
end
local function transfer(from, to, dx, dy)
  local carry = Objects.carryOut(dx, dy)
  shiftPlayer(dx, dy)
  Ghosts.capture(from)
  local pool = Ghosts._pools[from]
  for _, eo in pairs(pool.byId) do
    T.check(eo ~= boat and eo ~= actor, "carried actors absent from departing ghost pool " .. from)
  end
  T.check(boat.scriptBusy and boat.frozen and actor.scriptBusy and actor.frozen,
    "capture preserves held movement state " .. from)
  Objects.loadMap(game, to, empty)
  Objects.carryIn(carry)
  Runtime.session.map = to
  Map.world = { { id = "TEST_A", def = first, ox = 0, oy = 0 } }
  if from ~= "TEST_A" then Map.world[#Map.world + 1] = { id = from, def = empty, ox = 0, oy = 0 } end
  T.eq(Objects.find(Objects.foreignKey("TEST_A", 7)), boat, "foreign boat lookup survives " .. to)
  T.eq(Objects.find(Objects.foreignKey("TEST_A", 8)), actor, "generic foreign lookup survives " .. to)
end
transfer("TEST_A", "TEST_B", 2, 0)
T.eq(Ghosts._pools.TEST_A.byId[9], npc, "ordinary departing NPC remains captured")
T.check(not npc.scriptBusy and not npc.frozen, "ordinary departing NPC is released")
local firstNpcY = npc.py
local function frame()
  local before = boat.py
  Objects.update(game)
  local afterLive = boat.py
  Ghosts.update(game)
  T.eq(boat.py, afterLive, "ghost pass never moves live carried boat twice")
  Player.tick(game)
  T.eq(boat.py - Player.py, 16, "boat and player retain relative sailing pixels")
  return boat.py - before
end
frame()
T.check(npc.py > firstNpcY, "ordinary ghost movement still advances")
transfer("TEST_B", "TEST_C", 3, 0)
for _ = 1, 30 do frame() end
T.eq(callbacks.boat, 1, "boat completion callback fires once")
T.eq(callbacks.actor, 1, "generic actor completion callback fires once")
T.eq(callbacks.player, 1, "player completion callback fires once")
T.check(Objects._tracks[Objects.foreignKey("TEST_A", 7)].done, "foreign boat track completes")
Ghosts.clear()
Objects.clear()

local Collision = require("src.core.game3.collision")
local realConnection, realPairs = Collision.scriptConnection, pairs
Runtime.session.version = "emerald"
Collision._grid, Collision._widthCells, Collision._heightCells = { 0 }, 4, 8
local seamLayout = { width = 4, height = 8, collAt = function() return 0 end }
local function contains(list, actor)
  for _, eo in ipairs(list) do if eo == actor then return true end end
  return false
end
for _, playerFirst in ipairs({ true, false }) do
  Objects.clear()
  Ghosts.clear()
  local source = { midLayout = seamLayout, objects = {
    { localId = 7, x = 3, y = 2 }, { localId = 9, x = -1, y = 4 },
  } }
  local destination = { midLayout = seamLayout, objects = { { localId = 9, x = -1, y = 4 } } }
  local from, seams = "SEAM_A", 0
  Runtime.session.map = from
  Objects.loadMap(game, from, source)
  Player.reset(3, 1, "right")
  local vessel, outside = Objects.find(7), Objects.find(9)
  T.check(not contains(Objects.forDraw(), outside), "ordinary off-map EO remains filtered")
  local movement = { { kind = "sleep", frames = 1 } }
  for _ = 1, 9 do movement[#movement + 1] = { kind = "step", dir = "right", fast = true } end
  local done = { boat = 0, player = 0 }
  Objects.startTrack(7, movement, function() done.boat = done.boat + 1 end)
  Objects.startTrack(255, movement, function() done.player = done.player + 1 end)
  local boatTrack, playerTrack = Objects._tracks[7], Objects._tracks[255]
  pairs = function(t)
    if t ~= Objects._tracks then return realPairs(t) end
    local order = playerFirst and { 255, vessel.localId } or { vessel.localId, 255 }
    local index = 0
    return function()
      index = index + 1
      local id = order[index]
      if id then return id, t[id] end
    end
  end
  Collision.scriptConnection = function(_, fx, fy, dir)
    T.eq(dir, "right", "script seam uses current movement direction")
    seams = seams + 1
    local to = "SEAM_" .. seams
    local carry = Objects.carryOut(-4, 0)
    Ghosts.capture(from)
    Objects.loadMap(game, to, destination)
    Objects.carryIn(carry)
    Runtime.session.map, from = to, to
    Player.cellX, Player.cellY = fx - 4, fy
    Player.px, Player.py = Player.cellX * 16, Player.cellY * 16
    Player.targetX, Player.targetY = Player.cellX, Player.cellY
    return 0, fy
  end
  for frame = 1, 80 do
    Objects.update(game)
    Player.tick(game)
    T.eq(vessel.px - Player.px, 0, "mid-track seam keeps horizontal boat/player pixels")
    T.eq(vessel.py - Player.py, 16, "mid-track seam keeps vertical boat/player pixels")
    if frame == 1 then
      T.check(vessel.cellX == -1 and contains(Objects.forDraw(), vessel),
        "visible foreign EO draws outside host map bounds")
      T.check(not contains(Objects.forDraw(), Objects.find(9)), "ordinary destination off-map EO remains filtered")
      vessel.hidden = true
      T.check(not contains(Objects.forDraw(), vessel), "hidden foreign EO remains filtered")
      vessel.hidden, vessel.invisible = false, true
      T.check(not contains(Objects.forDraw(), vessel), "invisible foreign EO remains filtered")
      vessel.invisible = false
      T.eq(boatTrack.i, playerTrack.i, "seam advances each original track once in either order")
    end
  end
  T.eq(seams, 3, "script track crosses three repeated seams")
  T.eq(done.boat, 1, "seam boat callback fires once")
  T.eq(done.player, 1, "seam player callback fires once")
  T.check(boatTrack.done and playerTrack.done, "seam keeps both held tracks to completion")
  pairs = realPairs
end
for _, mode in ipairs({ "removed", "track_replaced", "actor_replaced" }) do
  Objects.clear()
  Ghosts.clear()
  Objects.loadMap(game, "GUARD_A", { midLayout = seamLayout, objects = {
    { localId = 7, x = 3, y = 2 }, { localId = 8, x = 3, y = 4 },
  } })
  Runtime.session.map = "GUARD_A"
  Player.reset(3, 1, "right")
  local vessel, other = Objects.find(7), Objects.find(8)
  local movement = { { kind = "sleep", frames = 1 }, { kind = "step", dir = "right", fast = true } }
  local called = 0
  Objects.startTrack(7, movement)
  Objects.startTrack(8, movement, function() called = called + 1 end)
  Objects.startTrack(255, movement)
  local original = Objects._tracks[8]
  local replacement
  pairs = function(t)
    if t ~= Objects._tracks then return realPairs(t) end
    local order, index = { 255, vessel.localId, other.localId }, 0
    return function()
      index = index + 1
      local id = order[index]
      if id then return id, t[id] end
    end
  end
  Collision.scriptConnection = function(_, fx, fy)
    local carry = Objects.carryOut(-4, 0)
    Ghosts.capture("GUARD_A")
    Objects.loadMap(game, "GUARD_B", { midLayout = seamLayout, objects = {} })
    Objects.carryIn(carry)
    Runtime.session.map = "GUARD_B"
    Player.cellX, Player.cellY = fx - 4, fy
    Player.px, Player.py = Player.cellX * 16, Player.cellY * 16
    Player.targetX, Player.targetY = Player.cellX, Player.cellY
    if mode == "removed" then
      Objects.removeObject(other.localId)
    elseif mode == "track_replaced" then
      Objects.startTrack(other.localId, { { kind = "sleep", frames = 3 } })
      replacement = Objects._tracks[other.localId]
    else
      local copy = {}
      for key, value in realPairs(other) do copy[key] = value end
      Objects._byId[other.localId] = copy
    end
    return 0, fy
  end
  Objects.update(game)
  Player.tick(game)
  T.eq(original.i, 2, mode .. " snapshot never advances obsolete actor track")
  T.eq(original.sleep, 1, mode .. " snapshot never consumes obsolete actor sleep")
  T.eq(called, 0, mode .. " snapshot never fires obsolete actor callback")
  if replacement then T.eq(replacement.sleep, 3, "replacement track waits until next frame") end
  pairs = realPairs
end
Objects.clear()
Objects.startTrack(31, { { kind = "sleep", frames = 1 }, { kind = "sleep", frames = 1 } },
  function() callbacks.actor = callbacks.actor + 1 end)
Objects.update(game)
Objects.update(game)
T.eq(callbacks.actor, 2, "initially missing optional EO track still completes")
pairs, Collision.scriptConnection = realPairs, realConnection
Ghosts.clear()
Objects.clear()
T.finish("game3_carried_actor_ghost")
