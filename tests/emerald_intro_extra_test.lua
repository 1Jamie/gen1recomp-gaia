package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_intro_extra_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_intro_extra_test: skipped (" .. ROM_PATH .. " is not Emerald)")
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

local M = require("src.import.gba.rse.extract_intro_extra_emerald")
local ROOT = "data/generated/gba"
check(not M.ready(cache, ROOT), "not ready before run")
local ok, man = M.run(rom, cache, { cacheRoot = ROOT })
eq(ok, true, "extractor ran")
check(M.ready(cache, ROOT), "ready after run")
for _, rel in ipairs(M.REQUIRED) do
  check(files[ROOT .. "/" .. rel] ~= nil, "wrote " .. rel)
end

local aff = man.gfAffineAnims
eq(#aff, 4, "four Game Freak affine anims")
eq(aff[2][2].xScale, 16, "grow step x")
eq(aff[2][2].duration, 16, "grow step duration")
eq(aff[2][3].xScale, -16, "shrink step x")
eq(aff[3][1].xScale, 256, "grow big starts at unit scale")
eq(aff[4][2].xScale, 2, "logo grows by 2")
eq(aff[1][2].op, "end", "small anim ends")

local bike = man.playerBicycleAnims
eq(bike[1][1].duration, 4, "fast bicycle frames last 4")
eq(bike[1][2].frame, 1, "second bicycle frame is 64 tiles in")
eq(bike[1][5].op, "jump", "fast bicycle loops")

eq(man.waterDropRipple.w, 64, "ripple frame width")
eq(man.waterDropRipple.h, 32, "ripple frame height")
eq(man.groudonRocks.w, 32, "rock sprite width")
eq(man.groudonRocks.tileTag, 10058, "ANIM_TAG_ROCKS")
eq(#man.groudonRocks.anims, 6, "six rock anims")
eq(#man.palettes.rocks, 16, "rock palette")

T.finish()
