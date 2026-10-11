package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

local realOpen, realRemove = io.open, os.remove

local files = {}
love = {
  filesystem = {
    read = function(rel)
      local data = files[rel]
      if data == nil then return nil, "Could not open file " .. rel end
      return data
    end,
  },
}

local CacheFs = require("src.import.CacheFs")
local CacheBlob = require("src.import.CacheBlob")

local stalePath = "firered/data/generated/gba/pokemon/pokedex/paper_bg.rgba"
local staleBytes = string.rep("\255", 240 * 160 * 4)
files[stalePath] = staleBytes

local okRead, got = pcall(CacheFs.readAt, stalePath)
check(okRead, "undecodable blob read does not raise: " .. tostring(got))
check(okRead and got == nil, "undecodable blob reads as a cache miss")

local okStrict = pcall(CacheBlob.decode, stalePath, staleBytes)
check(not okStrict, "CacheBlob.decode stays strict for runtime readers")

local okBackend, deflated = pcall(CacheBlob.deflate, staleBytes)
if okBackend then
  files[stalePath] = deflated
  check(CacheFs.readAt(stalePath) == staleBytes, "fresh deflated blob still decodes")
  files[stalePath] = staleBytes
end

local probeRoot = "data/generated/gba"
local probeFiles = setmetatable({}, { __index = function(_, rel)
  if rel:match("%.rgba$") then return staleBytes end
  return string.rep("x", 256)
end })
love.filesystem.read = function(rel) return probeFiles[rel] end
local cache = {
  read = function(_, rel) return CacheFs.read(rel) end,
  exists = function(_, rel) return CacheFs.exists(rel) end,
}
local PokedexChromeExtract = require("src.import.gba.pokedex_chrome_extract")
local okProbe, ready = pcall(PokedexChromeExtract.ready, cache, probeRoot)
check(okProbe, "import readiness probe over a stale blob does not raise: " .. tostring(ready))
check(okProbe and ready == false, "stale blob makes the extractor not ready, so it rewrites it")

local SaveData = require("src.core.SaveData")
local tmpBase = (os.getenv("TMPDIR") or "/tmp"):gsub("/+$", "")
local saveDir = ("%s/pp2866-%d-%d/Am\195\186ro/save"):format(tmpBase, os.time(), math.random(1, 1e6))
local blobRel = "firered/data/generated/gba/pokemon/pokedex/paper_bg.rgba"
local otherRel = "firered/data/generated/gba/pokemon/front/1.rgba"
check(SaveData.mkdirNative(saveDir .. "/firered/data/generated/gba/pokemon/pokedex"), "fixture dir")
check(SaveData.mkdirNative(saveDir .. "/firered/data/generated/gba/pokemon/front"), "fixture dir 2")
for _, rel in ipairs({ blobRel, otherRel }) do
  local f = assert(realOpen(saveDir .. "/" .. rel, "wb"))
  f:write(staleBytes)
  f:close()
end

local function realStat(p)
  local f = realOpen(p, "rb")
  if not f then return nil end
  local okR, _, rerr = pcall(f.read, f, 0)
  f:close()
  if okR and rerr ~= nil then return "directory" end
  return "file"
end

love = {
  system = { getOS = function() return "Windows" end },
  filesystem = {
    getSaveDirectory = function() return saveDir end,
    getInfo = function(rel)
      local kind = realStat(saveDir .. "/" .. rel)
      return kind and { type = kind } or nil
    end,
    getDirectoryItems = function(rel)
      return SaveData.listNative(saveDir .. "/" .. rel) or {}
    end,
    remove = function(rel) return realRemove(saveDir .. "/" .. rel) ~= nil end,
  },
}

local function ansiOnly(fn)
  return function(p, ...)
    if type(p) == "string" and p:find("[\128-\255]") then
      return nil, p .. ": No such file or directory"
    end
    return fn(p, ...)
  end
end
SaveData.openNative = function(p, mode) return realOpen(p, mode or "rb") end
SaveData.removeNative = function(p) return realRemove(p) end
io.open, os.remove = ansiOnly(realOpen), ansiOnly(realRemove)

local RomImporter = require("src.import.RomImporter")
local okClear, clearErr = pcall(RomImporter._removeSaveDirTree, "firered/data/generated")
io.open, os.remove = realOpen, realRemove

check(okClear, "clearing a non-ASCII save dir does not raise: " .. tostring(clearErr))
check(realOpen(saveDir .. "/" .. blobRel, "rb") == nil,
  "stale blob under a non-ASCII save dir is removed before reimport")
check(realOpen(saveDir .. "/" .. otherRel, "rb") == nil,
  "every stale file under a non-ASCII save dir is removed")

for _, rel in ipairs({ blobRel, otherRel }) do realRemove(saveDir .. "/" .. rel) end
for _, rel in ipairs({
  "firered/data/generated/gba/pokemon/pokedex", "firered/data/generated/gba/pokemon/front",
  "firered/data/generated/gba/pokemon", "firered/data/generated/gba",
  "firered/data/generated", "firered/data", "firered", "",
}) do
  realRemove(rel == "" and saveDir or (saveDir .. "/" .. rel))
end
realRemove(saveDir:match("^(.*)/save$"))
realRemove(saveDir:match("^(.*)/Am[^/]*/save$"))

T.finish()
