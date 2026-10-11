package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local HostShell = require("src.core.HostShell")
local Platform = require("src.core.Platform")
local RomImporter = require("src.import.RomImporter")

local commands = {}
local realPopen, realPclose, realPump = HostShell.popen, HostShell.pclose, HostShell.pumpHostEvents
local realSpawn = Platform.canSpawnProcess
local realOS = love.system.getOS
HostShell.popen = function(cmd)
  commands[#commands + 1] = cmd
  return { read = function() return "" end, close = function() end }
end
HostShell.pclose = function() end
HostShell.pumpHostEvents = function() end
Platform.canSpawnProcess = function() return true end
love.system.getOS = function() return "Linux" end
love.filesystem.getDirectoryItems = function() return {} end

local imp = RomImporter.new(function() end, { launcher = true })
imp.nativePicker, imp.android = false, false
imp._inboxImport = function() return false end
local okKit, Kit = pcall(require, "src.ui.kit.Kit")
imp:choose("firered")
if okKit and Kit.FileBrowser then Kit.FileBrowser.close() end

local zenity, kdialog
for _, cmd in ipairs(commands) do
  if cmd:find("zenity", 1, true) then zenity = cmd end
  if cmd:find("kdialog", 1, true) then kdialog = cmd end
end
T.check(zenity ~= nil, "Linux Choose ROM runs zenity")
T.check(kdialog ~= nil, "Linux Choose ROM falls back to kdialog")
for _, ext in ipairs({ "gb", "gbc", "gba", "GB", "GBC", "GBA" }) do
  T.check(zenity and zenity:find("*." .. ext .. " ", 1, true) ~= nil
      or zenity and zenity:find("*." .. ext .. "\"", 1, true) ~= nil,
    "zenity filter lists *." .. ext)
  T.check(kdialog and kdialog:find("*." .. ext, 1, true) ~= nil,
    "kdialog filter lists *." .. ext)
end

local globs = RomImporter._pickerGlobs({ "gba", "7z" })
T.eq(table.concat(globs, " "), "*.gba *.GBA *.7z *.7Z", "upper-case twins for each extension")

HostShell.popen, HostShell.pclose, HostShell.pumpHostEvents = realPopen, realPclose, realPump
Platform.canSpawnProcess = realSpawn
love.system.getOS = realOS

T.finish("rom_picker_case_globs_test")
