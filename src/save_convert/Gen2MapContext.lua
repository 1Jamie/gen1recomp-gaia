-- Gen2MapContext -- the saved object state a Gen 2 cart save has to carry
-- for the map it stands on.
--
-- Continuing a real Gen 2 save re-derives the map itself but not its people.
-- MapSetupScript_Continue (data/maps/setup_scripts.asm) runs
-- LoadMapAttributes_SkipObjects: attributes, blocks, graphics and palettes
-- all come back out of the ROM by wMapGroup/wMapNumber, but ReadObjectEvents
-- is deliberately skipped, so wMapObjects, the object structs, the object
-- masks and wCurMapObjectEventCount/Pointer are trusted straight out of the
-- save file. A cartridge save always has them because the game wrote them.
--
-- An export from this port did not, whenever the save had MOVED since the
-- cartridge image it writes into: encode updated wMapGroup, wMapNumber and
-- the coordinates and left the whole object window describing the old map.
-- The real game then continues onto the new map with the old map's NPCs,
-- object scripts and event flags walking around in it, which is the garbled
-- overworld users see after exporting a save that progressed past the map it
-- was imported on. Gen 1 had the same class of bug and closed it in
-- MapContext.lua (#889, finished by #1691); this is that module for Gen 2.
--
-- The rebuild replays ReadObjectEvents (home/map.asm) exactly:
--
--   * each object_event's thirteen ROM bytes are copied verbatim behind a
--     MAPOBJECT_OBJECT_STRUCT_ID of -1, "no struct spawned yet";
--   * the remaining map-object slots get 0 / -1, the empty pattern;
--   * every NPC object struct is cleared (ClearObjectStructs), and the
--     engine respawns them from wMapObjects the same way it does after any
--     ordinary warp;
--   * wObjectMasks is zeroed and wObjectFollow_Leader/Follower reset to -1;
--   * wCurMapObjectEventCount and wCurMapObjectEventsPointer are set to the
--     new map's count and its object list's ROM address, which is what a
--     later ReloadMapEvents reads.
--
-- The player keeps the template's own struct and map object, standing and
-- idle exactly as an in-game SAVE leaves them, with only the four map
-- coordinate bytes re-anchored to the new position.
--
-- Offsets are .sav file offsets. The anchor is the same one
-- tools/gen2_sram_offsets.py uses (wMoney against Gen2Layout), and every
-- value below was summed from the pret .sym files and cross-checked against
-- Gen2Layout's own rows: pokecrystal wMapGroup $DCB5 lands at 0x2843 and
-- pokegold's at 0x2868, which are the numbers Gen2Layout already ships.
--
-- Known limitation, deliberate: wObjectMasks starts at zero, so an object a
-- scene script would hide is visible until the first re-entry runs that
-- scene. Objects hidden by their own event flag, which is nearly all of
-- them, hide correctly, because the flag lives in wEventFlags and travels
-- with the save.
--
-- Pure Lua, no love.*: shared by the runtime exporter, the CLI and the tests.

local Gen2MapContext = {}

local NUM_OBJECTS = 16          -- wMapObjects slots, the player plus fifteen
local MAPOBJECT_LENGTH = 16
local OBJECT_EVENT_SIZE = 13    -- the ROM bytes CopyMapObjectEvents copies
local NUM_OBJECT_STRUCTS = 13   -- the player plus twelve
local OBJECT_LENGTH = 40
-- object_struct's map coordinate bytes (macros/wram.asm): OBJECT_MAP_X at
-- +16, OBJECT_MAP_Y at +17, then the LAST_MAP pair. Same in pokegold
-- (wPlayerMapX $D20D against wPlayerStruct $D1FD) and pokecrystal
-- (wPlayerMapX $D4E6 against wPlayerStruct $D4D6).
local STRUCT_MAP_X = 16
local STRUCT_MAP_Y = 17
local STRUCT_LAST_MAP_X = 18
local STRUCT_LAST_MAP_Y = 19

Gen2MapContext.OFFSETS = {
  goldSilver = {
    objectFollow = 0x205C,       -- wObjectFollow_Leader, then _Follower
    objectStructs = 0x2065,      -- wObjectStructs / wPlayerStruct
    mapObjects = 0x22AD,         -- wMapObjects, slot 0 is the player's
    objectMasks = 0x23AD,        -- wObjectMasks
    objectEventCount = 0x27B6,   -- wCurMapObjectEventCount
    objectEventsPointer = 0x27B7,
  },
  crystal = {
    objectFollow = 0x205B,
    objectStructs = 0x2064,
    mapObjects = 0x22AC,
    objectMasks = 0x23AC,
    objectEventCount = 0x2792,
    objectEventsPointer = 0x2793,
  },
}

function Gen2MapContext.offsetsFor(gameVersion)
  if gameVersion == "crystal" then return Gen2MapContext.OFFSETS.crystal end
  if gameVersion == "gold" or gameVersion == "silver" then
    return Gen2MapContext.OFFSETS.goldSilver
  end
  return nil
end

local function findMap(data, group, number)
  for id, def in pairs((data and data.maps) or {}) do
    if type(def) == "table" and def.group == group and def.map == number then
      return id, def
    end
  end
  return nil
end

local function u8(v) return math.floor(tonumber(v) or 0) % 256 end
local function signedU8(v)
  v = math.floor(tonumber(v) or 0)
  if v < 0 then v = v + 256 end
  return v % 256
end

-- One wMapObjects slot from the extractor's decoded object_event, laid out
-- exactly as CopyMapObjectEvents leaves it: -1 for the struct id, then the
-- thirteen ROM bytes verbatim, then the two bytes the struct pads to
-- sixteen with. The extractor stores coordinates biased back by the game's
-- +4 and the radius split into nibbles; both transforms are undone here so
-- the slot is byte-for-byte what the cartridge would hold.
local function mapObjectSlot(obj)
  local radius = obj.radius or {}
  local hours = obj.hours or {}
  local eventFlag = obj.eventFlag or 0xFFFF
  local script = obj.script or 0
  return {
    0xFF,
    u8(obj.spriteId),
    u8((obj.y or 0) + 4),
    u8((obj.x or 0) + 4),
    u8(obj.movement),
    (u8(radius.y or 0) % 16) * 16 + u8(radius.x or 0) % 16,
    signedU8(hours[1]),
    signedU8(hours[2]),
    (u8(obj.palette or 0) % 16) * 16 + u8(obj.type or 0) % 16,
    u8(obj.sight),
    script % 256, math.floor(script / 256) % 256,
    eventFlag % 256, math.floor(eventFlag / 256) % 256,
    0, 0,
  }
end

-- build(data, gameVersion, group, number, x, y) -> ctx, err
--
-- ctx.writes  [.sav offset] = array of bytes
--
-- Returns nil plus a reason when the map is unknown to this data set or the
-- cache predates the extractor field this needs, so callers refuse the
-- export rather than write one that continues wrong.
function Gen2MapContext.build(data, gameVersion, group, number, x, y)
  local O = Gen2MapContext.offsetsFor(gameVersion)
  if not O then return nil, "no Gen 2 layout for " .. tostring(gameVersion) end
  local id, def = findMap(data, group, number)
  if not def then
    return nil, ("unknown map %d/%d"):format(tonumber(group) or -1, tonumber(number) or -1)
  end
  local objects = def.objects or {}
  if #objects > NUM_OBJECTS - 1 then
    return nil, ("%s declares %d objects and a save holds %d")
      :format(tostring(id), #objects, NUM_OBJECTS - 1)
  end
  if type(def.objectEventsAddr) ~= "number" then
    return nil, "map cache has no object-table address (re-import the ROM)"
  end
  x, y = math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0)

  local writes = {}

  -- The NPC map objects, then the empty pattern ReadObjectEvents pads with.
  local slots = {}
  for _, obj in ipairs(objects) do
    local slot = mapObjectSlot(obj)
    for i = 1, MAPOBJECT_LENGTH do slots[#slots + 1] = slot[i] end
  end
  for _ = #objects + 1, NUM_OBJECTS - 1 do
    slots[#slots + 1] = 0
    slots[#slots + 1] = 0xFF
    for _ = 3, MAPOBJECT_LENGTH do slots[#slots + 1] = 0 end
  end
  writes[O.mapObjects + MAPOBJECT_LENGTH] = slots

  -- The player's map object keeps the template's sprite and movement; only
  -- its coordinates move. Byte 0 is its struct id, byte 1 its sprite, and
  -- the coordinates sit where CopyMapObjectEvents put them, +2 and +3.
  writes[O.mapObjects + 2] = { u8(y + 4), u8(x + 4) }

  -- ClearObjectStructs, for the twelve NPC structs. The engine spawns fresh
  -- ones from wMapObjects the same way it does after a warp.
  local cleared = {}
  for _ = 1, (NUM_OBJECT_STRUCTS - 1) * OBJECT_LENGTH do cleared[#cleared + 1] = 0 end
  writes[O.objectStructs + OBJECT_LENGTH] = cleared

  -- The player's struct stays as the in-game SAVE left it, standing and
  -- idle, re-anchored to the new tile.
  writes[O.objectStructs + STRUCT_MAP_X] = { u8(x + 4) }
  writes[O.objectStructs + STRUCT_MAP_Y] = { u8(y + 4) }
  writes[O.objectStructs + STRUCT_LAST_MAP_X] = { u8(x + 4) }
  writes[O.objectStructs + STRUCT_LAST_MAP_Y] = { u8(y + 4) }

  -- Nobody is following anybody across an export.
  writes[O.objectFollow] = { 0xFF, 0xFF }

  local masks = {}
  for _ = 1, NUM_OBJECTS do masks[#masks + 1] = 0 end
  writes[O.objectMasks] = masks

  writes[O.objectEventCount] = { u8(#objects) }
  writes[O.objectEventsPointer] = {
    def.objectEventsAddr % 256,
    math.floor(def.objectEventsAddr / 256) % 256,
  }

  return { writes = writes, mapId = id }
end

-- STRUCT_MAP_Y and STRUCT_LAST_MAP_Y are documented above and pinned by the
-- tests; exported so the tests read the same constants the writes use.
Gen2MapContext.STRUCT_MAP_X = STRUCT_MAP_X
Gen2MapContext.STRUCT_MAP_Y = STRUCT_MAP_Y
Gen2MapContext.MAPOBJECT_LENGTH = MAPOBJECT_LENGTH
Gen2MapContext.OBJECT_LENGTH = OBJECT_LENGTH
Gen2MapContext.NUM_OBJECTS = NUM_OBJECTS
Gen2MapContext.NUM_OBJECT_STRUCTS = NUM_OBJECT_STRUCTS
Gen2MapContext.OBJECT_EVENT_SIZE = OBJECT_EVENT_SIZE

return Gen2MapContext
