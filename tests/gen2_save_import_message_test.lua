-- A Gen 2 cart save must be refused as a Gen 2 cart save, not as a corrupt
-- Gen 1 one (#1832).
--   luajit tests/gen2_save_import_message_test.lua
-- Also dofile'd by tests/run_tests.lua.
--
-- SaveFileIO.importToSlot judges anything that is not exactly SAVE_SIZE with
-- SaveConvert.mainChecksumValid, which is pokered's main-data checksum.  Gen 2
-- carts are MBC3+TIMER, so a real Gold/Silver/Crystal battery save carries an
-- RTC footer and is 32786 bytes: it misses the size test, is then measured
-- against a checksum rule written for a different generation, and the launcher
-- tells the player their save is corrupt.  It is not -- there is simply no Gen
-- 2 codec yet, which is a different sentence and an actionable one.
package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local S = require("tests.harness").suite("gen2 save import message")
local check = S.check

local SaveConvert = require("src.save_convert.SaveConvert")
local SaveFileIO = require("src.import.SaveFileIO")

-- The size a real Gen 2 cart save actually is: 32768 bytes of SRAM plus the
-- 18-byte RTC footer an MBC3+TIMER cart writes.
local GEN2_CART_SAVE_SIZE = 32786

local function blob(n) return string.rep("\0", n) end

-- readSource only takes a raw string when it is EXACTLY 32768 bytes; anything
-- else is treated as a picker path (its own comment says so).  A real Gen 2
-- cart save is 32786, so it can only ever reach importToSlot as a FILE -- which
-- is exactly how the player in #1832 supplied theirs.  Write one and hand over
-- the path, so this exercises the route the report came from.
local function savFile(n)
  local path = os.tmpname()
  local f = assert(io.open(path, "wb"))
  f:write(blob(n))
  f:close()
  return path
end

-- ------------------------------------------------------------------
-- The report: a real Gen 2 save is not "checksum invalid"
-- ------------------------------------------------------------------

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local ok, err = SaveFileIO.importToSlot(savFile(GEN2_CART_SAVE_SIZE), version, true)
  check(ok == false, version .. ": a Gen 2 cart save is still refused")
  check(type(err) == "string" and err:find("Gen 2 cart save", 1, true) ~= nil,
    version .. ": refused AS a Gen 2 save -- got: " .. tostring(err))
  check(type(err) == "string" and err:find("checksum", 1, true) == nil,
    version .. ": never blamed on a checksum it was never measured by -- got: "
      .. tostring(err))
end

-- ------------------------------------------------------------------
-- The predicate both callers share
-- ------------------------------------------------------------------

for _, version in ipairs({ "red", "blue", "yellow" }) do
  check(SaveConvert.importSupported(version) == true,
    version .. ": Gen 1 import is unaffected")
  check(SaveConvert.exportSupported(version) == true,
    version .. ": Gen 1 export is unaffected")
end

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local impOk, impWhy = SaveConvert.importSupported(version)
  local expOk, expWhy = SaveConvert.exportSupported(version)
  check(impOk == false and expOk == false, version .. ": both directions say no")
  -- One sentence per direction, wherever it is asked from: the early gate in
  -- SaveFileIO and the late one inside importSav must not describe the same
  -- game two different ways.
  local _, lateWhy = SaveConvert.importSav(blob(32768), version, version)
  check(impWhy == lateWhy,
    version .. ": the early gate and importSav answer identically")
  check(expWhy:find("exporting", 1, true) ~= nil,
    version .. ": the export sentence is about exporting")
end

-- ------------------------------------------------------------------
-- Gen 1 keeps its own diagnosis
-- ------------------------------------------------------------------
--
-- A Gen 1 save that really is the wrong size AND fails pokered's checksum must
-- still say so: this fix moves the generation check in front of that test, it
-- does not remove it.

do
  local ok, err = SaveFileIO.importToSlot(savFile(GEN2_CART_SAVE_SIZE), "red", true)
  check(ok == false, "red: a corrupt oversize save is still refused")
  check(type(err) == "string" and err:find("checksum", 1, true) ~= nil,
    "red: still diagnosed by pokered's checksum -- got: " .. tostring(err))
end

S.finish()
