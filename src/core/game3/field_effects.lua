-- FRLG tall-grass field effect (pret FldEff_TallGrass / UpdateGrassFieldEffectSubpriority).
-- Layering: full frame behind the avatar, bottom strip in front (covers feet).
-- Frame 1 is a solid green pad in ROM art — must stay behind the body.

local Extract = require("src.import.gba.extract_island1")

local FieldEffects = {}

FieldEffects._cache = nil
FieldEffects._image = nil
FieldEffects._quads = nil -- [frame] = full 16×16
FieldEffects._quadsFront = nil -- [frame] = bottom FEET_H strip
FieldEffects._fx = nil
FieldEffects._logged = false

local CELL = 16
local FRAME_W, FRAME_H = 16, 16
local FRAME_COUNT = 5
local FEET_H = 8 -- pret: lower half covers feet; upper stays behind body
-- pret sAnim_TallGrass: frames 1,2,3,4,0 × 10 vblanks each.
local RUSTLE = { 1, 2, 3, 4, 0 }
local FRAME_DUR = 10

local function log(msg)
  if FieldEffects._logged then return end
  FieldEffects._logged = true
  print("[game3/field_effects] " .. tostring(msg))
end

local function cache_root()
  return Extract.CACHE_ROOT or "data/generated/gba"
end

local function try_load_rgba(cache, rel, w, h)
  if not cache or not cache.read then return nil end
  local rgba = cache:read(rel)
  if not rgba or #rgba < w * h * 4 then return nil end
  if not (love and love.image and love.graphics) then return nil end
  local ok, id = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not ok or not id then return nil end
  local img = love.graphics.newImage(id)
  if img.setFilter then img:setFilter("nearest", "nearest") end
  return img
end

local function try_load_png(path)
  if not (love and love.graphics and love.graphics.newImage) then return nil end
  -- Indexed PNGs: love honors transparency; prefer ROM rgba extract.
  local ok, img = pcall(love.graphics.newImage, path)
  if ok and img then
    if img.setFilter then img:setFilter("nearest", "nearest") end
    return img
  end
  return nil
end

function FieldEffects.install(cache)
  FieldEffects._cache = cache
  FieldEffects._image = nil
  FieldEffects._quads = nil
  FieldEffects._quadsFront = nil
  FieldEffects._fx = nil
  FieldEffects._logged = false
  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and Heal.install then Heal.install(cache) end
end

function FieldEffects.invalidate()
  FieldEffects._image = nil
  FieldEffects._quads = nil
  FieldEffects._quadsFront = nil
  FieldEffects._fx = nil
  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and Heal.invalidate then Heal.invalidate() end
end

local function ensure_sheet()
  if FieldEffects._image and FieldEffects._quads and FieldEffects._quadsFront then
    return true
  end
  local img = try_load_rgba(
    FieldEffects._cache, cache_root() .. "/field_effects/tall_grass.rgba", 16, 80)
  if not img then
    img = try_load_png("src/import/gba/chrome/field_effects/tall_grass.png")
  end
  if not img then
    log("tall_grass sheet missing — re-run gba extract")
    return false
  end
  local quads, quadsFront = {}, {}
  local iw, ih = img:getDimensions()
  for i = 0, FRAME_COUNT - 1 do
    local y = i * FRAME_H
    if y + FRAME_H <= ih then
      quads[i] = love.graphics.newQuad(0, y, FRAME_W, FRAME_H, iw, ih)
      quadsFront[i] = love.graphics.newQuad(
        0, y + (FRAME_H - FEET_H), FRAME_W, FEET_H, iw, ih)
    end
  end
  FieldEffects._image = img
  FieldEffects._quads = quads
  FieldEffects._quadsFront = quadsFront
  log("tall_grass ready (behind+feet OAM split)")
  return true
end

local function current_frame()
  local fx = FieldEffects._fx
  if not fx then return nil end
  return RUSTLE[fx.step + 1] or 0
end

--- Start / refresh tall grass rustle at map cell (cx, cy).
-- seekEnd: pret spawn-on-grass SeekSpriteAnim near anim end (idle feet cover).
function FieldEffects.tallGrassAt(cx, cy, seekEnd)
  if not ensure_sheet() then return end
  cx, cy = tonumber(cx) or 0, tonumber(cy) or 0
  local fx = FieldEffects._fx
  if fx and fx.cx == cx and fx.cy == cy and not fx.leaving then
    return
  end
  FieldEffects._fx = {
    cx = cx,
    cy = cy,
    timer = 0,
    step = seekEnd and (#RUSTLE - 1) or 0,
    leaving = false,
    done = false,
  }
end

function FieldEffects.clearTallGrass()
  FieldEffects._fx = nil
end

function FieldEffects.leaveTallGrass()
  local fx = FieldEffects._fx
  if not fx then return end
  fx.leaving = true
end

function FieldEffects.step()
  local fx = FieldEffects._fx
  if fx and not fx.done then
    fx.timer = fx.timer + 1
    if fx.timer >= FRAME_DUR then
      fx.timer = 0
      fx.step = fx.step + 1
      if fx.step >= #RUSTLE then
        if fx.leaving then
          fx.done = true
          FieldEffects._fx = nil
        else
          fx.step = #RUSTLE - 1 -- hold frame 0 (feet cover only)
        end
      end
    end
  end
  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and Heal.step then Heal.step() end
end

--- pret dofieldeffect / waitfieldeffect for FLDEFF_POKECENTER_HEAL (25).
function FieldEffects.doFieldEffect(id)
  id = tonumber(id) or 0
  local Heal = require("src.core.game3.pokecenter_heal")
  if id == Heal.FLDEFF then
    return Heal.start()
  end
  return false
end

function FieldEffects.waitFieldEffect(id, done)
  id = tonumber(id) or 0
  local Heal = require("src.core.game3.pokecenter_heal")
  if id == Heal.FLDEFF then
    Heal.wait(done)
    return
  end
  if done then done() end
end

function FieldEffects.isFieldEffectActive(id)
  id = tonumber(id) or 0
  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and id == Heal.FLDEFF then
    return Heal.isActive()
  end
  return false
end

local function screen_xy(camX, camY)
  local fx = FieldEffects._fx
  if not fx then return nil end
  return fx.cx * CELL - (camX or 0), fx.cy * CELL - (camY or 0)
end

--- Pret: grass under avatar body (lower OAM priority / drawn first).
function FieldEffects.drawBehind(camX, camY)
  local fx = FieldEffects._fx
  if not fx or not FieldEffects._image then return end
  local frameIdx = current_frame()
  local q = FieldEffects._quads and FieldEffects._quads[frameIdx]
  if not q then return end
  local sx, sy = screen_xy(camX, camY)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(FieldEffects._image, q, sx, sy)
end

--- Pret: grass over feet (subpriority bumped above avatar).
-- playerPy: world Y of avatar cell origin (Player.py). Front strip is only
-- drawn when the feet sit in this grass cell — otherwise walking *up* into
-- the tile paints the destination's bottom strip over the hat/head.
function FieldEffects.drawFront(camX, camY, playerPy)
  local fx = FieldEffects._fx
  if not fx or not FieldEffects._image then return end
  if playerPy ~= nil then
    local feetY = playerPy + CELL
    local grassTop = fx.cy * CELL
    local grassBot = grassTop + CELL
    -- Feet must reach the lower half of the grass cell (cover zone).
    if feetY < grassTop + FEET_H or feetY > grassBot + 2 then
      return
    end
  end
  local frameIdx = current_frame()
  local q = FieldEffects._quadsFront and FieldEffects._quadsFront[frameIdx]
  if not q then return end
  local sx, sy = screen_xy(camX, camY)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(FieldEffects._image, q, sx, sy + (FRAME_H - FEET_H))
end

--- Legacy single-pass (front only) — prefer drawBehind + drawFront.
function FieldEffects.draw(camX, camY, playerPy)
  FieldEffects.drawFront(camX, camY, playerPy)
end

--- Screen-space Pokemon Center heal machine (after actors).
function FieldEffects.drawOverlay(camX, camY)
  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and Heal.draw then Heal.draw(camX, camY) end
end

return FieldEffects
