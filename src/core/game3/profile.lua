-- Per-game Gen 3 profile: the single place the Ruby/Sapphire/Emerald port
-- reads game-specific behaviour from. FireRed's row holds today's constants,
-- so every accessor here fails closed to it.
--
-- Design: docs/game3/rse-seams.md sections 3.1 and 5 (lead-approved).
-- Requires only GameVersion (zero-require) so it loads during boot and under
-- plain luajit; profile rows are plain data modules under profiles/.
--
-- Nothing consumes this module yet: the handoff tickets in rse-seams.md
-- wire the seams one file at a time (map ids, options, save schema, font).

local GameVersion = require("src.core.GameVersion")

local Profile = {}

Profile.FALLBACK_ID = "firered"

local cache = {}
local warned = {}

local function log(msg)
  print("[game3/profile] " .. tostring(msg))
end

--- Load a profile row by version id. Returns nil when the id has no row.
local function load(id)
  local ok, row = pcall(require, "src.core.game3.profiles." .. id)
  if ok and type(row) == "table" and row.id == id then return row end
  return nil
end

--- The profile for a version id (GameVersion id or save.version). Unknown
--- ids fail closed to the active game and then to FireRed, logging once.
function Profile.of(id)
  if type(id) ~= "string" or id == "" then return Profile.active() end
  local row = cache[id]
  if row then return row end
  row = load(id)
  if row then
    cache[id] = row
    return row
  end
  if id == Profile.FALLBACK_ID then
    error("game3 profile '" .. Profile.FALLBACK_ID .. "' is missing")
  end
  if not warned[id] then
    warned[id] = true
    log("no profile for '" .. id .. "'; using " .. Profile.active().id)
  end
  return Profile.active()
end

--- The active game's profile. Non-Gen3 processes fail closed to FireRed so
--- shared code and headless tests can require this without booting a game.
function Profile.active()
  local id = GameVersion.get()
  local info = GameVersion.info(id)
  if not info or (info.generation or 1) ~= 3 then id = Profile.FALLBACK_ID end
  local row = cache[id]
  if row then return row end
  row = load(id) or load(Profile.FALLBACK_ID)
  if not row then
    error("game3 profiles missing: " .. id .. " and " .. Profile.FALLBACK_ID)
  end
  cache[id] = row
  return row
end

function Profile.isGame3Version(id)
  local info = GameVersion.info(id)
  return info ~= nil and (info.generation or 1) == 3
end

--- Capability flags for a session's game (hook for the FRLG-only gates).
function Profile.capabilitiesFor(session)
  local id = type(session) == "table" and session.version or nil
  return Profile.of(id).capabilities or {}
end

function Profile.has(session, capability)
  return Profile.capabilitiesFor(session)[capability] == true
end

--- Test hook: drop the resolution cache so GameVersion swaps re-resolve.
function Profile.reset()
  cache = {}
  warned = {}
end

return Profile
