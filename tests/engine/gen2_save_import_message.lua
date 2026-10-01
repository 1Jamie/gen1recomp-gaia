-- A real Gen 2 cart save is 32786 bytes, and that must not be held against it
-- (#1832).
--   luajit tests/gen2_save_import_message_test.lua
-- Also dofile'd by tests/run_tests.lua.
--
-- Gen 2 carts are MBC3+TIMER, so a real Gold/Silver/Crystal battery save
-- carries an RTC footer past the 32768 bytes of SRAM. SaveFileIO.importToSlot
-- judges anything that is not exactly SAVE_SIZE, and it used to judge it with
-- pokered's main-data checksum whatever game it was for, so every real Gen 2
-- save came back "save data checksum invalid" -- a perfectly good save
-- reported as corrupt.
--
-- This is the size gate specifically. tests/gen2_save_import_test.lua covers
-- the codec.
package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

-- SaveData is stubbed so this stays about the gate: the real one wants a
-- filesystem and a registry, and neither is the subject here.
local written = {}
local carts = {}
local cartFs = {
  write = function(rel, bytes) carts[rel] = bytes return true end,
  createDirectory = function() return true end,
}
package.loaded["src.core.SaveData"] = {
  portableFs = function() return cartFs end,
  load = function() return { meta = {} } end,
  activeSlot = function() return "slot1" end,
  buildMeta = function(_, m) return m or {} end,
  createSlot = function() return "slot1" end,
  writeSlot = function(_, _, save) written[#written + 1] = save return true end,
  setActiveSlot = function() return true end,
}

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Gen2Save = require("src.save_convert.Gen2Save")
local SaveConvert = require("src.save_convert.SaveConvert")
local SaveFileIO = require("src.import.SaveFileIO")

local function gen2Data()
  SaveConvert.setGen2DataStub({
    pokemon = { CHIKORITA = { index = 152, dex = 152 }, CELEBI = { index = 251, dex = 251 } },
    moves = { TACKLE = { index = 33, pp = 35 } },
    items = { POTION = { index = 18, pocket = "ITEM" } },
    maps = {},
  })
end

-- The size a real Gen 2 cart save actually is: 32768 of SRAM plus an 18-byte
-- RTC footer. Verified against a real Gold cartridge in an emulator core,
-- which reports the cart's backup size as exactly this.
local GEN2_CART_SAVE_SIZE = 32786

local function validSave(version, trailing)
  local L = Gen2Save.layoutFor(version)
  local b = {}
  for i = 0, Gen2Save.SAVE_SIZE - 1 do b[i] = 0 end
  b[L.wPlayerName] = 0x80        -- "A", so the save is not entirely blank
  b[L.wPlayerName + 1] = 0x50
  b[L.sCheckValue1] = 0x63
  b[L.sCheckValue2] = 0x7F
  local sum = 0
  for i = L.sGameData, L.sGameDataEnd - 1 do sum = (sum + b[i]) % 65536 end
  b[L.sChecksum] = sum % 256
  b[L.sChecksum + 1] = math.floor(sum / 256) % 256
  local out = {}
  for i = 0, Gen2Save.SAVE_SIZE - 1 do out[i + 1] = string.char(b[i]) end
  return table.concat(out) .. string.rep("\0", trailing or 0)
end

local function savFile(bytes)
  local path = os.tmpname()
  local f = assert(io.open(path, "wb"))
  f:write(bytes)
  f:close()
  return path
end

-- ------------------------------------------------------------------
-- The report: a real-sized Gen 2 save imports
-- ------------------------------------------------------------------

do
  local ok, err = SaveFileIO.importToSlot(savFile(validSave("silver")), "silver")
  eq(ok, false, "silver: without its data cache the import is refused (G2-17)")
  check(type(err) == "string" and err:find("data cache is missing", 1, true) ~= nil,
    "silver: and the reason names the missing cache -- " .. tostring(err))
  check(type(err) == "string" and err:find("checksum", 1, true) == nil,
    "silver: not a checksum -- " .. tostring(err))
end
gen2Data()

for _, version in ipairs({ "gold", "crystal" }) do
  local trailing = GEN2_CART_SAVE_SIZE - Gen2Save.SAVE_SIZE
  local path = savFile(validSave(version, trailing))
  written = {}
  carts = {}
  -- force is deliberately NOT passed: the footer is the normal shape of a Gen
  -- 2 cart save, so it must not raise the oversize confirmation either.
  local ok, err = SaveFileIO.importToSlot(path, version)
  check(ok == true,
    version .. ": a 32786-byte cart save imports -- " .. tostring(err))
  check(type(err) ~= "string" or err:find("checksum", 1, true) == nil,
    version .. ": and is never blamed on a checksum -- " .. tostring(err))
  eq(#written, 1, version .. ": the slot is written")
  local cart = carts[("saves/%s/slot1.cart"):format(version)]
  eq(cart, nil, version .. ": no sidecar cart image is written")
  eq(written[1] and type(written[1].rawImport) == "string" and #written[1].rawImport,
    GEN2_CART_SAVE_SIZE, version .. ": and so does the image kept in the slot")
  local out = written[1] and Gen2Save.encode(written[1], version, nil, nil)
  eq(out and #out, GEN2_CART_SAVE_SIZE, version .. ": an export re-appends the footer")
end

-- ------------------------------------------------------------------
-- The checksum question is asked of the right generation
-- ------------------------------------------------------------------

do
  local gen2 = validSave("gold")
  eq(SaveConvert.mainChecksumValid(gen2, "gold"), true,
    "a Gen 2 save is valid under Gen 2's rule")
  eq(SaveConvert.mainChecksumValid(gen2), false,
    "and would read as invalid under Gen 1's, which is the whole bug")
  check(SaveConvert.isGen2Cart("crystal"), "Crystal is a Gen 2 cart")
  check(not SaveConvert.isGen2Cart("red"), "Red is not")
end

-- ------------------------------------------------------------------
-- Gen 1 keeps its own diagnosis
-- ------------------------------------------------------------------

do
  local path = savFile(string.rep("\0", GEN2_CART_SAVE_SIZE))
  local ok, err = SaveFileIO.importToSlot(path, "red", true)
  check(ok == false, "red: a corrupt oversize save is still refused")
  check(type(err) == "string" and err:find("checksum", 1, true) ~= nil,
    "red: still diagnosed by pokered's checksum -- got: " .. tostring(err))
end

-- ------------------------------------------------------------------
-- Export needs the map the save stands on, not a cartridge behind it

-- A save begun in this port has no cartridge image, and one is synthesized
-- for it. What export cannot invent is the map window the real game trusts
-- on CONTINUE, so a save that names no map is refused, in a line that says so.
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  eq(SaveConvert.exportSupported(version), true, version .. ": export is supported")
  local out, why = SaveConvert.exportSav({ meta = {}, player = { name = "A" } }, version)
  eq(out, nil, version .. ": a save that names no map is refused")
  check(type(why) == "string" and why:find("does not name one", 1, true) ~= nil,
    version .. ": and the reason is the missing map -- " .. tostring(why))
  check(type(why) == "string"
        and why:find("no cartridge image to write", 1, true) == nil,
    version .. ": the lineage refusal is gone -- " .. tostring(why))
end

T.finish()
