-- Android mod / save Import must open the SAF picker (love.system.pickFile
-- with kind) and consume picked_mod.zip / picked_save.sav on focus, mirroring
-- the ROM flow.  Self-contained: `luajit tests/rom_importer_android_mod_pick_test.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("rom importer android mod/save pick")
local eq = S.eq
local check = S.check

local RomImporter = require("src.import.RomImporter")

love.system = love.system or {}
local saved = {
  getOS = love.system.getOS,
  pickFile = love.system.pickFile,
  pickFileKinds = love.system.pickFileKinds,
}

local pickCalls = {}
love.system.getOS = function() return "Android" end
love.system.pickFile = function(kind)
  pickCalls[#pickCalls + 1] = kind or "rom"
  return true
end
love.system.pickFileKinds = function() return "rom,mod,sav,required_import" end

local function freshImporter(ready)
  return setmetatable({
    android = true,
    workState = nil,
    tab = "mods",
    ready = {
      red = ready.red and true or false,
      blue = ready.blue and true or false,
    },
    saveNotice = {},
    modNotice = nil,
    androidPendingVersion = nil,
    _installMod = function(self, source)
      self._installed = source
      self.modNotice = { ok = true, text = "Installed test" }
    end,
    _importSave = function(self, version, source)
      self._imported = { version = version, source = source }
      self.saveNotice[version] = { ok = true, text = "Imported" }
    end,
    _savedropTarget = RomImporter._savedropTarget,
    _refreshMods = function() end,
    _refreshSlots = function() end,
  }, RomImporter)
end

-- Choose mod with nothing pending opens the mod picker.
pickCalls = {}
local ri = freshImporter({ red = true, blue = true })
ri:chooseMod()
eq(#pickCalls, 1, "chooseMod opens the picker when no pending zip exists")
eq(pickCalls[1], "mod", "chooseMod asks pickFile for a mod")

-- Pending USB zip installs without opening the picker.
love.filesystem.write("usb_mod.zip", "PK\0fake")
pickCalls = {}
ri = freshImporter({ red = true, blue = true })
ri:chooseMod()
eq(#pickCalls, 0, "chooseMod installs a pending zip without opening the picker")
eq(ri._installed, "usb_mod.zip", "chooseMod consumed the USB zip")
check(love.filesystem.getInfo("usb_mod.zip") == nil,
  "successful install removes the pending zip")

-- Focus consumes picked_mod.zip even when both ROMs are already ready.
love.filesystem.write("picked_mod.zip", "PK\0saf")
ri = freshImporter({ red = true, blue = true })
ri:focus(true)
eq(ri._installed, "picked_mod.zip", "focus installs the SAF mod drop")
check(love.filesystem.getInfo("picked_mod.zip") == nil,
  "successful focus install removes picked_mod.zip")

-- Choose save opens the sav picker when nothing is pending.
pickCalls = {}
ri = freshImporter({ red = true, blue = true })
ri.tab = "blue"
ri:chooseSaveImport("blue")
eq(#pickCalls, 1, "chooseSaveImport opens the picker when no pending sav exists")
eq(pickCalls[1], "sav", "chooseSaveImport asks pickFile for a sav")
eq(ri.androidPendingVersion, "blue", "pending version is remembered for focus")

-- Focus consumes picked_save.sav into the remembered version.
love.filesystem.write("picked_save.sav", string.rep("S", 32))
ri = freshImporter({ red = true, blue = true })
ri.androidPendingVersion = "blue"
ri:focus(true)
check(ri._imported ~= nil, "focus imports the SAF save drop")
eq(ri._imported.version, "blue", "focus imports into the pending version")
eq(ri._imported.source, "picked_save.sav", "focus reads the SAF save filename")
check(love.filesystem.getInfo("picked_save.sav") == nil,
  "successful focus import removes picked_save.sav")

-- Required mod files use their own safe picker kind and pending filename.
pickCalls = {}
ri = freshImporter({ red = true, blue = true })
ri.nativePicker = true
ri.mobileFileBridge = true
ri.mods = { {
  id = "needs_source",
  manifest = { id = "needs_source", name = "Needs Source",
    required_imports = { { id = "source", name = "Source", file = "source.bin",
      format = "raw", md5 = { "00000000000000000000000000000000" } } } },
} }
ri:chooseRequiredImport("needs_source", "source")
eq(pickCalls[1], "required_import",
  "required file asks for the dedicated picker kind")
eq(ri.pickerPendingModId, "needs_source", "pending mod is remembered")
eq(ri.pickerPendingImportId, "source", "pending import is remembered")

-- A rejected selection stays on the imported-files page, where the player can
-- see it before choosing another file, instead of behind the modal.
ri.nativePicker = false
ri._importRequiredData = RomImporter._importRequiredData
local savedData = love.data
love.data = {
  hash = function() return "not accepted" end,
  encode = function() return "ffffffffffffffffffffffffffffffff" end,
}
ri:_importRequiredData("needs_source", "source", "wrong source bytes")
love.data = savedData
check(ri.requiredImportNotice ~= nil,
  "required import rejection creates an in-modal notice")
eq(ri.requiredImportNotice.modId, "needs_source",
  "required import notice identifies its mod")
eq(ri.requiredImportNotice.importId, "source",
  "required import notice identifies its file")
check(ri.requiredImportNotice.text:find("MD5 mismatch", 1, true) ~= nil,
  "required import notice includes the MD5 failure")
check(ri.modNotice == nil,
  "required import rejection is not hidden in the general Mods notice")

ri.nativePicker = true
ri._importRequiredSource = function(self, modId, importId, source)
  self._requiredImported = { modId = modId, importId = importId, source = source }
  return true
end
love.filesystem.write("picked_required_import.bin", "source bytes")
ri:focus(true)
check(ri._requiredImported ~= nil, "focus consumes a required-file SAF pick")
eq(ri._requiredImported.modId, "needs_source", "focus routes to the pending mod")
eq(ri._requiredImported.importId, "source", "focus routes to the pending declaration")
check(love.filesystem.getInfo("picked_required_import.bin") == nil,
  "focus removes the staged required-file pick")

love.system.getOS = saved.getOS
love.system.pickFile = saved.pickFile
love.system.pickFileKinds = saved.pickFileKinds
-- leftover cleanup if a failed assertion left files behind
love.filesystem.remove("usb_mod.zip")
love.filesystem.remove("picked_mod.zip")
love.filesystem.remove("picked_save.sav")
love.filesystem.remove("picked_required_import.bin")

S.finish()
