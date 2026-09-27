package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local PRET = os.getenv("POKEPORT_POKEEMERALD") or "../pokeemerald"
local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or (PRET .. "/pokeemerald.gba")
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_region_map_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()

local rom = {}
function rom:get(o) return data:byte(o + 1) end
function rom:u16(o) local a, b = data:byte(o + 1, o + 2); return a + b * 256 end
function rom:u32(o)
  local a, b, c, d = data:byte(o + 1, o + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
function rom:readString(o, n) return data:sub(o + 1, o + n) end

local files = {}
local cache = {}
function cache:write(rel, bytes) files[rel] = bytes; return true end
function cache:read(rel) return files[rel] end
function cache:exists(rel) return files[rel] ~= nil end

local ROOT = "data/generated/gba"
local function loadLua(rel)
  local src = assert(files[ROOT .. "/" .. rel], "missing " .. rel)
  return assert(load(src, "@" .. rel, "t", {}))()
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
require("src.import.gba.versions").select("emerald")

local enum = {}
do
  local h = io.open(PRET .. "/include/constants/region_map_sections.h", "r")
  if h then
    local n = 0
    for line in h:lines() do
      local name = line:match("^%s*(MAPSEC_[%w_]+),")
      if name then
        enum[name] = n
        n = n + 1
      end
    end
    h:close()
  end
end

local RM = require("src.import.gba.rse.region_map_extract")
local okRm, man = RM.run(rom, cache, { cacheRoot = ROOT, game = "emerald" })
check(okRm and type(man) == "table", "region map extractor runs")
for _, rel in ipairs(RM.REQUIRED) do
  check(files[ROOT .. "/" .. rel] ~= nil, "region map writes " .. rel)
end
man = loadLua("rse/region_map/manifest.lua")
eq(#man.layout, 15, "sRegionMap_MapSectionLayout has 15 rows")
eq(#man.layout[1], 28, "sRegionMap_MapSectionLayout has 28 columns")
eq(man.layout[13 - 2 + 1][5 - 1 + 1], 0, "cursor (5,13) is MAPSEC_LITTLEROOT_TOWN")
eq(man.layout[11 - 2 + 1][2 - 1 + 1], 7, "cursor (2,11) is MAPSEC_PETALBURG_CITY")
if next(enum) then
  for key, value in pairs(man.mapsecs) do
    eq(value, enum["MAPSEC_" .. key], "derived mapsec " .. key .. " matches region_map_sections.h")
  end
else
  print("emerald_region_map_test: pret region_map_sections.h not found, mapsec cross-check skipped")
end
eq(#man.heal, 50, "sMapHealLocations covers Littleroot..Route 134")
eq(man.heal[8].healLocation, 3, "Petalburg flies to HEAL_LOCATION_PETALBURG_CITY")
eq(man.heal[17].healLocation, 0, "Route 101 uses a map warp")
eq(man.multiNameFlyDestinations[1].mapSecId, 15, "Ever Grande is the multi-name destination")
eq(man.multiNameFlyDestinations[1].names[1], "POKéMON LEAGUE", "Ever Grande subtitle 0")
eq(man.multiNameFlyDestinations[1].names[2], "POKéMON CENTER", "Ever Grande subtitle 1")
eq(man.redOutlineFlyDestinations[1].mapSecId, man.mapsecs.BATTLE_FRONTIER, "red outline is the Battle Frontier")
eq(#man.sprites.flyIcons.rects, 7, "fly icon atlas has the 7 animation frames")
eq(man.sprites.cursor.frames, 2, "small cursor has 2 frames")
eq(#man.offMap, 3, "three event islands are off the map")

local MS = require("src.import.gba.rse.map_sections_extract")
MS.run(rom, cache, { cacheRoot = ROOT })
package.loaded["src.core.game3.dataset"] = { cache = function() return cache end }
_G.love = {
  filesystem = {
    getInfo = function(p) return files[p] and { type = "file" } or nil end,
    load = function(p) return load(files[p], "@" .. p) end,
    read = function(p) return files[p] end,
  },
}

local RegionMap = require("src.ui.game3.rse.region_map")
eq(RegionMap.mapSecAt(5, 13), 0, "runtime GetMapSecIdAt(5,13) = Littleroot")
eq(RegionMap.mapSecAt(0, 0), man.mapsecs.NONE, "outside the grid is MAPSEC_NONE")
local flags = {}
local s = { session = { flags = flags } }
local C = require("src.core.game3.constants").of("emerald")
eq(RegionMap.mapSecType(s, 7), RegionMap.TYPE.CITY_CANTFLY, "unvisited Petalburg can't be flown to")
flags[C:flag("FLAG_VISITED_PETALBURG_CITY")] = true
eq(RegionMap.mapSecType(s, 7), RegionMap.TYPE.CITY_CANFLY, "visited Petalburg is a fly destination")
eq(RegionMap.mapSecType(s, man.mapsecs.BATTLE_FRONTIER), RegionMap.TYPE.NONE, "Battle Frontier hidden before its landmark flag")
flags[C:flag("FLAG_LANDMARK_BATTLE_FRONTIER")] = true
eq(RegionMap.mapSecType(s, man.mapsecs.BATTLE_FRONTIER), RegionMap.TYPE.BATTLE_FRONTIER, "Battle Frontier after the landmark flag")
eq(RegionMap.mapSecType(s, 16), RegionMap.TYPE.ROUTE, "Route 101 is a route")
eq(RegionMap.correctSpecialMapSecId(s, enum.MAPSEC_PETALBURG_WOODS or 59), enum.MAPSEC_ROUTE_104 or 19, "Petalburg Woods shows as Route 104")
eq(RegionMap.mapName(0), "LITTLEROOT TOWN", "GetMapName(MAPSEC_LITTLEROOT_TOWN)")
eq(RegionMap.mapName(man.mapsecs.NONE), "", "GetMapName(MAPSEC_NONE) is blank")

local st = { session = { flags = flags }, mapDef = { mapType = 1, regionMapSectionId = 15, width = 40, height = 60 } }
local Player = { cellX = 27, cellY = 49 }
package.loaded["src.core.game3.player"] = Player
RegionMap.initFromPlayer(st)
local egs = require("src.ui.game3.rse.mapsec").entry(15)
check(st.cursorX >= egs.x + 1 and st.cursorY >= egs.y + 2, "Ever Grande places the cursor on its square")

local popup = require("src.ui.game3.map_name_popup")
eq(#popup.Rse.FRAME_TILES, 30, "DrawMapNamePopUpFrame lays out 30 outline tiles")
local pack = MS.load(files[ROOT .. "/" .. MS.SECTIONS_REL])
eq(MS.themeOf(pack, 7), "brick", "Petalburg popup theme is brick")
eq(MS.themeOf(pack, 20), "underwater", "Route 105 popup theme is underwater")
eq(MS.themeOf(pack, enum.MAPSEC_UNDERWATER_124 or 50), "stone2", "Underwater 124 popup theme is stone2")
eq(MS.themeOf(pack, enum.MAPSEC_PALLET_TOWN or 88), "wood", "Kanto sections fall back to theme 0")

T.finish()
