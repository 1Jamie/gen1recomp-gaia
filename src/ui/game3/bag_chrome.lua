-- Bag menu chrome + item icons from firered CacheFS (items/bag/).

local Extract = require("src.import.gba.extract_island1")
local BagChromeExtract = require("src.import.gba.bag_chrome_extract")

local BagChrome = {}

BagChrome._cache = nil
BagChrome._bg = nil
BagChrome._bagMale = nil
BagChrome._bagFemale = nil
BagChrome._bagQuads = {}
BagChrome._icons = {} -- id → Image
BagChrome._manifest = nil
BagChrome._logged = false

local function cache_root()
  return Extract.CACHE_ROOT or "data/generated/gba"
end

local function bag_root()
  return cache_root() .. "/" .. BagChromeExtract.CACHE_SUB
end

local function log(msg)
  if BagChrome._logged then return end
  BagChrome._logged = true
  print("[game3/bag_chrome] " .. tostring(msg))
end

local function read_bytes(rel)
  local cache = BagChrome._cache
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

function BagChrome.install(cache)
  if not cache or not cache.read then
    local okD, Dataset = pcall(require, "src.core.game3.dataset")
    if okD and Dataset and Dataset.cache then
      cache = Dataset.cache()
    end
  end
  BagChrome._cache = cache
  BagChrome._bg = nil
  BagChrome._bagMale = nil
  BagChrome._bagFemale = nil
  BagChrome._bagQuads = {}
  BagChrome._icons = {}
  BagChrome._manifest = nil
  BagChrome._logged = false
end

function BagChrome.ready()
  local man = BagChrome._manifest or load_lua(bag_root() .. "/manifest.lua")
  BagChrome._manifest = man
  return man ~= nil and read_bytes(bag_root() .. "/bg.rgba") ~= nil
end

local function ensure_bg()
  if BagChrome._bg then return BagChrome._bg end
  local man = BagChrome._manifest or load_lua(bag_root() .. "/manifest.lua")
  BagChrome._manifest = man
  local w = (man and man.width) or 240
  local h = (man and man.height) or 160
  local rgba = read_bytes(bag_root() .. "/bg.rgba")
  BagChrome._bg = rgba_to_image(rgba, w, h)
  if BagChrome._bg then log("bg ready") end
  return BagChrome._bg
end

local function ensure_bag_sheet(female)
  if female then
    if BagChrome._bagFemale then return BagChrome._bagFemale end
  else
    if BagChrome._bagMale then return BagChrome._bagMale end
  end
  local man = BagChrome._manifest or load_lua(bag_root() .. "/manifest.lua")
  BagChrome._manifest = man
  local w = (man and man.bagW) or 64
  local h = (man and man.bagH) or 256
  local rel = bag_root() .. (female and "/bag_female.rgba" or "/bag_male.rgba")
  local img = rgba_to_image(read_bytes(rel), w, h)
  if female then BagChrome._bagFemale = img else BagChrome._bagMale = img end
  return img
end

local function bag_quad(frame)
  frame = math.max(0, math.min(3, tonumber(frame) or 0))
  local q = BagChrome._bagQuads[frame]
  if q then return q end
  local img = BagChrome._bagMale or BagChrome._bagFemale
  if not img then return nil end
  local iw, ih = img:getDimensions()
  q = love.graphics.newQuad(0, frame * 64, 64, 64, iw, ih)
  BagChrome._bagQuads[frame] = q
  return q
end

--- Pocket index 1..5 → bag sprite frame 0..3 (TM/Berry share last frames).
local function frame_for_pocket(pocketIdx)
  pocketIdx = tonumber(pocketIdx) or 1
  if pocketIdx <= 1 then return 0 end
  if pocketIdx == 2 then return 1 end
  if pocketIdx == 3 then return 2 end
  return 3
end

function BagChrome.drawBg(x, y)
  local img = ensure_bg()
  if not img then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, x or 0, y or 0)
  return true
end

--- Draw bag sprite. pret field position ≈ (40, 68).
function BagChrome.drawBag(px, py, opts)
  opts = opts or {}
  local female = opts.female == true
  local img = ensure_bag_sheet(female)
  if not img then
    img = ensure_bag_sheet(not female)
  end
  if not img then return false end
  local frame = opts.frame
  if frame == nil then frame = frame_for_pocket(opts.pocketIdx) end
  local q = bag_quad(frame)
  love.graphics.setColor(1, 1, 1, 1)
  if q then
    love.graphics.draw(img, q, px or 40, py or 68)
  else
    love.graphics.draw(img, px or 40, py or 68)
  end
  return true
end

function BagChrome.iconImage(itemId)
  local ItemsData = require("src.core.game3.items_data")
  local id = ItemsData.toNumericId(itemId) or tonumber(itemId)
  if not id then return nil end
  if BagChrome._icons[id] ~= nil then
    return BagChrome._icons[id] or nil
  end
  local rgba = read_bytes(string.format("%s/icons/%d.rgba", bag_root(), id))
  local img = rgba_to_image(rgba, 24, 24)
  BagChrome._icons[id] = img or false
  return img
end

--- Draw 24×24 item icon at pixel coords.
function BagChrome.drawItemIcon(itemId, px, py, scale)
  local img = BagChrome.iconImage(itemId)
  if not img then return false end
  scale = scale or 1
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(img, px or 0, py or 0, 0, scale, scale)
  return true
end

return BagChrome
