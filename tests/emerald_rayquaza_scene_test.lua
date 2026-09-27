package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local PRET = os.getenv("POKEPORT_PRET_EMERALD") or "../pokeemerald"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_rayquaza_scene_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_rayquaza_scene_test: skipped (" .. ROM_PATH .. " is not Emerald)")
  os.exit(0)
end

local rom = { id = "emerald", size = #data }
function rom.get(_, o) return data:byte(o + 1) end
function rom.u16(_, o) local a, b = data:byte(o + 1, o + 2); return a + b * 256 end
function rom.u32(_, o)
  local a, b, c, d = data:byte(o + 1, o + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
function rom.readString(_, o, n) return data:sub(o + 1, o + n) end

local files = {}
local cache = {
  write = function(_, rel, bytes) files[rel] = bytes; return true end,
  read = function(_, rel) return files[rel] end,
}

local K = require("src.import.gba.rse.boot_gfx")
local M = require("src.import.gba.rse.rayquaza_scene_extract")
local ROOT = "data/generated/gba"
check(not M.ready(cache, ROOT), "not ready before run")
local ok, man = M.run(rom, cache, { cacheRoot = ROOT })
eq(ok, true, "extractor ran")
check(M.ready(cache, ROOT), "ready after run")
for _, rel in ipairs(M.REQUIRED) do
  check(files[ROOT .. "/" .. rel] ~= nil, rel .. " written")
end

local function dims(key)
  return K.pngSize(files[ROOT .. "/rayquaza_scene/" .. key])
end
for _, key in ipairs({ "clouds1", "clouds2", "clouds3", "tf_bg", "de_light", "de_bg", "de_bg_top", "ch_orbs",
  "ch_rayquaza", "ch_streaks", "ch_bg", "ca_light", "ca_bg" }) do
  local w, h = dims(key .. "_idx.png")
  eq(w, 256, key .. " text layer is 32 tiles wide")
  eq(h, 256, key .. " text layer is 32 tiles tall")
end
-- pokeemerald/src/rayquaza_scene.c:772
eq(({ dims("tf_rayquaza_idx.png") })[1], 256, "takes-flight Rayquaza is a 256px affine layer (screenSize 1)")
eq(man.layers.tf_rayquaza.bpp, 8, "affine layers are 8bpp")
-- pokeemerald/src/rayquaza_scene.c:1256
eq(({ dims("ca_ring_idx.png") })[1], 128, "ring is a 128px affine layer (screenSize 0)")
eq(#man.smokeCoords, 10, "sTakesFlight_SmokeCoords has MAX_SMOKE entries")
eq(man.smokeCoords[1][1], -1, "first smoke coord x (rayquaza_scene.c sTakesFlight_SmokeCoords)")
eq(man.smokeCoords[1][2], 5, "first smoke coord y")
eq(man.sprites.df_groudon.frames, 6, "duo fight Groudon has 6 64x64 frames")
eq(man.sprites.dfp_groudon.frames, 6, "pre-fight Groudon shares the duo fight sheet")
eq(#man.sprites.dfp_kyogre.anims, 9, "Kyogre template has the 9 part anims")
eq(man.sprites.tf_smoke.affineAnims[1][1].xScale, -64, "smoke affine anim starts at -64")
eq(#man.palettes.ch_bg, 64, "charges bg palette is four banks")

local py = io.popen("python3 -c 'import PIL' 2>&1")
local pyOut = py and py:read("*a") or "x"
if py then py:close() end
if pyOut == "" then
  local tmp = os.tmpname()
  local cmp = {
    { "df_groudon.png", "graphics/rayquaza_scene/scene_1/groudon.png" },
    { "df_groudon_claw.png", "graphics/rayquaza_scene/scene_1/groudon_claw.png" },
    { "de_rayquaza.png", "graphics/rayquaza_scene/scene_3/rayquaza.png" },
    { "ca_rayquaza.png", "graphics/rayquaza_scene/scene_5/rayquaza.png" },
    { "ca_groudon.png", "graphics/rayquaza_scene/scene_5/groudon.png" },
  }
  for _, row in ipairs(cmp) do
    local h = io.open(tmp, "wb")
    h:write(files[ROOT .. "/rayquaza_scene/" .. row[1]])
    h:close()
    local cmd = string.format(
      "python3 -W ignore -c \"from PIL import Image;a=Image.open('%s');b=Image.open('%s/%s');print(sum(1 for x,y in zip(a.getdata(),b.getdata()) if x!=y) if a.size==b.size else -1)\"",
      tmp, PRET, row[2])
    local p = io.popen(cmd)
    local out = p:read("*a")
    p:close()
    eq(tonumber(out), 0, row[1] .. " pixel indices equal pret " .. row[2])
  end
  os.remove(tmp)
end

T.finish()
