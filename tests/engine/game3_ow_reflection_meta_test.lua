package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local check, eq = T.check, T.eq
local OwExtract = require("src.import.gba.ow_extract")
local Versions = require("src.import.gba.versions")

local priorVersion = Versions.active()
Versions.select("leafgreen")
eq(Versions.OW_REFLECTION.palette_map, 0x35B914, "LeafGreen ROM profile resolves the palette map")
eq(Versions.OW_REFLECTION.player_palette_sets, 0x3A51E8,
  "LeafGreen ROM profile resolves player paired palettes")
eq(Versions.OW_REFLECTION.special_palette_sets, 0x3A5258,
  "LeafGreen ROM profile resolves special paired palettes")
eq(Versions.OW_REFLECTION.palette_tag_sets, 0x3A5310,
  "LeafGreen ROM profile resolves object palette tag sets")
Versions.select(priorVersion)

local bytes = {}
local function put8(offset, value) bytes[offset] = value % 256 end
local function put16(offset, value)
  put8(offset, value)
  put8(offset + 1, math.floor(value / 256))
end
local function put32(offset, value)
  put16(offset, value % 65536)
  put16(offset + 2, math.floor(value / 65536))
end
local fakeRom = { size = 0x1000 }
function fakeRom:get(offset) return bytes[offset] or 0 end
function fakeRom:u16(offset) return fakeRom:get(offset) + fakeRom:get(offset + 1) * 256 end
function fakeRom:u32(offset)
  return fakeRom:u16(offset) + fakeRom:u16(offset + 2) * 65536
end

local offsets = {
  palette_map = 0x100,
  palette_tag_sets = 0x200,
  player_palette_sets = 0x240,
  special_palette_sets = 0x250,
  palette_map_count = 16,
  palette_set_count = 4,
  palette_tag_slot_count = 10,
  paired_palette_stride = 8,
  paired_palette_count = 4,
}
for slot = 0, 15 do put8(offsets.palette_map + slot, slot) end
put8(offsets.palette_map + 3, 7)
for set = 0, 3 do
  local row = 0x300 + set * 0x20
  put32(offsets.palette_tag_sets + set * 4, 0x08000000 + row)
  for slot = 0, 9 do put16(row + slot * 2, 0x1200 + slot) end
end
put16(0x300 + 7 * 2, 0x1107)
local playerTags, specialTags = 0x400, 0x410
put32(offsets.player_palette_sets + 4, 0x08000000 + playerTags)
put32(offsets.special_palette_sets + 4, 0x08000000 + specialTags)
put16(offsets.player_palette_sets, 0x1100)
put16(offsets.special_palette_sets, 0x110B)
put16(offsets.player_palette_sets + 8, 0x11FF)
put16(offsets.special_palette_sets + 8, 0x11FF)
put16(playerTags, 0x1101)
put16(specialTags, 0x110C)
local reflectionMappings = OwExtract.loadReflectionMappings(fakeRom, offsets)
eq(OwExtract.reflectionPaletteTag({ paletteSlot = 3, paletteTag = 0x1133 }, reflectionMappings),
  0x1107, "ordinary slots use ROM slot map and tag set")
eq(OwExtract.reflectionPaletteTag({ paletteSlot = 0, paletteTag = 0x1100 }, reflectionMappings),
  0x1101, "player mapping uses ROM PairedPalettes")
eq(OwExtract.reflectionPaletteTag({ paletteSlot = 10, paletteTag = 0x110B }, reflectionMappings),
  0x110C, "special mapping uses ROM PairedPalettes")

local source, rawReflection, mappedReflection = {}, {}, {}
for c = 0, 15 do
  source[c] = c * 17
  rawReflection[c] = c * 23
  mappedReflection[c] = c * 31
end
local blob = OwExtract.encodeMeta({
  graphicsId = 7,
  width = 16,
  height = 32,
  frameCount = 3,
  paletteTag = 0x1100,
  reflectionPaletteTag = 0x1102,
  paletteSlot = 0,
  reflectionPaletteMappedTag = 0x1101,
  palette = source,
  reflectionPalette = rawReflection,
  mappedReflectionPalette = mappedReflection,
})
local meta = OwExtract.decodeMeta(blob)
check(meta ~= nil, "reflection metadata decodes")
eq(meta.formatVersion, 3, "new metadata format is explicit")
eq(meta.paletteTag, 0x1100, "base palette tag is retained")
eq(meta.reflectionPaletteTag, 0x1102, "ROM reflection palette tag is retained")
eq(meta.paletteSlot, 0, "ROM palette slot is retained")
eq(meta.reflectionPaletteMappedTag, 0x1101, "player palette mapping is retained")
eq(meta.palette[8], source[8], "base palette color is retained")
eq(meta.reflectionPalette[8], rawReflection[8], "graphics-info reflection palette color is retained")
eq(meta.mappedReflectionPalette[8], mappedReflection[8], "mapped reflection color is retained")
local unavailable = OwExtract.decodeMeta(OwExtract.encodeMeta({
  graphicsId = 8,
  width = 16,
  height = 32,
  frameCount = 1,
  paletteTag = 0x1100,
  palette = source,
}))
check(unavailable ~= nil, "metadata without a mapped reflection palette decodes")
eq(unavailable.reflectionPaletteMappedTag, nil, "missing mapped palette stays unavailable")
eq(unavailable.reflectionPalette, nil, "missing palette colors are not synthesized")
eq(unavailable.mappedReflectionPalette, nil, "missing mapped colors are not synthesized")
T.finish("game3_ow_reflection_meta_test")
