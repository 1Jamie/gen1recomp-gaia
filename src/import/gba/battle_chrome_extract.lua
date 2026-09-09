-- Bake FRLG battle interface chrome from ROM into data/generated/gba/pokemon/battle/.
-- Healthboxes are OAM-assembled (pret CreateBattlerHealthboxSprites): two side-by-side
-- sprites, not a flat 128-wide sheet blit.

local Versions = require("src.import.gba.versions")
local Lz77 = require("src.import.gba.lz77")

local BattleChromeExtract = {}

BattleChromeExtract.FORMAT_VERSION = 4
BattleChromeExtract.CACHE_SUB = "pokemon/battle"

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

local function bytes_to_array(tbl)
  if type(tbl) == "string" then
    local t = {}
    for i = 1, #tbl do t[i] = tbl:byte(i) end
    return t
  end
  return tbl
end

local function load_pal(bytes, count)
  bytes = bytes_to_array(bytes)
  local pal = {}
  for c = 0, (count or 16) - 1 do
    local i = c * 2 + 1
    pal[c] = (bytes[i] or 0) + (bytes[i + 1] or 0) * 256
  end
  return pal
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

local function indices_to_rgba(indices, pal, w, h)
  local chunks = {}
  for i = 1, w * h do
    local idx = indices[i] or 0
    if idx == 0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local r, g, b = bgr555_to_rgb8(pal[idx] or 0)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks)
end

--- GBA OAM multi-tile blit: tiles arranged row-major in an (tilesW × tilesH) grid.
local function blit_oam_rect(gfx, pal, tileStart, tilesW, tilesH, dest, destX, destY, destW)
  gfx = bytes_to_array(gfx)
  local tileCount = math.floor(#gfx / 32)
  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local ti = tileStart + ty * tilesW + tx
      if ti >= 0 and ti < tileCount then
        local tile = {}
        local base = ti * 32
        for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
        local tmp = {}
        for i = 1, 64 do tmp[i] = 0 end
        decode_tile_4bpp(tile, tmp, 0, 0, 8, false, false)
        for row = 0, 7 do
          for col = 0, 7 do
            local idx = tmp[row * 8 + col + 1] or 0
            if idx ~= 0 then
              local dx = destX + tx * 8 + col
              local dy = destY + ty * 8 + row
              dest[dy * destW + dx + 1] = idx
              -- stash palette via parallel not needed; single pal
            end
          end
        end
      end
    end
  end
end

--- Player singles: two 64×64 sprites, other at x+64 (SpriteCB_HealthBoxOther).
local function bake_player_healthbox(gfx, pal)
  local w, h = 128, 64
  local indices = {}
  for i = 1, w * h do indices[i] = 0 end
  blit_oam_rect(gfx, pal, 0, 8, 8, indices, 0, 0, w)
  blit_oam_rect(gfx, pal, 64, 8, 8, indices, 64, 0, w)
  return indices_to_rgba(indices, pal, w, h), w, h
end

--- Enemy singles: two 64×32 sprites (default OAM), other at x+64, tileNum+=32.
local function bake_enemy_healthbox(gfx, pal)
  local w, h = 128, 32
  local indices = {}
  for i = 1, w * h do indices[i] = 0 end
  blit_oam_rect(gfx, pal, 0, 8, 4, indices, 0, 0, w)
  blit_oam_rect(gfx, pal, 32, 8, 4, indices, 64, 0, w)
  return indices_to_rgba(indices, pal, w, h), w, h
end

local function bake_sheet_rgba(gfx, pal, w, h)
  gfx = bytes_to_array(gfx)
  local tilesW, tilesH = math.floor(w / 8), math.floor(h / 8)
  local indices = {}
  for i = 1, w * h do indices[i] = 0 end
  local ti = 0
  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local tile = {}
      local base = ti * 32
      for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
      decode_tile_4bpp(tile, indices, tx * 8, ty * 8, w, false, false)
      ti = ti + 1
    end
  end
  return indices_to_rgba(indices, pal, w, h)
end

local function bake_tilemap_rgba(gfx, palBytes, map, mapTilesW, mapTilesH, opts)
  opts = opts or {}
  gfx = bytes_to_array(gfx)
  map = bytes_to_array(map)
  palBytes = bytes_to_array(palBytes)
  local tileCount = math.floor(#gfx / 32)
  local bankCount = math.max(1, math.floor(#palBytes / 32))
  local banks = {}
  for b = 0, bankCount - 1 do
    local slice = {}
    for i = 1, 32 do slice[i] = palBytes[b * 32 + i] or 0 end
    banks[b] = load_pal(slice, 16)
  end

  local W, H = mapTilesW * 8, mapTilesH * 8
  local indices, pals = {}, {}
  for i = 1, W * H do indices[i] = 0; pals[i] = 0 end
  for ty = 0, mapTilesH - 1 do
    for tx = 0, mapTilesW - 1 do
      local mi = (ty * mapTilesW + tx) * 2 + 1
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
          local di = (ty * 8 + row) * W + (tx * 8 + col) + 1
          indices[di] = tmp[row * 8 + col + 1] or 0
          pals[di] = palNum
        end
      end
    end
  end
  local transparent0 = opts.transparent0 ~= false
  -- Terrain pals load at BG_PLTT_ID(2); textbox at BG_PLTT_ID(0).
  local bgPalBase = opts.bgPalBase or 0
  local chunks = {}
  for i = 1, W * H do
    local idx = indices[i] or 0
    if idx == 0 and transparent0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local palNum = pals[i] or 0
      local bi = palNum - bgPalBase
      if bi < 0 or bi >= bankCount then
        bi = math.max(0, math.min(bankCount - 1, palNum))
      end
      local bank = banks[bi] or banks[0]
      local r, g, b = bgr555_to_rgb8(bank[idx] or 0)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks), W, H
end

local function read_raw(rom, off, n)
  local t = {}
  for i = 0, n - 1 do t[i + 1] = rom:get(off + i) end
  return t
end

function BattleChromeExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. BattleChromeExtract.CACHE_SUB
  local cfg = Versions.BATTLE_UI
  local function get(i) return rom:get(i) end

  local tbGfx = Lz77.decompress(get, cfg.textbox_gfx)
  local tbPal = Lz77.decompress(get, cfg.textbox_pal)
  local tbMap = Lz77.decompress(get, cfg.textbox_tilemap)
  local textboxRgba, tw, th = bake_tilemap_rgba(tbGfx, tbPal, tbMap, 32, 64)
  cache:write(root .. "/textbox.rgba", textboxRgba)

  -- Healthbox pals are uncompressed INCBIN_U16 (not LZ).
  local hbPal = load_pal(read_raw(rom, cfg.healthbox_pal, 32), 16)
  local barPal = load_pal(read_raw(rom, cfg.healthbar_pal, 32), 16)
  local playerGfx = Lz77.decompress(get, cfg.healthbox_player)
  local enemyGfx = Lz77.decompress(get, cfg.healthbox_enemy)
  local playerRgba = bake_player_healthbox(playerGfx, hbPal)
  local enemyRgba = bake_enemy_healthbox(enemyGfx, hbPal)
  cache:write(root .. "/healthbox_player.rgba", playerRgba)
  cache:write(root .. "/healthbox_enemy.rgba", enemyRgba)

  local elGfx = read_raw(rom, cfg.healthbox_elements, 320 * 24 / 2)
  -- HP bar sprite uses TAG_HEALTHBAR_PAL; EXP is blitted into the healthbox
  -- which uses TAG_HEALTHBOX_PAL (cyan/blue fill). Bake both.
  cache:write(root .. "/elements.rgba", bake_sheet_rgba(elGfx, barPal, 320, 24))
  cache:write(root .. "/elements_exp.rgba", bake_sheet_rgba(elGfx, hbPal, 320, 24))

  -- Terrains (BG2). Palettes load at BG_PLTT_ID(2) → tilemap palNum 2/3/4.
  local terrains = {
    { key = "grass", cfg = cfg.terrain_grass },
    { key = "building", cfg = cfg.terrain_building },
  }
  local terrainMeta = {}
  for _, t in ipairs(terrains) do
    local tr = t.cfg
    if tr then
      local tGfx = Lz77.decompress(get, tr.tiles)
      local tPal = Lz77.decompress(get, tr.pal)
      local tMap = Lz77.decompress(get, tr.tilemap)
      local rgba, trW, trH = bake_tilemap_rgba(tGfx, tPal, tMap, 32, 32, {
        transparent0 = false,
        bgPalBase = 2,
      })
      cache:write(root .. "/terrain_" .. t.key .. ".rgba", rgba)
      terrainMeta[t.key] = { w = trW, h = trH }
    end
  end

  local grass = terrainMeta.grass or { w = 256, h = 256 }
  local building = terrainMeta.building or grass

  -- Party summary bar (128×8); balls use elements tiles 66..69.
  if cfg.party_summary_bar then
    local barGfx = Lz77.decompress(get, cfg.party_summary_bar)
    cache:write(root .. "/party_summary_bar.rgba", bake_sheet_rgba(barGfx, hbPal, 128, 8))
  end

  local manifest = string.format([[return {
  format = %d,
  textboxW = %d, textboxH = %d,
  terrainW = %d, terrainH = %d,
  terrains = {
    grass = { file = "terrain_grass.rgba", w = %d, h = %d },
    building = { file = "terrain_building.rgba", w = %d, h = %d },
  },
  partySummaryBar = { file = "party_summary_bar.rgba", w = 128, h = 8 },
  partyBarPlayer = { x = 136, y = 96 },
  partyBarOpponent = { x = 104, y = 40 },
  -- pret InitBattlerHealthboxCoords / sBattlerCoords (singles)
  -- Player TL uses stale 64x32 centerToCorner (−32,−16) even though shape is 64x64
  playerBox = { w = 128, h = 64, x = 158, y = 88 },
  enemyBox = { w = 128, h = 32, x = 44, y = 30 },
  -- Sprite centers before pic y_offset; final Y = base + y_offset [+8 player]
  playerSprite = { x = 72, y = 80 },
  enemySprite = { x = 176, y = 40 },
  -- HP bar: subsprite origin (center−16, center) relative to box TL
  playerHpBar = { x = 32, y = 16, pixels = 48 },
  enemyHpBar = { x = 24, y = 16, pixels = 48 },
  playerExpBar = { x = 32, y = 32, pixels = 64 },
  hpBarPixels = 48,
  expBarPixels = 64,
  msgY = 120,
  panelH = 40,
}
]], BattleChromeExtract.FORMAT_VERSION, tw, th,
    grass.w, grass.h,
    grass.w, grass.h,
    building.w, building.h)
  cache:write(root .. "/manifest.lua", manifest)

  return { root = root, textboxW = tw, textboxH = th }
end

function BattleChromeExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/" .. BattleChromeExtract.CACHE_SUB
  if cache and cache.exists and cache:exists(root .. "/manifest.lua")
      and cache:exists(root .. "/healthbox_player.rgba")
      and cache:exists(root .. "/terrain_building.rgba") then
    return true
  end
  return false
end

return BattleChromeExtract
