package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local PRET = os.getenv("POKEPORT_POKEEMERALD") or "../pokeemerald"
local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or (PRET .. "/pokeemerald.gba")
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_pokedex_test: skipped (no ROM at " .. ROM_PATH .. ")")
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
function rom:ptrOffset(p)
  if not p or p < 0x08000000 or p >= 0x0A000000 then return nil end
  return p - 0x08000000
end

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

require("src.core.GameVersion").set("emerald")
require("src.import.gba.versions").select("emerald")
local C = require("src.core.game3.constants").of("emerald")
local S = require("src.import.gba.syms").of("emerald")

local Dex = require("src.import.gba.rse.pokedex_chrome_extract")
local ok, man = Dex.run(rom, cache, { cacheRoot = ROOT, game = "emerald" })
check(ok and type(man) == "table", "pokedex chrome extractor runs")
for _, rel in ipairs(Dex.REQUIRED) do
  check(files[ROOT .. "/" .. rel] ~= nil, "pokedex extractor writes " .. rel)
end
man = loadLua("rse/pokedex/manifest.lua")
local orders = loadLua("rse/pokedex/orders.lua")
eq(#orders.numerical_hoenn, 202, "HOENN_DEX_COUNT entries in regional order")
eq(orders.numerical_hoenn[1], 252, "Hoenn #001 is TREECKO (national 252)")
eq(orders.numerical_hoenn[12], 263, "Hoenn #012 is ZIGZAGOON (national 263)")
eq(orders.type, nil, "Emerald has no type order table")
eq(orders.numerical_kanto, nil, "Emerald writes no Kanto order")
eq(#orders.atoz, 386, "gPokedexOrder_Alphabetical minus the 25 old Unown slots")
eq(orders.atoz[1], 63, "A TO Z starts with ABRA")
eq(#man.search.orders, 6, "six listing modes")
eq(man.search.orders[1].title, "NUMERICAL MODE", "sDexOrderOptions[0] title")
eq(#man.search.types, 18, "type list: NONE + 17 types")
eq(#man.search.colors, 11, "color list: DON'T SPECIFY + 10 body colors")
eq(#man.search.names, 10, "name list: DON'T SPECIFY + 9 letter groups")
eq(man.search.letterRanges[1][2], 3, "NAME_ABC covers 3 letters")
eq(man.search.typeIds[1], 255, "sDexSearchTypeIds[0] is TYPE_NONE")
eq(man.bodyColor[C.species.byName.SPECIES_TREECKO], 3, "TREECKO body color GREEN")
eq(man.sine[64], 256, "gSineTable[64]")
eq(#man.area.glowMapping, 256, "sAreaGlowTilemapMapping has 256 entries")
eq(man.area.feebas[1][1], C.species.byName.SPECIES_FEEBAS, "sFeebasData lists FEEBAS")
eq(#man.palettes.hoenn, 96, "gPokedexBgHoenn_Pal is 6 palettes")

local EncountersExtract = require("src.import.gba.encounters_extract")
EncountersExtract.run(rom, cache, { cacheRoot = ROOT })
local encounters = loadLua("encounters.lua")

local groups = S.off("gMapGroups")
local function mapsecOf(g, n)
  local gp = rom:ptrOffset(rom:u32(groups + g * 4))
  local hp = gp and rom:ptrOffset(rom:u32(gp + n * 4))
  return hp and rom:get(hp + 0x14) or 213
end

local RM = require("src.import.gba.rse.region_map_extract")
RM.run(rom, cache, { cacheRoot = ROOT, game = "emerald" })
require("src.import.gba.rse.map_sections_extract").run(rom, cache, { cacheRoot = ROOT })
package.loaded["src.core.game3.dataset"] = { cache = function() return cache end }
_G.love = {
  filesystem = {
    getInfo = function(p) return files[p] and { type = "file" } or nil end,
    load = function(p) return load(files[p], "@" .. p) end,
    read = function(p) return files[p] end,
  },
}
local RegionMap = require("src.ui.game3.rse.region_map")
local Area = require("src.ui.game3.rse.pokedex_area")

local flagsSet = {}
local function ctx(extra)
  local c = {
    encounters = encounters,
    groups = {
      towns = C:map("MAP_PETALBURG_CITY").group,
      dungeons = C:map("MAP_METEOR_FALLS_1F_1R").group,
      special = C:map("MAP_SAFARI_ZONE_NORTHWEST").group,
    },
    mapsecOf = mapsecOf,
    correct = function(sec) return RegionMap.correctSpecialMapSecId({ session = {} }, sec) end,
    alteringCaveMapSec = mapsecOf(C:map("MAP_ALTERING_CAVE").group, C:map("MAP_ALTERING_CAVE").num),
    alteringCaveId = 0,
    flag = function(id) return flagsSet[id] == true end,
    feebas = man.area.feebas,
    landmarks = man.area.landmarks,
    hiddenSpecies = man.area.hiddenSpecies,
    movingMapSecs = man.area.movingMapSecs,
    NONE = 213,
  }
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

local sp = C.species.byName
local zig = Area.findMapsWithMon(sp.SPECIES_ZIGZAGOON, ctx())
local secs = {}
for _, o in ipairs(zig.overworld) do secs[o.sec] = true end
check(secs[16] and secs[17] and secs[18], "ZIGZAGOON glows on Routes 101-103")
eq(#zig.special, 0, "ZIGZAGOON has no cave markers")
local feebas = Area.findMapsWithMon(sp.SPECIES_FEEBAS, ctx())
local f119 = false
for _, o in ipairs(feebas.overworld) do if o.sec == 34 then f119 = true end end
check(f119, "FEEBAS glows on Route 119 (sFeebasData)")
local wynaut = Area.findMapsWithMon(sp.SPECIES_WYNAUT, ctx())
eq(#wynaut.overworld + #wynaut.special, 0, "WYNAUT is hidden from the area screen")
local zubat = Area.findMapsWithMon(sp.SPECIES_ZUBAT, ctx())
check(#zubat.special > 0, "ZUBAT gets cave markers (" .. #zubat.special .. ")")
local roamer = Area.findMapsWithMon(sp.SPECIES_LATIAS, ctx({ roamer = { species = sp.SPECIES_LATIAS, active = true,
  group = C:map("MAP_ROUTE120").group, num = C:map("MAP_ROUTE120").num } }))
eq(#roamer.overworld, 1, "roamer species shows its current map only")
eq(roamer.overworld[1].sec, 35, "roamer on Route 120")

local glow = Area.buildGlowTilemap(zig.overworld, RegionMap.mapSecAt, man.area.glowMapping)
eq(glow[(13 - 1) * 32 + 5] % 4096, Area.GLOW_TILE_FULL, "Route 101 square is a full glow tile")
eq(math.floor(glow[(13 - 1) * 32 + 5] / 4096), Area.GLOW_PALETTE, "glow uses palette 10")
check(glow[(13 - 1) * 32 + 4] ~= 0, "the square left of Route 101 gets an edge tile")
local g = Area.newGlow(#zig.overworld, 0)
for _ = 1, 16 do Area.stepGlow(g, function(i) return man.sine[i % 256] end) end
check(g.eva > 0 and g.evb < 16, "area glow blends in (" .. g.eva .. "," .. g.evb .. ")")

local List = require("src.ui.game3.rse.pokedex_list")
local seen, owned = {}, {}
for _, n in ipairs({ 252, 253, 263, 265 }) do seen[n], owned[n] = true, true end
seen[261] = true
local lctx = {
  orders = orders, nationalEnabled = false, nationalCount = 386,
  seen = function(n) return seen[n] == true end,
  owned = function(n) return owned[n] == true end,
  hoennNumber = function(n)
    for i, v in ipairs(orders.numerical_hoenn) do if v == n then return i end end
    return 203
  end,
  firstChar = function(n) return (n == 252 or n == 253) and 0xCE or 0xD4 end,
  bodyColor = function(n) return (n == 252 or n == 253) and 3 or 5 end,
  types = function(n) return (n == 252 or n == 253) and { 12, 12 } or { 0, 0 } end,
  TYPE_NONE = 0xFF,
}
local list = List.create(lctx, List.DEX_MODE_HOENN, List.ORDER_NUMERICAL)
eq(list.count, 14, "Hoenn numerical list ends at the last seen mon (WURMPLE #014)")
eq(list.items[2].seen, false, "SCEPTILE unseen in the middle of the list")
local alpha = List.create(lctx, List.DEX_MODE_HOENN, List.ORDER_ALPHABETICAL)
eq(alpha.count, 5, "A TO Z lists seen mons only")
local heavy = List.create(lctx, List.DEX_MODE_HOENN, List.ORDER_HEAVIEST)
eq(heavy.count, 4, "HEAVIEST lists owned mons only")
local green = List.search(lctx, List.DEX_MODE_HOENN, List.ORDER_NUMERICAL, 0xFF, 3, 0xFF, 0xFF, man.search.letterRanges)
eq(green.count, 2, "color GREEN search finds TREECKO and GROVYLE")
local grass = List.search(lctx, List.DEX_MODE_HOENN, List.ORDER_NUMERICAL, 0xFF, 0xFF, 12, 0xFF, man.search.letterRanges)
eq(grass.count, 2, "type GRASS search finds owned grass mons")

local Pokedex = require("src.ui.game3.rse.pokedex")
eq(Pokedex.heightText(5):sub(4), "1'08\"", "TREECKO height 1'08\"")
eq(Pokedex.heightText(5):byte(3), 18, "height uses CLEAR_TO 18 for single-digit feet")
eq(Pokedex.weightText(50), "{UNK_SPACER}{UNK_SPACER}11.0 lbs.", "TREECKO weight 11.0 lbs. behind two CHAR_SPACERs")
eq(Pokedex.weightText(3520), "{UNK_SPACER}776.0 lbs.", "a 3-digit weight keeps one CHAR_SPACER")

local Cry = require("src.ui.game3.rse.pokedex_cry")
local tile = {}
for i = 0, 63 do tile[i] = 1 end
local c = Cry.new(tile)
check(c.pixels[28 * 256 + 10] ~= 1, "flatline at y 28 (pokeemerald/src/pokedex_cry_screen.c:390)")
eq(c.needle.rotation, Cry.MIN_NEEDLE_POS, "needle rests at MIN_NEEDLE_POS")

T.finish()
