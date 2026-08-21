-- Read-only views over verified, version-scoped generated datasets.
--
-- A view reads semantic registry records from another imported version without
-- changing GameVersion, CacheFs.prefix, the active Data table, or any PhysFS
-- mount. Records are detached copies and generated assets stay under the
-- selected version's virtual cache prefix.

local CacheFormat = require("src.import.CacheFormat")
local GameVersion = require("src.core.GameVersion")
local Builtins = require("src.mods.Builtins")
local Merge = require("src.mods.Merge")
local Registry = require("src.mods.Registry")
local Schemas = require("src.mods.Schemas")

local DatasetViews = {}
DatasetViews.__index = DatasetViews

local GEN1_MODULES = {
  constants = "constants", maps = "maps", tilesets = "tilesets",
  text = "text", text_pointers = "text_pointers",
  trainer_headers = "trainer_headers", font = "font", sprites = "sprites",
  pokemon = "pokemon", moves = "moves", items = "items",
  type_chart = "type_chart", trainers = "trainers",
  encounters = "encounters", field = "field",
  battle_anims = "battle_anims", audio = "audio",
  palettes = "palettes", icons = "icons",
}

local GEN2_MODULES = {
  pokemon = "pokemon", moves = "moves", items = "items",
  type_chart = "type_chart", audio = "audio", font = "font",
  gen2Maps = "maps", gen2Tilesets = "tilesets", gen2Text = "text",
  gen2Trainers = "trainers", gen2Encounters = "encounters",
  gen2Sprites = "sprites", gen2Palettes = "palettes",
  gen2Icons = "icons", gen2BattleAnims = "battle_anims",
  gen2Constants = "constants", gen2Landmarks = "landmarks",
}

local function compileTable(source, chunkname)
  if type(source) ~= "string" or source:byte(1) == 27 then return nil end
  local env = {}
  local chunk, err
  if setfenv then
    chunk, err = loadstring(source, chunkname)
    if chunk then setfenv(chunk, env) end
  else
    chunk, err = load(source, chunkname, "t", env)
  end
  if not chunk then return nil, err end
  local ok, value = pcall(chunk)
  if not ok or type(value) ~= "table" then
    return nil, ok and "generated module did not return a table" or value
  end
  return value
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

function DatasetViews.new(fs)
  assert(fs and fs.read, "DatasetViews.new requires a readable filesystem")
  return setmetatable({ fs = fs, datasets = {} }, DatasetViews)
end

function DatasetViews:_module(view, root)
  local moduleName = view.modules[root]
  if not moduleName then return nil end
  local cached = view.moduleCache[moduleName]
  if cached ~= nil then return cached or nil end
  local path = view.prefix .. "data/generated/" .. moduleName .. ".lua"
  local source = self.fs.read(path)
  local value = compileTable(source, "@" .. path)
  view.moduleCache[moduleName] = value or false
  return value
end

function DatasetViews:_data(view)
  if view.data then return view.data end
  local data = {}
  for root in pairs(view.modules) do
    local value = self:_module(view, root)
    if value ~= nil then data[root] = value end
  end
  view.data = data
  return data
end

local function registryBase(data, target)
  return function()
    return resolvePath(data, target)
  end
end

function DatasetViews:_registries(view)
  if view.registries then return view.registries end
  local data = self:_data(view)
  local registries = {}
  for name, catalogSpec in pairs(Schemas.REGISTRIES) do
    local spec = Schemas.shapeFor(name, catalogSpec, view.generation)
    local registry = Registry.new(name, spec)
    if spec.target then registry.base = registryBase(data, spec.target) end
    registries[name] = registry
  end
  Builtins.install(registries, data, view.generation)
  for _, registry in pairs(registries) do registry:freeze() end
  view.registries = registries
  return registries
end

function DatasetViews:_registry(view, name)
  local registry = self:_registries(view)[name]

  local function valueAt(id)
    local value = registry and registry:get(id)
    if value == nil then return nil end
    return Merge.deepCopy(value)
  end

  return {
    get = function(_, id)
      if type(id) ~= "string" or id == "" then return nil end
      return valueAt(id)
    end,
    has = function(_, id)
      return valueAt(id) ~= nil
    end,
    each = function()
      local ids = {}
      if registry then
        for id in registry:each() do
          if type(id) == "string" then ids[#ids + 1] = id end
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

  function assets:path(path)
    return view.prefix .. assetRelative(path)
  end

  function assets:info(path)
    local full = self:path(path)
    local info = service.fs.getInfo and service.fs.getInfo(full, "file")
    if not info then return nil end
    local out = { type = info.type }
    if info.size ~= nil then out.size = info.size end
    return out
  end

  return assets
end

function DatasetViews:open(version)
  if type(version) ~= "string" or not GameVersion.VERSIONS[version] then
    return nil, "unknown_version"
  end
  local internal = self.datasets[version]
  if not internal then
    local prefix = GameVersion.cachePrefix(version)
    local marker = self.fs.read(prefix .. "rom-cache.complete")
    if not CacheFormat.matches(version, marker) then
      return nil, "not_imported"
    end

    local generation = GameVersion.generation(version)
    internal = {
      version = version, generation = generation, prefix = prefix,
      modules = generation == 2 and GEN2_MODULES or GEN1_MODULES,
      moduleCache = {},
    }
    internal.registries = self:_registries(internal)
    self.datasets[version] = internal
  end
  local view = {
    version = version,
    generation = internal.generation,
    content = {},
  }
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
