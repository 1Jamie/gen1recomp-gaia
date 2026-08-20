-- #1479 / #1449: TILESET_KANTO takes no map-group roof (home/map.asm:1738-1749)
--   luajit tests/engine/gen2_kanto_no_roof_bug1479.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local MapPreview = require("src.world.gen2.MapPreview")

local baker = {
  tilesets = {
    TILESET_KANTO = { image = "assets/generated/tilesets/kanto.png" },
    TILESET_JOHTO = { image = "assets/generated/tilesets/johto.png" },
  },
  roofs = {
    mapGroupRoofs = { [19] = "ROOF_SILVER" },
    roofs = { ROOF_SILVER = {} },
  },
  atlasCache = {},
  mapImages = {},
}

-- data/maps/maps.asm:396: SilverCaveOutside and Route28 are both group 19
-- (MapGroup_Silver) and both TILESET_KANTO.
MapPreview.atlasFor(baker, { tileset = "TILESET_KANTO", group = 19 })
MapPreview.atlasFor(baker, { tileset = "TILESET_JOHTO", group = 19 })

local keys = {}
for key in pairs(baker.atlasCache) do keys[key] = true end

T.check(keys["TILESET_KANTO"],
  "the Kanto atlas is cached under the bare tileset, with no roof")
T.check(not keys["TILESET_KANTO|ROOF_SILVER"],
  "and never under a map-group roof")
T.check(keys["TILESET_JOHTO|ROOF_SILVER"],
  "while TILESET_JOHTO still takes its group's roof")

print("gen2 Kanto roof gate (#1479): ok")
