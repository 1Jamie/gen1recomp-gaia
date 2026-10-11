package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

local realOpen = io.open

love = {
  system = { getOS = function() return "Windows" end },
  filesystem = {
    read = function() return nil end,
    getInfo = function() return nil end,
  },
}

local tmpBase = (os.getenv("TMPDIR") or "/tmp"):gsub("/+$", "")
local dir = ("%s/pp2866-pick-%d-%d/Am\195\186ro"):format(tmpBase, os.time(), math.random(1, 1e6))
local SaveData = require("src.core.SaveData")
check(SaveData.mkdirNative(dir), "fixture dir")

local romPath = dir .. "/pokeport_rom_pick.gb"
local savPath = dir .. "/pokeport_sav_pick.sav"
local romBytes = string.rep("\1", 4096)
local savBytes = string.rep("\2", 32768)
for path, bytes in pairs({ [romPath] = romBytes, [savPath] = savBytes }) do
  local f = assert(realOpen(path, "wb"))
  f:write(bytes)
  f:close()
end

local function ansiOnly(fn)
  return function(p, ...)
    if type(p) == "string" and p:find("[\128-\255]") then
      return nil, p .. ": No such file or directory"
    end
    return fn(p, ...)
  end
end
SaveData.openNative = function(p, mode) return realOpen(p, mode or "rb") end
io.open = ansiOnly(realOpen)

local FilePicker = require("src.core.FilePicker")
local got = FilePicker.read(romPath)
check(got == romBytes, "FilePicker.read opens a picked file under a non-ASCII user folder")

local SaveFileIO = require("src.import.SaveFileIO")
local bytes = SaveFileIO._readSource(savPath)
check(bytes == savBytes, "SaveFileIO reads a picked .sav under a non-ASCII user folder")

local LauncherMods = require("src.mods.LauncherMods")
local modBytes = LauncherMods._readArchive(romPath)
check(modBytes == romBytes, "LauncherMods reads a picked zip under a non-ASCII user folder")

io.open = realOpen
os.remove(romPath)
os.remove(savPath)
os.remove(dir)
os.remove(dir:match("^(.*)/[^/]+$"))

T.finish()
