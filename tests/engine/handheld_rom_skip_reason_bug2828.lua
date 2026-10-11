-- luajit tests/engine/handheld_rom_skip_reason_bug2828.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local check, eq = T.check, T.eq
local noop = function() end

love.data = love.data or {}
love.data.hash = function(_, data) return data:sub(1, 8) end
love.data.encode = function(_, _, digest) return tostring(digest) end

local getenv = os.getenv
os.getenv = function(key)
  if key == "POKEPORT_HANDHELD" then return "1" end
  return getenv(key)
end

local Logger = require("src.core.Logger")

local Kit = require("src.ui.kit.Kit")
local opened
Kit.FileBrowser = {
  open = function(opts) opened = opts end,
  close = noop,
}

local Importer = require("src.import.RomImporter")

local MIB = 1024 * 1024
local function gbaBytes(tag, code, rev, size)
  local head = tag .. ("\0"):rep(0xAC - #tag) .. code .. ("\0"):rep(0xB2 - 0xB0)
    .. "\150" .. ("\0"):rep(0xBC - 0xB3) .. string.char(rev)
  return head .. ("\0"):rep((size or 16 * MIB) - #head)
end

local function fresh()
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    if love.filesystem.getInfo(name, "file") then love.filesystem.remove(name) end
  end
  opened = nil
  for i = #Logger.history, 1, -1 do Logger.history[i] = nil end
  local imp = Importer.new(noop, { launcher = true })
  for v in pairs(imp.ready) do imp.ready[v] = false end
  return imp
end

local function logHas(fragment)
  for _, line in ipairs(Logger.history) do
    if line:find(fragment, 1, true) then return true end
  end
  return false
end

-- 1. Unknown SHA-1 with a FireRed header: the launcher names the hash and the guess.
local imp = fresh()
love.filesystem.write("FireRed.gba", gbaBytes("hack0001", "BPRE", 1))
imp:choose("firered")
check(imp.notice ~= nil, "a skipped candidate leaves a notice on the column")
if imp.notice then
  eq(imp.notice.version, "firered", "the notice targets the chosen column")
  eq(imp.notice.status, "Skipped FireRed.gba:", "the notice names the skipped file")
  check(imp.notice.detail:find("unknown SHA-1 hack0001", 1, true) ~= nil,
    "the notice carries the hash: " .. tostring(imp.notice.detail))
  check(imp.notice.detail:find("FireRed (USA) rev 1", 1, true) ~= nil,
    "the notice guesses the game from the GBA header: " .. tostring(imp.notice.detail))
end
check(opened ~= nil and opened.hint ~= nil and opened.hint:find("hack0001", 1, true) ~= nil,
  "the file browser opens with the skip reason as its hint")
check(logHas("skipped ROM candidate") and logHas("hack0001"),
  "the skip reason is written to the log")

-- 2. A wrong-size dump reports the actual size.
imp = fresh()
love.filesystem.write("Sapphire.GBA", gbaBytes("trim0001", "AXPE", 0, 16 * MIB - 4096))
imp:choose("sapphire")
check(imp.notice and imp.notice.detail:find("wrong size 15.99 MiB (16773120 bytes)", 1, true) ~= nil,
  "a trimmed dump reports its size: " .. tostring(imp.notice and imp.notice.detail))

-- 3. A clean dump under an odd extension says which name to give it.
imp = fresh()
love.filesystem.write("firered.agb", gbaBytes("good0001", "BPRE", 0))
imp._versionForSha1 = function(_, hash) return hash == "good0001" and "firered" or nil end
imp:choose("firered")
check(imp.notice and imp.notice.detail:find("unrecognized extension .agb; rename it to .gba", 1, true) ~= nil,
  "an .agb dump is told to become .gba: " .. tostring(imp.notice and imp.notice.detail))

-- 4. An archive the device cannot open says so.
imp = fresh()
local realCaps = require("src.import.RomArchive").capabilities
require("src.import.RomArchive").capabilities = function() return { zip = false, z7 = false } end
love.filesystem.write("roms.zip", "PK\3\4" .. ("x"):rep(64))
imp:choose("ruby")
check(imp.notice and imp.notice.detail:find("a .zip archive this device cannot open", 1, true) ~= nil,
  "an unmountable archive is explained: " .. tostring(imp.notice and imp.notice.detail))
require("src.import.RomArchive").capabilities = realCaps

-- 5. Header guesses for the other GBA carts and a GB title.
eq(Importer._romHeaderGuess(gbaBytes("x", "AXPE", 2, 256)), "Sapphire (USA) rev 2",
  "AXPE reads as Sapphire")
eq(Importer._romHeaderGuess(gbaBytes("x", "BPEJ", 0, 256)), "Emerald (Japan) rev 0",
  "BPEJ reads as Japanese Emerald")
local gb = ("\0"):rep(0x134) .. "POKEMON RED" .. ("\0"):rep(0x150 - 0x134 - 11)
eq(Importer._romHeaderGuess(gb), "Red", "a Game Boy title is read back")

-- 6. A valid, already imported cart is not a skip.
imp = fresh()
love.filesystem.write("Red.gb", "redsha01" .. ("\0"):rep(MIB - 8))
imp._versionForSha1 = function(_, hash) return hash == "redsha01" and "red" or nil end
imp.ready.red = true
imp:choose("blue")
check(imp.notice == nil, "an already imported cart is not reported as skipped")

os.getenv = getenv
T.finish("handheld_rom_skip_reason_bug2828")
