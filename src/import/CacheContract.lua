-- Pure version-scoped readiness rules shared by the importer and read-only
-- dataset consumers. Callers inject a filesystem; no global cache prefix or
-- active game state is changed while inspecting another version.

local CacheFormat = require("src.import.CacheFormat")
local GameVersion = require("src.core.GameVersion")

local CacheContract = {}

CacheContract.MARKER_PATH = "rom-cache.complete"

local REQUIRED_FILES = {
  "data/generated/constants.lua", "data/generated/maps.lua",
  "data/generated/text.lua", "data/generated/field.lua",
  "data/generated/battle_anims.lua",
  "assets/generated/title/pokemon_logo.png",
  "assets/generated/fonts/font.png",
  "assets/generated/battle/front/pikachu.png",
  "assets/generated/battle/anims/move_anim_0.png",
  "assets/generated/battle/anims/move_anim_1.png",
  "assets/generated/audio/programs.bin",
  "assets/generated/trade/game_boy.png",
}

local VERSION_REQUIRED_FILES = {
  yellow = {
    "assets/generated/battle/trainers/jessie_james.png",
    "assets/generated/battle/profoakb.png",
    "assets/generated/pikachu/pikapic_1.png",
  },
}

local GOLD_REQUIRED_FILES = {
  "data/generated/constants.lua", "data/generated/maps.lua",
  "data/generated/roofs.lua", "data/generated/sprites.lua",
  "data/generated/scripts.lua", "data/generated/text.lua",
  "data/generated/rom_text.lua",
  "data/generated/pokemon.lua", "data/generated/tilesets.lua",
  "data/generated/audio.lua", "data/generated/marts.lua",
  "assets/generated/fonts/font.png", "assets/generated/fonts/frames.png",
  "assets/generated/title/pokemon_logo.png",
  "assets/generated/title/title_screen.png", "assets/generated/title/hooh.png",
  "assets/generated/title/hooh_5.png", "assets/generated/title/clouds.png",
  "assets/generated/title/copyright_splash.png",
  "data/generated/oak_speech.lua", "assets/generated/intro/oak.png",
  "assets/generated/intro/cal.png", "assets/generated/tilesets/johto.png",
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
}

local SEMANTIC_MODULES = {
  [1] = {
    "constants", "maps", "tilesets", "text", "text_pointers",
    "trainer_headers", "font", "sprites", "pokemon", "moves", "items",
    "type_chart", "trainers", "encounters", "field", "battle_anims",
  },
  [2] = {
    "pokemon", "moves", "items", "type_chart", "audio", "font", "maps",
    "tilesets", "text", "trainers", "encounters", "sprites", "palettes",
    "icons", "battle_anims", "constants", "landmarks",
  },
}

local OPTIONAL_SEMANTIC_MODULES = { [1] = { "audio", "palettes", "icons" }, [2] = {} }

local function copy(values)
  local out = {}
  for index, value in ipairs(values or {}) do out[index] = value end
  return out
end

function CacheContract.requiredFiles(version, semantic)
  local files
  if version == "gold" or version == "silver" then
    files = copy(GOLD_REQUIRED_FILES)
  else
    files = copy(REQUIRED_FILES)
    for _, path in ipairs(VERSION_REQUIRED_FILES[version] or {}) do
      files[#files + 1] = path
    end
  end
  if semantic then
    local generation = GameVersion.generation(version)
    for _, name in ipairs(SEMANTIC_MODULES[generation] or {}) do
      files[#files + 1] = "data/generated/" .. name .. ".lua"
    end
  end
  local unique, out = {}, {}
  for _, path in ipairs(files) do
    if not unique[path] then unique[path], out[#out + 1] = true, path end
  end
  return out
end

function CacheContract.semanticModules(version)
  return copy(SEMANTIC_MODULES[GameVersion.generation(version)])
end

function CacheContract.optionalSemanticModules(version)
  return copy(OPTIONAL_SEMANTIC_MODULES[GameVersion.generation(version)])
end

local function isFile(fs, path)
  local info = fs.getInfo and fs.getInfo(path, "file")
  if info then return info.type == nil or info.type == "file" end
  return false
end

local function hasFiles(version, fs, prefix, semantic)
  for _, path in ipairs(CacheContract.requiredFiles(version, semantic)) do
    if not isFile(fs, prefix .. path) then return false, path end
  end
  return true
end

local function sourcePrefix(version)
  return version == "red" and "" or GameVersion.cachePrefix(version)
end

local function sourceReady(version, fs, semantic)
  if not (fs.getRealDirectory and fs.getSource) then return nil end
  local prefix = sourcePrefix(version)
  local ok = hasFiles(version, fs, prefix, semantic)
  if not ok then return nil end
  local first = prefix .. CacheContract.requiredFiles(version, semantic)[1]
  if fs.getRealDirectory(first) ~= fs.getSource() then return nil end
  return { kind = "source", prefix = prefix }
end

function CacheContract.inspect(version, fs, opts)
  opts = opts or {}
  if not (GameVersion.VERSIONS[version] and fs and fs.read and fs.getInfo) then
    return nil, "not_imported", "unsupported cache inspection"
  end
  if opts.allowSource then
    local source = sourceReady(version, fs, opts.semantic)
    if source then return source end
  end
  local prefix = GameVersion.cachePrefix(version)
  local marker = fs.read(prefix .. CacheContract.MARKER_PATH)
  if not CacheFormat.matches(version, marker) then
    return nil, "not_imported", "completion marker is missing or stale"
  end
  local complete, missing = hasFiles(version, fs, prefix, opts.semantic)
  if not complete then
    return nil, "not_imported", "required cache file is missing: " .. missing
  end
  return { kind = "cache", prefix = prefix, marker = marker }
end

return CacheContract
