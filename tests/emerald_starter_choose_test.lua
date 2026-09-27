package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local PRET = os.getenv("POKEPORT_PRET_EMERALD") or "../pokeemerald"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_starter_choose_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_starter_choose_test: skipped (" .. ROM_PATH .. " is not Emerald)")
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
local M = require("src.import.gba.rse.extract_starter_choose_rse")
local ROOT = "data/generated/gba"
check(not M.ready(cache, ROOT), "not ready before run")
local ok, man = M.run(rom, cache, { cacheRoot = ROOT })
eq(ok, true, "extractor ran")
check(M.ready(cache, ROOT), "ready after run")
for _, rel in ipairs(M.REQUIRED) do
  check(files[ROOT .. "/" .. rel] ~= nil, rel .. " written")
end
local C = require("src.core.game3.constants").of("emerald")
eq(man.species[1], C.species.byName.SPECIES_TREECKO, "sStarterMon[0] Treecko")
eq(man.species[2], C.species.byName.SPECIES_TORCHIC, "sStarterMon[1] Torchic")
eq(man.species[3], C.species.byName.SPECIES_MUDKIP, "sStarterMon[2] Mudkip")
local dims = { grass = { 256, 160 }, bag = { 256, 160 }, pokeball = { 32, 96 }, hand = { 32, 32 }, circle = { 64, 64 } }
for key, d in pairs(dims) do
  local pw, ph = K.pngSize(files[ROOT .. "/starter_choose/" .. key .. ".png"])
  eq(pw, d[1], key .. ".png width")
  eq(ph, d[2], key .. ".png height")
end

local src = io.open(PRET .. "/src/starter_choose.c", "rb")
if src then
  local text = src:read("*a")
  src:close()
  local function pairsOf(name)
    local body = text:match(name .. "%[[^%]]*%]%[2%]%s*=%s*(%b{})")
    local out = {}
    for a, b in (body or ""):gmatch("{%s*(%d+)%s*,%s*(%d+)%s*}") do out[#out + 1] = { tonumber(a), tonumber(b) } end
    return out
  end
  for _, pair in ipairs({ { "sPokeballCoords", "pokeballCoords" }, { "sStarterLabelCoords", "labelCoords" },
      { "sCursorCoords", "cursorCoords" } }) do
    local want = pairsOf(pair[1])
    eq(#want, 3, pair[1] .. " parsed from pret")
    for i = 1, #want do
      eq(man[pair[2]][i][1] .. "," .. man[pair[2]][i][2], want[i][1] .. "," .. want[i][2], pair[1] .. "[" .. (i - 1) .. "]")
    end
  end
else
  print("emerald_starter_choose_test: pret source not found, coordinate parse skipped")
end

local py = io.popen("python3 -c 'import PIL' 2>/dev/null && echo yes")
local havePil = py and py:read("*l") == "yes"
if py then py:close() end
if not havePil or not io.open(PRET .. "/graphics/starter_choose/tiles.png", "rb") then
  print("emerald_starter_choose_test: python3/PIL or pret graphics missing, pixel compare skipped")
  T.finish()
  return
end

local tmp = os.tmpname()
os.remove(tmp)
os.execute('mkdir -p "' .. tmp .. '"')
for _, key in ipairs({ "grass", "bag", "pokeball", "hand", "circle" }) do
  local out = io.open(tmp .. "/" .. key .. ".png", "wb")
  out:write(files[ROOT .. "/starter_choose/" .. key .. ".png"])
  out:close()
end
local script = [[
import sys, struct
from PIL import Image
tmp, pret = sys.argv[1], sys.argv[2] + "/graphics/starter_choose/"
def idx(p): return Image.open(p).load(), Image.open(p).size
bad = {}
sel, (sw, sh) = idx(pret + "pokeball_selection.png")
for key, y0, n in (("pokeball", 0, 96), ("hand", 96, 32)):
    px, _ = idx(tmp + "/" + key + ".png")
    bad[key] = sum(1 for y in range(n) for x in range(32) if px[x, y] != sel[x, y0 + y])
cir, _ = idx(pret + "starter_circle.png")
px, _ = idx(tmp + "/circle.png")
bad["circle"] = sum(1 for y in range(64) for x in range(64) if px[x, y] != cir[x, y])
tiles, (tw, th) = idx(pret + "tiles.png")
for key, binf in (("grass", "birch_grass.bin"), ("bag", "birch_bag.bin")):
    raw = open(pret + binf, "rb").read()
    px, _ = idx(tmp + "/" + key + ".png")
    n = 0
    for ty in range(20):
        for tx in range(32):
            i = ty * 32 + tx
            if i * 2 + 1 >= len(raw): continue
            e = struct.unpack_from("<H", raw, i * 2)[0]
            tile, hf, vf, bank = e & 0x3FF, (e >> 10) & 1, (e >> 11) & 1, e >> 12
            for yy in range(8):
                for xx in range(8):
                    sx = 7 - xx if hf else xx
                    sy = 7 - yy if vf else yy
                    col = (tile % (tw // 8)) * 8 + sx
                    row = (tile // (tw // 8)) * 8 + sy
                    v = tiles[col, row] % 16 if row < th else 0
                    want = bank * 16 + v if v else 0
                    got = px[tx * 8 + xx, ty * 8 + yy]
                    if key == "grass" and v == 0: continue
                    if got != want: n += 1
    bad[key] = n
print(" ".join("%s=%d" % (k, bad[k]) for k in sorted(bad)))
]]
local sf = io.open(tmp .. "/cmp.py", "wb")
sf:write(script)
sf:close()
local p = io.popen('python3 "' .. tmp .. '/cmp.py" "' .. tmp .. '" "' .. PRET .. '" 2>&1')
local line = p and p:read("*a") or ""
if p then p:close() end
print("emerald_starter_choose_test: differing pixels " .. line:gsub("%s+$", ""))
for _, key in ipairs({ "pokeball", "hand", "circle", "grass", "bag" }) do
  eq(tonumber(line:match(key .. "=(%d+)")), 0, key .. " matches pret graphics/starter_choose pixel for pixel")
end
os.execute('rm -f "' .. tmp .. '"/*.png "' .. tmp .. '"/cmp.py; rmdir "' .. tmp .. '"')

T.finish()
