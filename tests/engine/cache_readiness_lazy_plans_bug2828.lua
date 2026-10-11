package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")

love.filesystem.getSource = function() return "/game" end
love.filesystem.getRealDirectory = function() return nil end
love.filesystem.getInfo = function() return nil end
love.filesystem.read = function() return nil end

local CacheContract = require("src.import.CacheContract")
local CacheFs = require("src.import.CacheFs")
local GameVersion = require("src.core.GameVersion")

local function heavyLoaded()
  local out = {}
  for name in pairs(package.loaded) do
    if name:match("^src%.import%.gba%.games%.") or name:match("^src%.import%.gba%.plans%.")
        or name:match("^src%.import%.gba%.syms%.") or name:match("^src%.import%.gba%.rse%.")
        or name:match("^src%.import%.gba%.rs%.extract_") then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

local before = #heavyLoaded()
for _, version in ipairs(GameVersion.ORDER) do
  if GameVersion.generation(version) == 3 then
    T.eq(CacheContract.sourceTreeHasData(version), false, version .. " has no source-tree cache")
    T.eq(CacheContract.isReady(version, CacheFs), false, version .. " is not ready")
    local presence = CacheContract.presenceFilesFor and CacheContract.presenceFilesFor(version)
    T.check(type(presence) == "table" and #presence > 0, version .. " has presence probe files")
  end
end
local loaded = heavyLoaded()
T.eq(#loaded - before, 0,
  "probing un-imported Gen 3 versions loads no extractor or game modules ("
    .. table.concat(loaded, ", "):sub(1, 200) .. ")")

local full = CacheContract.requiredFilesFor("emerald")
local seen = {}
for _, path in ipairs(full) do seen[path] = true end
for _, path in ipairs(CacheContract.presenceFilesFor and CacheContract.presenceFilesFor("emerald") or {}) do
  T.check(seen[path] == true, "presence file " .. path .. " is part of the full Emerald contract")
end

T.finish("cache_readiness_lazy_plans_bug2828")
