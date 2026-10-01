package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local Json = require("src.link.Json")
local Writer = require("src.import.LuaWriter")
local SaveData = require("src.core.SaveData")
local SaveConvert = require("src.save_convert.SaveConvert")
local GameVersion = require("src.core.GameVersion")
local CacheFs = require("src.import.CacheFs")
local Contract = require("src.import.CacheContract")
local Importer = require("src.import.RomImporter")
local Gen2Save = require("src.save_convert.Gen2Save")
local MapContext = require("src.save_convert.Gen2MapContext")
local Compat = require("src.save_convert.Compat")

local realFS, oldVersion, oldPrefix = love.filesystem, GameVersion.get(), CacheFs.prefix
local portableFs, portableBaseDir, isPortable = SaveData.portableFs, SaveData.portableBaseDir, SaveData.isPortable
SaveData.portableFs = function() return nil end
SaveData.portableBaseDir = function() return nil end
SaveData.isPortable = function() return false end
CacheFs._resetPortableForTests()
local function json(path)
  local f = assert(io.open(path, "rb"))
  local value = assert(Json.decode(f:read("*a")))
  f:close()
  return value
end
local builds = json("tests/fixtures/save/gen2_sprite_context.json").builds
local oldFormats = { gold = "rom-cache-v12:", silver = "rom-cache-v12:", crystal = "rom-cache-v12-crystal4:" }
local function fixture(version, metadata)
  local constants = json("tools/rom_manifest_" .. version .. ".json").constants
  constants.spriteContext = metadata
  local sprites, teacher = {}, nil
  for id, name in ipairs(constants.spriteOrder) do
    if name ~= "UNUSED" then sprites[name] = {} end
    if name == "SPRITE_TEACHER" then teacher = id end
  end
  assert(teacher)
  local blocks = {}
  for i = 1, 180 do blocks[i] = 1 end
  return { pokemon = {}, moves = {}, items = {}, scripts = {}, constants = constants, sprites = sprites,
    maps = { CHERRYGROVE_CITY = { group = 26, map = 3, width = 20, height = 9, blocks = blocks,
      objectEventsAddr = 0x4000, environment = "TOWN", objects = {
        { spriteId = teacher, x = 8, y = 4, movement = 1, radius = { x = 0, y = 0 } },
      } } } }, teacher
end
local function filesystem(files)
  return {
    read = function(path) return files[path] end,
    write = function(path, bytes) files[path] = bytes return true end,
    remove = function(path) files[path] = nil return true end,
    createDirectory = function() return true end,
    getSaveDirectory = function() return "/scratch/gen2-cache-refresh" end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      for key in pairs(files) do
        if key:sub(1, #path + 1) == path .. "/" then return { type = "directory" } end
      end
    end,
    getDirectoryItems = function(path)
      local result, seen, prefix = {}, {}, path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then
          local child = key:sub(#prefix + 1):match("^[^/]+")
          if child and not seen[child] then seen[child] = true result[#result + 1] = child end
        end
      end
      return result
    end,
  }
end

for _, build in ipairs(builds) do
  local version = build.edition
  local data, teacher = fixture(version, build.metadata)
  local prefix, files = GameVersion.cachePrefix(version), {}
  for name, value in pairs(data) do files[prefix .. "data/generated/" .. name .. ".lua"] = Writer.encode(value) end
  for _, path in ipairs(Contract.requiredFilesFor(version)) do
    files[prefix .. path] = files[prefix .. path] or "asset"
  end
  local constantsPath = prefix .. "data/generated/constants.lua"
  local currentConstants = files[constantsPath]
  data.constants.spriteContext = nil
  files[constantsPath] = Writer.encode(data.constants)
  files[prefix .. Contract.MARKER_PATH] = oldFormats[version] .. GameVersion.info(version).sha1
  love.filesystem = filesystem(files)
  SaveData.resetSlotState()
  SaveConvert.setGen2DataStub(nil)
  GameVersion.set("red")
  CacheFs.prefix = "caller/"
  local slot = assert(SaveData.createSlot(version))
  assert(SaveData.writeSlot(version, slot, {
    version = version, generation = 2, engine = GameVersion.engine(version),
    player = { name = "CHRIS", id = 12345, gender = "male", money = 3000 },
    position = { map = "CHERRYGROVE_CITY", mapGroup = 26, mapNumber = 3, x = 7, y = 3, facing = "down" },
    playerState = "normal", party = {}, events = {},
  }))
  assert(SaveData.setActiveSlot(version, slot))
  local imp = setmetatable({ workState = "idle", launcher = true, saveNotice = {},
    ready = {}, returning = {}, romName = {}, _rememberRomSource = function() end },
    { __index = Importer })
  T.eq(Importer.isReady(version), false, version .. " old metadata cache is not ready")
  imp:exportSave(version)
  T.eq(imp.saveNotice[version].ok, false, version .. " missing metadata refuses launcher export")
  T.check(imp.saveNotice[version].text:find(
    "this save cannot be exported onto map 26/3: Gen 2 sprite metadata is missing (re-import the ROM)", 1, true),
    version .. " launcher reports the exact map and missing metadata")
  T.eq(files["exports/" .. version .. "/gen1recomp-" .. version .. "-" .. slot .. ".sav"], nil,
    version .. " refused export writes no cartridge image")

  files[constantsPath] = currentConstants
  imp:_completeImport(version, prefix, "scratch-" .. version .. ".gbc")
  T.eq(files[prefix .. Contract.MARKER_PATH], Contract.markerFor(version), version .. " reimport publishes current marker")
  T.eq(Importer.isReady(version), true, version .. " regenerated metadata cache is ready")
  T.eq(CacheFs.prefix, "caller/", version .. " completion restores the caller prefix")
  T.eq(GameVersion.get(), "red", version .. " completion does not switch the active game")
  imp:exportSave(version)
  T.eq(imp.saveNotice[version].ok, true,
    version .. " successful reimport refreshes memoized launcher conversion data: " .. tostring(imp.saveNotice[version].text))
  local bytes = files["exports/" .. version .. "/gen1recomp-" .. version .. "-" .. slot .. ".sav"]
  T.eq(bytes and #bytes, Gen2Save.SAVE_SIZE, version .. " recovered export writes a complete SRAM image")
  if bytes then
    T.check(Gen2Save.checksumValid(bytes, Gen2Save.layoutFor(version)), version .. " recovered export passes cartridge checksum")
    T.eq(#Compat.check(bytes, version).errors, 0, version .. " recovered export passes reader gate")
    local O = MapContext.offsetsFor(version)
    T.eq(bytes:byte(O.objectStructs + MapContext.OBJECT_LENGTH + 1), teacher,
      version .. " recovered export reconstructs visible teacher")
    local decoded = assert(Gen2Save.decode(bytes, version, data))
    T.eq(decoded.position.mapGroup, 26, version .. " recovered export retains Cherrygrove group")
    T.eq(decoded.position.mapNumber, 3, version .. " recovered export retains Cherrygrove number")
    T.eq(decoded.player.name, "CHRIS", version .. " recovered export retains player")
  end

  local wrong = assert(loadstring(currentConstants))()
  wrong.spriteContext.edition = version == "crystal" and "gold" or "crystal"
  files[constantsPath] = Writer.encode(wrong)
  imp:_completeImport(version, prefix, "scratch-wrong.gbc")
  imp:exportSave(version)
  T.eq(imp.saveNotice[version].ok, false, version .. " refreshed wrong-edition metadata still refuses export")
  T.check(imp.saveNotice[version].text:find("belongs to a different edition", 1, true),
    version .. " wrong-edition refusal remains explicit")

  local corrupt = assert(loadstring(currentConstants))()
  corrupt.spriteContext.rows[teacher].palette = 8
  files[constantsPath] = Writer.encode(corrupt)
  imp:_completeImport(version, prefix, "scratch-corrupt.gbc")
  imp:exportSave(version)
  T.eq(imp.saveNotice[version].ok, false, version .. " refreshed corrupt sprite row still refuses export")
  T.check(imp.saveNotice[version].text:find("has no data for sprite", 1, true),
    version .. " corrupt-row refusal remains explicit")

  files[constantsPath] = currentConstants
  imp:_completeImport(version, prefix, "scratch-repaired.gbc")
  imp:exportSave(version)
  T.eq(imp.saveNotice[version].ok, true, version .. " second valid reimport recovers from rejected metadata")
end

SaveConvert.setGen2DataStub(nil)
SaveData.resetSlotState()
SaveData.portableFs, SaveData.portableBaseDir, SaveData.isPortable = portableFs, portableBaseDir, isPortable
CacheFs._resetPortableForTests()
love.filesystem = realFS
CacheFs.prefix = oldPrefix
GameVersion.set(oldVersion)
T.finish("gen2 cache refresh")
