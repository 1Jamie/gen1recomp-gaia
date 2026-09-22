-- Virtual-object registry for the `createvobject` / `turnvobject` seam
-- (docs/game3/e10-opcode-spec.md sections 5.3/5.4).
--
-- pret: CreateVirtualObject(graphicsId, virtualObjId, x, y, elevation, direction)
-- builds a sprite-only NPC that never collides or talks
-- (src/event_object_movement.c:1719), looked up by id
-- (GetVirtualObjectSpriteId, src/event_object_movement.c:9236), turned by
-- facing its sprite (TurnVirtualObject, src/event_object_movement.c:9248-9257),
-- and torn down en masse (DestroyVirtualObjects, :9225). This module is the
-- data side only: the OW-sprite draw path consumes list() and the draw/collision
-- files never see it (new file, unwired — the wiring handoff is listed in the
-- spec).

local VirtualObjects = {}

-- pret include/constants/global.h:110 (also event.inc createvobject default)
VirtualObjects.DIR_SOUTH = 1

local byId = {}
local order = {} -- stable spawn order for the draw path (index = position)
local logged = {}

local function log_once(key, msg)
  if logged[key] then return end
  logged[key] = true
  print("[game3/virtual_objects] " .. tostring(msg))
end

--- Register (or replace) a virtual object. Mirrors pret's argument order:
-- createvobject graphicsId(B), id(B), x(H), y(H), elevation(B), direction(B)
-- (src/scrcmd.c:1171-1181). Returns the record, or nil on a bad id.
--
-- Documented divergence: pret allows two sprites to share an id and resolves
-- turn() to the first; this is a keyed map, so a duplicate id REPLACES the
-- entry (a script that re-spawns gets fresh coordinates). Registered ids are
-- u8 by construction (the opcode decoder only ever yields a byte).
function VirtualObjects.spawn(vObjId, graphicsId, x, y, elevation, direction)
  local id = tonumber(vObjId)
  if id == nil then
    log_once("spawn:" .. tostring(vObjId), "createvobject with a non-numeric id")
    return nil
  end
  if byId[id] == nil then
    order[#order + 1] = id
  end
  local rec = {
    id = id,
    graphicsId = tonumber(graphicsId) or 0,
    x = tonumber(x) or 0,
    y = tonumber(y) or 0,
    -- event.inc:1346 defaults: elevation=3, direction=DIR_SOUTH
    elevation = tonumber(elevation) or 3,
    direction = tonumber(direction) or VirtualObjects.DIR_SOUTH,
  }
  byId[id] = rec
  return rec
end

--- Face an existing object (pret TurnVirtualObject). A missing id is a
-- logged no-op returning false, mirroring pret's MAX_SPRITES miss path.
function VirtualObjects.turn(vObjId, direction)
  local id = tonumber(vObjId)
  local rec = id and byId[id] or nil
  if not rec then
    log_once("turn:" .. tostring(vObjId),
      "turnvobject for an id that was never created (" .. tostring(vObjId) .. ")")
    return false
  end
  rec.direction = tonumber(direction) or rec.direction
  return true
end

--- The record for an id, or nil (pret GetVirtualObjectSpriteId's miss case).
function VirtualObjects.get(vObjId)
  local id = tonumber(vObjId)
  return id and byId[id] or nil
end

--- Live records in spawn order — the draw path iterates this and nothing else.
function VirtualObjects.list()
  local out = {}
  for i = 1, #order do
    local rec = byId[order[i]]
    if rec then out[#out + 1] = rec end
  end
  return out
end

function VirtualObjects.count()
  local n = 0
  for _ in pairs(byId) do n = n + 1 end
  return n
end

--- Map unload / map change: pret DestroyVirtualObjects (event_object_movement.c:9225).
function VirtualObjects.clear()
  for k in pairs(byId) do byId[k] = nil end
  for i = #order, 1, -1 do order[i] = nil end
end

--- Test/tool hook: forget the state and the log-once keys.
function VirtualObjects.reset()
  VirtualObjects.clear()
  logged = {}
end

return VirtualObjects
