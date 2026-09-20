-- Bake Kanto Region Map background, cursor and marker sprites from the ROM.
-- Outputs to data/generated/gba/region_map/:
--   kanto_map.png (240x160)
--   cursor.png (16x16), dungeon_icon.png (8x8)
--   player_red.png (16x16), player_leaf.png (16x16)

local RegionMapExtract = {}

RegionMapExtract.CACHE_SUB = "region_map"
RegionMapExtract.FORMAT_VERSION = 2

RegionMapExtract.FILES = {
  "kanto_map.png",
  "cursor.png",
  "dungeon_icon.png",
  "player_red.png",
  "player_leaf.png",
}

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function bgr555_to_rgb8(c)
  c = (tonumber(c) or 0) % 32768
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return math.floor(r5 * 255 / 31 + 0.5),
    math.floor(g5 * 255 / 31 + 0.5),
    math.floor(b5 * 255 / 31 + 0.5)
end

-- Kanto 22x15 layout from pokefirered/src/data/region_map/region_map_layout_kanto.h
RegionMapExtract.MAP_WIDTH = 22
RegionMapExtract.MAP_HEIGHT = 15

-- Fallback-only text.  The authoritative section names and area descriptions
-- are read from the ROM by src/import/gba/map_preview_extract.lua; these tables
-- keep the module usable when no ROM was imported (ROM-free CI, unit tests).
-- See RegionMapExtract.ensureGenerated.
RegionMapExtract.FALLBACK_SECTION_NAMES = {
  MAPSEC_PALLET_TOWN = "PALLET TOWN",
  MAPSEC_VIRIDIAN_CITY = "VIRIDIAN CITY",
  MAPSEC_PEWTER_CITY = "PEWTER CITY",
  MAPSEC_CERULEAN_CITY = "CERULEAN CITY",
  MAPSEC_LAVENDER_TOWN = "LAVENDER TOWN",
  MAPSEC_VERMILION_CITY = "VERMILION CITY",
  MAPSEC_CELADON_CITY = "CELADON CITY",
  MAPSEC_FUCHSIA_CITY = "FUCHSIA CITY",
  MAPSEC_CINNABAR_ISLAND = "CINNABAR ISLAND",
  MAPSEC_INDIGO_PLATEAU = "INDIGO PLATEAU",
  MAPSEC_SAFFRON_CITY = "SAFFRON CITY",
  MAPSEC_ROUTE_4_POKECENTER = "ROUTE 4",
  MAPSEC_ROUTE_10_POKECENTER = "ROUTE 10",
  MAPSEC_ROUTE_1 = "ROUTE 1",
  MAPSEC_ROUTE_2 = "ROUTE 2",
  MAPSEC_ROUTE_3 = "ROUTE 3",
  MAPSEC_ROUTE_4 = "ROUTE 4",
  MAPSEC_ROUTE_5 = "ROUTE 5",
  MAPSEC_ROUTE_6 = "ROUTE 6",
  MAPSEC_ROUTE_7 = "ROUTE 7",
  MAPSEC_ROUTE_8 = "ROUTE 8",
  MAPSEC_ROUTE_9 = "ROUTE 9",
  MAPSEC_ROUTE_10 = "ROUTE 10",
  MAPSEC_ROUTE_11 = "ROUTE 11",
  MAPSEC_ROUTE_12 = "ROUTE 12",
  MAPSEC_ROUTE_13 = "ROUTE 13",
  MAPSEC_ROUTE_14 = "ROUTE 14",
  MAPSEC_ROUTE_15 = "ROUTE 15",
  MAPSEC_ROUTE_16 = "ROUTE 16",
  MAPSEC_ROUTE_17 = "ROUTE 17",
  MAPSEC_ROUTE_18 = "ROUTE 18",
  MAPSEC_ROUTE_19 = "ROUTE 19",
  MAPSEC_ROUTE_20 = "ROUTE 20",
  MAPSEC_ROUTE_21 = "ROUTE 21",
  MAPSEC_ROUTE_22 = "ROUTE 22",
  MAPSEC_ROUTE_23 = "ROUTE 23",
  MAPSEC_ROUTE_24 = "ROUTE 24",
  MAPSEC_ROUTE_25 = "ROUTE 25",
  MAPSEC_VIRIDIAN_FOREST = "VIRIDIAN FOREST",
  MAPSEC_MT_MOON = "MT. MOON",
  MAPSEC_S_S_ANNE = "S.S. ANNE",
  MAPSEC_UNDERGROUND_PATH = "UNDERGROUND PATH",
  MAPSEC_UNDERGROUND_PATH_2 = "UNDERGROUND PATH",
  MAPSEC_DIGLETTS_CAVE = "DIGLETT'S CAVE",
  MAPSEC_KANTO_VICTORY_ROAD = "VICTORY ROAD",
  MAPSEC_ROCKET_HIDEOUT = "ROCKET HIDEOUT",
  MAPSEC_SILPH_CO = "SILPH CO.",
  MAPSEC_POKEMON_MANSION = "POKéMON MANSION",
  MAPSEC_KANTO_SAFARI_ZONE = "SAFARI ZONE",
  MAPSEC_POKEMON_TOWER = "POKéMON TOWER",
  MAPSEC_CERULEAN_CAVE = "CERULEAN CAVE",
  MAPSEC_POWER_PLANT = "POWER PLANT",
  MAPSEC_SEAFOAM_ISLANDS = "SEAFOAM ISLANDS",
  MAPSEC_ROCK_TUNNEL = "ROCK TUNNEL",
}

-- [y][x] 0-indexed layout (15 rows, 22 cols)
RegionMapExtract.KANTO_GRID = {
  [0] = { [0]=nil },
  [1] = { [14]="MAPSEC_ROUTE_24", [15]="MAPSEC_ROUTE_25", [16]="MAPSEC_ROUTE_25" },
  [2] = { [14]="MAPSEC_ROUTE_24" },
  [3] = { [2]="MAPSEC_INDIGO_PLATEAU", [8]="MAPSEC_ROUTE_4_POKECENTER", [9]="MAPSEC_ROUTE_4", [10]="MAPSEC_ROUTE_4", [11]="MAPSEC_ROUTE_4", [12]="MAPSEC_ROUTE_4", [13]="MAPSEC_ROUTE_4", [14]="MAPSEC_CERULEAN_CITY", [15]="MAPSEC_ROUTE_9", [16]="MAPSEC_ROUTE_9", [17]="MAPSEC_ROUTE_9", [18]="MAPSEC_ROUTE_10_POKECENTER" },
  [4] = { [2]="MAPSEC_ROUTE_23", [4]="MAPSEC_PEWTER_CITY", [5]="MAPSEC_ROUTE_3", [6]="MAPSEC_ROUTE_3", [7]="MAPSEC_ROUTE_3", [8]="MAPSEC_ROUTE_3", [14]="MAPSEC_ROUTE_5", [18]="MAPSEC_ROUTE_10" },
  [5] = { [2]="MAPSEC_ROUTE_23", [4]="MAPSEC_ROUTE_2", [14]="MAPSEC_ROUTE_5", [18]="MAPSEC_ROUTE_10" },
  [6] = { [2]="MAPSEC_ROUTE_23", [4]="MAPSEC_ROUTE_2", [7]="MAPSEC_ROUTE_16", [8]="MAPSEC_ROUTE_16", [9]="MAPSEC_ROUTE_16", [10]="MAPSEC_ROUTE_16", [11]="MAPSEC_CELADON_CITY", [12]="MAPSEC_ROUTE_7", [13]="MAPSEC_ROUTE_7", [14]="MAPSEC_SAFFRON_CITY", [15]="MAPSEC_ROUTE_8", [16]="MAPSEC_ROUTE_8", [17]="MAPSEC_ROUTE_8", [18]="MAPSEC_LAVENDER_TOWN" },
  [7] = { [2]="MAPSEC_ROUTE_23", [4]="MAPSEC_ROUTE_2", [7]="MAPSEC_ROUTE_17", [14]="MAPSEC_ROUTE_6", [18]="MAPSEC_ROUTE_12" },
  [8] = { [2]="MAPSEC_ROUTE_22", [3]="MAPSEC_ROUTE_22", [4]="MAPSEC_VIRIDIAN_CITY", [7]="MAPSEC_ROUTE_17", [14]="MAPSEC_ROUTE_6", [18]="MAPSEC_ROUTE_12" },
  [9] = { [4]="MAPSEC_ROUTE_1", [7]="MAPSEC_ROUTE_17", [14]="MAPSEC_VERMILION_CITY", [15]="MAPSEC_ROUTE_11", [16]="MAPSEC_ROUTE_11", [17]="MAPSEC_ROUTE_11", [18]="MAPSEC_ROUTE_12" },
  [10] = { [4]="MAPSEC_ROUTE_1", [7]="MAPSEC_ROUTE_17", [18]="MAPSEC_ROUTE_12" },
  [11] = { [4]="MAPSEC_PALLET_TOWN", [7]="MAPSEC_ROUTE_17", [15]="MAPSEC_ROUTE_14", [16]="MAPSEC_ROUTE_13", [17]="MAPSEC_ROUTE_13", [18]="MAPSEC_ROUTE_12" },
  [12] = { [4]="MAPSEC_ROUTE_21", [7]="MAPSEC_ROUTE_18", [8]="MAPSEC_ROUTE_18", [9]="MAPSEC_ROUTE_18", [10]="MAPSEC_ROUTE_18", [11]="MAPSEC_ROUTE_18", [12]="MAPSEC_FUCHSIA_CITY", [13]="MAPSEC_ROUTE_15", [14]="MAPSEC_ROUTE_15", [15]="MAPSEC_ROUTE_14" },
  [13] = { [4]="MAPSEC_ROUTE_21", [12]="MAPSEC_ROUTE_19" },
  [14] = { [4]="MAPSEC_CINNABAR_ISLAND", [5]="MAPSEC_ROUTE_20", [6]="MAPSEC_ROUTE_20", [7]="MAPSEC_ROUTE_20", [8]="MAPSEC_ROUTE_20", [9]="MAPSEC_ROUTE_20", [10]="MAPSEC_ROUTE_20", [11]="MAPSEC_ROUTE_20", [12]="MAPSEC_ROUTE_19" },
}

-- Dungeon layer [y][x] 0-indexed layout from pokefirered LAYER_DUNGEON
RegionMapExtract.DUNGEON_GRID = {
  [3] = { [9] = "MAPSEC_MT_MOON", [14] = "MAPSEC_CERULEAN_CAVE", [18] = "MAPSEC_ROCK_TUNNEL" },
  [4] = { [2] = "MAPSEC_KANTO_VICTORY_ROAD", [18] = "MAPSEC_POWER_PLANT" },
  [5] = { [4] = "MAPSEC_DIGLETTS_CAVE" },
  [6] = { [4] = "MAPSEC_VIRIDIAN_FOREST", [18] = "MAPSEC_POKEMON_TOWER" },
  [9] = { [15] = "MAPSEC_DIGLETTS_CAVE" },
  [12] = { [12] = "MAPSEC_KANTO_SAFARI_ZONE" },
  [14] = { [4] = "MAPSEC_POKEMON_MANSION", [8] = "MAPSEC_SEAFOAM_ISLANDS" },
}

-- Authentic FRLG Area Descriptions (pokefirered/src/strings.c gText_RegionMap_AreaDesc_*)
RegionMapExtract.FALLBACK_DUNGEON_DESCRIPTIONS = {
  MAPSEC_VIRIDIAN_FOREST = "A deep and sprawling forest that extends around VIRIDIAN CITY. A natural maze, many people become lost inside.",
  MAPSEC_MT_MOON = "A mystical mountain that is known for its frequent meteor falls. The shards of stars that fall here are known as MOON STONES.",
  MAPSEC_DIGLETTS_CAVE = "A seemingly plain tunnel that was dug by wild DIGLETT. It is famous for connecting ROUTES 2 and 11.",
  MAPSEC_KANTO_VICTORY_ROAD = "A tunnel situated on ROUTE 23. It earned its name because it must be traveled by all TRAINERS aiming for the top.",
  MAPSEC_POKEMON_MANSION = "A decrepit, burned-down mansion on CINNABAR ISLAND. It got its name because a famous POKéMON researcher lived there.",
  MAPSEC_KANTO_SAFARI_ZONE = "An amusement park outside FUCHSIA CITY where many rare POKéMON can be observed in the wild. Catch them in a popular game!",
  MAPSEC_ROCK_TUNNEL = "A naturally formed underground tunnel. Because it has not been developed, it is inky dark inside. A light is needed to get through.",
  MAPSEC_SEAFOAM_ISLANDS = "A pair of islands that is situated on ROUTE 20. The two islands are shaped the same, as if they were twins.",
  MAPSEC_POKEMON_TOWER = "A tower that houses the graves of countless POKéMON. Many people visit it daily to pay their respects to the fallen.",
  MAPSEC_CERULEAN_CAVE = "A mysterious cave that is filled with terribly tough POKéMON. It is so dangerous, the POKéMON LEAGUE is in charge of it.",
  MAPSEC_POWER_PLANT = "A power plant that was abandoned years ago, though some of the machines still work. It is infested with electric POKéMON.",
}

-- Effective tables the UI reads.  Seeded from the fallbacks and overlaid with
-- ROM-derived text by ensureGenerated.
local function copyTable(src)
  local out = {}
  for k, v in pairs(src) do out[k] = v end
  return out
end

RegionMapExtract.SECTION_NAMES = copyTable(RegionMapExtract.FALLBACK_SECTION_NAMES)
RegionMapExtract.DUNGEON_DESCRIPTIONS = copyTable(RegionMapExtract.FALLBACK_DUNGEON_DESCRIPTIONS)

local generatedLoaded = false
local generatedOk = false

--- Overlay ROM-derived names/descriptions onto the effective tables.
-- `names` is keyed by numeric mapsec (88..196) and `dungeonInfo` by the same,
-- so both are bridged to the symbolic MAPSEC_* keys the UI uses via `sections`
-- (map_sections_extract.SECTIONS).  Returns the number of sections updated.
function RegionMapExtract.applyGeneratedText(names, dungeonInfo, sections)
  if not sections then return 0 end
  local updated = 0
  if names then
    for secId, name in pairs(names) do
      local info = sections[secId]
      if info and info.id and name and name ~= "" then
        RegionMapExtract.SECTION_NAMES[info.id] = name
        updated = updated + 1
      end
    end
  end
  if dungeonInfo then
    for secId, entry in pairs(dungeonInfo) do
      local info = sections[secId]
      if info and info.id and entry then
        if entry.name and entry.name ~= "" then
          RegionMapExtract.SECTION_NAMES[info.id] = entry.name
        end
        if entry.desc and entry.desc ~= "" then
          RegionMapExtract.DUNGEON_DESCRIPTIONS[info.id] = entry.desc
        end
        updated = updated + 1
      end
    end
  end
  return updated
end

--- Load the generated region-map text from the cache and apply it, once.
-- Falls back silently to the hand-authored tables when the cache has no
-- generated text (ROM-free checkouts).  Returns true when ROM text was applied.
function RegionMapExtract.ensureGenerated()
  if generatedLoaded then return generatedOk end
  generatedLoaded = true
  generatedOk = pcall(function()
    local CacheFs = require("src.import.CacheFs")
    local MapPreviewExtract = require("src.import.gba.map_preview_extract")
    local MapSectionsExtract = require("src.import.gba.map_sections_extract")
    local names = MapPreviewExtract.loadNames(CacheFs)
    local dungeonInfo = MapPreviewExtract.loadDungeonInfo(CacheFs)
    if not names and not dungeonInfo then return end
    RegionMapExtract.applyGeneratedText(names, dungeonInfo, MapSectionsExtract.SECTIONS)
  end) and true or false
  return generatedOk
end


RegionMapExtract.HOST_MAP_TO_GRID = {
  PALLET_TOWN = { 4, 11 },
  REDS_HOUSE_1F = { 4, 11 },
  REDS_HOUSE_2F = { 4, 11 },
  BLUES_HOUSE = { 4, 11 },
  OAKS_LAB = { 4, 11 },
  VIRIDIAN_CITY = { 4, 8 },
  PEWTER_CITY = { 4, 4 },
  CERULEAN_CITY = { 14, 3 },
  LAVENDER_TOWN = { 18, 6 },
  VERMILION_CITY = { 14, 9 },
  CELADON_CITY = { 11, 6 },
  FUCHSIA_CITY = { 12, 12 },
  CINNABAR_ISLAND = { 4, 14 },
  INDIGO_PLATEAU = { 2, 3 },
  SAFFRON_CITY = { 14, 6 },
  ROUTE_1 = { 4, 9 },
  ROUTE_2 = { 4, 5 },
  ROUTE_3 = { 6, 4 },
  ROUTE_4 = { 11, 3 },
  ROUTE_5 = { 14, 4 },
  ROUTE_6 = { 14, 7 },
  ROUTE_7 = { 12, 6 },
  ROUTE_8 = { 16, 6 },
  ROUTE_9 = { 16, 3 },
  ROUTE_10 = { 18, 5 },
  ROUTE_11 = { 16, 9 },
  ROUTE_12 = { 18, 8 },
  ROUTE_13 = { 17, 11 },
  ROUTE_14 = { 15, 12 },
  ROUTE_15 = { 13, 12 },
  ROUTE_16 = { 9, 6 },
  ROUTE_17 = { 7, 8 },
  ROUTE_18 = { 9, 12 },
  ROUTE_19 = { 12, 13 },
  ROUTE_20 = { 8, 14 },
  ROUTE_21 = { 4, 13 },
  ROUTE_22 = { 3, 8 },
  ROUTE_23 = { 2, 5 },
  ROUTE_24 = { 14, 2 },
  ROUTE_25 = { 15, 1 },
  VIRIDIAN_FOREST = { 4, 6 },
  MT_MOON = { 9, 3 },
  ROCK_TUNNEL = { 18, 3 },
  POWER_PLANT = { 18, 4 },
  POKEMON_TOWER = { 18, 6 },
  DIGLETTS_CAVE = { 4, 5 },
  KANTO_VICTORY_ROAD = { 2, 4 },
  POKEMON_MANSION = { 4, 14 },
  KANTO_SAFARI_ZONE = { 12, 12 },
  SEAFOAM_ISLANDS = { 8, 14 },
  CERULEAN_CAVE = { 14, 3 },
}

function RegionMapExtract.resolveLocation(mapId, mapSec)
  RegionMapExtract.ensureGenerated()
  if mapSec and RegionMapExtract.SECTION_NAMES[mapSec] then
    local name = RegionMapExtract.SECTION_NAMES[mapSec]
    -- 1. Check DUNGEON_GRID first for dungeon mapsecs
    for y = 0, RegionMapExtract.MAP_HEIGHT - 1 do
      local dRow = RegionMapExtract.DUNGEON_GRID[y]
      if dRow then
        for x = 0, RegionMapExtract.MAP_WIDTH - 1 do
          if dRow[x] == mapSec then
            return { x = x, y = y, name = name, mapsec = mapSec }
          end
        end
      end
    end
    -- 2. Check overworld KANTO_GRID
    for y = 0, RegionMapExtract.MAP_HEIGHT - 1 do
      local row = RegionMapExtract.KANTO_GRID[y]
      if row then
        for x = 0, RegionMapExtract.MAP_WIDTH - 1 do
          if row[x] == mapSec then
            return { x = x, y = y, name = name, mapsec = mapSec }
          end
        end
      end
    end
  end

  if mapId then
    local u = tostring(mapId):upper()
    local g = RegionMapExtract.HOST_MAP_TO_GRID[u]
    if g then
      local dSec = RegionMapExtract.DUNGEON_GRID[g[2]] and RegionMapExtract.DUNGEON_GRID[g[2]][g[1]]
      local oSec = RegionMapExtract.KANTO_GRID[g[2]] and RegionMapExtract.KANTO_GRID[g[2]][g[1]]
      local sec = dSec or oSec
      if RegionMapExtract.SECTION_NAMES["MAPSEC_" .. u] then
        sec = "MAPSEC_" .. u
      end
      local name = sec and RegionMapExtract.SECTION_NAMES[sec] or u:gsub("_", " ")
      return { x = g[1], y = g[2], name = name, mapsec = sec }
    end
    -- Sub-locations / Buildings lookup
    for hostKey, grid in pairs(RegionMapExtract.HOST_MAP_TO_GRID) do
      if u:find(hostKey, 1, true) then
        local dSec = RegionMapExtract.DUNGEON_GRID[grid[2]] and RegionMapExtract.DUNGEON_GRID[grid[2]][grid[1]]
        local oSec = RegionMapExtract.KANTO_GRID[grid[2]] and RegionMapExtract.KANTO_GRID[grid[2]][grid[1]]
        local sec = dSec or oSec
        if RegionMapExtract.SECTION_NAMES["MAPSEC_" .. hostKey] then
          sec = "MAPSEC_" .. hostKey
        end
        local name = sec and RegionMapExtract.SECTION_NAMES[sec] or hostKey:gsub("_", " ")
        return { x = grid[1], y = grid[2], name = name, mapsec = sec }
      end
    end
  end

  return { x = 4, y = 11, name = "PALLET TOWN", mapsec = "MAPSEC_PALLET_TOWN" }
end

local function readBytes(rom, off, len)
  local out = {}
  for i = 1, len do out[i] = rom:get(off + i - 1) or 0 end
  return out
end

-- src/region_map.c:1495-1510
local function bakeBgPixels(BgBake, gfx, banks, map, mapW, W, H)
  local tileCount = math.floor(BgBake.byteLen(gfx) / 32)
  local pixels = {}
  for i = 1, W * H * 4 do pixels[i] = 0 end
  local tile, tmp = {}, {}
  for ty = 0, math.floor(H / 8) - 1 do
    for tx = 0, math.floor(W / 8) - 1 do
      local mi = (ty * mapW + tx) * 2 + 1
      local entry = (map[mi] or 0) + (map[mi + 1] or 0) * 256
      local tileId = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      local bank = banks[math.floor(entry / 4096) % 16] or banks[0] or {}
      if tileId < tileCount then
        local base = tileId * 32
        for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
        for i = 1, 64 do tmp[i] = 0 end
        BgBake.decodeTile4bpp(tile, tmp, 0, 0, 8, hflip, vflip)
        for row = 0, 7 do
          for col = 0, 7 do
            local r, g, b = BgBake.bgr555ToRgb8(bank[tmp[row * 8 + col + 1] or 0] or 0)
            local o = ((ty * 8 + row) * W + tx * 8 + col) * 4
            pixels[o + 1], pixels[o + 2], pixels[o + 3], pixels[o + 4] = r, g, b, 255
          end
        end
      end
    end
  end
  return pixels
end

local function bakeSpritePixels(BgBake, gfx, bank, tilesW, tilesH, frame)
  local W, H = tilesW * 8, tilesH * 8
  local pixels = {}
  for i = 1, W * H * 4 do pixels[i] = 0 end
  local first = (frame or 0) * tilesW * tilesH
  local tile, tmp = {}, {}
  for t = 0, tilesW * tilesH - 1 do
    local tx, ty = t % tilesW, math.floor(t / tilesW)
    local base = (first + t) * 32
    for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
    for i = 1, 64 do tmp[i] = 0 end
    BgBake.decodeTile4bpp(tile, tmp, 0, 0, 8, false, false)
    for row = 0, 7 do
      for col = 0, 7 do
        local idx = tmp[row * 8 + col + 1] or 0
        local r, g, b = BgBake.bgr555ToRgb8(bank[idx] or 0)
        local o = ((ty * 8 + row) * W + tx * 8 + col) * 4
        pixels[o + 1], pixels[o + 2], pixels[o + 3] = r, g, b
        pixels[o + 4] = (idx == 0) and 0 or 255
      end
    end
  end
  return pixels, W, H
end

function RegionMapExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. RegionMapExtract.CACHE_SUB
  for _, name in ipairs(RegionMapExtract.FILES) do
    local rel = root .. "/" .. name
    local have = false
    if cache and cache.read then
      local data = cache:read(rel)
      have = (data ~= nil and #data > 8)
    elseif cache and cache.exists then
      have = cache:exists(rel) and true or false
    end
    if not have then return false end
  end
  return true
end

function RegionMapExtract.run(rom, cache, opts)
  opts = opts or {}
  local Versions = require("src.import.gba.versions")
  local Lz77 = require("src.import.gba.lz77")
  local BgBake = require("src.import.gba.bg_bake")
  local encodePng = require("src.import.gba.battle_anim_extract").encodePng
  local root = (opts.cacheRoot or default_cache_root()) .. "/" .. RegionMapExtract.CACHE_SUB
  local get = function(i) return rom:get(i) end

  local written = {}
  local function put(name, pixels, w, h)
    local png = encodePng(pixels, w, h)
    if not png or #png < 8 then
      error("region_map: could not encode " .. name)
    end
    local ok, err = cache:write(root .. "/" .. name, png)
    if ok == false then
      error("region_map: could not write " .. name .. ": " .. tostring(err))
    end
    written[#written + 1] = name
  end

  -- src/region_map.c:1111-1135
  local gfx = Lz77.decompress(get, Versions.REGION_MAP_GFX)
  local tilemap = Lz77.decompress(get, Versions.REGION_MAP_KANTO_TILEMAP)
  local banks = BgBake.loadPalBanks(
    readBytes(rom, Versions.REGION_MAP_PAL, Versions.REGION_MAP_PAL_BANKS * 32),
    Versions.REGION_MAP_PAL_BANKS)
  local mapW = Versions.REGION_MAP_TILEMAP_W
  local need = mapW * Versions.REGION_MAP_TILEMAP_H * 2
  if Lz77.len(tilemap) < need then
    error(("region_map: kanto tilemap is %d bytes, expected %d"):format(Lz77.len(tilemap), need))
  end
  put("kanto_map.png", bakeBgPixels(BgBake, gfx, banks, tilemap, mapW, 240, 160), 240, 160)

  local sprites = {
    -- src/region_map.c:2692-2713
    { name = "cursor.png", gfx = Versions.REGION_MAP_CURSOR_GFX,
      pal = Versions.REGION_MAP_CURSOR_PAL, w = 2, h = 2, frame = 0 },
    -- src/region_map.c:3448, 3595-3601
    { name = "dungeon_icon.png", gfx = Versions.REGION_MAP_DUNGEON_ICON_GFX,
      pal = Versions.REGION_MAP_MISC_ICON_PAL, w = 1, h = 1, frame = 0 },
    -- src/region_map.c:3375-3408
    { name = "player_red.png", gfx = Versions.REGION_MAP_PLAYER_RED_GFX,
      pal = Versions.REGION_MAP_PLAYER_RED_PAL, w = 2, h = 2, frame = 0 },
    { name = "player_leaf.png", gfx = Versions.REGION_MAP_PLAYER_LEAF_GFX,
      pal = Versions.REGION_MAP_PLAYER_LEAF_PAL, w = 2, h = 2, frame = 0 },
  }
  for _, s in ipairs(sprites) do
    local tiles = Lz77.decompress(get, s.gfx)
    local bank = BgBake.loadPalBanks(readBytes(rom, s.pal, 32), 1)[0]
    local wanted = (s.frame + 1) * s.w * s.h * 32
    if Lz77.len(tiles) < wanted then
      error(("region_map: %s is %d bytes, expected %d"):format(s.name, Lz77.len(tiles), wanted))
    end
    put(s.name, bakeSpritePixels(BgBake, tiles, bank, s.w, s.h, s.frame))
  end

  return { root = root, files = written }
end

return RegionMapExtract
