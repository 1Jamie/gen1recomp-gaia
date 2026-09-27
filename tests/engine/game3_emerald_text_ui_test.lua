package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local TextIR = require("src.core.game3.scripting.text_ir")
local Chrome = require("src.ui.game3.chrome")
local FrlgFont = require("src.ui.game3.frlg_font")

local prevVersion = GameVersion.get()
local prevProvider = TextIR._provider
Profile.reset()

local function segs(ir)
  local out = {}
  for _, s in ipairs(ir) do out[#out + 1] = s.t .. ":" .. tostring(s.s or s.tag or s.name or "") end
  return table.concat(out, "|")
end

-- pokeemerald/charmap.txt:45
local bytes = { 0xCC, 0x00, 0x55, 0x56, 0x57, 0x58, 0x59, 0x00, 0x34, 0xA6, 0x77, 0x79, 0x7A, 0x7B, 0x7C, 0xFF }
eq(segs(TextIR.decode(bytes, { dialect = "rse" })),
  "text:R |tag:{POKEBLOCK}|text: |tag:{LV}|text:5|tag:{UNK_SPACER}|tag:{UP_ARROW}|tag:{DOWN_ARROW}"
    .. "|tag:{LEFT_ARROW}|tag:{RIGHT_ARROW}|eos:",
  "rse decodes LV, the POKEBLOCK run, UNK_SPACER and the four arrows as tags")
eq(segs(TextIR.decode(bytes, { dialect = "frlg" })), "text:R ????? ?5?????|eos:",
  "frlg decode of the same bytes is unchanged")
eq(segs(TextIR.decode({ 0x56, 0x57, 0xBB, 0xFF }, { dialect = "rse" })), "text:A|eos:",
  "a broken POKEBLOCK run prints nothing for its tail pieces")
eq(TextIR.toPlain(TextIR.decode({ 0xCC, 0x55, 0x56, 0x57, 0x58, 0x59, 0xFF }, { dialect = "rse" })), "R{POKEBLOCK}",
  "toPlain keeps the POKEBLOCK tag for the font")
for _, name in ipairs({ "LV", "POKEBLOCK", "UNK_SPACER", "UP_ARROW", "DOWN_ARROW", "LEFT_ARROW", "RIGHT_ARROW" }) do
  check(TextIR.TAG_NAMES[name], "fromAscii knows {" .. name .. "}")
  check(FrlgFont.GLYPH_TAGS[name] ~= nil, "the font has glyphs for {" .. name .. "}")
end
eq(FrlgFont.GLYPH_TAGS.UP_ARROW[1], 0x79, "UP_ARROW is glyph 0x79")

-- pokeemerald/src/string_util.c:456
local ph = { VERSION = "EMERALD", byGender = { RIVAL = { male = "MAY", female = "BRENDAN" }, KUN = { male = "", female = "" } } }
local rivalIr = TextIR.decode({ 0xFD, 0x06, 0x00, 0xFD, 0x07, 0xFD, 0x05, 0xFF }, { dialect = "rse" })
eq(TextIR.toPlain(rivalIr, { dialect = "rse", placeholders = ph }), "MAY EMERALD", "male player: FD 06 is MAY")
eq(TextIR.toPlain(rivalIr, { dialect = "rse", placeholders = ph, playerGender = 1 }), "BRENDAN EMERALD",
  "female player: FD 06 is BRENDAN")
eq(TextIR.toPlain(rivalIr, { dialect = "rse", placeholders = ph, playerGender = "female", rivalName = "BLUE" }),
  "BRENDAN EMERALD", "a saved rival name never overrides the rse rival placeholder")
eq(TextIR.toPlain(rivalIr, { dialect = "frlg", rivalName = "BLUE" }), "BLUE ", "frlg FD 06 is still the saved rival name")

local asked = {}
TextIR.setContextProvider(function(kind, dialect)
  asked[#asked + 1] = kind .. ":" .. tostring(dialect and dialect.name)
  if kind == "placeholders" then return ph end
  if kind == "gender" then return "female" end
end)
eq(TextIR.toPlain(rivalIr, { dialect = "rse" }), "BRENDAN EMERALD", "the provider supplies placeholders and gender")
asked = {}
eq(TextIR.toPlain(rivalIr, { dialect = "frlg", rivalName = "BLUE" }), "BLUE ", "frlg never asks the provider")
eq(#asked, 0, "no provider calls for frlg text")
TextIR.setContextProvider(prevProvider)

GameVersion.set("emerald")
eq(TextIR.dialectOf(), "rse", "Emerald text is the rse dialect")
local em = Profile.of("emerald")
check(type(em.ui) == "table", "Emerald has a ui block")
check(em.ui.fonts == em.font, "ui.fonts is the font block")
for name, face in pairs(em.font.faces) do
  check(TextIR.DIALECTS.rse.FONT_CODE[face.fontId] ~= nil, "face " .. name .. " names a pret font id")
end
for _, name in ipairs({ "normal", "small", "short", "narrow", "small_narrow" }) do
  check(em.font.faces[name] ~= nil, "Emerald has the " .. name .. " face")
end
eq(em.font.npcTextColors, false, "Emerald has no NPC text colours")
eq(Chrome.userFrameCount(), 20, "Emerald cycles 20 window frames")
local L, Top, W, H = Chrome.dialogueWindow()
eq(table.concat({ L, Top, W, H }, ","), "2,15,27,4", "Emerald message window is sStandardTextBox_WindowTemplates")
eq(em.ui.frames.std, "user", "Emerald std windows use the user frame")
eq(em.ui.frames.sign, false, "Emerald has no signpost frame")
check(FrlgFont.sync() == em.font, "the font provider follows the Emerald profile")
eq(FrlgFont.getNpcTextColor(22), FrlgFont.NPC_TEXT_COLOR.NEUTRAL, "Emerald NPC text is neutral")
local sawMale = false
for ttype, val, col in FrlgFont.scanTokens("\252\006\004A") do
  if ttype == "char" then sawMale = col.fg == FrlgFont.STDPAL[8] end
end
eq(sawMale, false, "rse font id 4 is FONT_SHORT_COPY_2, not FONT_MALE")

GameVersion.set("firered")
eq(TextIR.dialectOf(), "frlg", "FireRed text is the frlg dialect")
eq(Chrome.userFrameCount(), 10, "FireRed cycles 10 window frames")
L, Top, W, H = Chrome.dialogueWindow()
eq(table.concat({ L, Top, W, H }, ","), "2,15,26,4", "FireRed message window unchanged")
eq(Chrome.arrowSpec(), nil, "FireRed keeps its down_arrows sheet")
eq(FrlgFont.sync(), nil, "FireRed has no face table")
eq(FrlgFont.getNpcTextColor(22), 1, "FireRed NPC text colours unchanged")
sawMale = false
for ttype, val, col in FrlgFont.scanTokens("\252\006\004A") do
  if ttype == "char" then sawMale = col.fg == FrlgFont.STDPAL[8] end
end
eq(sawMale, true, "frlg font id 4 is still FONT_MALE")

GameVersion.set(prevVersion)
Profile.reset()
T.finish("game3_emerald_text_ui_test")
