package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local before = GameVersion.get()
GameVersion.set("emerald")

local Schema = require("src.core.game3.save_schema_firered")
local SaveSections = require("src.core.game3.save_sections")
local Flags = require("src.core.game3.scripting.flags")
local C = require("src.core.game3.constants").of("emerald")

for _, name in ipairs({ "dewfordTrends", "oldMan", "lilycoveLady", "apprentice" }) do
  SaveSections.register(name, SaveSections.fields({ name }))
end

local ran = {}
local function fakeScript(session, key)
  ran[#ran + 1] = key
  Flags.setFlag(session, nil, C:require("flags", "FLAG_HIDE_LITTLEROOT_TOWN_BIRCHS_LAB_BIRCH"), true)
end

print("[test] emerald new game (pokeemerald/src/new_game.c:149)")
local s = Schema.newGame({ version = "emerald", name = "MAY", gender = 1, runScript = fakeScript, rngSeed = 7 })
eq(s.version, "emerald", "version is emerald")
eq(s.money, 3000, "money 3000 (new_game.c:172)")
eq(s.coins, 0, "coins 0")
eq(s.map, "EM_INSIDE_OF_TRUCK", "starts in the truck (new_game.c:195)")
eq(s.x, 2, "truck x")
eq(s.y, 2, "truck y")
eq(s.rivalName, nil, "no stored rival name")
eq(s.name, "MAY", "player name kept")
eq(s.vsSeeker, nil, "no VS Seeker state")
eq(s.easyChatProfile, nil, "FR easy chat defaults not copied")
eq(#s.storage.items, 1, "one PC item")
eq(s.storage.items[1].id, C:require("items", "ITEM_POTION"), "PC Potion (player_pc.c:225)")
eq(s.storage.items[1].qty, 1, "one Potion")
eq(ran[1], "EventScript_ResetAllMapFlags", "reset script runs (new_game.c:196)")
check(Flags.getFlag(s, nil, C:require("flags", "FLAG_HIDE_LITTLEROOT_TOWN_BIRCHS_LAB_BIRCH")),
  "reset script flags land in the session")
eq(s.vars[C:require("vars", "VAR_SEEDOT_SIZE_RECORD")], 0x8000, "Seedot size record default")
eq(s.vars[C:require("vars", "VAR_LOTAD_SIZE_RECORD")], 0x8000, "Lotad size record default")
eq(s.encryptionKey, 0, "encryption key zeroed (new_game.c:155)")
eq(type(s.localTimeOffset), "table", "RTC offset seeded")
eq(s.localTimeOffset.hours, 0, "RTC offset hours 0")
eq(s.rtcSkew, 0, "rtc skew 0")
eq(s.specialVars[0x8015], 0, "special var 0x8015 exists (vars.h:306)")
eq(s.specialVars[0x8016], nil, "no special var past 0x8015")
check(not Flags.getFlag(s, nil, 0x820), "no FireRed badge flag")
eq(s.bag.pockets.TM_CASE and #s.bag.pockets.TM_CASE, 0, "empty TM pocket")

print("[test] save round trip")
s.money = 1234
s.specialVars[0x8015] = 9
s.localTimeOffset.hours = 5
s.encryptionKey = 77
local saved = Schema.toSaveTable(s)
eq(saved.encryptionKey, 77, "encryption key exported")
eq(saved.localTimeOffset.hours, 5, "RTC offset exported")
eq(saved.money, 1234, "money exported")
check(saved.vsSeeker == nil, "no vsSeeker exported")
local back = Schema.fromSaveTable(saved)
eq(back.version, "emerald", "version restored")
eq(back.money, 1234, "money restored")
eq(back.encryptionKey, 77, "encryption key restored")
eq(back.localTimeOffset.hours, 5, "RTC offset restored")
eq(back.specialVars[0x8015], 9, "special var restored")
eq(back.map, "EM_INSIDE_OF_TRUCK", "map restored")
eq(back.vsSeeker, nil, "no vsSeeker after load")
check(not Flags.getFlag(back, nil, 0x092) and not Flags.getFlag(back, nil, 0x033),
  "FireRed repairSaveState flags not applied")
check(Flags.getFlag(back, nil, C:require("flags", "FLAG_HIDE_LITTLEROOT_TOWN_BIRCHS_LAB_BIRCH")),
  "flags survive the round trip")

print("[test] continue clears the safari flag (pokeemerald/src/overworld.c:1711)")
local safari = C:require("flags", "FLAG_SYS_SAFARI_MODE")
saved.flags[safari] = true
saved.flags[tostring(safari)] = true
local cont = Schema.fromSaveTable(saved)
check(not Flags.getFlag(cont, nil, safari), "safari flag cleared on continue")

print("[test] continue game warp (pokeemerald/src/load_save.c:134)")
saved.specialSaveWarpFlags = 1
saved.continueGameWarp = { map = "EM_LITTLEROOT_TOWN", x = 5, y = 6 }
local warped = Schema.fromSaveTable(saved)
eq(warped.map, "EM_LITTLEROOT_TOWN", "continue warp map")
eq(warped.x, 5, "continue warp x")
eq(warped.specialSaveWarpFlags, 0, "continue warp bit cleared")

print("[test] save sections registry")
local def = SaveSections.fields({ "fooA", "fooB" }, function(sess) sess.fooA = { 1 } end)
local fake = {}
def.newGame(fake)
eq(fake.fooA[1], 1, "section newGame")
local out = {}
fake.fooB = "x"
def.export(fake, out)
eq(out.fooA[1], 1, "section export copies")
check(out.fooA ~= fake.fooA, "section export deep copies")
local into = {}
def.restore(out, into)
eq(into.fooB, "x", "section restore")
SaveSections.register("r6_test", def)
local okErr = pcall(function()
  return SaveSections.of("emerald")
end)
check(okErr, "emerald sections resolve")
local bad = pcall(function()
  local row = require("src.core.game3.profile").of("emerald")
  local prev = row.save.sections
  row.save.sections = { "no_such_section" }
  local ok = pcall(SaveSections.of, "emerald")
  row.save.sections = prev
  assert(ok == false)
end)
check(bad, "unknown section raises")
SaveSections.unregister("r6_test")

print("[test] FireRed new game unchanged")
GameVersion.set("firered")
local fr = Schema.newGame({ version = "firered", rngSeed = 7 })
eq(fr.name, "RED", "FR default name")
eq(fr.rivalName, "BLUE", "FR default rival")
eq(fr.map, "FR_PLAYERS_HOUSE_2F", "FR start map")
eq(fr.storage.items[1].id, 13, "FR PC Potion")
eq(type(fr.vsSeeker), "table", "FR vsSeeker state")
eq(fr.easyChatProfile[1], 2601, "FR easy chat profile")
eq(fr.specialVars[0x8014], 0, "FR special var 0x8014")
eq(fr.specialVars[0x8015], nil, "FR has no 0x8015")
eq(fr.encryptionKey, nil, "FR has no encryption key field")
eq(fr.localTimeOffset, nil, "FR has no RTC fields")
local frSaved = Schema.toSaveTable(fr)
eq(frSaved.encryptionKey, nil, "FR save has no encryption key")
eq(frSaved.localTimeOffset, nil, "FR save has no RTC offset")

GameVersion.set(before)
T.finish("game3_emerald_save_schema_test")
