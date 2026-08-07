-- Opaque playthrough identity: New Game uniqueness, save/load persistence,
-- stable legacy backfill, and version/slot isolation. No real save directory.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local GameVersion = require("src.core.GameVersion")

local realFS = love.filesystem

local function memfs(files)
  return {
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    createDirectory = function() return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    getDirectoryItems = function(path)
      local prefix, seen, out = path .. "/", {}, {}
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then
          local child = key:sub(#prefix + 1):match("^[^/]+")
          if child and not seen[child] then
            seen[child] = true
            out[#out + 1] = child
          end
        end
      end
      table.sort(out)
      return out
    end,
  }
end

local function fresh()
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set("red")
  return files
end

local function legacy(version, name)
  return {
    version = version,
    meta = { format = 4, mods = {} },
    player = { name = name, map = "PALLET_TOWN", x = 5, y = 6 },
    flags = {}, inventory = {}, pcItems = {}, party = {}, box = {}, boxes = {},
    money = 3000, defeatedTrainers = {}, pokedex = { seen = {}, owned = {} },
  }
end

-- Removing playthroughId generation from New Game must fail these assertions.
do
  fresh()
  local first = SaveData.newGame({ version = "red" })
  local second = SaveData.newGame({ version = "red" })
  T.check(type(first.meta.playthroughId) == "string"
      and first.meta.playthroughId ~= "",
    "New Game receives an opaque playthrough id")
  T.neq(second.meta.playthroughId, first.meta.playthroughId,
    "separate New Games receive separate playthrough ids")
end

-- Dropping the id from buildMeta or save encoding must fail the roundtrip.
do
  fresh()
  local save = SaveData.newGame({ version = "red" })
  local expected = save.meta.playthroughId
  T.check(SaveData.save(save), "identity fixture saves")
  local loaded = SaveData.load("red")
  T.eq(loaded and loaded.meta.playthroughId, expected,
    "normal save/load preserves the playthrough id")
end

-- Legacy identity is persisted independently: the legacy progress bytes remain
-- unchanged, yet two loads resolve the same id before a normal SAVE occurs.
do
  local files = fresh()
  local raw = legacy("red", "LEGACY")
  files["save.lua"] = SaveSerializer.encode(raw)

  local first = SaveData.load("red")
  local id = first and first.meta.playthroughId
  T.check(type(id) == "string" and id ~= "",
    "a legacy save receives a playthrough id")

  local slotBytes = files["saves/red/slot1.lua"]
  local onDisk = slotBytes and SaveSerializer.decode(slotBytes)
  T.eq(onDisk and onDisk.meta.playthroughId, nil,
    "legacy backfill does not rewrite normal progress")

  SaveData.resetSlotState()
  local second = SaveData.load("red")
  T.eq(second and second.meta.playthroughId, id,
    "legacy backfill is stable across reload before normal SAVE")
end

-- Reusing names and coordinates cannot merge identities across slots or games.
do
  fresh()
  local redA = SaveData.createSlot("red")
  local redB = SaveData.createSlot("red")
  SaveData.setActiveSlot("red", redA)
  T.check(SaveData.writeSlot("red", redA, legacy("red", "SAME")),
    "seed red slot A")
  local idA = SaveData.load("red").meta.playthroughId

  SaveData.setActiveSlot("red", redB)
  T.check(SaveData.writeSlot("red", redB, legacy("red", "SAME")),
    "seed red slot B")
  local idB = SaveData.load("red").meta.playthroughId

  GameVersion.set("blue")
  local blue = SaveData.createSlot("blue")
  SaveData.setActiveSlot("blue", blue)
  T.check(SaveData.writeSlot("blue", blue, legacy("blue", "SAME")),
    "seed blue slot")
  local idBlue = SaveData.load("blue").meta.playthroughId

  T.neq(idA, idB, "two active slots do not share legacy identity")
  T.neq(idA, idBlue, "Red and Blue do not share legacy identity")
  T.neq(idB, idBlue, "every version/slot scope is isolated")
end

love.filesystem = realFS
SaveData.resetSlotState()
GameVersion.set("red")

T.finish("playthrough_identity")
