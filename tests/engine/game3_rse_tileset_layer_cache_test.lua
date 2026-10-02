package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Anim = require("src.core.game3.tileset_anim")
local Pack = require("src.import.gba.native_pack")
local Versions = require("src.import.gba.versions")
Versions.NATIVE_RENDER, Versions.TILESET_ANIM = true, true

local function imageData(w, h, _, rgba)
  local data = { rgba = rgba or string.rep("\0", w * h * 4) }
  function data:paste(piece, dx, dy, sx, sy, sw, sh)
    for y = 0, sh - 1 do
      local dst = ((dy + y) * w + dx) * 4
      local src = ((sy + y) * 16 + sx) * 4
      self.rgba = self.rgba:sub(1, dst) .. piece.rgba:sub(src + 1, src + sw * 4)
        .. self.rgba:sub(dst + sw * 4 + 1)
    end
  end
  return data
end
love = { image = { newImageData = imageData } }

local pals = {}
for p = 0, 15 do
  pals[p] = {}
  for c = 0, 15 do pals[p][c] = 0 end
end
pals[0][1], pals[0][2] = 31, 31 * 1024
local files = {
  ["anim_manifest.lua"] = [[return { family = "rse",
    counters = { primary = { max = 256 }, secondary = { max = 256 } },
    banks = { { name = "electric_gates", kind = "tiles", counter = "secondary",
      period = 2, frames = 2, file = "floor.idx", overFile = "gates.idx",
      mids = {1}, quads = {3}, overMids = {2}, overQuads = {12} } } }]],
  ["palettes.bin"] = Pack.encodePalettes(pals),
  ["floor.idx"] = string.rep("\1", 256) .. string.rep("\2", 256),
  ["gates.idx"] = string.rep("\0", 128) .. "\2" .. string.rep("\0", 127)
    .. string.rep("\0", 128) .. "\1" .. string.rep("\0", 127),
}
local cache = { read = function(_, path) return files[path:match("([^/]+)$")] end }
local atlas = { cols = 2, midToSlot = { [1] = 0, [2] = 1 },
  imageData = imageData(32, 16), overImageData = imageData(32, 16) }
Anim.install(cache)
T.check(Anim.bindPair("test_gym", atlas), "mixed floor/foreground animation binds")
local function pixel(data, x, y)
  local offset = (y * 32 + x) * 4
  return data.rgba:sub(offset + 1, offset + 4)
end
local red, blue = string.char(255, 0, 0, 255), string.char(0, 0, 255, 255)
local clear = string.rep("\0", 4)
for cycle = 1, 6 do
  Anim.stepRse()
  Anim.stepRse()
  local odd = cycle % 2 == 1
  T.eq(pixel(atlas.imageData, 0, 0), odd and blue or red, "floor keeps its frame " .. cycle)
  T.eq(pixel(atlas.overImageData, 16, 8), odd and red or blue,
    "foreground uses its own frame " .. cycle)
  T.eq(pixel(atlas.overImageData, 17, 8), clear,
    "foreground transparent pixels preserve sprites " .. cycle)
  T.eq(pixel(atlas.overImageData, 16, 0), clear,
    "foreground quadrant mask preserves untouched pixels " .. cycle)
end
T.finish()
