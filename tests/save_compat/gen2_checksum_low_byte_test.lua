package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local K = require("tests.save_compat._codec")
local B = require("tests.fixtures.save.bytes")
local G2 = require("tests.fixtures.save.gen2_build")
local Gen2Save = require("src.save_convert.Gen2Save")
local Compat = require("src.save_convert.Compat")
local SaveConvert = require("src.save_convert.SaveConvert")

local DATA = {
  items = K.gen2Data.items, maps = K.gen2Data.maps,
  pokemon = { CYNDAQUIL = { index = 155, dex = 155, name = "CYNDAQUIL", genderRatio = 0x1F } },
  moves = { TACKLE = { index = 33, pp = 35 }, GROWL = { index = 43, pp = 40 } },
}

local function ruleOf(list, rule)
  for _, e in ipairs(list) do if e.rule == rule then return e end end
end

for _, v in ipairs({ "gold", "silver", "crystal" }) do
  local L = Gen2Save.layoutFor(v)
  local src = G2.build({ version = v, lowByteZero = true })
  eq(src:byte(L.sChecksum + 1), 0, v .. ": the fixture's primary checksum has a zero low byte")

  local report = Compat.check(src, v)
  check(ruleOf(report.errors, "gen2.openhomeChecksum") ~= nil, v .. ": OpenHome's reader rejects it -- " .. Compat.describe(report))
  eq(#report.errors, 1, v .. ": and nothing else is wrong with it")

  local refused, why = Compat.gate(src, v)
  eq(refused, nil, v .. ": with no source to compare, the gate refuses it")
  check(why and why:find("openhomeChecksum", 1, true) ~= nil, v .. ": naming the rule")

  local save = assert(Gen2Save.decode(src, v, DATA))
  local out = assert(Gen2Save.encode(save, v, src, DATA))
  eq(out, src, v .. ": an unchanged re-export is byte-exact")
  local ok, warnings = Compat.gate(out, v, src)
  eq(ok, true, v .. ": and the gate accepts it")
  check(ruleOf(warnings, "gen2.openhomeChecksum") ~= nil, v .. ": with the OpenHome rule demoted to a warning")

  SaveConvert.setGen2DataStub(DATA)
  local exported, exportErr = SaveConvert.exportSav(save, v, src)
  SaveConvert.setGen2DataStub(nil)
  eq(exported, src, v .. ": exportSav returns the genuine cart unchanged -- " .. tostring(exportErr))
  check(type(exportErr) == "string" and exportErr:find("gen2.openhomeChecksum", 1, true),
    v .. ": exportSav surfaces the accepted OpenHome warning")

  local moved, whyMoved = Compat.gate(out:sub(1, L.wMoney) .. string.char((out:byte(L.wMoney + 1) + 1) % 256)
    .. out:sub(L.wMoney + 2), v, src)
  eq(moved, nil, v .. ": a different byte string gets no such leniency")
  check(whyMoved ~= nil, v .. ": and says why")

  local base = G2.build({ version = v })
  local want
  for money = 0, 255 do
    local probe = G2.build({ version = v, money = 123456 - 123456 % 256 + money, lowByteZero = false })
    local bytes = {}
    for i = 1, #probe do bytes[i - 1] = probe:byte(i) end
    if B.sum16(bytes, L.sGameData, L.sGameDataEnd) % 256 == 0 then want = 123456 - 123456 % 256 + money break end
  end
  check(want ~= nil, v .. ": some money value lands the primary sum on a zero low byte")
  local edited = assert(Gen2Save.decode(base, v, DATA))
  edited.player.money = want
  local nudged = assert(Gen2Save.encode(edited, v, base, DATA))
  local pad = L.wGreensName + G2.NAME - 1
  check(nudged:byte(pad + 1) ~= base:byte(pad + 1), v .. ": the changed export is nudged through the pad byte after GREEN")
  check(nudged:byte(L.sChecksum + 1) ~= 0, v .. ": so the sum's low byte is no longer zero")
  local after = Compat.check(nudged, v)
  eq(#after.errors, 0, v .. ": and the validator passes it -- " .. Compat.describe(after))
  local gated = Compat.gate(nudged, v, base)
  eq(gated, true, v .. ": the gate accepts the nudged export")
  local back = assert(Gen2Save.decode(nudged, v, DATA))
  eq(back.player.money, want, v .. ": the nudge leaves the edit intact")
end

for _, v in ipairs({ "gold", "silver" }) do
  local src = G2.build({ version = v, after = function(b) B.fill(b, 0x3D69, 0x2D, 0x5A) end })
  local save = assert(Gen2Save.decode(src, v, DATA))
  SaveConvert.setGen2DataStub(DATA)
  local exported, note = SaveConvert.exportSav(save, v, src)
  SaveConvert.setGen2DataStub(nil)
  eq(exported, src, v .. ": the Hall of Fame warning preserves the cartridge bytes")
  check(type(note) == "string" and note:find("gen2.pkhexHallOfFame", 1, true),
    v .. ": exportSav returns the Hall of Fame warning for the launcher and CLI")
end

T.finish()
