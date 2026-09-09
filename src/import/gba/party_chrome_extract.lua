-- Bake FRLG party-menu chrome from ROM into extract/v1/pokemon/party/.
-- BG tilemap + slot panels (slot_*.bin) + pokéball frames.

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")

local PartyChromeExtract = {}

PartyChromeExtract.CACHE_SUB = "pokemon/party"

local SLOT_PATHS = {
  main = {},
  wide = {},
  empty = {},
}

local DEFAULT_SLOT_MAIN = string.char(
  24, 25, 25, 25, 25, 25, 25, 25, 25, 26,
  32, 33, 33, 33, 33, 33, 33, 33, 33, 34,
  32, 33, 33, 33, 33, 33, 33, 33, 33, 34,
  32, 33, 33, 33, 33, 33, 33, 33, 33, 34,
  40, 59, 60, 58, 58, 58, 58, 58, 58, 61,
  15, 16, 16, 16, 16, 16, 16, 16, 16, 17,
  46, 47, 47, 47, 47, 47, 47, 47, 47, 48
)

local DEFAULT_SLOT_WIDE = string.char(
  43, 44, 44, 44, 44, 44, 44, 44, 44, 44, 44, 44, 44, 44, 44, 44, 44, 45,
  49, 33, 33, 33, 33, 33, 33, 33, 33, 52, 53, 51, 51, 51, 51, 51, 51, 54,
  55, 56, 56, 56, 56, 56, 56, 56, 56, 56, 56, 56, 56, 56, 56, 56, 56, 57
)

local DEFAULT_SLOT_WIDE_EMPTY = string.char(
  21, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 23,
  30,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0,  0, 31,
  37, 38, 38, 38, 38, 38, 38, 38, 38, 38, 38, 38, 38, 38, 38, 38, 38, 39
)

local STATUS_ICON_PATHS = {}

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
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

local function decode_tile_4bpp(tileBytes, out, baseX, baseY, stride, hflip, vflip)
  for row = 0, 7 do
    local srcRow = vflip and (7 - row) or row
    for bx = 0, 3 do
      local byte = tileBytes[srcRow * 4 + bx + 1] or 0
      local p0 = byte % 16
      local p1 = math.floor(byte / 16) % 16
      local x0 = bx * 2
      local x1 = x0 + 1
      if hflip then
        x0, x1 = 7 - x0, 7 - x1
      end
      out[(baseY + row) * stride + (baseX + x0) + 1] = p0
      out[(baseY + row) * stride + (baseX + x1) + 1] = p1
    end
  end
end

local function load_pal_banks(bytes, count)
  local banks = {}
  for b = 0, count - 1 do
    local colors = {}
    local off = b * 32
    for c = 0, 15 do
      local i = off + c * 2 + 1
      colors[c] = (bytes[i] or 0) + (bytes[i + 1] or 0) * 256
    end
    banks[b] = colors
  end
  return banks
end

local function read_bin(candidates)
  for _, p in ipairs(candidates) do
    local f = io.open(p, "rb")
    if f then
      local d = f:read("*a")
      f:close()
      if d then return d end
    end
  end
  return nil
end

local function bake_bg_rgba(gfx, palBytes, map, W, H)
  local tileCount = math.floor(#gfx / 32)
  local banks = load_pal_banks(palBytes, math.floor(#palBytes / 32))
  local mapW = 32
  local indices, pals = {}, {}
  for i = 1, W * H do indices[i] = 0; pals[i] = 0 end

  local tilesH = math.min(32, math.floor(H / 8))
  local tilesW = math.min(32, math.floor(W / 8))
  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local mi = (ty * mapW + tx) * 2 + 1
      local entry = (map[mi] or 0) + (map[mi + 1] or 0) * 256
      local tileId = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      local palNum = math.floor(entry / 4096) % 16
      if tileId >= tileCount then tileId = 0 end
      local tile = {}
      local base = tileId * 32
      for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
      local tmp = {}
      for i = 1, 64 do tmp[i] = 0 end
      decode_tile_4bpp(tile, tmp, 0, 0, 8, hflip, vflip)
      for row = 0, 7 do
        for col = 0, 7 do
          local px, py = tx * 8 + col, ty * 8 + row
          if px < W and py < H then
            local di = py * W + px + 1
            indices[di] = tmp[row * 8 + col + 1] or 0
            pals[di] = palNum
          end
        end
      end
    end
  end

  local chunks = {}
  for i = 1, W * H do
    local idx = indices[i] or 0
    local bank = banks[pals[i] or 0] or banks[0]
    local c = bank and bank[idx] or 0
    local r, g, b = bgr555_to_rgb8(c)
    chunks[i] = string.char(r, g, b, 255)
  end
  return table.concat(chunks)
end

--- Blit slot tilemap (u8 tile ids) using party BG gfx + one pal bank.
-- Color 0 → transparent (window chrome).
local function bake_slot_rgba(gfx, palBytes, tilemap, tilesW, tilesH, palBank)
  local W, H = tilesW * 8, tilesH * 8
  local banks = load_pal_banks(palBytes, math.floor(#palBytes / 32))
  local pal = banks[palBank] or banks[0] or {}
  local tileCount = math.floor(#gfx / 32)
  local pixels = {}
  for i = 1, W * H do pixels[i] = 0 end

  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local tileId = tilemap:byte(ty * tilesW + tx + 1) or 0
      if tileId >= tileCount then tileId = 0 end
      local tile = {}
      local base = tileId * 32
      for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
      decode_tile_4bpp(tile, pixels, tx * 8, ty * 8, W, false, false)
    end
  end

  local chunks = {}
  for i = 1, W * H do
    local idx = pixels[i] or 0
    if idx == 0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local r, g, b = bgr555_to_rgb8(pal[idx] or 0)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks), W, H
end

--- Two 32×32 frames (closed / open) stacked vertically.
local function bake_ball_sheet(gfx, palBytes)
  local fw, fh = 32, 32
  local banks = load_pal_banks(palBytes, math.max(1, math.floor(#palBytes / 32)))
  local pal = banks[0] or {}
  local tileCount = math.floor(#gfx / 32)
  local sheetH = fh * 2
  local pixels = {}
  for i = 1, fw * sheetH do pixels[i] = 0 end

  for frame = 0, 1 do
    local ti = frame * 16 -- 16 tiles per 32×32
    for ty = 0, 3 do
      for tx = 0, 3 do
        if ti < tileCount then
          local tile = {}
          local base = ti * 32
          for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
          decode_tile_4bpp(tile, pixels, tx * 8, frame * fh + ty * 8, fw, false, false)
        end
        ti = ti + 1
      end
    end
  end

  local chunks = {}
  for i = 1, fw * sheetH do
    local idx = pixels[i] or 0
    if idx == 0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local r, g, b = bgr555_to_rgb8(pal[idx] or 0)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks), fw, sheetH, 2
end

function PartyChromeExtract.run(rom, cache, opts)
  opts = opts or {}
  local root = (opts.cacheRoot or default_cache_root()) .. "/" .. PartyChromeExtract.CACHE_SUB
  local W = opts.width or 240
  local H = opts.height or 160

  local function get(i) return rom:get(i) end
  local gfx = Lz77.decompress(get, Versions.PARTY_MENU_BG_GFX)
  local pal = Lz77.decompress(get, Versions.PARTY_MENU_BG_PAL)
  local map = Lz77.decompress(get, Versions.PARTY_MENU_BG_TILEMAP)
  cache:write(root .. "/bg.rgba", bake_bg_rgba(gfx, pal, map, W, H))

  local mainBin = read_bin(SLOT_PATHS.main) or DEFAULT_SLOT_MAIN
  local wideBin = read_bin(SLOT_PATHS.wide) or DEFAULT_SLOT_WIDE
  local emptyBin = read_bin(SLOT_PATHS.empty) or DEFAULT_SLOT_WIDE_EMPTY
  if not mainBin then
    error("party chrome: missing slot_main data")
  end
  if mainBin and #mainBin >= 70 then
    -- Window pals 3–8 are remapped party-box colors; bank 3 is the blue unselected look.
    local rgba = bake_slot_rgba(gfx, pal, mainBin, 10, 7, 3)
    cache:write(root .. "/slot_main.rgba", rgba)
  end
  if wideBin and #wideBin >= 54 then
    local rgba = bake_slot_rgba(gfx, pal, wideBin, 18, 3, 3)
    cache:write(root .. "/slot_wide.rgba", rgba)
  end
  if emptyBin and #emptyBin >= 54 then
    local rgba = bake_slot_rgba(gfx, pal, emptyBin, 18, 3, 3)
    cache:write(root .. "/slot_wide_empty.rgba", rgba)
  end

  local ballGfx = Lz77.decompress(get, Versions.PARTY_MENU_BALL_GFX)
  local ballPal = Lz77.decompress(get, Versions.PARTY_MENU_BALL_PAL)
  local ballRgba, bw, bh, frames = bake_ball_sheet(ballGfx, ballPal)
  cache:write(root .. "/status_balls.rgba", ballRgba)

  local statusPng = read_bin(STATUS_ICON_PATHS)
  if statusPng then
    cache:write(root .. "/status_icons.png", statusPng)
  end

  local manifest = string.format(
    "return {\n  width = %d, height = %d,\n  ballW = %d, ballSheetH = %d, ballFrames = %d,\n  slotMainW = 80, slotMainH = 56,\n  slotWideW = 144, slotWideH = 24,\n  pokemonVersion = %d,\n}\n",
    W, H, bw, bh, frames or 2, Versions.POKEMON_VERSION or 1)
  cache:write(root .. "/manifest.lua", manifest)

  return {
    root = root, width = W, height = H,
    ballW = bw, ballSheetH = bh, ballFrames = frames,
  }
end

function PartyChromeExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. PartyChromeExtract.CACHE_SUB
  local need = root .. "/slot_main.rgba"
  if cache and cache.exists and cache:exists(need) then return true end
  return false
end

return PartyChromeExtract
