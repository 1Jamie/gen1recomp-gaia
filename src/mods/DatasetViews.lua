-- Read-only, bounded views over version-scoped generated datasets.

local CacheContract = require("src.import.CacheContract")
local DatasetHydration = require("src.core.DatasetHydration")
local GameVersion = require("src.core.GameVersion")
local Logger = require("src.core.Logger")
local SaveSerializer = require("src.core.SaveSerializer")
local Builtins = require("src.mods.Builtins")
local Registry = require("src.mods.Registry")
local Schemas = require("src.mods.Schemas")

local DatasetViews = {}
DatasetViews.__index = DatasetViews

-- A generated module is ROM-sized data, never an arbitrary program. These
-- caps bound both one malicious file and the aggregate work one open performs.
local DECODE_LIMITS = {
  allowArray = true,
  allowComments = true,
  maxBytes = 8 * 1024 * 1024,
  maxDepth = 64,
  maxNodes = 500000,
  maxStringBytes = 2 * 1024 * 1024,
  maxTableEntries = 250000,
  rootName = "generated data",
}
local MAX_AGGREGATE_BYTES = 48 * 1024 * 1024

local GEN1_ROOTS = {
  constants = "constants", maps = "maps", tilesets = "tilesets",
  text = "text", text_pointers = "text_pointers",
  trainer_headers = "trainer_headers", font = "font", sprites = "sprites",
  pokemon = "pokemon", moves = "moves", items = "items",
  type_chart = "type_chart", trainers = "trainers",
  encounters = "encounters", field = "field",
  battle_anims = "battle_anims", audio = "audio",
  palettes = "palettes", icons = "icons",
}

local GEN2_ROOTS = {
  pokemon = "pokemon", moves = "moves", items = "items",
  type_chart = "type_chart", audio = "audio", font = "font",
  gen2Maps = "maps", gen2Tilesets = "tilesets", gen2Text = "text",
  gen2Trainers = "trainers", gen2Encounters = "encounters",
  gen2Sprites = "sprites", gen2Palettes = "palettes",
  gen2Icons = "icons", gen2BattleAnims = "battle_anims",
  gen2Constants = "constants", gen2Landmarks = "landmarks",
}

local function decode(source)
  return SaveSerializer.decode(source, DECODE_LIMITS)
end

local function resolvePath(root, suffix)
  local node = root
  for key in suffix:gmatch("[^.]+") do
    if type(node) ~= "table" then return nil end
    node = node[key]
  end
  return node
end

local function assetRelative(path)
  if type(path) ~= "string" or path == "" then
    error("dataset asset path is required", 3)
  end
  if path:find("\\", 1, true) or path:sub(1, 1) == "/"
      or path:find("[%z\1-\31]") then
    error("dataset asset path must be a generated relative path", 3)
  end
  if path:sub(1, 17) ~= "assets/generated/" then
    error("dataset assets are limited to assets/generated/", 3)
  end
  for segment in path:gmatch("[^/]+") do
    if segment == "." or segment == ".." then
      error("dataset asset path may not traverse directories", 3)
    end
  end
  return path
end

local function copyData(value, state, depth)
  state = state or { seen = {}, nodes = 0 }
  state.nodes = state.nodes + 1
  if state.nodes > DECODE_LIMITS.maxNodes then return nil, false end
  local kind = type(value)
  if kind == "nil" or kind == "boolean" or kind == "number" then return value end
  if kind == "string" then
    if #value > DECODE_LIMITS.maxStringBytes then return nil, false end
    return value
  end
  if kind ~= "table" or getmetatable(value) ~= nil then return nil, false end
  depth = (depth or 0) + 1
  if depth > DECODE_LIMITS.maxDepth or state.seen[value] then return nil, false end
  state.seen[value] = true
  local out, entries = {}, 0
  for key, child in pairs(value) do
    entries = entries + 1
    if entries > DECODE_LIMITS.maxTableEntries then return nil, false end
    local keyCopy, keyOk = copyData(key, state, depth)
    local childCopy, childOk = copyData(child, state, depth)
    if keyOk == false or childOk == false or keyCopy == nil then return nil, false end
    out[keyCopy] = childCopy
  end
  state.seen[value] = nil
  return out, true
end

local function isDataOnly(value, state, depth)
  state = state or { seen = {}, nodes = 0 }
  state.nodes = state.nodes + 1
  if state.nodes > DECODE_LIMITS.maxNodes then return false end
  local kind = type(value)
  if kind == "nil" or kind == "boolean" or kind == "number" then return true end
  if kind == "string" then return #value <= DECODE_LIMITS.maxStringBytes end
  if kind ~= "table" or getmetatable(value) ~= nil then return false end
  depth = (depth or 0) + 1
  if depth > DECODE_LIMITS.maxDepth or state.seen[value] then return false end
  state.seen[value] = true
  local entries = 0
  for key, child in pairs(value) do
    entries = entries + 1
    if entries > DECODE_LIMITS.maxTableEntries
        or not isDataOnly(key, state, depth)
        or not isDataOnly(child, state, depth) then
      return false
    end
  end
  state.seen[value] = nil
  return true
end

function DatasetViews.new(fs, engineRequire)
  assert(fs and fs.read and fs.getInfo,
    "DatasetViews.new requires a readable filesystem")
  return setmetatable({ fs = fs, engineRequire = engineRequire or require,
    datasets = {} }, DatasetViews)
end

function DatasetViews:_validate(version, inspected)
  local sources, aggregate = {}, 0
  local modules = CacheContract.semanticModules(version)
  for _, name in ipairs(CacheContract.optionalSemanticModules(version)) do
    local path = inspected.prefix .. "data/generated/" .. name .. ".lua"
    if self.fs.getInfo(path, "file") then modules[#modules + 1] = name end
  end
  for _, name in ipairs(modules) do
    local path = inspected.prefix .. "data/generated/" .. name .. ".lua"
    local info = self.fs.getInfo(path, "file")
    local size = info and info.size
    if size and size > DECODE_LIMITS.maxBytes then return nil, name .. ": size limit" end
    aggregate = aggregate + (size or 0)
    if aggregate > MAX_AGGREGATE_BYTES then return nil, "aggregate size limit" end
  end
  aggregate = 0
  for _, name in ipairs(modules) do
    local path = inspected.prefix .. "data/generated/" .. name .. ".lua"
    local source = self.fs.read(path)
    if type(source) ~= "string" then return nil, "missing " .. name end
    aggregate = aggregate + #source
    if aggregate > MAX_AGGREGATE_BYTES then return nil, "aggregate size limit" end
    local value, err = decode(source)
    if type(value) ~= "table" then
      return nil, name .. ": " .. tostring(err or "non-table root")
    end
    sources[name] = source
  end
  return sources
end

function DatasetViews:_module(view, root)
  local moduleName = view.modules[root]
  if not moduleName then return nil end
  local source = view.sources[moduleName]
  if source == nil then return nil end
  local cached = view.moduleCache[moduleName]
  if cached and cached.source == source then return cached.value end
  local value = assert(decode(source))
  view.moduleCache[moduleName] = { source = source, value = value }
  return value
end

function DatasetViews:_data(view)
  if view.data then return view.data end
  local data = {}
  setmetatable(data, {
    __index = function(target, root)
      local value = self:_module(view, root)
      if value ~= nil then rawset(target, root, value) end
      return value
    end,
  })
  DatasetHydration.apply(data, view.version, self.engineRequire)
  view.data = data
  return data
end

local function registryBase(data, target)
  return function() return resolvePath(data, target) end
end

function DatasetViews:_registries(view)
  if view.registries then return view.registries end
  local data = self:_data(view)
  local registries = {}
  for name, catalogSpec in pairs(Schemas.REGISTRIES) do
    local spec = Schemas.shapeFor(name, catalogSpec, view.generation)
    local registry = Registry.new(name, spec)
    local target = Schemas.targetFor(name, catalogSpec, view.generation)
    if target then registry.base = registryBase(data, target) end
    registries[name] = registry
  end
  Builtins.install(registries, data, view.generation, self.engineRequire)
  for _, registry in pairs(registries) do registry:freeze() end
  view.registries = registries
  return registries
end

function DatasetViews:_registry(view, name)
  local registry = self:_registries(view)[name]
  local function rawAt(id)
    local value = registry and registry:get(id)
    if value == nil or not isDataOnly(value) then return nil end
    return value
  end
  local function valueAt(id)
    local value = rawAt(id)
    if value == nil then return nil end
    return (copyData(value))
  end
  return {
    get = function(_, id)
      if type(id) ~= "string" or id == "" then return nil end
      return valueAt(id)
    end,
    has = function(_, id)
      if type(id) ~= "string" or id == "" then return false end
      return rawAt(id) ~= nil
    end,
    each = function()
      local ids = {}
      if registry then
        for id, value in registry:each() do
          if type(id) == "string" and isDataOnly(value) then ids[#ids + 1] = id end
        end
      end
      table.sort(ids)
      local index = 0
      return function()
        index = index + 1
        local id = ids[index]
        if id == nil then return nil end
        return id, valueAt(id)
      end
    end,
  }
end

function DatasetViews:_assets(view)
  local service = self
  local assets = {}
  function assets:path(path) return view.prefix .. assetRelative(path) end
  function assets:info(path)
    local full = self:path(path)
    local info = service.fs.getInfo and service.fs.getInfo(full, "file")
    if not info or (info.type and info.type ~= "file") then return nil end
    local out = { type = "file" }
    if info.size ~= nil then out.size = info.size end
    return out
  end
  return assets
end

function DatasetViews:open(version)
  if type(version) ~= "string" or not GameVersion.VERSIONS[version] then
    return nil, "unknown_version"
  end
  local inspected, reason, detail = CacheContract.inspect(version, self.fs, {
    allowSource = true, semantic = true,
  })
  if not inspected then
    self.datasets[version] = nil
    Logger.warn("dataset %s unavailable: %s", version, detail)
    return nil, reason
  end
  local sources, invalid = self:_validate(version, inspected)
  if not sources then
    self.datasets[version] = nil
    Logger.warn("dataset %s cache rejected: %s", version, invalid)
    return nil, "invalid_cache"
  end

  local internal = self.datasets[version]
  local changed = not internal or internal.prefix ~= inspected.prefix
  if internal and not changed then
    for name, source in pairs(internal.sources) do
      if sources[name] ~= source then changed = true; break end
    end
  end
  if internal and not changed then
    for name, source in pairs(sources) do
      if internal.sources[name] ~= source then changed = true; break end
    end
  end
  if changed then
    internal = {
      version = version,
      generation = GameVersion.generation(version),
      prefix = inspected.prefix,
      modules = GameVersion.generation(version) == 2 and GEN2_ROOTS or GEN1_ROOTS,
      moduleCache = {}, sources = sources,
    }
    local ok, buildError = pcall(function() internal.registries = self:_registries(internal) end)
    if not ok then
      Logger.warn("dataset %s semantic hydration failed: %s", version,
        tostring(buildError))
      self.datasets[version] = nil
      return nil, "invalid_cache"
    end
    self.datasets[version] = internal
  else
    internal.sources = sources
  end

  local view = { version = version, generation = internal.generation, content = {} }
  for name in pairs(Schemas.REGISTRIES) do
    view.content[name] = self:_registry(internal, name)
  end
  for alias, canonical in pairs(Schemas.ALIASES) do
    view.content[alias] = view.content[canonical]
  end
  view.assets = self:_assets(internal)
  return view
end

return DatasetViews
