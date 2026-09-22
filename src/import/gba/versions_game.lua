-- Per-game selector over the GBA version tables (T6.3a skeleton).
--
-- Today there is one flat FireRed monolith (src/import/gba/versions.lua) and
-- every extractor reads it as a singleton, so an RSE port has nowhere to put
-- its own ROM offsets (I7).  This module maps a game id to its table module;
-- the FireRed/LeafGreen rows name the monolith, an RSE row lands with
-- versions_rse.lua (T6.4).
--
-- Unwired: nothing requires this file yet.  The T6.2/T6.3 handoff patch aliases
--   Versions.game = require("src.import.gba.versions_game").game
-- and routes extractor reads through it.  Resolution fails closed to FireRed,
-- the same contract as src/core/game3/profile.lua.

local GameVersion = require("src.core.GameVersion")

local VersionsGame = {}

VersionsGame.GAMES = {
  firered = "src.import.gba.versions",
  leafgreen = "src.import.gba.versions", -- shares FireRed's tables
}

VersionsGame.FALLBACK = "firered"

local cache, warned = {}, {}

local function log(msg)
  print("[versions_game] " .. tostring(msg))
end

local function load(id)
  local path = VersionsGame.GAMES[id]
  if type(path) ~= "string" or path == "" then return nil end
  local ok, mod = pcall(require, path)
  if ok and type(mod) == "table" then return mod end
  return nil
end

--- The version table module for a game id (nil or "" = active game).
function VersionsGame.game(id)
  if type(id) ~= "string" or id == "" then
    local active = GameVersion.get()
    local info = GameVersion.info(active)
    id = (info and (info.generation or 1) == 3) and active or VersionsGame.FALLBACK
  end
  local row = cache[id]
  if row then return row end
  local mod = load(id)
  if mod then
    cache[id] = mod
    return mod
  end
  if id == VersionsGame.FALLBACK then
    error("versions_game: fallback row '" .. VersionsGame.FALLBACK .. "' does not load")
  end
  if not warned[id] then
    warned[id] = true
    log("no version table for '" .. id .. "'; using " .. VersionsGame.FALLBACK)
  end
  return VersionsGame.game(VersionsGame.FALLBACK)
end

--- Register a game's table module (a port adds its row at boot; the test seam).
function VersionsGame.register(id, modulePath)
  if type(id) ~= "string" or id == "" then return false end
  if type(modulePath) ~= "string" or modulePath == "" then return false end
  VersionsGame.GAMES[id] = modulePath
  cache[id] = nil
  return true
end

--- Test/tool hook: drop resolutions; registrations survive.
function VersionsGame.reset()
  cache = {}
  warned = {}
end

return VersionsGame
