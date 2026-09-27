package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local PRET = os.getenv("POKEPORT_POKEEMERALD") or "../pokeemerald"
local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or (PRET .. "/pokeemerald.gba")
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_places_test: skipped (no ROM at " .. ROM_PATH .. ")")
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
function rom:ptrOffset(p)
  if not p or p < 0x08000000 or p >= 0x0A000000 then return nil end
  return p - 0x08000000
end

local cache = { files = {} }
function cache:write(rel, bytes) self.files[rel] = bytes; return true end
function cache:read(rel) return self.files[rel] end
function cache:exists(rel) return self.files[rel] ~= nil end

local function loadLua(rel)
  local src = assert(cache:read(rel), "missing " .. rel)
  return assert(load(src, "@" .. rel, "t", {}))()
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
local C = require("src.core.game3.constants").of("emerald")
local ROOT = "gba"

local EncountersExtract = require("src.import.gba.encounters_extract")
local enc = EncountersExtract.run(rom, cache, { cacheRoot = ROOT })
eq(enc.headers, 124, "124 wild headers")
eq(enc.extraHeaders, 11, "7 pyramid + 4 pike headers")
local wild = loadLua(ROOT .. "/encounters.lua")
local r101 = C:map("MAP_ROUTE101")
local w101 = wild[r101.group .. ":" .. r101.num]
check(w101 and w101.land, "route 101 land table")
eq(w101 and w101.land.rate, 20, "route 101 land rate")
eq(w101 and w101.land.slots[1].species, C.species.byName.SPECIES_WURMPLE, "route 101 slot 0 wurmple")
check(wild.EM_ROUTE101 ~= nil, "EM_ROUTE101 alias")
local cave = wild.EM_ALTERING_CAVE
eq(cave and cave.variants and #cave.variants, 9, "altering cave has 9 header variants")
local groups = 0
for k in pairs(wild) do
  if type(k) == "string" and k:match("^%d+:%d+$") then groups = groups + 1 end
  check(not k:find("^FR_"), "no FR alias " .. k)
end
eq(groups, 116, "116 distinct wild maps")

local extra = loadLua(ROOT .. "/wild_extra.lua")
eq(#extra.headerSets.pyramid, 7, "7 pyramid rounds")
eq(#extra.headerSets.pike, 4, "4 pike rooms")
eq(extra.headerSets.pyramid[1].mapNum, 1, "pyramid round index 1")
eq(extra.feebas.mon.species, C.species.byName.SPECIES_FEEBAS, "feebas species")
eq(extra.feebas.mon.minLevel, 20, "feebas min level")
eq(extra.feebas.mon.maxLevel, 25, "feebas max level")
eq(#extra.feebas.sections, 3, "3 route 119 sections")
eq(extra.feebas.sections[3].spotBase, 131 + 167, "section 3 spot base")
eq(extra.feebas.sections[3].yMax, 139, "section 3 y max")
eq(#extra.alteringCaveHeldItems, 9, "9 altering cave rows")
eq(extra.alteringCaveHeldItems[2].species, C.species.byName.SPECIES_MAREEP, "altering cave row 1 mareep")
eq(extra.alteringCaveHeldItems[2].item, C.items.byName.ITEM_GANLON_BERRY, "altering cave row 1 ganlon")
eq(extra.alteringCaveHeldItems[9].item, C.items.byName.ITEM_SALAC_BERRY, "altering cave row 8 salac")

local Heal = require("src.import.gba.heal_locations_extract")
local okH, detail = Heal.run(rom, cache, { cacheRoot = ROOT, force = true, strict = true })
check(okH, "heal locations extract")
eq(detail.healLocations, 22, "22 heal rows")
eq(detail.flyDestinations, 16, "16 fly destinations")
local heal = loadLua(ROOT .. "/region_map/heal_locations.lua")
eq(heal.model, "heal_row", "heal row model")
eq(heal.whiteout[1].map, "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", "heal row 1 map")
eq(heal.whiteout[1].x, 4, "heal row 1 x")
eq(heal.whiteout[1].y, 2, "heal row 1 y")
eq(heal.whiteout[3].map, "EM_PETALBURG_CITY", "heal row 3 petalburg")
eq(heal.whiteout[22].map, "EM_BATTLE_FRONTIER_OUTSIDE_EAST", "heal row 22 battle frontier")
for id, row in pairs(heal.whiteout) do
  eq(row.healerLocalId, nil, "no healer npc on row " .. id)
end
local fly = loadLua(ROOT .. "/region_map/fly_destinations.lua")
local f0 = fly.fly_destinations[0] or fly.fly_destinations.MAPSEC_LITTLEROOT_TOWN
eq(f0 and f0.healLocation, 1, "mapsec 0 flies to heal location 1")
eq(f0 and f0.townMap, "EM_LITTLEROOT_TOWN", "mapsec 0 town map")
local warps = 0
for _ in pairs(fly.map_warps) do warps = warps + 1 end
eq(warps, 34, "34 route mapsecs warp to their map")

local MapSections = require("src.import.gba.rse.map_sections_extract")
local ms = MapSections.run(rom, cache, { cacheRoot = ROOT })
eq(ms.sections, 213, "213 region map entries")
eq(ms.themes, 6, "6 popup themes")
check(MapSections.ready(cache, ROOT), "map sections ready")
local pack = MapSections.load(cache:read(ROOT .. "/" .. MapSections.SECTIONS_REL))
eq(pack.sections[0].name, "LITTLEROOT TOWN", "mapsec 0 LITTLEROOT TOWN")
eq(pack.sections[0].x, 4, "mapsec 0 x")
eq(pack.sections[0].y, 11, "mapsec 0 y")
eq(pack.sections[0].theme, "wood", "littleroot popup wood")
eq(pack.sections[7].theme, "brick", "petalburg popup brick")
eq(pack.sections[88].name, "PALLET TOWN", "kanto section name")
eq(pack.KANTO_MAPSEC_COUNT, 109, "109 kanto mapsecs")
local themed = 0
for i = 0, pack.count - 1 do
  if pack.sections[i].theme then themed = themed + 1 end
end
eq(themed, 213, "every section resolves a theme")
local manifest = loadLua(ROOT .. "/chrome/map_popup/manifest.lua")
eq(#manifest.palettes.wood, 16, "wood palette")
eq(#manifest.underwaterPalette, 16, "underwater palette")
for _, t in ipairs(MapSections.THEMES) do
  eq(#cache:read(ROOT .. "/chrome/map_popup/" .. t .. ".rgba"), 80 * 24 * 4, t .. " rgba size")
  eq(#cache:read(ROOT .. "/chrome/map_popup/" .. t .. "_outline.idx"), 80 * 24, t .. " outline idx size")
end

local header = readFile(PRET .. "/include/constants/region_map_sections.h")
local popupSrc = readFile(PRET .. "/src/map_name_popup.c")
if header and popupSrc then
  local enum, idx = {}, {}
  for name in header:gmatch("\n%s*(MAPSEC_[%w_]+),") do
    enum[#enum + 1] = name
    idx[name] = #enum - 1
  end
  local kc = idx.MAPSEC_SPECIAL_AREA - idx.MAPSEC_PALLET_TOWN + 1
  local ids = { WOOD = 0, MARBLE = 1, STONE = 2, BRICK = 3, UNDERWATER = 4, STONE2 = 5 }
  local body = popupSrc:match("sMapSectionToThemeId%[.-%]%s*=%s*(%b{})")
  local expect = {}
  for name, sub, theme in body:gmatch("%[(MAPSEC_[%w_]+)(%s*%-?%s*[%w_]*)%]%s*=%s*MAPPOPUP_THEME_([%w_]+)") do
    local s = idx[name]
    if sub:find("KANTO_MAPSEC_COUNT", 1, true) then s = s - kc end
    expect[s] = ids[theme]
  end
  local bad = 0
  for i = 0, 103 do
    local sec = i
    if i >= idx.MAPSEC_PALLET_TOWN then sec = i + kc end
    if (expect[i] or 0) ~= pack.sections[sec].themeId then bad = bad + 1 end
  end
  eq(bad, 0, "theme ids match pret sMapSectionToThemeId")
end

local Multichoice = require("src.import.gba.multichoice_extract")
Multichoice.run(rom, cache, { cacheRoot = ROOT })
local lists = loadLua(ROOT .. "/" .. Multichoice.CACHE_REL)
local n = 0
for i = 0, 200 do if lists[i] then n = n + 1 end end
eq(n, 114, "114 multichoice lists")
eq(lists[0].labels[1], "PETALBURG", "MULTI_SSTIDAL_SLATEPORT_WITH_BF first label")
eq(lists[12].labels[2], "ACRO", "MULTI_BIKE acro")
eq(lists[113].labels[1], "NORMAL TAG MATCH", "MULTI_TAG_MATCH_TYPE")
eq(lists[113].count, 5, "tag match 5 rows")
eq(lists[86].labels[5], "", "forced start menu blank player row")
eq(lists[95].labels[4], "{PKMN} TYPE & NO.", "PKMN ligature survives")
local qmark = 0
for byte, ch in pairs(require("src.core.game3.scripting.text_ir").CHARMAP) do
  if ch == "?" then qmark = byte end
end
for i = 0, 113 do
  local listOff = rom:u32(Versions.MULTICHOICE_LISTS + i * 8) - 0x08000000
  for a, s in ipairs(lists[i].labels) do
    local textOff = rom:u32(listOff + (a - 1) * 8) - 0x08000000
    local want = 0
    for k = 0, 63 do
      local b = rom:get(textOff + k)
      if b == 0xFF then break end
      if b == qmark then want = want + 1 end
    end
    local _, got = s:gsub("%?", "")
    eq(got, want, ("list %d label %d decodes cleanly: %s"):format(i, a, s))
  end
end

local Marts = require("src.import.gba.marts_extract")
local S = Versions.SYMS
local scripts = {
  a = { { op = "pokemartdecoration2", S.addr("LilycoveCity_DepartmentStore_5F_Pokemart_Dolls") } },
  b = { { op = "pokemart", S.addr("OldaleTown_Mart_Pokemart_Basic") } },
}
local marts = Marts.build(rom, scripts)
local dolls = marts[S.addr("LilycoveCity_DepartmentStore_5F_Pokemart_Dolls")]
eq(dolls and dolls.kind, "decorations", "lilycove dolls tagged")
eq(dolls and C:name("decorations", dolls.items[1], "DECOR_"), "DECOR_PICHU_DOLL", "dolls list first DECOR")
eq(dolls and C:name("decorations", dolls.items[2], "DECOR_"), "DECOR_PIKACHU_DOLL", "dolls list second DECOR")
local basic = marts[S.addr("OldaleTown_Mart_Pokemart_Basic")]
eq(basic and basic.kind, nil, "item mart untagged")
eq(basic and C:name("items", basic.items[1], "ITEM_"), "ITEM_POTION", "oldale first item")

GameVersion.set(before)
T.finish("emerald_places_test")
