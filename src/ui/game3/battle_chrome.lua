-- FRLG battle interface chrome (ROM-baked under pokemon/battle/).

local Extract = require("src.import.gba.extract_island1")
local BattleChromeExtract = require("src.import.gba.battle_chrome_extract")

local BattleChrome = {}

BattleChrome._cache = nil
BattleChrome._manifest = nil
BattleChrome._textbox = nil
BattleChrome._playerBox = nil
BattleChrome._enemyBox = nil
BattleChrome._elements = nil
BattleChrome._partyBar = nil
BattleChrome._terrains = {}
BattleChrome._logged = false
BattleChrome._quads = {}

local function cache_root()
  return Extract.CACHE_ROOT or "data/generated/gba"
end

local function battle_root()
  return cache_root() .. "/pokemon/battle"
end

local function log(msg)
  if BattleChrome._logged then return end
  BattleChrome._logged = true
  print("[game3/battle_chrome] " .. tostring(msg))
end

local function resolve_cache(cache)
  if cache and cache.read then return cache end
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    return Dataset.cache()
  end
  return {
    read = function(_, rel)
      local ok, CacheFs = pcall(require, "src.import.CacheFs")
      if ok and CacheFs and CacheFs.readActive then
        return CacheFs.readActive(rel)
      end
      return nil
    end,
  }
end

local function read_bytes(rel)
  local cache = BattleChrome._cache
  if cache and cache.read then
    local d = cache:read(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local d = Dataset.cache():read(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  local ok, CacheFs = pcall(require, "src.import.CacheFs")
  if ok and CacheFs and CacheFs.readActive then
    local d = CacheFs.readActive(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  if love and love.filesystem and love.filesystem.read then
    local d = love.filesystem.read(rel)
    if type(d) == "string" and #d > 0 then return d end
    local alt = "data/generated/gba/" .. (rel:gsub("^data/generated/gba/", ""))
    d = love.filesystem.read(alt)
    if type(d) == "string" and #d > 0 then return d end
  end
  local candidates = {
    rel,
    "data/generated/gba/" .. (rel:gsub("^data/generated/gba/", "")),
  }
  for _, p in ipairs(candidates) do
    local f = io.open(p, "rb")
    if f then
      local d = f:read("*a")
      f:close()
      if d and #d > 0 then return d end
    end
  end
  return nil
end

local function load_lua(rel)
  local src = read_bytes(rel)
  if not src then return nil end
  local chunk = load(src, "@" .. rel, "t", {})
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  if ok then return t end
  return nil
end

local function rgba_to_image(rgba, w, h)
  if not (love and love.image and love.graphics) then return nil end
  if not rgba or #rgba < w * h * 4 then return nil end
  local ok, imageData = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not ok or not imageData then return nil end
  local image = love.graphics.newImage(imageData)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  return image
end

function BattleChrome.install(cache)
  BattleChrome._cache = resolve_cache(cache)
  BattleChrome._manifest = nil
  BattleChrome._textbox = nil
  BattleChrome._playerBox = nil
  BattleChrome._enemyBox = nil
  BattleChrome._elements = nil
  BattleChrome._elementsExp = nil
  BattleChrome._partyBar = nil
  BattleChrome._terrains = {}
  BattleChrome._quads = {}
  BattleChrome._logged = false
  local root = battle_root()
  BattleChrome._manifest = load_lua(root .. "/manifest.lua")
  local m = BattleChrome._manifest or {}
  local tw, th = m.textboxW or 256, m.textboxH or 512
  local tb = read_bytes(root .. "/textbox.rgba")
  local pb = read_bytes(root .. "/healthbox_player.rgba")
  local eb = read_bytes(root .. "/healthbox_enemy.rgba")
  local el = read_bytes(root .. "/elements.rgba")
  local elExp = read_bytes(root .. "/elements_exp.rgba")
  local pbar = read_bytes(root .. "/party_summary_bar.rgba")
  BattleChrome._textbox = rgba_to_image(tb, tw, th)
  BattleChrome._playerBox = rgba_to_image(pb, 128, 64)
  BattleChrome._enemyBox = rgba_to_image(eb, 128, 32)
  BattleChrome._elements = rgba_to_image(el, 320, 24)
  -- EXP bar tiles need healthbox palette (blue); fall back to HP sheet if missing
  BattleChrome._elementsExp = rgba_to_image(elExp, 320, 24) or BattleChrome._elements
  local pinfo = m.partySummaryBar or { w = 128, h = 8 }
  BattleChrome._partyBar = rgba_to_image(pbar, pinfo.w or 128, pinfo.h or 8)
  local terrains = m.terrains or {
    grass = { file = "terrain_grass.rgba", w = m.terrainW or 256, h = m.terrainH or 256 },
  }
  for key, info in pairs(terrains) do
    local rgba = read_bytes(root .. "/" .. (info.file or ("terrain_" .. key .. ".rgba")))
    local img = rgba_to_image(rgba, info.w or 256, info.h or 256)
    local bgRgba = read_bytes(root .. "/terrain_bg_" .. key .. ".rgba")
    local enemyPlatRgba = read_bytes(root .. "/terrain_enemy_" .. key .. ".rgba")
    local playerPlatRgba = read_bytes(root .. "/terrain_player_" .. key .. ".rgba")
    local bgImg = rgba_to_image(bgRgba, 256, 160)
    local enemyPlatImg = rgba_to_image(enemyPlatRgba, 256, 160)
    local playerPlatImg = rgba_to_image(playerPlatRgba, 256, 160)
    if img then
      BattleChrome._terrains[key] = {
        image = img,
        bgImage = bgImg,
        enemyPlat = enemyPlatImg,
        playerPlat = playerPlatImg,
        w = info.w or 256,
        h = info.h or 256,
      }
    end
  end

  if pb and eb and tb and next(BattleChrome._terrains) then
    log("battle chrome ready (v" .. tostring(m.format or "?") .. ")")
  else
    log("battle chrome missing — re-run --pokemon extract")
  end
end

function BattleChrome.ready()
  if BattleChrome._playerBox and next(BattleChrome._terrains) then return true end
  return BattleChromeExtract.ready(BattleChrome._cache, cache_root())
end

function BattleChrome.hasAssets()
  local root = battle_root()
  return read_bytes(root .. "/healthbox_player.rgba") ~= nil
    and read_bytes(root .. "/textbox.rgba") ~= nil
end

function BattleChrome.manifest()
  if not BattleChrome._manifest then BattleChrome.install(BattleChrome._cache) end
  return BattleChrome._manifest or {}
end

--- Draw terrain sheet ("grass" | "building"). Returns false if missing.
-- During intro slide-in:
-- 1. Base clean wallpaper (continuous sky and ground, no platforms).
-- 2. Transparent enemy platform oval sliding with enemyOx (no wrap, no solid bars).
-- 3. Transparent player platform oval sliding with playerOx (no wrap, no solid bars).
-- When at rest (enemyOx == 0, playerOx == 0), draws standard full terrain at (0, 0).
function BattleChrome.drawTerrain(key, enemyOx, playerOx)
  key = key or "building"
  enemyOx = tonumber(enemyOx) or 0
  playerOx = tonumber(playerOx) or 0
  local entry = BattleChrome._terrains[key] or BattleChrome._terrains.building
    or BattleChrome._terrains.grass
  if not entry or not entry.image then return false end

  local qFullKey = "terrain_full_" .. key
  if not BattleChrome._quads[qFullKey] and love and love.graphics then
    BattleChrome._quads[qFullKey] = love.graphics.newQuad(0, 0, 240, 160, entry.w, entry.h)
  end

  if enemyOx == 0 and playerOx == 0 then
    local q = BattleChrome._quads[qFullKey]
    if q then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(entry.image, q, 0, 0)
      return true
    end
    return false
  end

  -- During intro slide, use split transparent platforms over continuous wallpaper
  if entry.bgImage and entry.enemyPlat and entry.playerPlat then
    local qBgKey = "terrain_bg_view_" .. key
    if not BattleChrome._quads[qBgKey] and love and love.graphics then
      BattleChrome._quads[qBgKey] = love.graphics.newQuad(0, 0, 240, 160, 256, 160)
    end
    local qBg = BattleChrome._quads[qBgKey]
    love.graphics.setColor(1, 1, 1, 1)
    if qBg then
      love.graphics.draw(entry.bgImage, qBg, 0, 0)
    end
    love.graphics.draw(entry.enemyPlat, enemyOx, 0)
    love.graphics.draw(entry.playerPlat, playerOx, 0)
    return true
  end

  local q = BattleChrome._quads[qFullKey]
  if q then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(entry.image, q, 0, 0)
    return true
  end
  return false
end

--- Draw clean background wallpaper without battle platforms (e.g. for evolution scene).
function BattleChrome.drawCleanBg(key)
  key = key or "building"
  local entry = BattleChrome._terrains[key] or BattleChrome._terrains.building
    or BattleChrome._terrains.grass
  if not entry then return false end

  if entry.bgImage and love and love.graphics then
    local qBgKey = "terrain_bg_view_" .. key
    if not BattleChrome._quads[qBgKey] then
      BattleChrome._quads[qBgKey] = love.graphics.newQuad(0, 0, 240, 160, 256, 160)
    end
    local qBg = BattleChrome._quads[qBgKey]
    love.graphics.setColor(1, 1, 1, 1)
    if qBg then
      love.graphics.draw(entry.bgImage, qBg, 0, 0)
      return true
    end
  end

  local qFullKey = "terrain_full_" .. key
  if not BattleChrome._quads[qFullKey] and entry.image and love and love.graphics then
    BattleChrome._quads[qFullKey] = love.graphics.newQuad(0, 0, 240, 160, entry.w, entry.h)
  end
  local q = BattleChrome._quads[qFullKey]
  if q and entry.image then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(entry.image, q, 0, 0)
    return true
  end
  return false
end

--- Draw textbox panel: message / action / fight.
--- Tilemap chrome starts at y=112 (not 120); panels are 48px tall, 160px apart.
function BattleChrome.drawPanel(mode)
  if not BattleChrome._textbox then return end
  local scroll = 0
  if mode == "menu" then scroll = 160
  elseif mode == "moves" then scroll = 320 end
  local tw = (BattleChrome._manifest and BattleChrome._manifest.textboxW) or 256
  local th = (BattleChrome._manifest and BattleChrome._manifest.textboxH) or 512
  local key = "panel48_" .. tostring(scroll)
  if not BattleChrome._quads[key] and love and love.graphics then
    local y = 112 + scroll
    if y + 48 > th then y = math.max(0, th - 48) end
    BattleChrome._quads[key] = love.graphics.newQuad(0, y, 240, 48, tw, th)
  end
  local q = BattleChrome._quads[key]
  if q then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(BattleChrome._textbox, q, 0, 112)
  end
end

function BattleChrome.drawEnemyBox(x, y)
  if not BattleChrome._enemyBox then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(BattleChrome._enemyBox, x, y)
end

function BattleChrome.drawPlayerBox(x, y)
  if not BattleChrome._playerBox then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(BattleChrome._playerBox, x, y)
end

function BattleChrome.hpColor(ratio)
  if ratio > 0.5 then return "green" end
  if ratio > 0.2 then return "yellow" end
  return "red"
end

-- Element tile bases (pret B_INTERFACE_GFX_*)
local HP_TEXT_TILE = 1
local HP_BAR_BASE = { green = 3, yellow = 47, red = 56 }
local HP_BAR_TILES = 6
local EXP_BAR_TILE = 12
local EXP_BAR_TILES = 8

local function elements_tile_quad(ti, sheet)
  sheet = sheet or BattleChrome._elements
  if not sheet or not love or not love.graphics then return nil end
  local key = (sheet == BattleChrome._elementsExp and "exp_" or "elt_") .. tostring(ti)
  if not BattleChrome._quads[key] then
    local tw = 40 -- 320/8
    local tx, ty = ti % tw, math.floor(ti / tw)
    BattleChrome._quads[key] = love.graphics.newQuad(tx * 8, ty * 8, 8, 8, 320, 24)
  end
  return BattleChrome._quads[key]
end

local function filled_pixels_for_bar(ratio, numTiles)
  local total = numTiles * 8
  local filled = math.floor(total * ratio + 0.5)
  if filled < 1 and ratio > 0 then filled = 1 end
  local remaining = filled
  local out = {}
  for i = 1, numTiles do
    local pix = math.max(0, math.min(8, remaining))
    remaining = remaining - pix
    out[i] = pix
  end
  return out
end

--- Draw pret HP bar: HP label tiles + 6 fill tiles (48px). Top-left of 64×8 strip.
function BattleChrome.drawHpBar(x, y, ratio)
  if not BattleChrome._elements then return end
  ratio = math.max(0, math.min(1, ratio or 0))
  local color = BattleChrome.hpColor(ratio)
  local base = HP_BAR_BASE[color] or HP_BAR_BASE.green
  local pix = filled_pixels_for_bar(ratio, HP_BAR_TILES)

  love.graphics.setColor(1, 1, 1, 1)
  for i = 0, 1 do
    local q = elements_tile_quad(HP_TEXT_TILE + i)
    if q then love.graphics.draw(BattleChrome._elements, q, x + i * 8, y) end
  end
  for i = 0, HP_BAR_TILES - 1 do
    local q = elements_tile_quad(base + (pix[i + 1] or 0))
    if q then love.graphics.draw(BattleChrome._elements, q, x + 16 + i * 8, y) end
  end
end

function BattleChrome.drawHpFill(x, y, ratio, _pixels)
  BattleChrome.drawHpBar(x - 16, y, ratio)
end

--- Pret EXP bar: 8 element tiles in healthbox VRAM (TAG_HEALTHBOX_PAL → blue).
function BattleChrome.drawExpBar(x, y, ratio)
  local sheet = BattleChrome._elementsExp or BattleChrome._elements
  if not sheet then return end
  ratio = math.max(0, math.min(1, ratio or 0))
  local pix = filled_pixels_for_bar(ratio, EXP_BAR_TILES)
  love.graphics.setColor(1, 1, 1, 1)
  for i = 0, EXP_BAR_TILES - 1 do
    local q = elements_tile_quad(EXP_BAR_TILE + (pix[i + 1] or 0), sheet)
    if q then love.graphics.draw(sheet, q, x + i * 8, y) end
  end
end

function BattleChrome.drawExpFill(x, y, ratio, _pixels)
  BattleChrome.drawExpBar(x, y, ratio)
end

-- Party summary balls: pret B_INTERFACE_GFX_BALL_PARTY_SUMMARY = tile 66.
-- In pokefirered (battle_interface.c:1183-1202):
--   tile 66 (+0): ok (filled normal Pokéball)
--   tile 67 (+1): empty (empty circle outline)
--   tile 68 (+2): status (status ailment circle)
--   tile 69 (+3): faint (fainted dark circle)
local PARTY_BALL_TILE = {
  ok = 66,
  empty = 67,
  status = 68,
  faint = 69,
}

function BattleChrome.drawPartyBall(x, y, kind)
  local ti = PARTY_BALL_TILE[kind or "ok"] or PARTY_BALL_TILE.ok
  local q = elements_tile_quad(ti)
  if not q or not BattleChrome._elements then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(BattleChrome._elements, q, x, y)
end

--- Draw party summary bar and 6 ball slots (1:1 with pokefirered CreatePartyStatusSummarySprites).
-- Player: base (136, 96), un-flipped bar (<=====), balls at y=92 from x=160..210 (left-to-right).
-- Opponent: base (104, 40), H-flipped bar (=====>), balls at y=36 from x=30..80 (right-aligned).
function BattleChrome.drawPartyBar(x, y, balls, ox, isOpponent)
  ox = tonumber(ox) or 0
  balls = balls or {}
  if isOpponent then
    local barX = x + ox
    if BattleChrome._partyBar then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(BattleChrome._partyBar, barX, y, 0, -1, 1)
    end
    for i = 1, 6 do
      local kind = balls[i] or "empty"
      local bx = (x + ox) - 24 - 10 * (6 - i)
      BattleChrome.drawPartyBall(bx, y - 7, kind)
    end
  else
    local barX = x + ox
    if BattleChrome._partyBar then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(BattleChrome._partyBar, barX, y, 0, 1, 1)
    end
    for i = 1, 6 do
      local kind = balls[i] or "empty"
      local bx = (x + ox) + 24 + 10 * (i - 1)
      BattleChrome.drawPartyBall(bx, y - 8, kind)
    end
  end
end

return BattleChrome
