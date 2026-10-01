package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local K = require("tests.save_compat._codec")
local G3 = require("tests.fixtures.save.gen3_build")
local Gen3Save = require("src.save_convert.Gen3Save")
local Breeding = require("src.core.game3.breeding")
local Pokemon = require("src.core.game3.pokemon")

package.loaded["src.core.game3.pokemon"] = {
  _names = {},
  name = function() return "CHARMANDER" end,
  currentMapSec = function() return 88 end,
  applyStats = function() end,
}

for _, version in ipairs({ "firered", "leafgreen", "emerald" }) do
  local codec = Gen3Save.forVersion(version)
  for _, language in ipairs({ 1, 2 }) do
    local w = G3.base(version)
    G3.setParty(w, { G3.mon({ egg = true, nick = "EGG", lang = language, friendship = 20 }) })
    local rawName = language == 1 and codec.L.EGG_NICKNAME .. string.rep("\255", 7)
      or string.char(0xBF, 0xC1, 0xC1) .. string.rep("\255", 7)
    for i = 1, 10 do w.sb1[w.F.party + 7 + i] = rawName:byte(i) end
    local bytes = G3.emit(w)
    local save = assert(K.import(3, version, bytes))
    local out = assert(K.export(3, version, save))
    local mon = assert(codec.decode(out)).party[1]
    local label = version .. "/" .. language
    T.eq(mon.nicknameBytes, rawName, label .. ": an unchanged egg preserves its exact name bytes")
    T.eq(mon.language, language, label .. ": an unchanged egg preserves its language")

    local renamed = assert(K.import(3, version, bytes))
    renamed.party[1].nickname = "CUSTOM"
    local renamedMon = assert(codec.decode(assert(K.export(3, version, renamed)))).party[1]
    T.eq(renamedMon.nickname, "CUSTOM", label .. ": an edited egg name replaces the imported bytes")

    local languageEdit = assert(K.import(3, version, bytes))
    languageEdit.party[1].language = language == 1 and 2 or 1
    local languageMon = assert(codec.decode(assert(K.export(3, version, languageEdit)))).party[1]
    local expectedName = language == 1 and string.char(0xBF, 0xC1, 0xC1) or codec.L.EGG_NICKNAME
    T.eq(languageMon.nicknameBytes:sub(1, 3), expectedName, label .. ": an edited egg language re-encodes its name")

    local hatched = assert(K.import(3, version, bytes))
    Breeding.hatchMon({ version = version, party = hatched.party, name = "OWNER", trainerId = 4321,
      secretId = 1234, gender = 1 }, hatched.party[1])
    local hatchMon = assert(codec.decode(assert(K.export(3, version, hatched)))).party[1]
    T.eq(hatchMon.isEgg, false, label .. ": the engine hatch clears the egg bit")
    T.eq(hatchMon.nickname, "CHARMANDER", label .. ": the engine hatch exports the species name")
    T.eq(hatchMon.language, 2, label .. ": the engine hatch uses the game language")
    T.eq(hatchMon.friendship, 120, label .. ": the engine hatch exports hatch friendship")
    T.eq(hatchMon.otIdRaw, 4321 + 1234 * 65536, label .. ": a traded egg hatches with the player's trainer ID")
    T.eq(hatchMon.otName, "OWNER", label .. ": a traded egg hatches with the player's trainer name")
    T.eq(hatchMon.otGender, 1, label .. ": a traded egg hatches with the player's trainer gender")
    T.eq(hatchMon.personality, 0x12345678, label .. ": hatching preserves personality and its nature and gender bits")
    T.same(hatchMon.ivs, mon.ivs, label .. ": hatching preserves every inherited IV")

    local edited = assert(K.import(3, version, bytes))
    edited.party[1].isEgg, edited.party[1].nickname = false, "CUSTOM"
    local editedMon = assert(codec.decode(assert(K.export(3, version, edited)))).party[1]
    T.eq(editedMon.nickname, "CUSTOM", label .. ": clearing the egg flag cannot reuse the egg name carrier")
  end
  for _, vector in ipairs({ { pid = 0x444C, before = true, after = false },
    { pid = 0x1433, before = false, after = true } }) do
    local w = G3.base(version)
    G3.setParty(w, { G3.mon({ egg = true, nick = "EGG", lang = 1, pid = vector.pid }) })
    local save = assert(K.import(3, version, G3.emit(w)))
    local mon = save.party[1]
    T.eq(Pokemon.isShiny(mon), vector.before, version .. ": the foreign OT determines the original shiny value")
    mon.isShiny = vector.before
    Breeding.hatchMon({ version = version, name = "OWNER", trainerId = 4321, secretId = 1234 }, mon)
    T.eq(Pokemon.isShiny(mon), vector.after, version .. ": the fixed PID is checked against the hatch owner's ID")
    local decoded = assert(codec.decode(assert(K.export(3, version, save)))).party[1]
    T.eq(decoded.personality, vector.pid, version .. ": rebinding an egg's OT never rerolls the PID")
    T.eq(Pokemon.isShiny({ personality = decoded.personality, otId = decoded.otId,
      otSecretId = decoded.otSecretId }), vector.after, version .. ": cartridge shiny calculation matches the hatch owner")
  end
end

T.finish()
