package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local SaveData = require("src.core.SaveData")
local SaveFileIO = require("src.import.SaveFileIO")
local SaveConvert = require("src.save_convert.SaveConvert")
local Gen2Save = require("src.save_convert.Gen2Save")
local EngineSave = require("src.core.gen2.Save")
local G2 = require("tests.fixtures.save.gen2_build")

SaveConvert.setGen2DataStub({
  pokemon = { CYNDAQUIL = { index = 155, dex = 155, name = "CYNDAQUIL" } },
  moves = {}, items = G2.ITEMS,
  maps = { M = { group = 24, map = 7, objectEventsAddr = 0x5A17, width = 2, height = 2, blocks = { 1, 2, 3, 4 }, objects = {} } },
})

local function savFile(bytes)
  local path = os.tmpname()
  local f = assert(io.open(path, "wb"))
  f:write(bytes)
  f:close()
  return path
end

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local reset = EngineSave.loadOptions()
  reset.textSpeed = "MID"
  EngineSave.saveOptions(reset)
  local before = EngineSave.loadOptions()
  eq(before.textSpeed, "MID", version .. ": the engine starts on the default text speed")
  local bytes = G2.build({ version = version, patch = function(b, L)
    b[L.sOptions] = 0x05 + 0x80 + 0x40 + 0x20
    b[L.sOptions + 2] = 6
    b[L.sOptions + 4] = 0x60
    b[L.sOptions + 5] = 0
  end })
  local ok, slot = SaveFileIO.importToSlot(savFile(bytes), version)
  check(ok == true, version .. ": the import lands -- " .. tostring(slot))
  local after = EngineSave.loadOptions()
  eq(after.textSpeed, "SLOW", version .. ": cart text speed persists to the engine options")
  eq(after.battleScene, false, version .. ": battle scene off")
  eq(after.battleStyle, "SET", version .. ": battle style")
  eq(after.sound, "STEREO", version .. ": sound")
  eq(after.frame, 7, version .. ": frame")
  eq(after.print, "DARKER", version .. ": print")
  eq(after.menuAccount, false, version .. ": menu account")
  eq(after.speed, before.speed, version .. ": port-only options are untouched")
  local loaded = SaveData.load(version)
  check(loaded ~= nil, version .. ": the slot loads")
  eq(loaded and loaded.options.textSpeed, "SLOW", version .. ": SaveData.load answers with the Gen 2 option block")
  check(loaded and loaded.importedOptions == nil, version .. ": the import carrier is not stored in the slot")
  local out, why = SaveConvert.exportSav(loaded, version)
  check(out ~= nil, version .. ": the loaded slot exports -- " .. tostring(why))
  if out then
    local L = Gen2Save.layoutFor(version)
    eq(out:byte(L.sOptions + 1), 0x05 + 0x80 + 0x40 + 0x20, version .. ": and the options bits come back")
  end
  local changed = EngineSave.loadOptions()
  changed.textSpeed = "FAST"
  EngineSave.saveOptions(changed)
  SaveData.saveOptions(SaveData.loadOptions())
  eq(EngineSave.loadOptions().textSpeed, "FAST", version .. ": a later change in the engine sticks")
end

T.finish()
