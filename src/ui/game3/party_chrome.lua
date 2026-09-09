-- Party menu chrome from firered GBA extract (ROM-baked BG, slots, balls).

local Display = require("src.core.game3.display")
local Extract = require("src.import.gba.extract_island1")
local PartyChromeExtract = require("src.import.gba.party_chrome_extract")

local PartyChrome = {}

PartyChrome._cache = nil
PartyChrome._bg = nil
PartyChrome._balls = nil
PartyChrome._slotMain = nil
PartyChrome._slotWide = nil
PartyChrome._slotEmpty = nil
PartyChrome._status = nil
PartyChrome._manifest = nil
PartyChrome._logged = false

local function cache_root()
  return Extract.CACHE_ROOT or "data/generated/gba"
end

local function party_root()
  return cache_root() .. "/pokemon/party"
end

local function log(msg)
  if PartyChrome._logged then return end
  PartyChrome._logged = true
  print("[game3/party_chrome] " .. tostring(msg))
end

local function read_bytes(rel)
  local cache = PartyChrome._cache
  if cache and cache.read then
    local d = cache:read(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  -- Standalone Game3 has no mod.cache — use firered CacheFs / Dataset.
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
  if not ok or not imageData then
    imageData = love.image.newImageData(w, h)
    local i = 1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        imageData:setPixel(x, y,
          (rgba:byte(i) or 0) / 255,
          (rgba:byte(i + 1) or 0) / 255,
          (rgba:byte(i + 2) or 0) / 255,
          (rgba:byte(i + 3) or 0) / 255)
        i = i + 4
      end
    end
  end
  local image = love.graphics.newImage(imageData)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  return image
end

local function load_status_png()
  local rel = party_root() .. "/status_icons.png"
  local bytes = read_bytes(rel)
  if bytes and love and love.image and love.graphics then
    local ok, img = pcall(function()
      local fd = love.filesystem.newFileData(bytes, "status_icons.png")
      local id = love.image.newImageData(fd)
      local image = love.graphics.newImage(id)
      if image.setFilter then image:setFilter("nearest", "nearest") end
      return image
    end)
    if ok and img then return img end
  end
  if love and love.graphics and love.filesystem and love.filesystem.getInfo
      and love.filesystem.getInfo(rel) then
    local ok, img = pcall(love.graphics.newImage, rel)
    if ok and img then
      if img.setFilter then img:setFilter("nearest", "nearest") end
      return img
    end
  end
  return nil
end

function PartyChrome.install(cache)
  if not cache or not cache.read then
    local okD, Dataset = pcall(require, "src.core.game3.dataset")
    if okD and Dataset and Dataset.cache then
      cache = Dataset.cache()
    end
  end
  PartyChrome._cache = cache
  PartyChrome._bg = nil
  PartyChrome._balls = nil
  PartyChrome._slotMain = nil
  PartyChrome._slotWide = nil
  PartyChrome._slotEmpty = nil
  PartyChrome._status = nil
  PartyChrome._manifest = load_lua(party_root() .. "/manifest.lua")
  PartyChrome._logged = false
  if PartyChrome._manifest then
    log("party chrome manifest ready")
  else
    log("party chrome missing — re-import FireRed ROM")
  end
end

local function man()
  if not PartyChrome._manifest then
    PartyChrome._manifest = load_lua(party_root() .. "/manifest.lua")
  end
  return PartyChrome._manifest or {}
end

local function ensureBg()
  if PartyChrome._bg then return PartyChrome._bg end
  local m = man()
  local w, h = m.width or 240, m.height or 160
  local img = rgba_to_image(read_bytes(party_root() .. "/bg.rgba"), w, h)
  if img then
    PartyChrome._bg = { image = img, w = w, h = h }
    log("party chrome BG+slots ready")
  else
    log("party chrome missing — re-import FireRed ROM")
  end
  return PartyChrome._bg
end

local function ensureSlot(kind)
  if kind == "main" and PartyChrome._slotMain then return PartyChrome._slotMain end
  if kind == "wide" and PartyChrome._slotWide then return PartyChrome._slotWide end
  if kind == "empty" and PartyChrome._slotEmpty then return PartyChrome._slotEmpty end
  local m = man()
  local file, w, h
  if kind == "main" then
    file, w, h = "slot_main.rgba", m.slotMainW or 80, m.slotMainH or 56
  elseif kind == "empty" then
    file, w, h = "slot_wide_empty.rgba", m.slotWideW or 144, m.slotWideH or 24
  else
    file, w, h = "slot_wide.rgba", m.slotWideW or 144, m.slotWideH or 24
  end
  local img = rgba_to_image(read_bytes(party_root() .. "/" .. file), w, h)
  if not img then return nil end
  local entry = { image = img, w = w, h = h }
  if kind == "main" then PartyChrome._slotMain = entry
  elseif kind == "empty" then PartyChrome._slotEmpty = entry
  else PartyChrome._slotWide = entry end
  return entry
end

local function ensureBalls()
  if PartyChrome._balls then return PartyChrome._balls end
  local m = man()
  local w = m.ballW or 32
  local sheetH = m.ballSheetH or 64
  local frames = m.ballFrames or 2
  local img = rgba_to_image(read_bytes(party_root() .. "/status_balls.rgba"), w, sheetH)
  if not img then return nil end
  local fh = math.floor(sheetH / frames)
  local quads = {}
  for i = 0, frames - 1 do
    quads[i] = love.graphics.newQuad(0, i * fh, w, fh, w, sheetH)
  end
  PartyChrome._balls = {
    image = img, w = w, h = fh, frameH = fh, frameCount = frames, quads = quads,
  }
  return PartyChrome._balls
end

local function ensureStatus()
  if PartyChrome._status then return PartyChrome._status end
  local img = load_status_png()
  if not img then return nil end
  local iw, ih = img:getDimensions()
  local fw, fh = 16, 8
  local entry = { image = img, quads = {}, frameW = fw, frameH = fh }
  local cols = math.max(1, math.floor(iw / fw))
  for i = 0, cols - 1 do
    entry.quads[i] = love.graphics.newQuad(i * fw, 0, fw, fh, iw, ih)
  end
  PartyChrome._status = entry
  return entry
end

function PartyChrome.ready()
  return PartyChromeExtract.ready(PartyChrome._cache, cache_root())
end

function PartyChrome.drawBg()
  local W, H = Display.W or 240, Display.H or 160
  local bg = ensureBg()
  love.graphics.setColor(1, 1, 1, 1)
  if bg and bg.image then
    love.graphics.draw(bg.image, 0, 0)
    return
  end
  love.graphics.setColor(0.31, 0.69, 0.47, 1)
  love.graphics.rectangle("fill", 0, 0, W, H)
  love.graphics.setColor(1, 1, 1, 1)
end

--- Draw pret slot panel at window tile coords. kind: main|wide|empty
function PartyChrome.drawSlot(kind, tileLeft, tileTop, selected)
  local slot = ensureSlot(kind == "main" and "main" or (kind == "empty" and "empty" or "wide"))
  local T = Display.TILE or 8
  local px, py = tileLeft * T, tileTop * T
  love.graphics.setColor(1, 1, 1, 1)
  if slot and slot.image then
    love.graphics.draw(slot.image, px, py)
    if selected then
      love.graphics.setColor(1, 1, 0.7, 0.18)
      love.graphics.rectangle("fill", px, py, slot.w, slot.h)
      love.graphics.setColor(1, 1, 1, 1)
    end
    return
  end
  love.graphics.setColor(selected and 0.55 or 0.40, selected and 0.82 or 0.72, 0.88, 1)
  local pw = (kind == "main") and 80 or 144
  local ph = (kind == "main") and 56 or 24
  love.graphics.rectangle("fill", px, py, pw, ph)
  love.graphics.setColor(1, 1, 1, 1)
end

function PartyChrome.ballEntry()
  return ensureBalls()
end

function PartyChrome.statusEntry(frame)
  frame = tonumber(frame)
  if not frame or frame < 1 then return nil, nil end
  local st = ensureStatus()
  if not st then return nil, nil end
  return st.image, st.quads[frame - 1]
end

function PartyChrome.drawBall(px, py, frame)
  local balls = ensureBalls()
  if not balls then return end
  frame = tonumber(frame) or 0
  if frame < 0 then frame = 0 end
  if frame >= balls.frameCount then frame = balls.frameCount - 1 end
  local q = balls.quads[frame]
  love.graphics.setColor(1, 1, 1, 1)
  if q then
    love.graphics.draw(balls.image, q, px, py)
  else
    love.graphics.draw(balls.image, px, py)
  end
end

function PartyChrome.drawStatus(px, py, frame)
  frame = tonumber(frame)
  if not frame or frame < 1 then return end
  local st = ensureStatus()
  if not st then return end
  local q = st.quads[frame - 1]
  if not q then return end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(st.image, q, px, py)
end

function PartyChrome.statusFrameFor(status)
  if not status or status == 0 or status == "OK" or status == "ok" or status == "none" then
    return 0
  end
  local s = tostring(status):lower()
  if s:find("sleep") or s == "slp" or s == "1" then return 1 end
  if s:find("poison") or s == "psn" or s == "2" then return 2 end
  if s:find("burn") or s == "brn" or s == "3" then return 3 end
  if s:find("freeze") or s:find("frozen") or s == "frz" or s == "4" then return 4 end
  if s:find("paraly") or s == "par" or s == "5" then return 5 end
  if s:find("toxic") or s == "tox" then return 2 end
  return 1
end

return PartyChrome
