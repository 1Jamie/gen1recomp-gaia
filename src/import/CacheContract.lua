-- Engine-owned contract for generated ROM caches.
--
-- A cache is playable only when its versioned marker matches the ROM and every
-- required output for that version exists. Extraction writers may differ by
-- platform, but they must publish through this contract so partial staging
-- cannot look ready to the runtime.
local GameVersion = require("src.core.GameVersion")

local CacheContract = {}

CacheContract.FORMAT = "rom-cache-v10:"
CacheContract.VERSION_FORMAT = {
  crystal = "rom-cache-v10-crystal2:",
}
CacheContract.MARKER_PATH = "rom-cache.complete"

CacheContract.REQUIRED_FILES = {
  "data/generated/constants.lua",
  "data/generated/maps.lua",
  "data/generated/text.lua",
  "data/generated/field.lua",
  "data/generated/battle_anims.lua",
  "assets/generated/title/pokemon_logo.png",
  "assets/generated/fonts/font.png",
  "assets/generated/battle/front/pikachu.png",
  "assets/generated/battle/anims/move_anim_0.png",
  "assets/generated/battle/anims/move_anim_1.png",
  "assets/generated/audio/programs.bin",
  "assets/generated/trade/game_boy.png",
}

CacheContract.VERSION_REQUIRED_FILES = {
  yellow = {
    "assets/generated/battle/trainers/jessie_james.png",
    "assets/generated/battle/profoakb.png",
    "assets/generated/pikachu/pikapic_1.png",
  },
}

CacheContract.VERSION_REQUIRED_FILES_OVERRIDE = {
  gold = {
    "data/generated/constants.lua",
    "data/generated/maps.lua",
    "data/generated/roofs.lua",
    "data/generated/sprites.lua",
    "data/generated/scripts.lua",
    "data/generated/text.lua",
    -- The engine's label-keyed strings are separate from Gen 2 script text.
    -- Caches made before RomExtractorGen2:extractText must be rebuilt so
    -- src/core/RomText.lua does not silently fall back to built-in wording.
    "data/generated/rom_text.lua",
    "data/generated/pokemon.lua",
    "data/generated/tilesets.lua",
    "data/generated/audio.lua",
    "data/generated/marts.lua",
    "assets/generated/fonts/font.png",
    "assets/generated/fonts/frames.png",
    "assets/generated/title/pokemon_logo.png",
    "assets/generated/title/title_screen.png",
    "assets/generated/title/hooh.png",
    "assets/generated/title/hooh_5.png",
    "assets/generated/title/clouds.png",
    "assets/generated/title/copyright_splash.png",
    "data/generated/oak_speech.lua",
    "assets/generated/intro/oak.png",
    "assets/generated/intro/cal.png",
    "assets/generated/tilesets/johto.png",
    "assets/generated/tilesets/roofs/new_bark.png",
    "assets/generated/sprites/chris.png",
    "assets/generated/battle/front/chikorita.png",
    "assets/generated/battle/front/pikachu.png",
    "assets/generated/battle/front/marill.png",
    "assets/generated/battle/trainers/falkner.png",
    "assets/generated/battle/hud/balls.png",
    "assets/generated/audio/programs.bin",
    "assets/generated/slots/gold_slots_1.png",
    "assets/generated/card_flip/card_flip_1.png",
    "assets/generated/pc/mail_item.png",
    -- engine/events/fishing_gfx.asm:23
    "assets/generated/emotes/fishing.png",
  },
  crystal = {
    "data/generated/constants.lua",
    "data/generated/maps.lua",
    "data/generated/roofs.lua",
    "data/generated/sprites.lua",
    "data/generated/scripts.lua",
    "data/generated/text.lua",
    "data/generated/rom_text.lua",
    "data/generated/pokemon.lua",
    "data/generated/encounters.lua",
    "data/generated/tilesets.lua",
    "data/generated/landmarks.lua",
    "data/generated/audio.lua",
    "data/generated/marts.lua",
    "data/generated/oak_speech.lua",
    "data/generated/title.lua",
    "data/generated/intro.lua",
    "assets/generated/fonts/font.png",
    "assets/generated/fonts/frames.png",
    "assets/generated/title/crystal_logo.png",
    "assets/generated/title/crystal_wordmark.png",
    "assets/generated/title/crystal_suicune.png",
    "assets/generated/title/copyright_splash.png",
    "assets/generated/splash/ditto.png",
    "assets/generated/intro/chris.png",
    "assets/generated/intro/kris.png",
    "assets/generated/intro/suicune_run_sprites.png",
    "assets/generated/intro/unowns_tiles.png",
    "assets/generated/intro/oak.png",
    "assets/generated/tilesets/johto.png",
    "assets/generated/tilesets/roofs/new_bark.png",
    "assets/generated/sprites/chris.png",
    "assets/generated/sprites/kris.png",
    "assets/generated/battle/front/chikorita.png",
    "assets/generated/battle/front/wooper.png",
    "assets/generated/battle/front/pikachu.png",
    "assets/generated/battle/trainers/falkner.png",
    "assets/generated/battle/hud/balls.png",
    "assets/generated/audio/programs.bin",
    "assets/generated/slots/gold_slots_1.png",
    "assets/generated/card_flip/card_flip_1.png",
    "assets/generated/pc/mail_item.png",
    "assets/generated/trainer_card/card_f.png",
    "data/generated/mobile_gfx.lua",
    "assets/generated/battle/player_back_female.png",
    "assets/generated/battle/trainers/kris.png",
    "assets/generated/battle/trainers/chris.png",
    -- ../pokecrystal/engine/events/fishing_gfx.asm:38-42
    "assets/generated/emotes/fishing.png",
  },
}
CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.silver =
  CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.gold

function CacheContract.requiredFilesFor(version)
  local override = CacheContract.VERSION_REQUIRED_FILES_OVERRIDE[version]
  if override then return override, true end
  return CacheContract.REQUIRED_FILES, false
end

function CacheContract.formatFor(version)
  return CacheContract.VERSION_FORMAT[version] or CacheContract.FORMAT
end

function CacheContract.markerFor(version, sha1)
  return CacheContract.formatFor(version)
    .. (sha1 or GameVersion.info(version).sha1)
end

function CacheContract.markerMatches(version, marker)
  for _, revision in ipairs(GameVersion.revisions(version)) do
    if marker == CacheContract.markerFor(version, revision.sha1) then return true end
  end
  return false
end

-- Keep the process-global CacheFs prefix isolated even when a filesystem
-- adapter raises while probing or publishing.  The real CacheFs methods
-- return errors, but this also makes the contract safe for platform adapters
-- that surface I/O failures as Lua errors.
local function withVersionPrefix(version, fs, action)
  local saved = fs.prefix
  fs.prefix = GameVersion.cachePrefix(version)
  local ok, first, second = pcall(action)
  fs.prefix = saved
  if not ok then return false, first end
  return true, first, second
end

function CacheContract.allRequiredFilesExist(version, fs)
  fs = fs or require("src.import.CacheFs")
  local ok, complete, missing = withVersionPrefix(version, fs, function()
    local required, isOverride = CacheContract.requiredFilesFor(version)
    local missingPath
    for _, path in ipairs(required) do
      if not fs.exists(path) then missingPath = path; break end
    end
    if not missingPath and not isOverride then
      for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES[version] or {}) do
        if not fs.exists(path) then missingPath = path; break end
      end
    end
    return missingPath == nil, missingPath
  end)
  if not ok then return false, complete end
  return complete, missing
end

function CacheContract.readMarker(version, fs)
  fs = fs or require("src.import.CacheFs")
  local ok, marker, readError = withVersionPrefix(version, fs, function()
    return fs.read(CacheContract.MARKER_PATH)
  end)
  if not ok then return nil, marker end
  -- LÖVE may return contents plus a byte count; only a nil contents result
  -- makes the auxiliary value an error.  CacheFs' portable reader returns
  -- just the contents, so this remains adapter-neutral.
  if marker == nil then return nil, readError end
  return marker
end

function CacheContract.isReady(version, fs)
  fs = fs or require("src.import.CacheFs")
  if CacheContract.sourceTreeHasData(version) then return true end
  local marker, readError = CacheContract.readMarker(version, fs)
  if readError or not CacheContract.markerMatches(version, marker) then return false end
  return CacheContract.allRequiredFilesExist(version, fs)
end

function CacheContract.publish(version, fs, sha1)
  fs = fs or require("src.import.CacheFs")
  local complete, missing = CacheContract.allRequiredFilesExist(version, fs)
  if not complete then
    -- A caller may be retrying over a partially replaced cache.  Do not
    -- leave its old marker advertising readiness after this failed check.
    local removed, removeError = withVersionPrefix(version, fs, function()
      if not fs.remove then
        error("cache filesystem cannot remove the completion marker")
      end
      return fs.remove(CacheContract.MARKER_PATH)
    end)
    if not removed then
      return false, "cache is incomplete; missing " .. tostring(missing)
        .. "; could not remove completion marker: " .. tostring(removeError)
    end
    return false, "cache is incomplete; missing " .. tostring(missing)
  end
  local changed, ok, err = withVersionPrefix(version, fs, function()
    return fs.write(CacheContract.MARKER_PATH, CacheContract.markerFor(version, sha1))
  end)
  if not changed then return false, tostring(ok) end
  return ok, err
end

function CacheContract.sourceTreeHasData(version)
  if not (love and love.filesystem and love.filesystem.getInfo
      and love.filesystem.getRealDirectory and love.filesystem.getSource) then
    return false
  end
  local prefix = version == "red" and "" or GameVersion.cachePrefix(version)
  local required, isOverride = CacheContract.requiredFilesFor(version)
  local source = love.filesystem.getSource()
  for _, path in ipairs(required) do
    local fullPath = prefix .. path
    if love.filesystem.getInfo(fullPath, "file") == nil
        or love.filesystem.getRealDirectory(fullPath) ~= source then
      return false
    end
  end
  if not isOverride then
    for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES[version] or {}) do
      local fullPath = prefix .. path
      if love.filesystem.getInfo(fullPath, "file") == nil
          or love.filesystem.getRealDirectory(fullPath) ~= source then
        return false
      end
    end
  end
  return true
end

return CacheContract
