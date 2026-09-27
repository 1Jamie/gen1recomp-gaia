package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local prevVersion = GameVersion.get()
GameVersion.set("firered")

local Opcodes = require("src.core.game3.scripting.opcodes")
local Disasm = require("src.core.game3.scripting.disasm")
local FRCMDS = require("src.core.game3.constants.firered.script_cmds")
local EMCMDS = require("src.core.game3.constants.emerald.script_cmds")

local function argBytes(row)
  local n = 1
  for _, a in ipairs(row.args) do
    n = n + (a.kind == "byte" and 1 or a.kind == "half" and 2 or 4)
  end
  return n
end

local function fingerprint(tbl)
  local parts = {}
  for byte = 0, 0xFF do
    local r = tbl[byte]
    if r and byte ~= 0x72 and byte ~= 0xAA then
      local k = {}
      for _, a in ipairs(r.args) do k[#k + 1] = a.kind end
      parts[#parts + 1] = string.format("%02x %s %d %s", byte, r.name, r.size, table.concat(k, ","))
    end
  end
  local s = table.concat(parts, "\n")
  local h = 0
  for i = 1, #s do h = (h * 31 + s:byte(i)) % 2147483647 end
  return #s, h
end

local count = 0
for _ in pairs(Opcodes.TABLE) do count = count + 1 end
eq(count, 213, "FireRed keeps 213 script commands")
eq(Opcodes.MAX, 0xD4, "FireRed table ends at 0xD4")
local len, hash = fingerprint(Opcodes.TABLE)
eq(len, 5549, "FireRed opcode inventory text is unchanged")
eq(hash, 1388146932, "FireRed opcode inventory hash is unchanged")

local fr = Opcodes.forGame("firered")
check(fr.TABLE == Opcodes.TABLE, "the FireRed set is the legacy table")
check(Opcodes.forGame("leafgreen") == fr, "LeafGreen shares the FireRed set")
check(Opcodes.forGame("red") == fr, "a non-Gen3 id resolves to the FireRed set")

eq(Opcodes.get(0x72).size, 1, "drawbox has no operands")
eq(#Opcodes.get(0x72).args, 0, "drawbox reads nothing")
eq(Opcodes.get(0xAA).size, 9, "createvobject is 9 bytes")
eq(argBytes(Opcodes.get(0xAA)), 9, "createvobject operands sum to 9 bytes")

for byte = 0, 0xD4 do
  local row, pret = Opcodes.TABLE[byte], FRCMDS.byId[byte]
  if byte ~= 0x5C and byte ~= 0xCC then
    eq(argBytes(row), pret.size, string.format("FireRed 0x%02X %s operands match pokefirered", byte, row.name))
  end
end

local em = Opcodes.forGame("emerald")
local emCount = 0
for _ in pairs(em.TABLE) do emCount = emCount + 1 end
eq(emCount, EMCMDS.count, "Emerald has every pokeemerald script command")
eq(em.MAX, 0xE2, "Emerald table ends at 0xE2")
for byte = 0, em.MAX do
  local row, pret = em.TABLE[byte], EMCMDS.byId[byte]
  check(row ~= nil, string.format("Emerald 0x%02X is defined", byte))
  if row and byte ~= 0x5C then
    eq(row.size, pret.size, string.format("Emerald 0x%02X %s size matches pokeemerald", byte, row.name))
    eq(argBytes(row), pret.size, string.format("Emerald 0x%02X operands match pokeemerald", byte))
  end
end
for byte = 0, 0xC6 do
  check(em.TABLE[byte] == Opcodes.TABLE[byte], string.format("0x%02X is shared by both games", byte))
end
for _, byte in ipairs({ 0xC7, 0xC8, 0xC9, 0xCA, 0xCB, 0xCC, 0xD0 }) do
  eq(em:get(byte).name, "nop1", string.format("Emerald 0x%02X is ScrCmd_nop1", byte))
end
eq(em:get(0xD3).name, "moverotatingtileobjects", "Emerald 0xD3 is moverotatingtileobjects")
eq(em:get(0xDB).name, "messageinstant", "Emerald 0xDB is messageinstant")
eq(em:get(0xDF).name, "pokenavcall", "Emerald 0xDF is pokenavcall")
eq(em:get(0xE2).name, "bufferitemnameplural", "Emerald 0xE2 is bufferitemnameplural")
eq(em:get(0xCD).name, "setmonmodernfatefulencounter", "Emerald 0xCD keeps the engine verb name")

eq(fr:trainerBattleType(9), "EARLY_RIVAL", "FireRed trainerbattle 9 is EARLY_RIVAL")
eq(em:trainerBattleType(9), "PYRAMID", "Emerald trainerbattle 9 is PYRAMID")
eq(em:trainerBattleType(10), "SET_TRAINER_A", "Emerald trainerbattle 10 is SET_TRAINER_A")
eq(em:trainerBattleType(11), "SET_TRAINER_B", "Emerald trainerbattle 11 is SET_TRAINER_B")
eq(em:trainerBattleType(12), "HILL", "Emerald trainerbattle 12 is HILL")
eq(fr:trainerBattleType(10), nil, "FireRed has no trainerbattle 10")

eq(fr.STD.RECEIVED_ITEM, 9, "FireRed std 9 is RECEIVED_ITEM")
eq(em.STD.MSGBOX_POKENAV, 10, "Emerald std 10 is MSGBOX_POKENAV")
eq(fr.brailleFormatSize, 0, "FireRed braille text has no header")
eq(em.brailleFormatSize, 6, "Emerald braille text has the 6-byte brailleformat header")

local function battleBytes(typ, nptr)
  local b = { 0x5C, typ, 0x34, 0x12, 0x02, 0x00 }
  for p = 1, nptr do
    for _, v in ipairs({ p, 0x00, 0x00, 0x08 }) do b[#b + 1] = v end
  end
  b[#b + 1] = 0x02
  return b
end

local rows = Disasm.decode(battleBytes(9, 2), 1, nil, em)
eq(rows[1].type, 9, "Emerald trainerbattle type is kept")
eq(rows[1].introText, 0x08000001, "Emerald PYRAMID reads an intro text")
eq(rows[1].defeatText, 0x08000002, "Emerald PYRAMID reads a defeat text")
eq(rows[1].flags, nil, "Emerald PYRAMID is not an early rival battle")
eq(rows[2] and rows[2].op, "end", "Emerald PYRAMID resyncs at the next command")

rows = Disasm.decode(battleBytes(9, 2), 1, nil, fr)
eq(rows[1].flags, 2, "FireRed EARLY_RIVAL keeps rival flags")
eq(rows[1].defeatText, 0x08000001, "FireRed EARLY_RIVAL reads defeat text first")
eq(rows[1].victoryText, 0x08000002, "FireRed EARLY_RIVAL reads victory text second")
eq(rows[2] and rows[2].op, "end", "FireRed EARLY_RIVAL resyncs")

for _, typ in ipairs({ 10, 11, 12 }) do
  rows = Disasm.decode(battleBytes(typ, 2), 1, nil, em)
  eq(rows[1].defeatText, 0x08000002, "Emerald trainerbattle " .. typ .. " reads two texts")
  eq(rows[2] and rows[2].op, "end", "Emerald trainerbattle " .. typ .. " resyncs")
end
rows = Disasm.decode(battleBytes(10, 2), 1, nil, fr)
eq(rows[1].opaque, true, "FireRed has no trainerbattle 10 and stops")

rows = Disasm.decode({ 0x72, 0x02 }, 1, nil, em)
eq(rows[1].op, "drawbox", "drawbox decodes")
eq(rows[2] and rows[2].op, "end", "drawbox is one byte")
rows = Disasm.decode({ 0xAA, 1, 2, 3, 0, 4, 0, 5, 6, 0x02 }, 1, nil, em)
eq(rows[1][6], 6, "createvobject reads its facing byte")
eq(rows[2] and rows[2].op, "end", "createvobject is nine bytes")
rows = Disasm.decode({ 0xC7, 0x02 }, 1, nil, em)
eq(rows[1].op, "nop1", "Emerald 0xC7 is a one-byte nop")
eq(rows[2] and rows[2].op, "end", "Emerald 0xC7 reads no operand")
rows = Disasm.decode({ 0xC7, 0x01, 0x02 }, 1, nil, fr)
eq(rows[1].op, "textcolor", "FireRed 0xC7 is textcolor")
eq(rows[2] and rows[2].op, "end", "FireRed textcolor reads one byte")

local ExtractScripts = require("src.import.gba.extract_scripts")
local function fakeRom(mem)
  local rom = {}
  function rom:ptrOffset(p)
    p = tonumber(p) or 0
    if p < 0x08000000 or p >= 0x08000000 + #mem then return nil end
    return p - 0x08000000
  end
  function rom:get(off) return mem[off + 1] end
  function rom:readBytes(off, n)
    local out = {}
    for i = 1, n do
      local b = mem[off + i]
      if b == nil then break end
      out[i] = b
    end
    return out
  end
  function rom:u32(off)
    return mem[off + 1] + mem[off + 2] * 256 + mem[off + 3] * 65536 + mem[off + 4] * 16777216
  end
  return rom
end
local mem = { 0x78, 0x10, 0x00, 0x00, 0x08, 0x02 }
while #mem < 0x10 do mem[#mem + 1] = 0 end
for _, v in ipairs({ 4, 6, 26, 13, 7, 9, 0x01, 0x05, 0xFF }) do mem[#mem + 1] = v end

GameVersion.set("emerald")
local out = ExtractScripts.bfsFromSeeds(fakeRom(mem), { 0x08000000 })
local ir = out.text[Opcodes.key(0x08000010)]
eq(ir and ir[1] and ir[1].s, "AB", "Emerald braillemessage skips the brailleformat header")
GameVersion.set("firered")
out = ExtractScripts.bfsFromSeeds(fakeRom(mem), { 0x08000000 })
ir = out.text[Opcodes.key(0x08000010)]
check(ir and ir[1] and ir[1].s ~= "AB", "FireRed braillemessage reads from the pointer")

local mem2 = { 0xDB, 0x08, 0x00, 0x00, 0x08, 0x02, 0x00, 0x00, 0xBB, 0xFF }
GameVersion.set("emerald")
out = ExtractScripts.bfsFromSeeds(fakeRom(mem2), { 0x08000000 })
local row = out.scripts[Opcodes.key(0x08000000)][1]
eq(row.op, "messageinstant", "messageinstant decodes on Emerald")
eq(row.ptr, Opcodes.key(0x08000008), "messageinstant text pointer becomes a key")
check(out.text[row.ptr] ~= nil, "messageinstant text is extracted")

GameVersion.set(prevVersion)
T.finish("game3_opcodes_per_game_test")
