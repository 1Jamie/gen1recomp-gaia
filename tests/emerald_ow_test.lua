package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local PRET = os.getenv("POKEPORT_POKEEMERALD") or "../pokeemerald"
local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or (PRET .. "/pokeemerald.gba")
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_ow_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()

local rom = { md5 = "f3ae088181bf583e55daf962a92bb46f4f1d07b7", size = #data }
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

local files = {}
local cache = {
  write = function(_, rel, s) files[rel] = s; return true end,
  read = function(_, rel) return files[rel] end,
  exists = function(_, rel) return files[rel] ~= nil end,
}

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
local Versions = require("src.import.gba.versions")
Versions.select("emerald")
local S = Versions.SYMS
local OwExtract = require("src.import.gba.ow_extract")

local ROOT = "data/generated/gba"
eq(Versions.NUM_OBJ_EVENT_GFX, 239, "239 Emerald object event graphics")
local res = OwExtract.run(rom, cache, { cacheRoot = ROOT })
eq(res.count, 239, "every gfx id extracted")
eq(res.total, 239, "manifest total")
check(res.avatars, "avatar table written")
check(OwExtract.ready(cache, ROOT), "step ready after run")
for _, rel in ipairs(OwExtract.REQUIRED) do
  check(files[ROOT .. "/" .. rel] ~= nil, "wrote " .. rel)
end

local manifest = assert(load(files[ROOT .. "/ow/manifest.lua"], "@manifest", "t", {}))()
eq(manifest.ow_version, Versions.OW_VERSION, "manifest stamp")
eq(manifest.count, 239, "manifest count")

local pals = OwExtract.loadPaletteTable(rom)
local np = 0
for _ in pairs(pals) do np = np + 1 end
eq(np, Versions.OW_SPRITE_PALETTE_COUNT - 1, "every sObjectEventSpritePalettes entry loaded")

local frameMismatch, missingPal, blobBad = 0, 0, 0
for gid = 0, 238 do
  local s = manifest.sprites[gid]
  local info = rom:u32(Versions.OW_GFX_POINTERS + gid * 4) - 0x08000000
  local images = rom:u32(info + 0x1C) - 0x08000000
  local want
  for _, n in ipairs(S.namesAt(images)) do
    if n:find("PicTable", 1, true) then want = S.size(n) / 8 end
  end
  if not s or s.frameCount ~= want then frameMismatch = frameMismatch + 1 end
  if s and not pals[s.paletteTag] then missingPal = missingPal + 1 end
  local rgba = files[ROOT .. "/ow/" .. gid .. ".rgba"]
  if not (s and rgba and #rgba == s.atlasW * s.atlasH * 4 and s.atlasH == s.height * s.frameCount) then
    blobBad = blobBad + 1
  end
  local meta = OwExtract.decodeMeta(files[ROOT .. "/ow/" .. gid .. ".meta"])
  if not meta or meta.graphicsId ~= gid then blobBad = blobBad + 1 end
end
eq(frameMismatch, 0, "frame counts equal pret pic table lengths")
eq(missingPal, 0, "every sprite palette tag resolves")
eq(blobBad, 0, "every rgba sheet and meta blob is well formed")

local av = manifest.avatars
local want = {
  NORMAL = { Versions.OW_PLAYER_MALE, Versions.OW_PLAYER_FEMALE },
  MACH_BIKE = { Versions.OW_PLAYER_MALE_BIKE, Versions.OW_PLAYER_FEMALE_BIKE },
  ACRO_BIKE = { Versions.OW_PLAYER_MALE_ACRO_BIKE, Versions.OW_PLAYER_FEMALE_ACRO_BIKE },
  SURFING = { Versions.OW_PLAYER_MALE_SURF, Versions.OW_PLAYER_FEMALE_SURF },
  UNDERWATER = { Versions.OW_PLAYER_MALE_UNDERWATER, Versions.OW_PLAYER_FEMALE_UNDERWATER },
  FIELD_MOVE = { Versions.OW_PLAYER_MALE_FIELD_MOVE, Versions.OW_PLAYER_FEMALE_FIELD_MOVE },
  FISHING = { Versions.OW_PLAYER_MALE_FISH, Versions.OW_PLAYER_FEMALE_FISH },
  WATERING = { Versions.OW_PLAYER_MALE_WATERING, Versions.OW_PLAYER_FEMALE_WATERING },
}
eq(#av.player, 8, "8 player avatar states")
eq(#av.rival, 8, "8 rival avatar states")
for _, row in ipairs(av.player) do
  local w = want[row.state]
  check(w and row.male == w[1] and row.female == w[2], "player " .. row.state .. " gfx matches event_objects.h")
end
eq(av.rival[1].male, 100, "rival Brendan normal")
eq(av.rival[1].female, 105, "rival May normal")
eq(#av.stateFlags.male, 5, "5 gfx-to-state flag rows per gender")
eq(av.stateFlags.male[1].gfx, Versions.OW_PLAYER_MALE, "state flag row 0 is Brendan normal")
eq(av.stateFlags.female[4].gfx, Versions.OW_PLAYER_FEMALE_SURF, "state flag row 3 is May surfing")

local function png_indices(path, fw, fh, frames)
  local cmd = string.format(
    "python3 -c \"import sys\nfrom PIL import Image\nim=Image.open(sys.argv[1]);px=im.load()\n"
      .. "for f in range(%d):\n print(''.join('%%x'%%(px[f*%d+x,y]&15) for y in range(%d) for x in range(%d)))\" %s 2>/dev/null",
    frames, fw, fh, fw, path)
  local p = io.popen(cmd)
  if not p then return nil end
  local out = {}
  for line in p:lines() do out[#out + 1] = line end
  p:close()
  if #out ~= frames then return nil end
  return out
end

local pals2 = OwExtract.loadPaletteTable(rom)
for _, spec in ipairs({
  { gid = Versions.OW_PLAYER_MALE, png = PRET .. "/graphics/object_events/pics/people/brendan/walking.png" },
  { gid = Versions.OW_PLAYER_FEMALE, png = PRET .. "/graphics/object_events/pics/people/may/walking.png" },
}) do
  local spr = assert(OwExtract.extractOne(rom, spec.gid, pals2))
  local ref = png_indices(spec.png, spr.width, spr.height, 9)
  if not ref then
    print("emerald_ow_test: pixel spot check skipped (no python3/PIL or pret png)")
  else
    for fi = 1, 9 do
      local got = {}
      for p = 1, spr.width * spr.height do got[p] = string.format("%x", spr.frames[fi][p]) end
      eq(table.concat(got), ref[fi], "gfx " .. spec.gid .. " walk frame " .. (fi - 1) .. " pixel exact vs pret png")
    end
  end
end

T.finish("emerald_ow_test")
