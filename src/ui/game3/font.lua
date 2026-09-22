-- Game3 font provider: resolves the active game's glyph implementation through
-- the profile (profile.font.module) and forwards its public API, so shared
-- code requires one seam instead of src.ui.game3.frlg_font directly.
--
-- Design: docs/game3/rse-seams.md section 3.2 (T5.1).  New file; nothing
-- requires it yet, and FireRed's profile names frlg_font, so the resolution
-- returns exactly that module and every forwarded value is identical.
--
-- frlg_font.lua itself stays owned by the Refactor lane: this provider is the
-- seam, the existing 48 call sites migrate later.

local Profile = require("src.core.game3.profile")

local Font = {}

-- Backs a game whose profile names no font module (FireRed today).
Font.DEFAULT_MODULE = "src.ui.game3.frlg_font"

local impls = {}
local overrides = {}
local logged = false

local function modulePath(versionId)
  local row = Profile.of(versionId)
  local font = type(row) == "table" and row.font or nil
  return (font and font.module) or Font.DEFAULT_MODULE
end

local function log(msg)
  if logged then return end
  logged = true
  print("[game3/font] " .. tostring(msg))
end

--- Register a glyph implementation for a version id.  This is the test seam
-- and the hook a game with an extracted font bank registers through.
function Font.register(versionId, impl)
  if type(versionId) ~= "string" or versionId == "" then return false end
  if type(impl) ~= "table" then return false end
  overrides[versionId] = impl
  impls[versionId] = impl
  return true
end

--- Drop a registration; the profile's module answers again.
function Font.unregister(versionId)
  if type(versionId) ~= "string" then return false end
  overrides[versionId] = nil
  impls[versionId] = nil
  return true
end

--- The implementation table for a version id (nil or "" = active game).
function Font.impl(versionId)
  local key = versionId
  if type(key) ~= "string" or key == "" then key = Profile.active().id end
  local impl = overrides[key] or impls[key]
  if impl then return impl end
  local ok, mod = pcall(require, modulePath(key))
  if ok and type(mod) == "table" then
    impls[key] = mod
    return mod
  end
  if key ~= Profile.FALLBACK_ID then
    local okDefault, fallback = pcall(require, modulePath(Profile.FALLBACK_ID))
    if okDefault and type(fallback) == "table" then
      impls[key] = fallback
      return fallback
    end
  end
  log("no glyph implementation for '" .. tostring(key) .. "'")
  return nil
end

function Font.active()
  return Font.impl(nil)
end

--- Test/tool hook: drop resolved implementations.  Explicit registrations are
-- boot-time API calls, not cache, so they survive.
function Font.reset()
  impls = {}
  logged = false
end

-- Reads forward live: Font.draw resolves through the active implementation on
-- every call, so invalidate()/ensure() state can never go stale behind a
-- snapshot.  The implementation functions carry no self (frlg_font.lua), so
-- forwarding the raw function is exact.
setmetatable(Font, {
  __index = function(_, key)
    local impl = Font.impl(nil)
    if not impl then return nil end
    return rawget(impl, key)
  end,
})

return Font
