-- COLL byte -> permission vocabulary shared by the gen2 world runtime and the
-- Gen 3 import path.
--
-- Why it lives in src/core (review-v3 I9, import/world seam): import
-- src/import/gba/native_pack.lua classifies COLL bytes while packing FRLG
-- native mid layouts, and src/world/gen2/Map.lua classifies them while the
-- player walks. One table, two consumers below different layers, so the table
-- lives above both and src/world/gen2/Permissions.lua re-exports it for its
-- existing callers. Import must not reach into src/world for it.
--
-- Provenance: pokegold CollisionPermissionTable (lo nybble),
-- home/map_objects.asm GetTilePermission.  LAND=0, WATER=1, WALL=0x0f.

local CollPermissions = {}

CollPermissions.LAND = 0x00
CollPermissions.WATER = 0x01
CollPermissions.WALL = 0x0f

-- CollisionPermissionTable, lo nybble only (256 entries).
local TABLE = {
   0,  0,  0,  0,  0,  0,  0, 15,  0,  0,  0,  0,  0,  0,  0, 15,
   0,  0, 15,  0,  0, 15,  0,  0,  0,  0, 15,  0,  0, 15,  0,  0,
   1,  1,  1,  0,  1,  1,  1, 15,  1,  1,  1,  0,  1,  1,  1, 15,
   1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
   0,  0, 15,  0,  0,  0,  0,  0,  0,  0, 15,  0,  0,  0,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
  15, 15, 15, 15, 15,  0,  0,  0, 15, 15, 15, 15, 15,  0,  0,  0,
  15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
   1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,  1,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,
   0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 15,
}

function CollPermissions.of(coll)
  if coll == nil or coll < 0 then return CollPermissions.WALL end
  return TABLE[(coll % 256) + 1] or CollPermissions.WALL
end

function CollPermissions.isLand(coll)
  return CollPermissions.of(coll) == CollPermissions.LAND
end

function CollPermissions.isWater(coll)
  return CollPermissions.of(coll) == CollPermissions.WATER
end

function CollPermissions.isWall(coll)
  return CollPermissions.of(coll) == CollPermissions.WALL
end

-- Walkable on foot: DoPlayerMovement's .CheckWalkable, which is nothing more
-- than "the permission is LAND_TILE".
function CollPermissions.isWalkable(coll)
  return CollPermissions.of(coll) == CollPermissions.LAND
end

-- Ledges: a ledge tile is LAND in the permission table, and only the hi nybble
-- (the $a0 family — $a0-$a7 carry the defined hop variants) marks it as one.
function CollPermissions.isLedge(coll)
  if coll == nil or coll < 0 then return false end
  return math.floor((coll % 256) / 16) == 0xa
end

return CollPermissions
