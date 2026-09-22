-- Shared GBA extract cache roots (T6.3a skeleton).
--
-- Why: src/import/gba/extract_island1.lua owns Extract.CACHE_ROOT today, and
-- src/core/game3/pokemon.lua requires that extractor just to read the root
-- (I8: runtime → extractor → runtime).  This module is the one place the root
-- lives, so the runtime can read it without pulling the extractor in, and
-- Dataset.mountExtractRoots can set one root for both.
--
-- Unwired: nothing requires this file yet.  The T6.2/T6.3 handoff patch makes
-- extract_island1.lua read/write CachePaths and swaps pokemon.lua's require.
-- The defaults below are exactly extract_island1.lua:19-21's current values.

local CachePaths = {}

CachePaths.CACHE_ROOT = "data/generated/gba"
CachePaths.NATIVE_ROOT = "data/generated/gba/native"

--- Set both roots from one cache root (mountExtractRoots / POKEPORT_GBA_CACHE).
function CachePaths.setRoot(root)
  if type(root) ~= "string" or root == "" then return false end
  CachePaths.CACHE_ROOT = root
  CachePaths.NATIVE_ROOT = root .. "/native"
  return true
end

--- Test/tool hook: back to the packaged defaults.
function CachePaths.reset()
  CachePaths.CACHE_ROOT = "data/generated/gba"
  CachePaths.NATIVE_ROOT = "data/generated/gba/native"
end

return CachePaths
