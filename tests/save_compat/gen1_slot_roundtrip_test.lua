package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
local K = require("tests.save_compat._codec")

if not K.gen1Available() then
  print("gen1_slot_roundtrip skipped (needs data/generated/ for the Gen 1 save codec)")
  os.exit(0)
end

local GenSave = require("src.save_convert.GenSave")
local SaveConvert = require("src.save_convert.SaveConvert")
local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
local SaveFileIO = require("src.import.SaveFileIO")
local SaveSerializer = require("src.core.SaveSerializer")
local Pokemon = require("src.pokemon.Pokemon")
local G1 = require("tests.fixtures.save.gen1_build")
local Diff = require("tests.save_compat._diff")

local O = GenSave.OFFSETS
local realFS = love.filesystem

local function memfs(files)
  return {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    createDirectory = function() return true end,
    getSaveDirectory = function() return "/fake/save" end,
  }
end

local function fresh()
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set("red")
  return files
end

local function engineCart(version)
  local data = K.gen1Data(version)
  local save = SaveData.newGame({})
  save.version = version
  save.player.name = "ASH"
  save.player.map, save.player.x, save.player.y = "PALLET_TOWN", 5, 6
  save.party = { Pokemon.new(data, "CHARMANDER", 8) }
  save.flags.EVENT_GOT_STARTER = true
  save.flags.EVENT_CHOSE_CHARMANDER = true
  save.options = { textSpeed = 3, battleStyle = "shift", animations = true }
  return assert(SaveConvert.exportSav(save, version))
end

local function withOptions(bytes, byte)
  local at = O.options
  local out = bytes:sub(1, at) .. string.char(byte) .. bytes:sub(at + 2)
  local sum = 0
  for i = O.checksumStart + 1, O.checksumEnd do sum = (sum + out:byte(i)) % 256 end
  return out:sub(1, O.mainChecksum) .. string.char(255 - sum) .. out:sub(O.mainChecksum + 2)
end

local function normalized(bytes)
  local tag = O.identityTag
  return bytes:sub(1, tag) .. string.rep("\0", 36) .. bytes:sub(tag + 37)
end

local base = engineCart("red")

for _, case in ipairs({
  { byte = 0x01, speed = 1, style = "shift", anim = true },
  { byte = 0x05, speed = 5, style = "shift", anim = true },
  { byte = 0x43, speed = 3, style = "set", anim = true },
  { byte = 0xC1, speed = 1, style = "set", anim = false },
  { byte = 0x80 + 0x20 + 0x07, speed = 7, style = "shift", anim = false },
}) do
  local files = fresh()
  local cart = withOptions(base, case.byte)
  local ok, slot = SaveFileIO.importToSlot(cart, "red")
  eq(ok, true, ("options %02X: import succeeds (%s)"):format(case.byte, tostring(slot)))
  local live = SaveData.loadOptions()
  eq(live.textSpeed, case.speed, ("options %02X: the cart text speed becomes the live setting"):format(case.byte))
  eq(live.battleStyle, case.style, ("options %02X: the cart battle style becomes the live setting"):format(case.byte))
  eq(live.animations, case.anim, ("options %02X: the cart battle animations setting becomes the live setting"):format(case.byte))

  local loaded = SaveData.load("red")
  eq(loaded.options.textSpeed, case.speed, ("options %02X: the loaded save sees them"):format(case.byte))
  eq(loaded.importedOptions, nil, ("options %02X: the one-shot hand-off never reaches the slot file"):format(case.byte))
  local onDisk = SaveSerializer.decode(files["saves/red/" .. slot .. ".lua"])
  eq(onDisk.importedOptions, nil, ("options %02X: the slot file carries no hand-off"):format(case.byte))
  eq(onDisk.options, nil, ("options %02X: and no embedded options"):format(case.byte))

  eq(SaveFileIO.exportActiveSlot("red"), true, "export succeeds")
  local out = files["exports/red/gen1recomp-red-" .. slot .. ".sav"]
  eq(out:byte(O.options + 1), case.byte, ("options %02X: an untouched slot exports the cart's wOptions byte"):format(case.byte))
  check(normalized(out) == normalized(cart), ("options %02X: and the whole image is unchanged (%s)"):format(case.byte,
    Diff.format(Diff.diff(normalized(cart), normalized(out), Diff.regionsFor(1, "red")), 4)))

  loaded.options.textSpeed = 3
  loaded.options.battleStyle = "set"
  loaded.options.animations = false
  SaveData.save(loaded)
  eq(SaveFileIO.exportActiveSlot("red"), true, "re-export succeeds")
  out = files["exports/red/gen1recomp-red-" .. slot .. ".sav"]
  eq(bit.band(out:byte(O.options + 1), 0xC7), 0xC3, ("options %02X: a live change in game reaches the cart"):format(case.byte))
  eq(bit.band(out:byte(O.options + 1), 0x38), bit.band(case.byte, 0x38), ("options %02X: the bits the engine has no setting for are kept"):format(case.byte))
end

do
  local files = fresh()
  SaveData.saveOptions(SaveData.mergeOptions({ textSpeed = 5, battleStyle = "set", animations = false, musicVol = 2 }))
  local ok, slot = SaveFileIO.importToSlot(withOptions(base, 0x01), "red")
  eq(ok, true, "import over customised options")
  local live = SaveData.loadOptions()
  eq(live.musicVol, 2, "machine settings (audio) are never touched by an import")
  eq(live.textSpeed, 1, "only the three wOptions settings follow the cart")
end

do
  local files = fresh()
  local ok, slot = SaveFileIO.importToSlot(base, "red")
  eq(ok, true, "import for the image round trip")
  local slotFile = SaveSerializer.decode(files["saves/red/" .. slot .. ".lua"])
  eq(slotFile.rawImport, base, "G1-19: the whole 32768-byte cart image rides the slot file")
  local loaded = SaveData.load("red")
  eq(loaded.rawImport, base, "and survives SaveData.load, migrations and validation")
  loaded.money = 1234
  SaveData.save(loaded)
  local again = SaveData.load("red")
  eq(again.rawImport, base, "and an in-game save of the slot")
  eq(SaveFileIO.exportActiveSlot("red"), true, "export")
  local out = files["exports/red/gen1recomp-red-" .. slot .. ".sav"]
  local back = assert(SaveConvert.importSav(out, "red", "red"))
  eq(back.money, 1234, "the export carries the in-game change")
  local changed = Diff.diff(normalized(base), normalized(out), Diff.regionsFor(1, "red"))
  local names = {}
  for _, e in ipairs(changed) do names[#names + 1] = e.name end
  table.sort(names)
  eq(table.concat(names, ","), "money", "and nothing else differs from the source cart")
  eq(SaveFileIO.exportActiveSlot("red"), true, "second export")
  eq(files["exports/red/gen1recomp-red-" .. slot .. ".sav"], out, "the export is a fixed point")
end

love.filesystem = realFS
SaveData.resetSlotState()
GameVersion.set("red")

T.finish()
