-- Cross-version imported datasets through the public sandboxed mod API.
-- The view is semantic and read-only: registry-shaped records in, detached
-- copies out, with generated assets kept inside the selected version namespace.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local GameVersion = require("src.core.GameVersion")
local CacheFs = require("src.import.CacheFs")
local CacheFormat = require("src.import.CacheFormat")

local function serialized(value)
  local function encode(v)
    if type(v) == "string" then return string.format("%q", v) end
    if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
    local keys = {}
    for key in pairs(v) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = { "{" }
    for _, key in ipairs(keys) do
      out[#out + 1] = "[" .. encode(key) .. "]=" .. encode(v[key]) .. ","
    end
    out[#out + 1] = "}"
    return table.concat(out)
  end
  return "return " .. encode(value)
end

local files = {
  ["mods/dataset_probe/manifest.json"] = [[{
    "id": "dataset_probe",
    "name": "Dataset Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2,
    "games": ["all"]
  }]],
  ["mods/dataset_probe/main.lua"] = [[
local mod = ...
local out = {}
for _, version in ipairs({ "red", "blue", "yellow", "gold" }) do
  local view, reason = mod.datasets:open(version)
  if not view then
    out[version] = { reason = reason }
  else
    local registry = view.content.pokemon
    local first = registry:get("FIXMON")
    first.name = "MUTATED"
    local ids = {}
    for id in registry:each() do ids[#ids + 1] = id end
    local immune = view.content.type_chart:get("NORMAL>GHOST")
    local steel = view.content.type_chart:get("STEEL")
    out[version] = {
      version = view.version,
      generation = view.generation,
      name = registry:get("FIXMON").name,
      has = registry:has("FIXMON"),
      ids = ids,
      writable = registry.register ~= nil or registry.patch ~= nil
        or registry.override ~= nil or registry.remove ~= nil,
      sprite = view.assets:path(registry:get("FIXMON").spriteFront),
      spriteInfo = view.assets:info(registry:get("FIXMON").spriteFront),
      normalGhost = immune and immune.multiplier,
      steelCategory = steel and steel.category,
    }
  end
end
local missing, missingReason = mod.datasets:open("silver")
local unknown, unknownReason = mod.datasets:open("crystal")
out.silver = { present = missing ~= nil, reason = missingReason }
out.crystal = { present = unknown ~= nil, reason = unknownReason }
local gold = mod.datasets:open("gold")
out.assetEscape = pcall(function() gold.assets:path("../save.lua") end)
out.rawAssetRead = gold.assets.read ~= nil
mod.exports.result = out
  ]],
}

local isolationMods = {
  ["mods/dataset_mutator/manifest.json"] = [[{
    "id": "dataset_mutator",
    "name": "Dataset Mutator",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2,
    "games": ["all"]
  }]],
  ["mods/dataset_mutator/main.lua"] = [[
local mod = ...
local view = assert(mod.datasets:open("red"))
view.content.pokemon.get = function() return { name = "POISONED" } end
  ]],
  ["mods/dataset_observer/manifest.json"] = [[{
    "id": "dataset_observer",
    "name": "Dataset Observer",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2,
    "games": ["all"],
    "dependencies": ["dataset_mutator"]
  }]],
  ["mods/dataset_observer/main.lua"] = [[
local mod = ...
local view = assert(mod.datasets:open("red"))
mod.exports.name = view.content.pokemon:get("FIXMON").name
  ]],
}

local labels = {
  red = "RED SOURCE", blue = "BLUE SOURCE",
  yellow = "YELLOW SOURCE", gold = "GOLD SOURCE",
}

for _, version in ipairs({ "red", "blue", "yellow", "gold" }) do
  local prefix = GameVersion.cachePrefix(version)
  files[prefix .. "rom-cache.complete"] =
    "rom-cache-v10:" .. GameVersion.info(version).sha1
  files[prefix .. "data/generated/pokemon.lua"] = serialized({
    FIXMON = {
      id = "FIXMON", name = labels[version], dex = version == "gold" and 252 or 152,
      spriteFront = "assets/generated/battle/front/fixmon.png",
    },
    ALPHA = { id = "ALPHA", name = "ALPHA", dex = 1,
      spriteFront = "assets/generated/battle/front/alpha.png" },
  })
  files[prefix .. "data/generated/type_chart.lua"] = serialized({
    matchups = { { attacker = "NORMAL", defender = "GHOST", multiplier = 0 } },
    types = version == "gold" and {
      STEEL = { name = "STEEL", category = "physical", index = 9 },
    } or {},
  })
  files[prefix .. "assets/generated/battle/front/fixmon.png"] = "png-" .. version
end

-- An otherwise plausible Silver tree has no completion marker.  A view must
-- not execute or expose it.
files[GameVersion.cachePrefix("silver") .. "data/generated/pokemon.lua"] =
  serialized({ FIXMON = { id = "FIXMON", name = "UNVERIFIED" } })

T.eq(CacheFormat.markerFor("red"),
  "rom-cache-v10:" .. GameVersion.info("red").sha1,
  "cache marker follows the importer format and version hash")
T.eq(CacheFormat.matches("silver", "rom-cache-v9:stale"), false,
  "stale cache formats are rejected")
T.eq(CacheFormat.markerFor("crystal"), nil,
  "unknown versions have no valid cache marker")

local originalVersion = GameVersion.get()
local originalPrefix = CacheFs.prefix
GameVersion.set("red")

local function isVersionCachePath(path)
  for _, version in ipairs(GameVersion.ORDER) do
    local prefix = GameVersion.cachePrefix(version)
    if path:sub(1, #prefix) == prefix then return true end
  end
  return false
end

-- No mod means the new service is completely cold.  Count only cross-version
-- cache reads so the loader's ordinary discovery/state reads do not matter.
local vanillaFiles = {}
for path, body in pairs(files) do
  if not path:match("^mods/") then
    vanillaFiles[path] = body
  end
end
local vanillaFs = T.sdk.memfs(vanillaFiles)
local vanillaReads = 0
local vanillaRead = vanillaFs.read
vanillaFs.read = function(path)
  if isVersionCachePath(path) then
    vanillaReads = vanillaReads + 1
  end
  return vanillaRead(path)
end
local vanillaData = { pokemon = { ACTIVE = { id = "ACTIVE", name = "ACTIVE" } } }
local vanilla = T.sdk.loadNone({ fs = vanillaFs, data = vanillaData })
T.eq(#vanilla.errors, 0, "no-mod loader remains clean")
T.eq(vanillaReads, 0, "no mod performs no imported-dataset reads")
T.eq(vanillaData.pokemon.ACTIVE.name, "ACTIVE",
  "no mod leaves the active dataset unchanged")
vanilla.release()

local activeData = { pokemon = { ACTIVE = { id = "ACTIVE", name = "ACTIVE" } } }
local run = T.sdk.loadMods({ "mods/dataset_probe" }, {
  fs = T.sdk.memfs(files), data = activeData, generation = 1,
})
T.eq(#run.errors, 0,
  "sandboxed dataset probe loads clean: " .. tostring(run.errors[1]))
local out = run.loader.exports.dataset_probe
  and run.loader.exports.dataset_probe.result or {}

for _, version in ipairs({ "red", "blue", "yellow", "gold" }) do
  local got = out[version] or {}
  T.eq(got.version, version, version .. " view reports its selected version")
  T.eq(got.generation, version == "gold" and 2 or 1,
    version .. " view reports the selected generation")
  T.eq(got.name, labels[version],
    version .. " returns its own semantic species record")
  T.eq(got.has, true, version .. " registry has() reads the imported view")
  T.same(got.ids, { "ALPHA", "FIXMON" },
    version .. " registry each() is deterministic")
  T.eq(got.writable, false, version .. " registry exposes no write verbs")
  T.eq(got.sprite,
    GameVersion.cachePrefix(version) .. "assets/generated/battle/front/fixmon.png",
    version .. " asset path stays in its cache namespace")
  T.same(got.spriteInfo, { type = "file" },
    version .. " asset info is sanitized metadata")
  T.eq(got.normalGhost, 0,
    version .. " exposes structured matchup ids semantically")
end
T.eq(out.gold and out.gold.steelCategory, "physical",
  "Gold exposes imported Steel as a semantic type record")

T.same(out.silver, { present = false, reason = "not_imported" },
  "an unverified cache is unavailable")
T.same(out.crystal, { present = false, reason = "unknown_version" },
  "an unknown version fails with a stable reason")
T.eq(out.assetEscape, false, "dataset asset paths reject traversal")
T.eq(out.rawAssetRead, false, "dataset assets expose no raw byte reader")
T.eq(activeData.pokemon.ACTIVE.name, "ACTIVE",
  "cross-version reads do not mutate the active game dataset")
T.eq(activeData.pokemon.FIXMON, nil,
  "cross-version records are not merged into active game data")
T.eq(GameVersion.get(), "red", "dataset reads do not switch the active game")
T.eq(CacheFs.prefix, originalPrefix, "dataset reads do not change cache prefix state")

run.release()

local isolationFiles = {}
for path, body in pairs(files) do
  if not path:match("^mods/") then
    isolationFiles[path] = body
  end
end
for path, body in pairs(isolationMods) do isolationFiles[path] = body end
local isolationRun = T.sdk.loadMods({
  "mods/dataset_mutator", "mods/dataset_observer",
}, { fs = T.sdk.memfs(isolationFiles),
     data = { pokemon = {} }, generation = 1 })
T.eq(#isolationRun.errors, 0, "cross-mod isolation fixture loads cleanly")
T.eq(isolationRun.loader.exports.dataset_observer
    and isolationRun.loader.exports.dataset_observer.name,
  labels.red, "one mod cannot mutate another mod dataset facade")
isolationRun.release()

GameVersion.set(originalVersion)
CacheFs.prefix = originalPrefix

T.finish("dataset_views")
