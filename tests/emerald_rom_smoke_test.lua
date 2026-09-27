package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_rom_smoke_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local rom = f:read("*a")
f:close()

local function u8(off) return rom:byte(off + 1) end
local function u32(off)
  local a, b, c, d = rom:byte(off + 1, off + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end

local CHARS = { [0x00] = " " }
for i = 0, 25 do CHARS[0xBB + i] = string.char(65 + i) end
for i = 0, 9 do CHARS[0xA1 + i] = string.char(48 + i) end
local function text(off, max)
  local out = {}
  for i = 0, max - 1 do
    local b = u8(off + i)
    if b == 0xFF then break end
    out[#out + 1] = CHARS[b] or "?"
  end
  return table.concat(out)
end

eq(rom:sub(0xAD, 0xB0), "BPEE", "header game code")
eq(#rom, 16777216, "16 MiB ROM")

local V = require("src.import.gba.games.emerald")
eq(text(V.SPECIES_NAMES + 1 * (V.SPECIES_NAME_LENGTH), V.SPECIES_NAME_LENGTH), "BULBASAUR", "species 1 name")
eq(text(V.ITEMS + 1 * V.ITEM_STRIDE, 14), "MASTER BALL", "item 1 name")
eq(text(V.MOVE_NAMES + 1 * (V.MOVE_NAME_LENGTH + 1), V.MOVE_NAME_LENGTH + 1), "POUND", "move 1 name")
eq(V.NUM_MAP_GROUPS, 34, "34 map groups")
local pointers = 0
for i = 0, V.NUM_MAP_GROUPS - 1 do
  local p = u32(V.G_MAP_GROUPS + i * 4)
  if p >= 0x08000000 and p < 0x0A000000 then pointers = pointers + 1 end
end
eq(pointers, 34, "every map group entry is a ROM pointer")
local group0 = u32(V.G_MAP_GROUPS) - 0x08000000
local header0 = u32(group0) - 0x08000000
local layout = u32(header0) - 0x08000000
eq(u32(layout), 30, "group 0 map 0 (Petalburg City) layout is 30 wide")
eq(u32(layout + 4), 30, "group 0 map 0 layout is 30 tall")
local std0 = u32(V.STD_SCRIPTS)
check(std0 >= 0x08000000 and std0 < 0x0A000000, "gStdScripts[0] is a ROM pointer")

T.finish("emerald_rom_smoke_test")
