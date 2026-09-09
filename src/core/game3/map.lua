-- Game3 map loader. Owns Sevii enter: player, collision, EventObjects, Space scripts.
-- Talk/interact is Field.interact. Do not call host setMap/warpToMapId here —
-- MAPSETUP.WARP races ON_FRAME and wipes applymovement tracks (Bill intro).

local MapIds = require("src.core.game3.map_ids")
local Map = {}

Map.current = nil
Map.neighbors = {}
Map._loadedLayouts = {}
Map._def = nil
Map._currentDef = nil

function Map.currentDef()
  return Map._def or Map._currentDef
end

local function host_map_def(game, mapId)
  local data = game and game.data
  return data and data.maps and data.maps[mapId]
end

local function host_world(game)
  return game and (game.overworld or game.world)
end

function Map.loadNeighborsDepth1(game, primaryDef)
  Map.neighbors = {}
  if not primaryDef or type(primaryDef.connections) ~= "table" then
    return Map.neighbors
  end
  local data = game and game.data and game.data.maps
  if not data then return Map.neighbors end
  for dir, conn in pairs(primaryDef.connections) do
    local mid = type(conn) == "table" and conn.map or conn
    if type(mid) == "string" and data[mid] then
      local def = data[mid]
      Map.ensureMidLayout(game, mid, def)
      Map.neighbors[dir] = {
        map = mid,
        mapId = mid,
        def = def,
        offset = type(conn) == "table" and (conn.offset or 0) or 0,
      }
      Map._loadedLayouts[mid] = true
    end
  end
  return Map.neighbors
end

function Map.overscanSlices()
  local slices = {}
  for dir, n in pairs(Map.neighbors) do
    slices[#slices + 1] = { dir = dir, mapId = n.map or n.mapId, offset = n.offset }
  end
  return slices
end

local function neighborFor(cardinal)
  local n = Map.neighbors
  if not n then return nil end
  -- Dataset keys are north/south/west/east; some callers use up/down/left/right.
  if cardinal == "north" or cardinal == "up" then
    return n.north or n.up
  elseif cardinal == "south" or cardinal == "down" then
    return n.south or n.down
  elseif cardinal == "west" or cardinal == "left" then
    return n.west or n.left
  elseif cardinal == "east" or cardinal == "right" then
    return n.east or n.right
  end
  return n[cardinal]
end

--- Resolve a cell in current-map space, sampling connected neighbors when OOB
-- (pret VMap connection fill). Returns mid, sourcePair. OOB with no neighbor
-- falls through to primary border tiling.
function Map.worldMidAt(cx, cy, primaryDef)
  local layout = primaryDef and primaryDef.midLayout
  if not layout then return 0, nil end
  local w, h = layout.width or 0, layout.height or 0
  local primaryPair = layout.pair or primaryDef.pair

  local function fromNeighbor(n, nx, ny)
    if not n or not n.def then return nil end
    local L = n.def.midLayout
    if not L then return nil end
    if nx < 0 or ny < 0 or nx >= (L.width or 0) or ny >= (L.height or 0) then
      return nil
    end
    local pair = L.pair or n.def.pair
    return L:midAt(nx, ny), pair or primaryPair
  end

  if cx >= 0 and cy >= 0 and cx < w and cy < h then
    return layout:midAt(cx, cy), primaryPair
  end

  if cy < 0 then
    local n = neighborFor("north")
    if n then
      local offset = tonumber(n.offset) or 0
      local L = n.def and n.def.midLayout
      local nh = L and L.height or 0
      local mid, pair = fromNeighbor(n, cx - offset, nh + cy)
      if mid ~= nil then return mid, pair end
    end
  elseif cy >= h then
    local n = neighborFor("south")
    if n then
      local offset = tonumber(n.offset) or 0
      local mid, pair = fromNeighbor(n, cx - offset, cy - h)
      if mid ~= nil then return mid, pair end
    end
  end

  if cx < 0 then
    local n = neighborFor("west")
    if n then
      local offset = tonumber(n.offset) or 0
      local L = n.def and n.def.midLayout
      local nw = L and L.width or 0
      local mid, pair = fromNeighbor(n, nw + cx, cy - offset)
      if mid ~= nil then return mid, pair end
    end
  elseif cx >= w then
    local n = neighborFor("east")
    if n then
      local offset = tonumber(n.offset) or 0
      local mid, pair = fromNeighbor(n, cx - w, cy - offset)
      if mid ~= nil then return mid, pair end
    end
  end

  return layout:midAt(cx, cy), primaryPair
end

--- Ensure mapDef.midLayout is bound (lazy; Dataset.hydrate usually did this).
function Map.ensureMidLayout(game, mapId, def)
  def = def or host_map_def(game, mapId)
  if not def then return nil end
  if def.midLayout then return def.midLayout end
  local Dataset = require("src.core.game3.dataset")
  if Dataset.attachMidLayouts and game and game.data and game.data.maps then
    Dataset.attachMidLayouts({ [mapId] = def })
  end
  return def.midLayout
end

--- Load a Sevii map under game3 ownership (pret enter order).
-- 1) Bind game3 player + collision + EventObjects
-- 2) Objects.loadMap then Space.runEnterScripts (ON_TRANSITION → ON_FRAME)
function Map.load(mod, game, mapId, opts)
  opts = opts or {}
  if not MapIds.isGame3Map(mapId) then
    return nil, "not a game3 map"
  end
  Map.current = mapId
  Map._loadedLayouts = { [mapId] = true }

  local def = host_map_def(game, mapId)
  if not def then
    local okD, Dataset = pcall(require, "src.core.game3.dataset")
    if okD and Dataset and Dataset.map then
      def = Dataset.map(mapId)
    end
  end
  Map.ensureMidLayout(game, mapId, def)
  Map._def = def
  Map._currentDef = def
  -- Dismount bicycle when entering non-outdoor maps.
  do
    local Player = require("src.core.game3.player")
    if Player.biking then
      local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
      local outdoor = type(pair) == "string" and pair:find("outdoor", 1, true)
      if not outdoor then Player.biking = false end
    end
  end
  if opts.depth1Connections ~= false then
    Map.loadNeighborsDepth1(game, def)
  else
    Map.neighbors = {}
  end

  local world = host_world(game)
  local x = tonumber(opts.x) or 0
  local y = tonumber(opts.y) or 0
  local facing = opts.facing or "down"

  local Runtime = require("src.core.game3.runtime")
  if not Runtime.isActive or not Runtime.isActive() then
    if Runtime.ensureActiveForMap then
      Runtime.ensureActiveForMap(mod, game, mapId)
    end
  end

  local session = Runtime.getSession and Runtime.getSession()
  if session then
    session.map = mapId
    session.x = x
    session.y = y
    session.facing = facing
  end

  -- Keep save.position current for ferry exit / host save without setMap.
  local save = game and game.save
  if save then
    save.position = save.position or {}
    save.position.map = mapId
    save.position.x = x
    save.position.y = y
    save.position.facing = facing
  end

  local Player = require("src.core.game3.player")
  if opts.seamless then
    -- Connection remap (pret LoadMapFromCameraTransition): keep mid-step motion.
    -- Caller parks one cell before landing and sets target toward landing.
    Player.cellX = x
    Player.cellY = y
    Player.px = x * 16
    Player.py = y * 16
    Player.facing = facing
  else
    Player.reset(x, y, facing)
  end
  Player.syncSavePosition(game)

  local okFv, FieldView = pcall(require, "src.core.game3.field_view")
  if okFv and FieldView then FieldView._nativeDirty = true end

  -- Scripts/events before spawn so Objects.loadMap sees mapDef.objects.
  local Space = package.loaded["src.core.game3.scripting.space"]
    or require("src.core.game3.scripting.space")
  if Space.ensureBundle then Space.ensureBundle(mod or Runtime._mod) end
  if def and Space.attachEventsToMaps and game and game.data and game.data.maps then
    Space.attachEventsToMaps({ [mapId] = def }, Space.bundle)
  end

  local Collision = require("src.core.game3.collision")
  if def then Collision.bindMap(game, mapId, def) end

  -- pret GroundEffect_SpawnOnTallGrass when warping onto grass.
  if not opts.seamless then
    local onGrass = Collision.isGrass and Collision.isGrass(Player.cellX, Player.cellY)
    local okE, Encounters = pcall(require, "src.core.game3.encounters")
    if okE and Encounters and Encounters.noteGrass then
      Encounters.noteGrass(onGrass)
    end
    local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
    if okFx and FieldEffects then
      if onGrass and FieldEffects.tallGrassAt then
        FieldEffects.tallGrassAt(Player.cellX, Player.cellY, true)
      elseif FieldEffects.clearTallGrass then
        FieldEffects.clearTallGrass()
      end
    end
  end

  -- Activate scripts (flag store) → spawn destination NPCs → ON_TRANSITION.
  -- pret order: never run setobjectxyperm against the previous map's localIds
  -- (Pallet sign-lady localId=1 was teleporting Mom on FR_PLAYERS_HOUSE_1F).
  local Field = require("src.core.game3.field")
  if not opts.seamless then
    Field.lock()
  end

  local Objects = require("src.core.game3.objects")
  if Space and Space.activate then
    Space.activate(mod or Runtime._mod, mapId, game, world)
  end
  if def then Objects.loadMap(game, mapId, def) end
  if Space and Space.runEnterScripts then
    Space.runEnterScripts(mod or Runtime._mod, mapId, game, world)
  elseif Space and Space.onMapEnter then
    Space.onMapEnter(mod or Runtime._mod, mapId, game, world)
  end

  -- Map BGM from extract index / header music.
  do
    local Audio = require("src.core.game3.audio")
    local music = def and def.music
    if not music and Audio._pack and Audio._pack.index and Audio._pack.index.mapSongs then
      music = Audio._pack.index.mapSongs[mapId]
    end
    if music and music ~= 0xFFFF then
      Audio.playMapSong(music)
    end
  end

  if not opts.seamless then
    if not Space._pendingOnFrame
        and not (Space.vm and Space.vm.isRunning and Space.vm:isRunning()) then
      Field.unlock()
    end
  end

  return {
    mapId = mapId,
    neighbors = Map.neighbors,
    overscan = Map.overscanSlices(),
  }
end

function Map.loadedLayoutCount()
  local n = 0
  for _ in pairs(Map._loadedLayouts) do n = n + 1 end
  return n
end

return Map
