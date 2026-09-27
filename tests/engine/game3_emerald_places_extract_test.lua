package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Constants = require("src.core.game3.constants")
local EncountersExtract = require("src.import.gba.encounters_extract")
local HealLocationsExtract = require("src.import.gba.heal_locations_extract")
local MartsExtract = require("src.import.gba.marts_extract")
local MultichoiceExtract = require("src.import.gba.multichoice_extract")
local MapSections = require("src.import.gba.rse.map_sections_extract")

local before = GameVersion.get()

local function newRom()
  local rom = { bytes = {} }
  function rom:get(o) return self.bytes[o] or 0 end
  function rom:u16(o) return self:get(o) + self:get(o + 1) * 256 end
  function rom:u32(o) return self:u16(o) + self:u16(o + 2) * 65536 end
  function rom:ptrOffset(p)
    if not p or p < 0x08000000 or p >= 0x0A000000 then return nil end
    return p - 0x08000000
  end
  function rom:put8(o, v) self.bytes[o] = v % 256 end
  function rom:put16(o, v) self:put8(o, v); self:put8(o + 1, math.floor(v / 256)) end
  function rom:put32(o, v) self:put16(o, v % 65536); self:put16(o + 2, math.floor(v / 65536)) end
  function rom:putBytes(o, list) for i, b in ipairs(list) do self:put8(o + i - 1, b) end end
  return rom
end

local function newCache()
  local c = { files = {} }
  function c:write(rel, bytes) self.files[rel] = bytes; return true end
  function c:read(rel) return self.files[rel] end
  function c:exists(rel) return self.files[rel] ~= nil end
  return c
end

local function loadLua(src, label)
  local chunk = assert(load(src, "@" .. label, "t", {}))
  return chunk()
end

local function putHeader(rom, off, group, num, landPtr)
  rom:put8(off, group)
  rom:put8(off + 1, num)
  rom:put32(off + 4, landPtr or 0)
end

local function putLand(rom, infoOff, monsOff, rate, species)
  rom:put8(infoOff, rate)
  rom:put32(infoOff + 4, 0x08000000 + monsOff)
  for i = 0, 11 do
    rom:put8(monsOff + i * 4, 2 + i)
    rom:put8(monsOff + i * 4 + 1, 3 + i)
    rom:put16(monsOff + i * 4 + 2, species)
  end
end

GameVersion.set("emerald")
Versions.select("emerald")
local C = Constants.of("emerald")

do
  local r101 = C:map("MAP_ROUTE101")
  local rom = newRom()
  putHeader(rom, 0x100, r101.group, r101.num, 0x08000200)
  putHeader(rom, 0x114, r101.group, r101.num, 0x08000210)
  putHeader(rom, 0x128, 0xFF, 0xFF)
  putLand(rom, 0x200, 0x300, 20, 261)
  putLand(rom, 0x210, 0x340, 10, 263)

  local pyr = Versions.WILD_EXTRA_HEADERS.pyramid.off
  putHeader(rom, pyr, 0, 1, 0x08000200)
  putHeader(rom, pyr + 20, 0xFF, 0xFF)
  putHeader(rom, Versions.WILD_EXTRA_HEADERS.pike.off, 0xFF, 0xFF)
  rom:putBytes(Versions.FEEBAS_WILD_MON, { 20, 25, 0x48, 0x01 })
  rom:put16(Versions.FEEBAS_TILE_DATA + 6, 46)
  rom:put16(Versions.FEEBAS_TILE_DATA + 8, 91)
  rom:put16(Versions.FEEBAS_TILE_DATA + 10, 131)
  rom:put16(Versions.ALTERING_CAVE_HELD_ITEMS + 4, 179)
  rom:put16(Versions.ALTERING_CAVE_HELD_ITEMS + 6, 169)

  local cache = newCache()
  local detail = EncountersExtract.writeExtract(rom, cache, "gba", { wild_mon_headers = 0x100 })
  eq(detail.headers, 2, "two headers parsed before the terminator")
  local src = cache:read("gba/encounters.lua")
  check(src:find("gWildMonHeaders (Emerald)", 1, true) ~= nil, "emerald pack names its source")
  local pack = loadLua(src, "encounters.lua")
  local key = ("%d:%d"):format(r101.group, r101.num)
  check(pack[key] ~= nil, "group:num key present")
  check(pack.EM_ROUTE101 == nil or pack.EM_ROUTE101.mapGroup == r101.group, "engine alias shape")
  eq(pack.EM_ROUTE101 and pack.EM_ROUTE101.land.rate, 20, "EM_ROUTE101 alias carries header 0")
  eq(pack.ROUTE101 and pack.ROUTE101.mapNum, r101.num, "prefix-stripped alias")
  eq(pack[key].variants and #pack[key].variants, 2, "duplicate header becomes a variant")
  eq(pack[key].variants[2].land.slots[1].species, 263, "variant 2 species")
  eq(#pack[key].land.slots, 12, "12 land slots")
  eq(pack[key].land.slots[12].maxLevel, 14, "slot 12 max level")
  for k in pairs(pack) do
    check(not k:find("^FR_") and not k:find("^SEVII_"), "no FR aliases in an emerald pack: " .. k)
  end
  eq(detail.aliases, 1, "one EM_ alias counted")

  local extra = EncountersExtract.writeExtra(rom, cache, "gba")
  eq(#extra.headerSets.pyramid, 1, "pyramid set stops at its terminator")
  eq(#extra.headerSets.pike, 0, "empty pike set")
  eq(extra.feebas.mon.species, 328, "feebas species")
  eq(extra.feebas.mon.maxLevel, 25, "feebas max level")
  eq(extra.feebas.sections[2].spotBase, 131, "feebas section 2 spot base")
  eq(#extra.alteringCaveHeldItems, Versions.ALTERING_CAVE_HELD_ITEM_COUNT, "altering cave rows")
  eq(extra.alteringCaveHeldItems[2].item, 169, "altering cave row 1 item")
  local ep = loadLua(cache:read("gba/wild_extra.lua"), "wild_extra.lua")
  eq(ep.headerSets.pyramid[1].land.slots[1].species, 261, "wild_extra.lua round trip")
  eq(ep.feebas.sections[2].yMax, 91, "wild_extra.lua feebas section")
  check(EncountersExtract.ready(cache, "gba"), "ready once both files exist")
end

do
  local rom = newRom()
  local rows = {
    { C:map("MAP_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F"), 4, 2 },
    { C:map("MAP_PETALBURG_CITY"), 20, 17 },
  }
  for i, r in ipairs(rows) do
    local o = 0x400 + (i - 1) * 8
    rom:put8(o, r[1].group); rom:put8(o + 1, r[1].num)
    rom:put16(o + 2, r[2]); rom:put16(o + 4, r[3])
  end
  local secs = { { "MAP_LITTLEROOT_TOWN", 1 }, { "MAP_PETALBURG_CITY", 2 }, { "MAP_ROUTE101", 0 } }
  for i, s in ipairs(secs) do
    local m = C:map(s[1])
    rom:putBytes(0x500 + (i - 1) * 3, { m.group, m.num, s[2] })
  end
  local opts = { healBase = 0x400, healCount = 2, mapHealBase = 0x500, mapHealCount = 3 }
  local plan = assert(HealLocationsExtract.buildHealRow(rom, opts))
  eq(plan.model, "heal_row", "heal row model")
  eq(plan.heal[1].map, "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", "heal row 1 map")
  eq(plan.heal[1].x, 4, "heal row 1 x")
  eq(plan.heal[1].healerLocalId, nil, "no healer npc on the heal row model")
  eq(#plan.fly, 2, "two fly rows")
  eq(plan.fly[1].map, "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", "fly lands on the heal row")
  eq(plan.fly[1].townMap, "EM_LITTLEROOT_TOWN", "fly row keeps the town map")
  eq(#plan.mapWarps, 1, "route mapsec is a map warp")
  eq(plan.mapWarps[1].map, "EM_ROUTE101", "map warp map")
  local heal = loadLua(HealLocationsExtract.formatHealRow(plan), "heal_locations.lua")
  eq(heal.model, "heal_row", "pack model")
  eq(heal.whiteout[2].map, "EM_PETALBURG_CITY", "whiteout row 2")
  local fly = loadLua(HealLocationsExtract.formatFlyHealRow(plan), "fly_destinations.lua")
  local n = 0
  for key, row in pairs(fly.fly_destinations) do
    n = n + 1
    check(type(row.map) == "string" and tonumber(row.x) and tonumber(row.y), "fly row shape " .. tostring(key))
  end
  eq(n, 2, "fly pack rows")
  local function bySec(t, sec)
    for _, row in pairs(t) do if row.mapsec == sec then return row end end
  end
  eq(fly.fly_destinations.MAPSEC_OLDALE_TOWN and fly.fly_destinations.MAPSEC_OLDALE_TOWN.healLocation, 2,
    "fly row keyed by the MAPSEC name")
  eq(bySec(fly.fly_destinations, 1).healLocation, 2, "fly row carries its mapsec")
  eq(bySec(fly.map_warps, 2).map, "EM_ROUTE101", "map warps carry their mapsec")

  rom:put8(0x500 + 5, 9)
  local bad, err = HealLocationsExtract.buildHealRow(rom, opts)
  check(bad == nil and err:find("heal location 9", 1, true), "unknown heal id fails loudly")
end

do
  local rom = newRom()
  rom:put16(0x400, 13); rom:put16(0x402, 14)
  rom:put16(0x500, C.decorations.byName.DECOR_PIKACHU_DOLL); rom:put16(0x502, 0)
  local scripts = {
    a = { { op = "pokemart", 0x08000400 } },
    b = { { op = "pokemartdecoration2", 0x08000500 } },
  }
  local marts = MartsExtract.build(rom, scripts)
  eq(marts[0x08000400].kind, nil, "item marts stay untagged")
  eq(#marts[0x08000400].items, 2, "item list read to terminator")
  eq(marts[0x08000500].kind, "decorations", "decoration mart tagged")
  eq(marts[0x08000500].martType, "DECOR2", "decoration mart type")
  eq(C:name("decorations", marts[0x08000500].items[1], "DECOR_"), "DECOR_PIKACHU_DOLL", "decoration id resolves")
  local out, row = {}, { op = "pokemartdecoration", 0x08000500 }
  MartsExtract.remapRow(rom, row, out)
  eq(out[0x08000500].martType, "DECOR", "remapRow tags too")
  check(type(row[1]) == "string", "remapRow rewrites the operand to a key")
end

do
  local L = MultichoiceExtract.label
  eq(L({ 0xD3, 0xBF, 0xCD, 0xFF }, "rse"), "YES", "plain label")
  eq(L({ 0xBB, 0xFC, 0x13, 0x40, 0xBC, 0xFF }, "rse"), "A B", "clear-to becomes a gap")
  eq(L({ 0xFD, 0x01, 0xFF }, "rse"), "{PLAYER}", "player placeholder")
  eq(L({ 0x53, 0x54, 0xFF }, "rse"), "{PKMN}", "PKMN ligature")
  eq(L({ 0xFF }, "rse"), "", "blank label")

  local rom = newRom()
  rom:put32(0x600, 0x08000700); rom:put8(0x604, 2)
  rom:put32(0x608, 0); rom:put8(0x60C, 0)
  rom:put32(0x700, 0x08000800); rom:put32(0x708, 0x08000810)
  rom:putBytes(0x800, { 0xD3, 0xBF, 0xCD, 0xFF })
  rom:putBytes(0x810, { 0xC8, 0xC9, 0xFF })
  local lists = MultichoiceExtract.extract(rom, { base = 0x600, count = 2, dialect = "rse" })
  eq(lists[0].count, 2, "list 0 count")
  eq(lists[0].labels[2], "NO", "list 0 label 2")
  eq(lists[1].count, 0, "null list")
  local src = MultichoiceExtract.formatLua(lists)
  check(src:find("Emerald Multichoice", 1, true) ~= nil, "emerald multichoice header")
end

do
  eq(MapSections.themeIndex(0, 88, 109), 0, "hoenn mapsec indexes itself")
  eq(MapSections.themeIndex(90, 88, 109), 0, "kanto mapsec falls back to entry 0")
  eq(MapSections.themeIndex(197, 88, 109), 88, "post-kanto mapsec shifts down")
  eq(MapSections.themeIndex(212, 88, 109), 103, "last mapsec lands on the last theme")
  local sections = {
    [0] = { name = "LITTLEROOT TOWN", theme = "wood", themeId = 0, x = 4, y = 11, width = 1, height = 1 },
    [1] = { name = "", x = 0, y = 0, width = 1, height = 1 },
  }
  local pack = MapSections.load(MapSections.formatSections(sections, 2))
  eq(pack.sections[0].name, "LITTLEROOT TOWN", "section 0 name round trip")
  eq(pack.count, 2, "section count")
  eq(MapSections.themeOf(pack, 0), "wood", "themeOf direct")
  eq(#pack.themes, 6, "six popup themes")
end

GameVersion.set("firered")
Versions.select("firered")
do
  local MapCatalog = require("src.import.gba.map_catalog")
  local num
  for n = 0, 80 do
    if MapCatalog.mapIdFor(3, n) == "FR_ROUTE_1" then num = n break end
  end
  check(num ~= nil, "FR_ROUTE_1 in the firered catalog")
  local rom = newRom()
  putHeader(rom, 0x100, 3, num, 0x08000200)
  putHeader(rom, 0x114, 0xFF, 0xFF)
  putLand(rom, 0x200, 0x300, 20, 16)
  local cache = newCache()
  EncountersExtract.writeExtract(rom, cache, "gba", { wild_mon_headers = 0x100 })
  local src = cache:read("gba/encounters.lua")
  check(src:find("gWildMonHeaders (FireRed)", 1, true) ~= nil, "firered header text unchanged")
  local pack = loadLua(src, "encounters.lua")
  for _, k in ipairs({ "FR_ROUTE_1", "ROUTE_1", "ROUTE1", "FR_ROUTE1", "3:" .. num }) do
    check(pack[k] ~= nil, "firered alias " .. k)
  end
  check(cache:read("gba/wild_extra.lua") == nil, "firered writes no wild_extra")
  check(EncountersExtract.ready(cache, "gba"), "firered ready needs only encounters.lua")
end

GameVersion.set(before)
T.finish("game3_emerald_places_extract_test")
