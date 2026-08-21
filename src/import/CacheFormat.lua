-- Current completion-marker contract for generated ROM caches.
-- Pure and version-aware so read-only consumers can verify an import without
-- loading the launcher or changing CacheFs.prefix.

local GameVersion = require("src.core.GameVersion")

local CacheFormat = {}

CacheFormat.PREFIX = "rom-cache-v10:"

function CacheFormat.markerFor(version)
  local info = GameVersion.VERSIONS[version]
  if not info then return nil end
  return CacheFormat.PREFIX .. info.sha1
end

function CacheFormat.matches(version, marker)
  local expected = CacheFormat.markerFor(version)
  return expected ~= nil and marker == expected
end

return CacheFormat
