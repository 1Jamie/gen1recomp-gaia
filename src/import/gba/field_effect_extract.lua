-- Extract FRLG tall-grass + Pokemon Center heal field-effect gfx.
-- Tall grass: 5×16×16 @ gFieldEffectObjectPic_TallGrass + general_1 palette.
-- Heal machine art is vendored as PNG under chrome/field_effects/ (pret pics).

local Versions = require("src.import.gba.versions")

local FieldEffectExtract = {}

FieldEffectExtract.FORMAT_VERSION = 1
FieldEffectExtract.FRAME_W = 16
FieldEffectExtract.FRAME_H = 16
FieldEffectExtract.FRAME_COUNT = 5
FieldEffectExtract.FRAME_BYTES = 128 -- 4 tiles × 32

local function log(msg)
  print("[gba/field_effects] " .. tostring(msg))
end

local function bgr555_to_rgb8(c)
  c = (tonumber(c) or 0) % 32768
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return math.floor(r5 * 255 / 31 + 0.5),
    math.floor(g5 * 255 / 31 + 0.5),
    math.floor(b5 * 255 / 31 + 0.5)
end

--- Decode one 16×16 4bpp frame (tile order TL, TR, BL, BR).
local function decode_frame(rom, off)
  local w, h = FieldEffectExtract.FRAME_W, FieldEffectExtract.FRAME_H
  local pixels = {}
  for i = 1, w * h do pixels[i] = 0 end
  local function put_tile(tileOff, ox, oy)
    for y = 0, 7 do
      for x = 0, 7 do
        local byteIndex = tileOff + y * 4 + math.floor(x / 2)
        local b = rom:get(byteIndex)
        local idx = (x % 2 == 1) and math.floor(b / 16) % 16 or (b % 16)
        pixels[(oy + y) * w + (ox + x) + 1] = idx
      end
    end
  end
  put_tile(off + 0 * 32, 0, 0)
  put_tile(off + 1 * 32, 8, 0)
  put_tile(off + 2 * 32, 0, 8)
  put_tile(off + 3 * 32, 8, 8)
  return pixels
end

local function load_palette(rom, palOff)
  local rgb = {}
  for i = 0, 15 do
    local c = rom:u16(palOff + i * 2)
    local r, g, b = bgr555_to_rgb8(c)
    rgb[i] = { r, g, b }
  end
  return rgb
end

local function bake_rgba(rom, picOff, palOff, frames)
  frames = frames or FieldEffectExtract.FRAME_COUNT
  local w = FieldEffectExtract.FRAME_W
  local fh = FieldEffectExtract.FRAME_H
  local h = fh * frames
  local rgb = load_palette(rom, palOff)
  local bytes = {}
  for f = 0, frames - 1 do
    local pix = decode_frame(rom, picOff + f * FieldEffectExtract.FRAME_BYTES)
    for i = 1, w * fh do
      local idx = pix[i] or 0
      local a = (idx == 0) and 0 or 255
      local c = rgb[idx] or { 0, 0, 0 }
      bytes[#bytes + 1] = string.char(c[1], c[2], c[3], a)
    end
  end
  return table.concat(bytes), w, h
end

function FieldEffectExtract.writeExtract(rom, cache, root, version)
  root = root or "data/generated/gba"
  version = version or {}
  if not rom or not cache then return nil, "rom and cache required" end

  local picOff = version.field_effect_tall_grass
    or Versions.FIELD_EFFECT_TALL_GRASS
  local palOff = version.field_effect_pal_general_1
    or Versions.FIELD_EFFECT_PAL_GENERAL_1
  if not picOff or not palOff then
    return nil, "missing tall grass / palette offsets"
  end

  local rgba, w, h = bake_rgba(rom, picOff, palOff, FieldEffectExtract.FRAME_COUNT)
  local rel = root .. "/field_effects"
  cache:write(rel .. "/tall_grass.rgba", rgba)
  cache:write(rel .. "/tall_grass.meta", string.format(
    "return { w = %d, h = %d, frames = %d, fw = %d, fh = %d, format = %d }\n",
    w, h, FieldEffectExtract.FRAME_COUNT,
    FieldEffectExtract.FRAME_W, FieldEffectExtract.FRAME_H,
    FieldEffectExtract.FORMAT_VERSION))
  log(string.format("tall_grass %dx%d (%d frames) → %s", w, h, FieldEffectExtract.FRAME_COUNT, rel))

  return { path = rel .. "/tall_grass.rgba", w = w, h = h, frames = FieldEffectExtract.FRAME_COUNT }
end

return FieldEffectExtract
