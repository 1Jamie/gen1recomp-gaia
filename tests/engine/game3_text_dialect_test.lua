package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq, same = T.check, T.eq, T.same

local GameVersion = require("src.core.GameVersion")
local prevVersion = GameVersion.get()
GameVersion.set("firered")

local TextIR = require("src.core.game3.scripting.text_ir")

eq(TextIR.dialectOf("firered"), "frlg", "FireRed text is the frlg dialect")
eq(TextIR.dialectOf("leafgreen"), "frlg", "LeafGreen text is the frlg dialect")
eq(TextIR.dialectOf("emerald"), "rse", "Emerald text is the rse dialect")
eq(TextIR.dialectOf("red"), "frlg", "a non-Gen3 id defaults to frlg")
eq(TextIR.dialect().name, "frlg", "the runtime default follows the active version")
GameVersion.set("emerald")
eq(TextIR.dialect().name, "rse", "an Emerald session defaults to rse")
GameVersion.set("firered")

local FRLG, RSE = TextIR.DIALECTS.frlg, TextIR.DIALECTS.rse
check(FRLG.B_TXT == TextIR.B_TXT, "frlg battle codes are the legacy table")
eq(FRLG.B_TXT[0x2E], "B_TRAINER2_LOSE_TEXT", "frlg 0x2E is TRAINER2_LOSE_TEXT")
eq(FRLG.B_TXT[0x30], "B_BUFF3", "frlg 0x30 is BUFF3")
eq(RSE.B_TXT[0x2E], "B_TRAINER2_CLASS", "rse 0x2E is TRAINER2_CLASS")
eq(RSE.B_TXT[0x2F], "B_TRAINER2_NAME", "rse 0x2F is TRAINER2_NAME")
eq(RSE.B_TXT[0x30], "B_TRAINER2_LOSE_TEXT", "rse 0x30 is TRAINER2_LOSE_TEXT")
eq(RSE.B_TXT[0x31], "B_TRAINER2_WIN_TEXT", "rse 0x31 is TRAINER2_WIN_TEXT")
eq(RSE.B_TXT[0x32], "B_PARTNER_CLASS", "rse 0x32 is PARTNER_CLASS")
eq(RSE.B_TXT[0x33], "B_PARTNER_NAME", "rse 0x33 is PARTNER_NAME")
eq(RSE.B_TXT[0x34], "B_BUFF3", "rse 0x34 is BUFF3")
for code = 0, 0x2D do
  eq(RSE.B_TXT[code], FRLG.B_TXT[code], string.format("battle code 0x%02X is shared", code))
end
eq(RSE.B_TXT_CODE.B_BUFF3, 0x34, "rse BUFF3 name maps to 0x34")

eq(FRLG.PH_NAMES[0x08], "MAGMA", "frlg FD 08 is MAGMA")
eq(RSE.PH_NAMES[0x08], "AQUA", "rse FD 08 is AQUA")
eq(RSE.PH_NAMES[0x09], "MAGMA", "rse FD 09 is MAGMA")
eq(RSE.PH_NAMES[0x0A], "ARCHIE", "rse FD 0A is ARCHIE")
eq(RSE.PH_NAMES[0x0B], "MAXIE", "rse FD 0B is MAXIE")
eq(RSE.PH_NAMES[0x0C], "KYOGRE", "rse FD 0C is KYOGRE")
eq(RSE.PH_NAMES[0x0D], "GROUDON", "rse FD 0D is GROUDON")
eq(RSE.PH_NAMES[0x07], "VERSION", "rse FD 07 is VERSION")

eq(FRLG.FONT_IDS[2], "FONT_NORMAL", "frlg font 2 is NORMAL")
eq(RSE.FONT_IDS[1], "FONT_NORMAL", "rse font 1 is NORMAL")
eq(RSE.FONT_IDS[7], "FONT_NARROW", "rse font 7 is NARROW")
eq(RSE.FONT_CODE.FONT_BOLD, 9, "rse BOLD is font 9")

local sample = {
  0xC2, 0xD9, 0xE0, 0xE0, 0xE3, 0xFD, 0x01, 0xFE, 0xFD, 0x02, 0xFA, 0xFD, 0x06, 0xFB,
  0xFD, 0x08, 0xFC, 0x06, 0x02, 0xF9, 0x00, 0x53, 0x54, 0xF8, 0x00, 0xAB, 0xFF,
}
local frIR = TextIR.decode(sample)
same(frIR, {
  { t = "text", s = "Hello" }, { t = "player" }, { t = "nl" }, { t = "strvar", n = 1 },
  { t = "scroll" }, { t = "rival" }, { t = "para" }, { t = "ph", code = 8 },
  { t = "ext", cmd = 6, args = { 2 } }, { t = "text", s = "↑" }, { t = "tag", tag = "{PKMN}" },
  { t = "tag", tag = "{A_BUTTON}" }, { t = "text", s = "!" }, { t = "eos" },
}, "FireRed decode keeps its IR shape")
same(TextIR.decode(sample, { dialect = "frlg" }), frIR, "an explicit frlg dialect is the default")

local rseIR = TextIR.decode(sample, { dialect = "rse" })
same(rseIR[8], { t = "ph", code = 8, name = "AQUA" }, "rse FD 08 decodes as AQUA")
same(rseIR[9], { t = "ext", cmd = 6, args = { 2 }, font = "FONT_SHORT" }, "rse FC 06 carries the font name")

local battle = TextIR.decode({ 0xFD, 0x30, 0xFF }, { battle = true, dialect = "rse" })
eq(battle[1].t, "bph", "battle text keeps raw codes")
eq(RSE.B_TXT[battle[1].code], "B_TRAINER2_LOSE_TEXT", "rse FD 30 is the second trainer's lose text")
local frBattle = TextIR.decode({ 0xFD, 0x30, 0xFF }, { battle = true })
eq(FRLG.B_TXT[frBattle[1].code], "B_BUFF3", "frlg FD 30 is still BUFF3")

eq(TextIR.fromAscii("{B_BUFF3}")[1].code, 0x30, "fromAscii defaults to frlg codes")
eq(TextIR.fromAscii("{B_BUFF3}", { dialect = "rse" })[1].code, 0x34, "fromAscii rse codes")
eq(TextIR.fromAscii("{B_PARTNER_NAME}", { dialect = "rse" })[1].code, 0x33, "rse-only battle name parses")

local ctx = { dialect = "rse", placeholders = { AQUA = "TEAM AQUA", VERSION = "EMERALD" } }
eq(TextIR.expandSeg({ t = "ph", code = 8, name = "AQUA" }, ctx), "TEAM AQUA", "named placeholder expands")
eq(TextIR.expandSeg({ t = "ph", code = 7 }, ctx), "EMERALD", "coded placeholder expands through the dialect")
eq(TextIR.expandSeg({ t = "ph", code = 8 }, {}), "", "without placeholder data FD 08 stays empty")
local ok, err = pcall(TextIR.expandSeg, { t = "bph", code = 0x33 }, { dialect = "rse", battle = {} })
check(not ok and tostring(err):find("B_PARTNER_NAME", 1, true) ~= nil, "missing battle value names the rse code")

GameVersion.set(prevVersion)
T.finish("game3_text_dialect_test")
