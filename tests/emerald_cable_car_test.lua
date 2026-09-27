package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local PRET = os.getenv("POKEPORT_PRET_EMERALD") or "../pokeemerald"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_cable_car_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_cable_car_test: skipped (" .. ROM_PATH .. " is not Emerald)")
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
local M = require("src.import.gba.rse.cable_car_extract")
local ROOT = "data/generated/gba"
check(not M.ready(cache, ROOT), "not ready before run")
local ok, man = M.run(rom, cache, { cacheRoot = ROOT })
eq(ok, true, "extractor ran")
check(M.ready(cache, ROOT), "ready after run")
for _, rel in ipairs(M.REQUIRED) do
  check(files[ROOT .. "/" .. rel] ~= nil, rel .. " written")
end

local function readBin(rel)
  local h = io.open(PRET .. "/" .. rel, "rb")
  if not h then return nil end
  local s = h:read("*a")
  h:close()
  local out = {}
  for i = 0, math.floor(#s / 2) - 1 do
    local lo, hi = s:byte(i * 2 + 1, i * 2 + 2)
    out[i + 1] = lo + hi * 256
  end
  return out
end

-- pokeemerald/src/cable_car.c:134
for key, file in pairs({ ground = "ground", trees = "trees", bgMountains = "bg_mountains", pylonTop = "pylon_top",
  pylonPole = "pylon_pole" }) do
  local want = readBin("graphics/cable_car/" .. file .. ".bin")
  if want then
    local got = man.tilemaps[key]
    eq(#got, #want, key .. " tilemap entry count matches pret " .. file .. ".bin")
    local diff = 0
    for i = 1, #want do if got[i] ~= want[i] then diff = diff + 1 end end
    eq(diff, 0, key .. " tilemap is byte-identical to pret " .. file .. ".bin")
  end
end

eq(#man.palettes.bg, 64, "gCableCarBg_Pal is four 16-colour banks")
eq(#man.palettes.car, 16, "gCableCar_Pal is one bank")
eq(man.bgTileCount * 32, #files[ROOT .. "/cable_car/bg_tiles.4bpp"], "bg tile data is whole 4bpp tiles")
local dims = { cable_car = { 64, 64 }, door = { 16, 8 }, cable = { 16, 16 }, ash = { 64, 128 } }
for key, d in pairs(dims) do
  local pw, ph = K.pngSize(files[ROOT .. "/cable_car/" .. key .. ".png"])
  eq(pw, d[1], key .. ".png width")
  eq(ph, d[2], key .. ".png height")
end
-- pokeemerald/src/cable_car.c:152
eq(man.sprites.car.affineMode, 3, "cable car OAM is ST_OAM_AFFINE_DOUBLE")
eq(man.sprites.car.priority, 2, "cable car OAM priority 2")
eq(man.sprites.cable.affineMode, 3, "cable OAM is ST_OAM_AFFINE_DOUBLE")
eq(man.sprites.door.paletteTag, 1, "door uses TAG_CABLE_CAR palette")
eq(man.sprites.ash.frames, 2, "ash sheet holds the two 64x64 frames (field_weather_effect.c:1629)")

local py = io.popen("python3 -c 'import PIL' 2>&1")
local pyOut = py and py:read("*a") or "x"
if py then py:close() end
if pyOut == "" then
  local tmp = os.tmpname()
  local cmp = {
    { "cable_car.png", "graphics/cable_car/cable_car.png" },
    { "door.png", "graphics/cable_car/door.png" },
    { "cable.png", "graphics/cable_car/cable.png" },
  }
  for _, row in ipairs(cmp) do
    local h = io.open(tmp, "wb")
    h:write(files[ROOT .. "/cable_car/" .. row[1]])
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
