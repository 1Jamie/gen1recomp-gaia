package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_audio_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local rom = f:read("*a")
f:close()

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
local Versions = require("src.import.gba.versions")
Versions.select("emerald")
local Constants = require("src.core.game3.constants")
local S = require("src.import.gba.syms").of("emerald")
local E = require("src.import.gba.extract_audio")

local C = Constants.of("emerald")
local function u16(off) local a, b = rom:byte(off + 1, off + 2) return a + b * 256 end

local files = {}
local cache = { write = function(_, p, b) files[p] = b; return true end }
local ok, idx = E.run({ data = rom }, cache, { sha1 = "f3ae088181bf583e55daf962a92bb46f4f1d07b7", cacheRoot = "g" })
check(ok, "extract ran")

eq(idx.songCount, 610, "610 songs")
eq(idx.songTable, S.off("gSongTable"), "song table at gSongTable")
local missing, bins = 0, 0
for id = 0, 609 do
  if idx.songs[id].missing then missing = missing + 1 end
  if files[("g/audio/songs/%d.bin"):format(id)] then bins = bins + 1 end
end
eq(missing, 0, "every song header resolves")
eq(bins, 610, "one bin per song")
eq(idx.songs[C.songs.byName.MUS_TITLE].kind, "bgm", "MUS_TITLE is a BGM")
eq(idx.songs[C.songs.byName.PH_NURSE_SOLO].player, 2, "phoneme SEs ride SE2")

local EXPECT = {
  { 367, 80 }, { 370, 160 }, { 371, 220 }, { 372, 220 }, { 368, 160 }, { 369, 340 },
  { 378, 180 }, { 387, 120 }, { 388, 710 }, { 389, 250 }, { 390, 150 }, { 391, 160 },
  { 550, 450 }, { 530, 170 }, { 529, 196 }, { 459, 313 }, { 466, 318 }, { 460, 135 },
}
local nff = 0
for _ in pairs(idx.fanfares) do nff = nff + 1 end
eq(nff, #EXPECT, "18 fanfares")
for _, row in ipairs(EXPECT) do
  local e = idx.fanfares[row[1]]
  eq(e and e.frames, row[2], "fanfare " .. row[1] .. " frames")
  eq(idx.songs[row[1]].kind, "fanfare", "song " .. row[1] .. " is a fanfare")
end
eq(idx.fanfares[C.songs.byName.MUS_OBTAIN_ITEM].name, "MUS_OBTAIN_ITEM", "fanfare named from constants")

local ncry, nrev, withSample = 0, 0, 0
for i = 0, 387 do
  if idx.cries[i] then ncry = ncry + 1 end
  if idx.criesReverse[i] then nrev = nrev + 1 end
  if idx.cries[i] and idx.cries[i].sampleId then withSample = withSample + 1 end
end
eq(ncry, 388, "388 cries")
eq(nrev, 388, "388 reverse cries")
eq(withSample, 388, "every cry has a sample")
eq(idx.cryTableReverse, S.off("gCryTable_Reverse"), "reverse table offset")
check(files["g/audio/crytable_reverse.bin"] and #files["g/audio/crytable_reverse.bin"] == 388 * 12, "reverse table dump")

local sp = C.species.byName
local base = S.off("gSpeciesIdToCryId")
local bad = 0
for species = 1, sp.NUM_SPECIES - 1 do
  local s, want = species - 1
  if s <= sp.SPECIES_CELEBI - 1 then want = s
  elseif s < sp.SPECIES_TREECKO - 1 then want = sp.SPECIES_UNOWN - 1
  else want = u16(base + (s - (sp.SPECIES_TREECKO - 1)) * 2) end
  if idx.cryIds[species] ~= want then bad = bad + 1 end
end
eq(bad, 0, "cryIds follow SpeciesToCryId over gSpeciesIdToCryId")
eq(idx.cryIds[sp.SPECIES_TREECKO], 273, "Treecko cry id")
eq(idx.cryIds[sp.SPECIES_LOTAD], 283, "Lotad cry id")

local nmap = 0
for _ in pairs(idx.mapSongs) do nmap = nmap + 1 end
eq(nmap, 496, "496 maps with music (22 MUS_NONE)")
local MapCatalog = require("src.import.gba.map_catalog")
local function mapId(name)
  local row = C.map_groups.byName[name]
  return MapCatalog.mapIdFor(row.group, row.num) or MapCatalog.pretToEngine(row.name)
end
eq(idx.mapSongs[mapId("MAP_ROUTE118")], C.songs.byName.MUS_ROUTE118, "MUS_ROUTE118 sentinel passes through")
eq(idx.mapSongs[mapId("MAP_LITTLEROOT_TOWN")], C.songs.byName.MUS_LITTLEROOT, "Littleroot music")
eq(idx.mapSongs[mapId("MAP_INSIDE_OF_TRUCK")], nil, "MUS_NONE maps are skipped")

eq(idx.roles.title, C.songs.byName.MUS_TITLE, "title role")
eq(idx.roles.battleWild, C.songs.byName.MUS_VS_WILD, "wild battle role")
eq(idx.roles.heal, C.songs.byName.MUS_HEAL, "heal role")

check(files["g/audio/meta.json"]:find('"song_count":610', 1, true) ~= nil, "meta.json song count")

T.finish("emerald_audio_test")
