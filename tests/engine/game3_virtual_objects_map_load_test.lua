package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")
require("src.core.GameVersion").set("emerald")

local activate, enter
package.preload["src.core.game3.scripting.space"] = function()
  return {
    bundle = {}, ensureBundle = function() end, attachEventsToMaps = function() end,
    activate = function() if activate then activate() end end,
    runEnterScripts = function() if enter then enter() end end,
  }
end
package.preload["src.core.game3.ghosts"] = function()
  return { capture = function() end, adopt = function() end,
    visibleIds = function() return {} end, openFadeWindow = function() end }
end
package.preload["src.core.game3.field"] = function()
  return { lock = function() end, unlock = function() end,
    clearMetatiles = function() end, metatileOverrides = {} }
end
package.preload["src.core.game3.runtime"] = function()
  return { isActive = function() return true end, getSession = function() end }
end
package.preload["src.core.game3.player"] = function()
  return { cellX = 0, cellY = 0, px = 0, py = 0, facing = "down", biking = false,
    reset = function() end, syncSavePosition = function() end }
end
package.preload["src.core.game3.collision"] = function()
  return { bindMap = function() end, clear = function() end }
end
package.preload["src.core.game3.audio"] = function()
  return { setSavedSong = function() end }
end
package.preload["src.core.game3.encounters"] = function()
  return { resetRateModifiers = function() end }
end
package.preload["src.core.game3.field_effects"] = function() return {} end
package.preload["src.core.game3.field_view"] = function() return {} end
package.preload["src.core.game3.field_modules"] = function()
  return { enabled = function() return false end }
end
package.preload["src.core.game3.dataset"] = function()
  return { map = function() end }
end

local Map = require("src.core.game3.map")
local Objects = require("src.core.game3.objects")
local VirtualObjects = require("src.core.game3.virtual_objects")
local layout = { width = 16, height = 16, collAt = function() return 0 end }
local function mapDef(localId)
  return { midLayout = layout, objects = {
    { localId = localId, x = 6, y = 6, graphicsId = 40 },
  } }
end
local game = { data = { maps = {
  EM_AUDIENCE_HALL = mapDef(1),
  EM_AUDIENCE_LOBBY = mapDef(2),
  EM_AUDIENCE_HOUSE = mapDef(3),
} } }
local function load(id, opts)
  local result = Map.load({}, game, id, opts or {})
  T.check(result and result.mapId == id, "real Map.load reaches " .. id)
end
local function drawnVirtuals()
  local count = 0
  for _, eo in ipairs(Objects.forDraw()) do
    if eo.virtualId ~= nil then count = count + 1 end
  end
  return count
end
local function spawn(id)
  VirtualObjects.spawn(id, 40, 3, 2, 3, 1)
  T.check(VirtualObjects.get(id) ~= nil, "old map virtual sprite " .. id .. " exists")
end

load("EM_AUDIENCE_HALL")
spawn(20)
T.eq(drawnVirtuals(), 1, "hall audience reaches the real draw list")
load("EM_AUDIENCE_LOBBY")
T.eq(VirtualObjects.count(), 0, "ordinary warp clears old virtual sprite registry")
T.eq(drawnVirtuals(), 0, "ordinary warp clears old virtual sprites from the draw list")
T.check(Objects.find(2) ~= nil, "ordinary warp retains destination native objects")

spawn(20)
load("EM_AUDIENCE_LOBBY")
T.eq(VirtualObjects.count(), 0, "same-map nonseamless reload clears old virtual sprites")
T.eq(drawnVirtuals(), 0, "same-map reload cannot redraw the old audience")

spawn(20)
load("EM_AUDIENCE_MISSING")
T.eq(VirtualObjects.count(), 0, "def-less nonseamless load clears old virtual sprites")
T.eq(drawnVirtuals(), 0, "def-less load cannot redraw the old audience")

load("EM_AUDIENCE_HALL")
spawn(20)
local actor = Objects.find(1)
Objects.startTrack(1, { { kind = "sleep", frames = 5 } })
local track = Objects._tracks[1]
local carry = Objects.carryOut(0, 0)
load("EM_AUDIENCE_LOBBY", { seamless = true, carry = carry })
T.eq(VirtualObjects.count(), 1, "seamless load preserves virtual sprite memory")
T.eq(drawnVirtuals(), 1, "seamless load keeps virtual sprites drawable")
T.eq(Objects.find(Objects.foreignKey("EM_AUDIENCE_HALL", 1)), actor,
  "seamless load preserves the actual carried actor")
T.eq(Objects._tracks[actor.localId], track, "seamless load preserves the carried movement track")
T.check(Objects.find(2) ~= nil, "seamless load still spawns destination native objects")

activate = function()
  T.eq(VirtualObjects.count(), 0, "ordinary reload clears sprites before destination activation")
  VirtualObjects.spawn(21, 40, 3, 2, 3, 1)
end
enter = function()
  T.eq(VirtualObjects.count(), 1, "destination activation sprite survives through enter scripts")
  VirtualObjects.spawn(22, 40, 4, 2, 3, 1)
end
load("EM_AUDIENCE_HOUSE")
T.eq(VirtualObjects.get(20), nil, "old map sprite stays removed after destination scripts")
T.eq(VirtualObjects.count(), 2, "destination scripts can create their own virtual sprites")
T.eq(drawnVirtuals(), 2, "new destination sprites reach the real draw list")
T.check(Objects.find(3) ~= nil, "destination scripts do not disturb native object spawning")

T.finish("game3_virtual_objects_map_load_test")
