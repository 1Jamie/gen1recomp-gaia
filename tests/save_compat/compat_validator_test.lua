package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Compat = require("src.save_convert.Compat")
local B = require("tests.fixtures.save.bytes")
local G1 = require("tests.fixtures.save.gen1_build")
local G2 = require("tests.fixtures.save.gen2_build")
local G3 = require("tests.fixtures.save.gen3_build")

local fired = {}

local function rules(report, list)
  local out = {}
  for _, e in ipairs(report[list]) do
    out[e.rule] = (out[e.rule] or 0) + 1
    fired[e.rule] = true
  end
  return out
end

local function expectError(bytes, version, rule, label)
  local r = Compat.check(bytes, version)
  check(rules(r, "errors")[rule] ~= nil, ("%s: flags %s -- got: %s"):format(label, rule, Compat.describe(r)))
  eq(r.ok, false, label .. ": the report is not ok")
  return r
end

local function expectWarn(bytes, version, rule, label)
  local r = Compat.check(bytes, version)
  check(rules(r, "warnings")[rule] ~= nil, ("%s: warns %s -- got: %s"):format(label, rule, Compat.describe(r)))
  eq(r.ok, true, label .. ": a warning alone keeps the report ok -- " .. Compat.describe(r))
  return r
end

local function expectClean(bytes, version, label)
  local r = Compat.check(bytes, version)
  eq(#r.errors, 0, label .. ": no errors -- " .. Compat.describe(r))
  return r
end

local function edit(bytes, fn)
  local b = B.fromString(bytes)
  fn(b)
  return B.pack(b)
end

for rule, sev in pairs(Compat.RULES) do
  check(sev == "error" or sev == "warn", "rule " .. rule .. " has a known severity")
end

local function g1(spec)
  spec = spec or {}
  spec.version = spec.version or "red"
  return G1.build(spec)
end

local function g1Reseal(b)
  b[0x3523] = B.complement8(b, 0x2598, 0x3523)
end

expectClean(g1(), "red", "gen1 basic")
expectClean(g1({ version = "yellow" }), "yellow", "gen1 yellow")
expectError(string.rep("\0", 100), "red", "size", "gen1 short file")
expectError(edit(g1(), function(b) b[0x3523] = (b[0x3523] + 1) % 256 end), "red", "gen1.mainChecksum",
  "gen1 bad main checksum")
expectError(edit(g1(), function(b)
  b[0x2D0D] = B.sum8(b, 0x2009, 0x2B83)
  b[0x1F0D] = B.sum8(b, 0x1209, 0x1D83)
  g1Reseal(b)
end), "red", "gen1.openhomeMisdetect", "gen1 image whose Crystal 8-bit sums validate")
expectError(edit(g1(), function(b)
  B.le(b, 0x2D0D, B.sum16(b, 0x2009, 0x2C8C), 2)
  B.le(b, 0x7F0D, B.sum16(b, 0x2009, 0x2C8C), 2)
  g1Reseal(b)
end), "red", "gen1.openhomeMisdetect", "gen1 image whose Japanese Gen 2 sums validate")
expectWarn(g1({ patch = function(b) b[0x271C] = 9 end }), "red", "gen1.versionMarker",
  "gen1 Red save whose byte 0x271C OpenHome reads as Pikachu friendship")
expectError(edit(g1(), function(b) b[0x2F2C + 2] = 0x99; g1Reseal(b) end), "red", "gen1.partyList",
  "gen1 party list without terminator")
expectError(edit(g1(), function(b) b[0x30C0] = 21; g1Reseal(b) end), "red", "gen1.curBoxList",
  "gen1 current box count past 20")
expectError(g1({ party = { G1.mon(), G1.mon() }, patch = function(b) b[0x2F2C + 2] = 0 end }), "red",
  "gen1.listSpecies0", "gen1 species 0 inside the party list")
expectError(g1({ currentBox = 12, genuineCurrentSlot = false }), "red", "gen1.currentBoxIndex", "gen1 box index 12")
expectError(g1({ patch = function(b) B.put(b, 0x2ED5, 0, 0xFF); B.put(b, 0x302D, 0, 0xFF) end }), "red",
  "gen1.japaneseCollision", "gen1 lists that also pass PKHeX's Japanese test")
expectError(edit(g1(), function(b)
  b[0x2D69] = B.sum8(b, 0x2009, 0x2D69)
  b[0x7E6D] = (B.sum8(b, 0x15C7, 0x17ED) + B.sum8(b, 0x3D96, 0x3F40) + B.sum8(b, 0x0C6B, 0x10E8)
    + B.sum8(b, 0x7E39, 0x7E6D) + B.sum8(b, 0x10E8, 0x15C7)) % 256
  g1Reseal(b)
end), "red", "gen1.openhomeMisdetect", "gen1 image whose Gold/Silver 8-bit sums validate (G1-25)")
expectError(edit(g1({ boxes = { G1.boxOf(1, 3) }, currentBox = 1 }), function(b)
  b[0x4000] = 25
end), "red", "gen1.bankList", "gen1 stored box count past 20")
expectWarn(g1({ party = { G1.mon({ species = 0x1F }) } }), "red", "gen1.unknownSpecies", "gen1 MissingNo index")
expectWarn(g1({ staleBankChecksums = true }), "red", "gen1.bankChecksum", "gen1 stale bank checksums")
expectWarn(g1({ starter = 0x54 }), "red", "gen1.versionMarker", "gen1 Red save with Pikachu as starter")
expectWarn(g1({ version = "yellow", patch = function(b) b[0x29C3] = 0xB0 end }), "yellow", "gen1.versionMarker",
  "gen1 Yellow save without the Pikachu starter")
expectWarn(g1({ boxes = { G1.boxOf(1, 3), G1.boxOf(1, 4) }, currentBox = 0,
  patch = function(b) b[0x4462 + 22 + 2] = 0xFF end }), "red", "gen1.openhomeHp255", "gen1 boxed mon with HP 255")
expectWarn(g1({ patch = function(b) b[0x29C5] = 0x30 end }), "red", "gen1.blackoutMap", "gen1 blackout map outside the fly table")
expectWarn(g1({ boxesInitialized = false, bankFill = 0,
  after = function(b) B.put(b, 0x4462, 1, 0x99, 0xFF) end }), "red", "gen1.boxesUninitialized",
  "gen1 bank list with bit 7 clear")
expectClean(g1({ boxesInitialized = false }), "red", "gen1 never changed boxes, banks still 0xFF")

local function g2(version, spec)
  spec = spec or {}
  spec.version = version
  return G2.build(spec)
end

for _, v in ipairs({ "gold", "silver", "crystal" }) do
  local L = G2.layout(v)
  expectClean(g2(v), v, v .. " basic")
  expectClean(g2(v, { footer = string.rep("\0", 48) }), v, v .. " with a 48-byte RTC footer")
  expectError(g2(v, { footer = string.rep("\0", 13) }), v, "size", v .. " with an odd 13-byte tail")
  expectError(edit(g2(v), function(b) b[L.sCheckValue1] = 0 end), v, "gen2.checkValues", v .. " check value 1")
  expectError(edit(g2(v), function(b) b[L.sChecksum] = (b[L.sChecksum] + 1) % 256 end), v, "gen2.checksum",
    v .. " bad primary sum")
  expectError(g2(v, { party = { G2.mon(), G2.mon() }, patch = function(b) b[L.wPartySpecies + 1] = 0 end }), v,
    "gen2.listSpecies0", v .. " species 0 inside the party list")
  expectError(g2(v, { patch = function(b) b[L.boxes[4]] = 30 end }), v, "gen2.boxList", v .. " box count past 20")
  expectError(g2(v, { patch = function(b) b[L.wPartyCount] = 30 end }), v, "gen2.partyList", v .. " party count past 6")
  expectError(edit(g2(v), function(b) b[L.sChecksum] = (b[L.sChecksum] + 1) % 256 end), v, "gen2.openhomeChecksum",
    v .. " whose 8-bit sums do not validate for OpenHome")
  local egg = expectClean(g2(v, { party = { G2.mon(), G2.mon({ listed = G2.EGG, nick = "EGG" }) } }), v,
    v .. " party egg is legal")
  eq(rules(egg, "warnings")["gen2.listStructMismatch"], nil, v .. ": an 0xFD egg marker is not a list mismatch")
  expectWarn(g2(v, { party = { G2.mon({ species = 252 }) } }), v, "gen2.unknownSpecies", v .. " species past Celebi")
  expectWarn(g2(v, { party = { G2.mon({ listed = 7 }) } }), v, "gen2.listStructMismatch", v .. " list/struct disagree")
  expectWarn(g2(v, { party = { G2.mon({ nick = "" }) } }), v, "gen2.blankNickname", v .. " blank nickname")
  expectWarn(g2(v, { patch = function(b)
    local caught = v == "crystal" and 0x2A27 or 0x2A4C
    b[caught + 25] = 1
  end }), v, "gen2.unownDex", v .. " Unown caught with an empty Unown dex")
end

for _, v in ipairs({ "gold", "silver" }) do
  expectWarn(g2(v, { after = function(b) B.fill(b, 0x3D69, 0x2D, 0x5A) end }),
    v, "gen2.pkhexHallOfFame", v .. " Hall of Fame tail overwritten by PKHeX")
  local clean = Compat.check(g2(v), v)
  eq(rules(clean, "warnings")["gen2.pkhexHallOfFame"], nil, v .. " empty Hall of Fame tail has no loss warning")
end
local crystalHall = Compat.check(g2("crystal", { after = function(b) B.fill(b, 0x3D69, 0x2D, 0x5A) end }), "crystal")
eq(rules(crystalHall, "warnings")["gen2.pkhexHallOfFame"], nil, "Crystal writer does not overlap Hall of Fame")

expectError(edit(g2("gold"), function(b) b[0x7E6D] = 0; b[0x7E6E] = 0 end), "gold", "gen2.backupChecksum",
  "gold whose PKHeX checksum 2 was never written (G2-08)")
expectError(edit(g2("crystal"), function(b) b[0x1F0D] = (b[0x1F0D] + 1) % 256 end), "crystal", "gen2.backupChecksum",
  "crystal backup sum wrong")
local gsBothZero = edit(g2("gold"), function(b)
  for _, seg in ipairs(G2.GS_BACKUP) do B.fill(b, seg.to, seg.size, 0) end
  B.fill(b, 0x7E30, 0x40, 0)
  local pad = 0x2D68
  b[pad] = (b[pad] - B.sum8(b, 0x2009, 0x2D69)) % 256
  B.le(b, 0x2D69, B.sum16(b, 0x2009, 0x2D69), 2)
end)
eq(gsBothZero:byte(0x2D69 + 1), 0, "the crafted Gold image sums to a 0 low byte")
expectError(gsBothZero, "gold", "gen2.openhomeChecksum", "gold with low byte 0 and an empty backup (G2-22)")
expectError(g2("gold", { after = function(b)
  B.le(b, 0x2D0D, B.sum16(b, 0x2009, 0x2C8C), 2)
  B.le(b, 0x7F0D, B.sum16(b, 0x2009, 0x2C8C), 2)
end }), "gold", "gen2.openhomeJapanCollision", "gold whose bytes also pass OpenHome's Japanese Gen 2 checksums")
expectError(g2("crystal", { patch = function(b) B.put(b, 0x288A, 0, 0xFF); B.put(b, 0x2D6C, 0, 0xFF) end }),
  "crystal", "gen2.gsCollision", "crystal whose bytes also pass PKHeX's Gold/Silver list test")
expectError(g2("gold", { patch = function(b) B.put(b, 0x2F2C, 0, 0xFF); B.put(b, 0x30C0, 0, 0xFF) end }),
  "gold", "gen2.gen1Collision", "gold whose bytes also pass PKHeX's Gen 1 list test")

local function g3(version, fn)
  local w = G3.base(version)
  if fn then fn(w) end
  return G3.emit(w), w
end

local function sectorOf(w, id) return w.at[id] end

local function reseal(b, off, size)
  local s = {}
  for k = 0, 0xF7F do s[k + 1] = string.char(b[off + k]) end
  B.le(b, off + 0xFF6, Compat.gen3SectorChecksum(table.concat(s), 0, size), 2)
end

for _, v in ipairs({ "firered", "leafgreen", "emerald" }) do
  local fam = v == "emerald" and "emerald" or "frlg"
  local chunks = G3.CHUNKS[fam]
  local good, w = g3(v)
  expectClean(good, v, v .. " basic")
  expectError(good:sub(1, 0x10000), v, "size", v .. " 64K file")
  expectWarn(good .. string.rep("\0", 16), v, "gen3.trailer", v .. " with a 16-byte trailer")
  expectWarn(good .. string.rep("\255", 7), v, "gen3.trailer", v .. " with a 7-byte footer")
  expectWarn(good .. string.rep("\255", 0x80), v, "gen3.trailer", v .. " with a uniform 0x80 pad that only PKForge trims")
  expectError(good .. string.rep("\1", 13), v, "gen3.trailerUnreadable", v .. " with a 13-byte non-uniform tail")
  expectError(good .. string.rep("\1", 0x80), v, "gen3.trailerUnreadable", v .. " with a 0x80-byte non-uniform tail")
  expectError(good .. string.rep("\0", 0x101), v, "size", v .. " past OpenHome's 0x20100 window")
  expectWarn(edit(good, function(b) B.le(b, sectorOf(w, 3) + 0xFFC, 0x01020304, 4) end), v, "gen3.slotCounter",
    v .. " section whose counter differs from section 0")
  expectWarn(edit(good, function(b)
    local other = w.at[0] < 0xE000 and 0xE000 or -0xE000
    for i = 0, 0xDFFF do b[w.at[0] - w.at[0] % 0xE000 + other + i] = b[w.at[0] - w.at[0] % 0xE000 + i] end
  end), v, "gen3.slotCounter", v .. " both slots with the same counter")
  expectWarn(g3(v, function(x) G3.setBoxMon(x, 5, 1, G3.mon({ pid = 81, lang = 12 })) end), v, "gen3.language",
    v .. " mon with language byte 12")
  expectError(edit(good, function(b) b[sectorOf(w, 3) + 0xFF4] = 2 end), v, "gen3.sectionIds",
    v .. " slot with section 2 twice")
  expectError(edit(good, function(b) b[sectorOf(w, 5) + 0x10] = (b[sectorOf(w, 5) + 0x10] + 1) % 256 end), v,
    "gen3.sectorChecksum", v .. " stale sector checksum")
  expectError(edit(good, function(b) B.le(b, sectorOf(w, 7) + 0xFF8, 0x01121999, 4) end), v, "gen3.signature",
    v .. " Unbound sector signature")
  expectError(edit(good, function(b)
    local off = sectorOf(w, 0)
    b[off + chunks[0] + 2] = 1
    reseal(b, off, chunks[0])
  end), v, "gen3.checksumWindow", v .. " nonzero byte past the section size")
  expectError(g3(v, function(x) B.le(x.sb2, 6, 0, 2) end), v, "gen3.japaneseOt", v .. " OT bytes 6-7 zero")
  expectError(g3(v, function(x) x.sb1[x.F.partyCount] = 7 end), v, "gen3.partyCount", v .. " party of 7")
  expectError(g3(v, function(x)
    G3.setBoxMon(x, 1, 1, G3.mon({ species = 0 }))
  end), v, "gen3.species0", v .. " has-species with species 0 (G3-08)")
  expectError(g3(v, function(x)
    for s = 1, 12 do G3.setBoxMon(x, 4, s, G3.mon({ pid = s * 101, breakChecksum = true })) end
  end), v, "gen3.monChecksumMajority", v .. " most boxed mons fail their checksum")
  expectWarn(g3(v, function(x) G3.setBoxMon(x, 4, 1, G3.mon({ pid = 77, breakChecksum = true })) end), v,
    "gen3.monChecksum", v .. " one bad mon checksum")
  expectWarn(g3(v, function(x) G3.setBoxMon(x, 4, 2, G3.mon({ pid = 78, species = 500 })) end), v,
    "gen3.foreignSpecies", v .. " species id 500")
  expectWarn(g3(v, function(x) G3.setBoxMon(x, 4, 3, G3.mon({ pid = 79, species = 260 })) end), v,
    "gen3.openhomeSpecies", v .. " filler species 260")
  expectWarn(g3(v, function(x) G3.setBoxMon(x, 4, 4, G3.mon({ pid = 80, badEgg = true })) end), v,
    "gen3.badEgg", v .. " bad egg flag")
  expectWarn(edit(good, function(b) B.fill(b, 0x1E000, 0x100, 0x5A) end), v, "gen3.extraSector",
    v .. " sector 30 with a stale checksum (G3-16)")
  expectClean(g3(v, function(x)
    G3.setParty(x, { G3.mon(), G3.mon({ pid = 0x2222, egg = true, nick = "EGG" }) })
  end), v, v .. " party egg is legal")
end

local function frlgKey(fn)
  return g3("firered", function(w)
    w.key = 0
    fn(w)
  end)
end
expectError(frlgKey(function(w) B.le(w.sb2, 0xF20, 0, 4); B.le(w.sb2, 0xAF8, 0, 4) end), "firered",
  "gen3.securityKey", "FireRed with key 0 at 0xF20 and 0xAF8 (G3-01)")
expectError(frlgKey(function(w) B.le(w.sb2, 0xAF8, 0, 4) end), "firered", "gen3.securityKey",
  "FireRed with 0 at 0xAF8 only, which OpenHome reads as the key")
expectError(g3("firered", function(w) B.le(w.sb2, 0xAC, 0, 4) end), "firered", "gen3.gameCode",
  "FireRed without the 1 marker at 0xAC")
expectError(g3("emerald", function(w) B.le(w.sb2, 0xAC, 0, 4) end), "emerald", "gen3.gameCode",
  "Emerald with key 0 (G3-02, typed Ruby/Sapphire)")
expectError(g3("emerald", function(w) B.le(w.sb2, 0xAC, 1, 4) end), "emerald", "gen3.gameCode",
  "Emerald with key 1 (G3-02, typed FireRed/LeafGreen)")
expectError(g3("emerald", function(w) B.fill(w.sb2, 0x890, 0xF2C - 0x890, 0) end), "emerald", "gen3.emeraldData",
  "Emerald with SB2 0x890-0xF2B empty (G3-17)")
expectError(string.rep("\255", 0x20000), "firered", "gen3.sectionIds", "an erased flash")

for rule in pairs(Compat.RULES) do
  check(fired[rule], "rule " .. rule .. " is exercised by a crafted bad image")
end

local ok, msg, report = Compat.gate(edit(g1(), function(b) b[0x3523] = (b[0x3523] + 1) % 256 end), "red")
eq(ok, nil, "gate refuses a hard failure")
check(type(msg) == "string" and msg:find("gen1.mainChecksum", 1, true) ~= nil, "and names the rule -- " .. tostring(msg))
eq(report.ok, false, "and hands back the report")
local ok2, warns = Compat.gate(g1({ staleBankChecksums = true }), "red")
eq(ok2, true, "gate passes a file with warnings only")
eq(#warns, 2, "and returns the warnings")
local ok3, msg3 = Compat.gate("x", "nonsense")
eq(ok3, nil, "an unknown version is refused")
check(tostring(msg3):find("unknown game version", 1, true) ~= nil, "with a reason -- " .. tostring(msg3))

T.finish()
