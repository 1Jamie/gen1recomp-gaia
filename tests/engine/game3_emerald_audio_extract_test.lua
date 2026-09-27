package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Constants = require("src.core.game3.constants")
local E = require("src.import.gba.extract_audio")

local function le16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
local function le32(v)
  return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
end

local function song_table(count, titleId)
  local parts = {}
  for id = 0, count - 1 do
    local player = 0
    if id == 1 then player = 1 elseif id == 5 then player = 2 elseif id ~= titleId and id ~= 0 then player = 1 end
    parts[#parts + 1] = le32(0x08001000 + id * 16) .. le16(player) .. le16(player)
  end
  return table.concat(parts)
end

do
  local pad = string.rep("\0", 64)
  local data = pad .. song_table(20, 12) .. pad
  eq(E.findSongTable(data, 20, 12), 64, "scan finds the table")
  eq(E.findSongTable(data, 20, 12, 64), 64, "hint accepted when it validates")
  eq(E.findSongTable(data, 20, 12, 8), 64, "bad hint falls back to the scan, not to the hint")
  eq(E.findSongTable(data, 20, 7), nil, "title id that is not a BGM entry finds nothing")
  check(not E.isSongTable(data, 64, 20, 30), "title id past the count is rejected")
  check(not pcall(E.findSongTable, data, 20), "probe needs a title id")
end

do
  local em = Constants.of("emerald")
  local sp = em.species.byName
  local treeckoSlot = sp.SPECIES_TREECKO - 1
  local n = sp.NUM_SPECIES - 1 - treeckoSlot
  local tbl = {}
  for i = 0, n - 1 do tbl[#tbl + 1] = le16(300 + i) end
  local data = "\0\0\0\0" .. table.concat(tbl)
  local ids = E.cryIdsFromTable(data, 4, n, sp, sp.NUM_SPECIES)
  eq(ids[1], 0, "Bulbasaur -> cry 0")
  eq(ids[sp.SPECIES_CELEBI], sp.SPECIES_CELEBI - 1, "Celebi keeps its own cry")
  eq(ids[sp.SPECIES_CELEBI + 1], sp.SPECIES_UNOWN - 1, "old Unown slot -> Unown cry")
  eq(ids[sp.SPECIES_TREECKO - 1], sp.SPECIES_UNOWN - 1, "last old Unown slot -> Unown cry")
  eq(ids[sp.SPECIES_TREECKO], 300, "Treecko reads table entry 0")
  eq(ids[sp.NUM_SPECIES - 1], 300 + n - 1, "last species reads the last table entry")
  eq(ids[sp.NUM_SPECIES], nil, "no entry past the species count")
  check(not pcall(E.cryIdsFromTable, data, 4, n - 1, sp, sp.NUM_SPECIES), "short table raises")
end

do
  local em = Constants.of("emerald")
  local data = le16(em.songs.byName.MUS_LEVEL_UP) .. le16(80) .. le16(em.songs.byName.MUS_AWAKEN_LEGEND) .. le16(710)
  local ff = E.readFanfares(data, 0, 2, em)
  eq(ff[em.songs.byName.MUS_LEVEL_UP].frames, 80, "fanfare frames")
  eq(ff[em.songs.byName.MUS_AWAKEN_LEGEND].name, "MUS_AWAKEN_LEGEND", "fanfare name from constants")
end

do
  local legacy = {
    battleWild = 298, battleTrainer = 297, battleGymLeader = 296, battleChampion = 299,
    victoryWild = 311, victoryTrainer = 310, victoryGymLeader = 312,
    encounterBoy = 285, encounterGirl = 284, encounterRival = 315, encounterRocket = 283,
    encounterGymLeader = 342, pokeCenter = 303, heal = 256, surf = 305, cycling = 282,
    caught = 322, caughtIntro = 319, evolution = 264, evolutionIntro = 263, evolved = 259,
    levelUp = 257, obtainItem = 258, followMe = 272, title = 278,
  }
  local roles = E.resolveRoles(Constants.of("firered"))
  local n = 0
  for k, v in pairs(roles) do
    n = n + 1
    eq(v, legacy[k], "FireRed role " .. k)
  end
  eq(n, 25, "FireRed resolves all 25 roles")
  local V = Versions.forGame("emerald")
  local em = E.resolveRoles(Constants.of("emerald"), V.AUDIO.roles)
  eq(em.title, 413, "Emerald MUS_TITLE role")
  eq(em.battleWild, 474, "Emerald MUS_VS_WILD role")
  eq(em.underwater, 411, "Emerald MUS_UNDERWATER role")
  eq(em.encounterRocket, nil, "FRLG-only role absent on Emerald")
end

do
  local V = Versions.forGame("emerald")
  local A = V.AUDIO
  eq(A.song_count, 610, "610 songs")
  eq(A.cry_count, 388, "388 cries")
  eq(A.cry_table_reverse_count, 388, "388 reverse cries")
  eq(A.fanfare_count, 18, "18 Emerald fanfares")
  eq(A.cry_id_count, 135, "gSpeciesIdToCryId rows")
  eq(A.fanfares, 0x5248BC, "sFanfares offset")
  eq(A.cry_id_table, 0x31F61C, "gSpeciesIdToCryId offset")
  eq(A.cry_table_reverse, 0x69EF24, "gCryTable_Reverse offset")
  eq(require("src.import.gba.versions_frlg").AUDIO.fanfares, nil, "FRLG AUDIO keeps its keys")
end

do
  local Plans = require("src.import.gba.plans.registry")
  local plan = Plans.of("emerald")
  local found
  for _, t in ipairs(plan.tasks) do
    if t.id == "audio" then found = t end
  end
  check(found and found.run == "steps" and found.steps[1].name == "extract_audio", "rse plan has the audio task")
  local seq = false
  for _, s in ipairs(plan.sequential) do seq = seq or s == "audio" end
  check(seq, "audio task in the sequential order")
  local req = {}
  for _, p in ipairs(require("src.import.CacheContract").planFilesFor("emerald")) do req[p] = true end
  check(req["data/generated/gba/audio/index.lua"], "Emerald cache requires audio/index.lua")
  check(req["data/generated/gba/audio/samples.bin"], "Emerald cache requires audio/samples.bin")
end

do
  local store = {}
  local cache = {
    read = function(_, p) return store[p] end,
    exists = function(_, p) return store[p] ~= nil end,
  }
  check(not E.ready(cache, "g"), "not ready without meta")
  store["g/audio/meta.json"] = '{"stub":true}'
  store["g/audio/index.lua"] = "return {}"
  check(not E.ready(cache, "g"), "stub marker is not ready")
  local prev = Versions.active()
  Versions.select("emerald")
  store["g/audio/meta.json"] = ('{"version":%d,"sha1":""}'):format(Versions.AUDIO_VERSION)
  check(E.ready(cache, "g"), "current meta + index is ready")
  store["g/audio/meta.json"] = ('{"version":%d,"sha1":""}'):format(Versions.AUDIO_VERSION + 1)
  check(not E.ready(cache, "g"), "stale audio version is not ready")
  Versions.select(prev)
end

do
  local prevV, prevG = Versions.active(), GameVersion.get()
  Versions.select("emerald")
  check(not pcall(E.run, "", { write = function() return true end }, {}), "no song table found raises")
  Versions.select(prevV)
  if prevG then GameVersion.set(prevG) end
end

T.finish("game3_emerald_audio_extract_test")
