package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local PRET = os.getenv("POKEPORT_POKEEMERALD") or "../pokeemerald"
local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or (PRET .. "/pokeemerald.gba")
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_maps_native_test: skipped (no ROM at " .. ROM_PATH .. ")")
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
function rom:clearCache() end

local files = {}
local cache = {}
function cache:write(rel, bytes) files[rel] = bytes; return true end
function cache:read(rel) return files[rel] end
function cache:exists(rel) return files[rel] ~= nil end

local function readFile(path)
  local h = io.open(path, "rb")
  if not h then return nil end
  local s = h:read("*a")
  h:close()
  return s
end

local ROOT = "data/generated/gba"
local function load_rel(rel)
  local src = files[ROOT .. "/" .. rel]
  return src and assert(load(src, "@" .. rel, "t", {}))() or nil
end

local GameVersion = require("src.core.GameVersion")
local before = GameVersion.get()
GameVersion.set("emerald")
local Versions = require("src.import.gba.versions")
Versions.select("emerald")

local MB = require("src.core.game3.mb")
local NativePack = require("src.import.gba.native_pack")
local Tileset = require("src.import.gba.tileset")
local Metatile = require("src.import.gba.metatile")
local Step = require("src.import.gba.maps_native_extract")

check(not Step.ready(cache, ROOT), "not ready on an empty cache")
local summary = Step.run(rom, cache, { cacheRoot = ROOT })
check(Step.ready(cache, ROOT), "ready after run")
for _, rel in ipairs(Step.REQUIRED) do
  check(files[ROOT .. "/" .. rel] ~= nil, "wrote " .. rel)
end
eq(summary.maps, 518, "every Emerald map packed")
eq(summary.layouts, 518, "manifest lists 518 map layouts")
eq(#summary.dropped, 0, "no map dropped")
eq(summary.policy, "full", "full atlas policy")
eq(summary.pairs, 75, "75 tileset pairs")
eq(summary.mids, 35116, "every metatile of every pair in the atlas")

local man = load_rel("native/manifest.lua")
local fullOk = true
for pair, p in pairs(man.pairs) do
  local idx = NativePack.decodeIdx(files[ROOT .. "/native/" .. pair .. "/mids.idx"])
  local over = NativePack.decodeIdx(files[ROOT .. "/native/" .. pair .. "/mids_over.idx"])
  local pals = NativePack.decodePalettes(files[ROOT .. "/native/" .. pair .. "/palettes.bin"])
  if not (idx and over and pals) or idx.midCount ~= p.midCount or over.midCount ~= p.midCount
      or pals.numPalsInPrimary ~= 6 or pals.numPalsTotal ~= 13 then
    fullOk = false
  end
end
check(fullOk, "every pair has under/over atlases and a 6/13 palette header")

local alt = {}
for _, key in ipairs(summary.altLayouts) do alt[key] = true end
for id = 433, 438 do check(alt["alt_" .. id], "sky pillar clean layout alt_" .. id) end
check(alt.alt_432, "birch lab with table layout")
check(files[ROOT .. "/native/layouts/alt_432.mid"] ~= nil, "alt_432.mid written")
check(man.layouts.alt_432 == nil, "alt layouts stay out of the manifest")

local pack = load_rel("objects/pack.lua")
local warps = load_rel("warps.lua")
local conns = load_rel("connections.lua")

local function layout(mapId)
  return NativePack.decodeMidLayout(files[ROOT .. "/native/layouts/" .. mapId .. ".mid"])
end

local L = layout("EM_LITTLEROOT_TOWN")
local beh = pack.behaviors[man.layouts.EM_LITTLEROOT_TOWN.pair]
local doors = 0
for _, w in ipairs(warps.EM_LITTLEROOT_TOWN) do
  local c = L.cells[w.y * L.width + w.x + 1]
  if beh[c.mid] == MB.ANIMATED_DOOR and c.coll == 0x71 then doors = doors + 1 end
end
eq(doors, 3, "Littleroot's 3 warp cells are animated doors baked as DOOR")

local R = layout("EM_ROUTE119")
local rbeh = pack.behaviors[man.layouts.EM_ROUTE119.pair]
local bridges, bridgeWarps = 0, 0
for _, c in ipairs(R.cells) do
  local b = rbeh[c.mid]
  if b == MB.BRIDGE_OVER_OCEAN or b == MB.FORTREE_BRIDGE then
    bridges = bridges + 1
    if c.coll == 0x71 or c.coll == 0x72 or (b >= 0x60 and b <= 0x7F) then bridgeWarps = bridgeWarps + 1 end
  end
end
check(bridges > 0, "Route 119 has bridge cells (" .. bridges .. ")")
eq(bridgeWarps, 0, "Route 119 bridge cells are not warps")

local P = layout("EM_ROUTE105")
local water = 0
for _, c in ipairs(P.cells) do if c.coll == 0x29 then water = water + 1 end end
check(water > 1000, "Route 105 ocean baked as water (" .. water .. ")")

local dive, cardinal = 0, 0
for _, list in pairs(conns) do
  for _, c in ipairs(list) do
    if c.dir == "dive" or c.dir == "emerge" then dive = dive + 1 else cardinal = cardinal + 1 end
  end
end
eq(dive, 14, "dive/emerge rows kept")
eq(cardinal, 134, "cardinal connections")

eq(pack.interactions[MB.PC].script, "EventScript_PC", "PC interaction")
eq(pack.interactions[MB.TELEVISION].facing, "up", "TV only from below")
check(type(pack.scripts.EventScript_BookShelf) == "table", "bookshelf script extracted")
check(pack.tileBits[MB.TALL_GRASS] % 2 == 1, "tall grass has encounters")
check(math.floor(pack.tileBits[MB.OCEAN_WATER] / 2) % 2 == 1, "ocean is surfable")

local S = require("src.import.gba.syms").of("emerald")
local function check_metatile(mapId, pretPrimary, pretSecondary)
  local pair = man.layouts[mapId].pair
  local bundle = assert(Tileset.loadPair(rom, Versions.lookup(rom.md5), pair))
  local pri = readFile(PRET .. "/data/tilesets/primary/" .. pretPrimary .. "/metatiles.bin")
  local sec = readFile(PRET .. "/data/tilesets/secondary/" .. pretSecondary .. "/metatiles.bin")
  if not (pri and sec) then
    print("[skip] pret metatiles.bin missing for " .. mapId)
    return
  end
  bundle.primaryMt = { data = pri, count = #pri / 16 }
  bundle.secondaryMt = { data = sec, count = #sec / 16 }
  local idx = NativePack.decodeIdx(files[ROOT .. "/native/" .. pair .. "/mids.idx"])
  local slot = {}
  for i, mid in ipairs(idx.midIds) do slot[mid] = i - 1 end
  local lay = layout(mapId)
  local bad, checked = 0, {}
  for _, c in ipairs(lay.cells) do
    if not checked[c.mid] then
      checked[c.mid] = true
      local want = Metatile.compositeIndexedUnder(bundle, c.mid)
      local base = slot[c.mid] * 256
      for p = 1, 256 do
        if idx.pixels[base + p] ~= want[p] then bad = bad + 1 end
      end
    end
  end
  eq(bad, 0, mapId .. " atlas pixels match pret metatiles.bin")
end
check_metatile("EM_LITTLEROOT_TOWN", "general", "petalburg")
check_metatile("EM_ROUTE101", "general", "petalburg")
check_metatile("EM_SLATEPORT_CITY", "general", "slateport")

local anims = load_rel("native/general__petalburg/anim_manifest.lua")
local banks = {}
for _, b in ipairs(anims.banks) do banks[b.name] = b end
eq(anims.counters.primary.max, 256, "general primary counter max")
eq(banks.general_water.frames, S.count("gTilesetAnims_General_Water", 4), "water frames = ARRAY_COUNT")
eq(banks.general_flower.frames, S.count("gTilesetAnims_General_Flower", 4), "flower frames = ARRAY_COUNT")
eq(banks.general_water.period, 16, "water period")
eq(banks.general_water.phase, 1, "water phase")
local wf = files[ROOT .. "/native/general__petalburg/" .. banks.general_water.file]
eq(#wf, #banks.general_water.mids * banks.general_water.frames * 256, "water bank size")
local soot = load_rel("native/general__sootopolis/anim_manifest.lua")
local stormy
for _, b in ipairs(soot.banks) do if b.name == "sootopolis_stormy_water" then stormy = b end end
check(stormy and stormy.counter == "secondary" and stormy.frames == S.count("gTilesetAnims_Sootopolis_StormyWater", 4),
  "sootopolis stormy water bank on the secondary counter")
local uw = load_rel("native/general__underwater/anim_manifest.lua")
eq(uw and uw.counters.secondary.max, 128, "underwater secondary counter max")

GameVersion.set(before)
T.finish("emerald_maps_native_test")
