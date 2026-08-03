-- NX-only asset overlay: fused love-nx cannot reliably mount
-- blue|yellow/assets/generated onto the un-prefixed assets/generated, so
-- instead of teaching every call site about versioned caches, this module
-- wraps the love loading entry points ONCE at boot: any string path under
-- assets/generated/ that does not resolve falls back to the active
-- version's prefixed copy (yellow|blue/assets/generated/...).
--
-- main.lua installs it only when Platform.isNX(); desktop/Android/iOS never
-- install it, so their mountVersion overlay stays the single mechanism and
-- their loaders keep stock behavior.  Writes are deliberately NOT wrapped:
-- the importer must keep targeting the versioned tree explicitly.
--
-- Two intentional exceptions stay outside this module:
--   * the chip-audio worker (src/core/chip_worker.lua) is a separate Lua
--     state without these wrappers; ChipAudio.slimAudio hands it the prefix
--     explicitly as audio.programPrefix.
--   * data/generated module loads go through CacheFs.readActive, which
--     already implements the same fallback for require bytes.

local GameVersion = require("src.core.GameVersion")

local GENERATED = "assets/generated/"

local NxAssetOverlay = {}

local originals -- raw love functions, non-nil while installed

-- Resolve `path` to the versioned copy when the un-prefixed file is missing
-- and the active version (Blue/Yellow) carries it.  Returns nil when the
-- caller's path should be used untouched (non-generated path, Red, the real
-- file exists, or no versioned copy).
local function versioned(path)
  if type(path) ~= "string" then return nil end
  if path:sub(1, #GENERATED) ~= GENERATED then return nil end
  local prefix = GameVersion.cachePrefix()
  if prefix == "" then return nil end
  if originals.getInfo(path) then return nil end
  local candidate = prefix .. path
  if originals.getInfo(candidate) then return candidate end
  return nil
end

local function wrapLoader(fn)
  return function(path, ...)
    local alt = versioned(path)
    if alt then return fn(alt, ...) end
    return fn(path, ...)
  end
end

function NxAssetOverlay.isInstalled()
  return originals ~= nil
end

function NxAssetOverlay.install()
  if originals then return end
  if not (love and love.filesystem) then return end
  originals = {
    read = love.filesystem.read,
    getInfo = love.filesystem.getInfo,
    newImage = love.graphics and love.graphics.newImage,
    newImageData = love.image and love.image.newImageData,
    newSource = love.audio and love.audio.newSource,
  }
  love.filesystem.read = wrapLoader(originals.read)
  love.filesystem.getInfo = function(path, ...)
    local alt = versioned(path)
    if alt then return originals.getInfo(alt, ...) end
    return originals.getInfo(path, ...)
  end
  if originals.newImage then
    love.graphics.newImage = wrapLoader(originals.newImage)
  end
  if originals.newImageData then
    love.image.newImageData = wrapLoader(originals.newImageData)
  end
  if originals.newSource then
    love.audio.newSource = wrapLoader(originals.newSource)
  end
end

-- Tests restore the stock loaders between cases; the game never uninstalls.
function NxAssetOverlay.uninstall()
  if not originals then return end
  love.filesystem.read = originals.read
  love.filesystem.getInfo = originals.getInfo
  if originals.newImage then love.graphics.newImage = originals.newImage end
  if originals.newImageData then
    love.image.newImageData = originals.newImageData
  end
  if originals.newSource then love.audio.newSource = originals.newSource end
  originals = nil
end

return NxAssetOverlay
