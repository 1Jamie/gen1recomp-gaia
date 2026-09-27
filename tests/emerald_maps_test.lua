package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local PRET = os.getenv("POKEPORT_POKEEMERALD") or "../pokeemerald"
local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or (PRET .. "/pokeemerald.gba")
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_maps_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()

local rom = { md5 = "f3ae088181bf583e55daf962a92bb46f4f1d07b7" }
function rom:get(o) return data:byte(o + 1) end
function rom:u16(o) local a, b = data:byte(o + 1, o + 2); return a + b * 256 end
function rom:u32(o)
  local a, b, c, d = data:byte(o + 1, o + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
function rom:readString(o, n) return data:sub(o + 1, o + n) end
function rom:readBytes(o, n)
  local t = {}
  for i = 1, n do t[i] = data:byte(o + i) end
  return t
end
function rom:ptrOffset(p)
  if not p or p < 0x08000000 or p >= 0x0A000000 then return nil end
  return p - 0x08000000
end

local function readFile(path)
  local h = io.open(path, "rb")
  if not h then return nil end
  local s = h:read("*a")
  h:close()
  return s
end

local GameVersion = require("src.core.GameVersion")
local before = GameVersion.get()
GameVersion.set("emerald")
local Versions = require("src.import.gba.versions")
Versions.select("emerald")

local Family = require("src.import.gba.family")
local MapTree = require("src.import.gba.map_tree")
local MapTreeExtract = require("src.import.gba.map_tree_extract")
local MapCatalog = require("src.import.gba.map_catalog")
local Tileset = require("src.import.gba.tileset")
local Metatile = require("src.import.gba.metatile")
local Lz77 = require("src.import.gba.lz77")

local F = Family.active()
eq(F.name, "rse", "emerald session uses the rse family")

local census = assert(MapTree.walk(rom, Versions.lookup(rom.md5)))
eq(census.map_count, 518, "census has every Emerald map")
eq(#census.groups, 34, "34 map groups")
eq(census.tileset_count, 73, "73 tileset structs referenced by layouts")

local dirs, kinds, objs, clones = {}, {}, 0, 0
local hiddenFlagsOk, berry = true, 0
for _, m in ipairs(census.maps) do
  for _, c in ipairs(m.connections) do dirs[c.dir] = (dirs[c.dir] or 0) + 1 end
  for _, b in ipairs(m.events and m.events.bgEvents or {}) do
    kinds[b.kind] = (kinds[b.kind] or 0) + 1
    if b.type == "hidden_item" and (b.flag < 0x1F4 or b.quantity ~= nil) then hiddenFlagsOk = false end
  end
  for _, o in ipairs(m.events and m.events.objects or {}) do
    objs = objs + 1
    if o.cloneTarget then clones = clones + 1 end
    if o.berryTreeId then berry = berry + 1 end
  end
end
eq(dirs.dive, 7, "7 dive connections")
eq(dirs.emerge, 7, "7 emerge connections")
eq(dirs.north, 27, "27 north connections")
eq(dirs.east, 40, "40 east connections")
eq(kinds[7], 112, "112 hidden items")
eq(kinds[8], 75, "75 secret base bg events")
check(hiddenFlagsOk, "hidden item flags start at 0x1F4 with no quantity")
eq(objs, 2941, "2941 object events")
eq(clones, 0, "no clone objects")
check(berry > 0, "berry trees carry berryTreeId")

local petal = census.maps[1]
eq(petal.pretName, "PetalburgCity", "0:0 is Petalburg")
eq(petal.layout.width, 30, "Petalburg 30 wide")
eq(petal.layout.borderWidth, 2, "border is always 2x2")

local byName = {}
for _, ts in pairs(census.tilesets) do
  local name = F:tilesetName(ts.structOff)
  check(name ~= nil, "tileset struct " .. ts.id .. " has a pret name")
  if name then byName[name] = ts end
end
eq(byName.general.mid_count, 512, "General has 512 metatiles")
eq(byName.general.attr_bytes, 1024, "General attributes are u16")
check(byName.general.compressed, "General tiles are compressed")
check(not byName.secret_base_brown_cave.compressed, "SecretBaseBrownCave tiles are raw")

local compared = 0
for name, ts in pairs(byName) do
  local dir = PRET .. "/data/tilesets/" .. (ts.secondary and "secondary/" or "primary/") .. name
  local mt = readFile(dir .. "/metatiles.bin")
  local at = readFile(dir .. "/metatile_attributes.bin")
  if mt and at then
    compared = compared + 1
    eq(rom:readString(rom:ptrOffset(ts.metatilesPtr), ts.metatile_bytes), mt, name .. " metatiles.bin byte exact")
    eq(rom:readString(rom:ptrOffset(ts.attributesPtr), ts.attr_bytes), at, name .. " metatile_attributes.bin byte exact")
  end
end
check(compared >= 60, "compared metatile blobs against pret for " .. compared .. " tilesets")

local function pngSize(path)
  local s = readFile(path)
  if not s then return nil end
  local function be32(o) local a, b, c, d = s:byte(o, o + 3); return ((a * 256 + b) * 256 + c) * 256 + d end
  return be32(17), be32(21)
end

local tileChecks = 0
for name, ts in pairs(byName) do
  local w, h = pngSize(PRET .. "/data/tilesets/" .. (ts.secondary and "secondary/" or "primary/") .. name .. "/tiles.png")
  if w then
    local tilesOff = rom:ptrOffset(ts.tilesPtr)
    local n
    if ts.compressed then
      n = #Lz77.decompressString(rom, tilesOff)
    else
      n = F:uncompressedTileBytes(rom, tilesOff, rom:ptrOffset(ts.palettesPtr), ts.secondary)
    end
    local sheet = w * h / 2
    check(n <= sheet and n > sheet - (w / 8) * 32, name .. " tile bytes fill pret tiles.png up to its last row (" .. n .. "/" .. sheet .. ")")
    tileChecks = tileChecks + 1
  end
end
check(tileChecks >= 60, "tile sheet sizes checked for " .. tileChecks .. " tilesets")

MapCatalog.rebuildIndex()
local order, byEngine = MapCatalog.allOrder(census)
eq(#order, 518, "catalog orders every map")
eq(order[1], "EM_PETALBURG_CITY", "catalog engine id for 0:0")
local registered = MapCatalog.registerOrder(rom, Versions.lookup(rom.md5), order, byEngine)
check(#registered >= 517, "registered " .. #registered .. " maps with a tileset pair")
eq(Versions.MAPS.EM_LITTLEROOT_TOWN.pair, "general__petalburg", "Littleroot uses General + Petalburg")
check((Versions.TILESETS.secret_base_brown_cave.tiles_bytes or 0) > 0, "uncompressed tileset has tile bytes")

do
  local bundle = assert(Tileset.loadPair(rom, Versions.lookup(rom.md5), "general__petalburg"))
  eq(bundle.primaryTiles.count, 512, "General tiles decode to 512")
  eq(bundle.primaryAttr.count, 512, "General attrs count 512")
  -- pokeemerald/include/constants/metatile_labels.h:240
  local beh = Tileset.behaviorOf(bundle, 0x00D)
  eq(beh, 0x02, "General TallGrass is MB_TALL_GRASS")
  local idx = Metatile.compositeIndexedBottom(bundle, 0x00D)
  local nonzero = 0
  for i = 1, 256 do if idx[i] ~= 0 then nonzero = nonzero + 1 end end
  check(nonzero > 0, "tall grass composites to pixels")
end

local files = {}
local cache = {
  write = function(_, rel, bytes) files[rel] = bytes end,
  exists = function(_, rel) return files[rel] ~= nil end,
}
local out = MapTreeExtract.run(rom, cache, { cacheRoot = "gba", strict = true })
eq(out, true, "strict map tree extract runs")
check(files["gba/map_tree/census.json"] ~= nil, "census.json written")
check(MapTreeExtract.ready(cache, "gba"), "ready after run")
local lr = files["gba/map_tree/maps/0_9/header.json"]
check(lr and lr:find('"allowCycling":1', 1, true) ~= nil, "Littleroot header has allowCycling")
check(lr and not lr:find('"floorNum"', 1, true), "RSE header has no floorNum")
local r124 = files["gba/map_tree/maps/0_39/header.json"]
check(r124 and r124:find('"dive"', 1, true) ~= nil, "Route 124 header lists its dive connection")

GameVersion.set(before)
T.finish("emerald_maps_test")
