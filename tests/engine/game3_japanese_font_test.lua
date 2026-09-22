#!/usr/bin/env luajit
-- The US FireRed cart keeps its Japanese fonts (pokefirered/src/text.c:141,
-- :227); FrlgFont draws a Japanese character with them, numbered by the Japanese
-- block of pokefirered/charmap.txt, while Latin text keeps its own glyphs.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check = T.check

local FrlgFont = require("src.ui.game3.frlg_font")
local BASE = FrlgFont.JAPANESE_BASE

-- pokefirered/charmap.txt: あ..っ are 01-50, ア..ッ 51-A0
check(FrlgFont.glyphId("あ") == BASE + 0x01, "あ is the Japanese font's glyph 01")
check(FrlgFont.glyphId("っ") == BASE + 0x50, "っ closes the hiragana at 50")
check(FrlgFont.glyphId("ア") == BASE + 0x51, "ア opens the katakana at 51")
check(FrlgFont.glyphId("ッ") == BASE + 0xA0, "ッ closes them at A0")
check(FrlgFont.glyphId("　") == BASE + 0x00, "the full-width space is glyph 00")
check(FrlgFont.glyphId("ー") == BASE + 0xAE, "ー is AE")
check(FrlgFont.glyphId("０") == BASE + 0xA1 and FrlgFont.glyphId("９") == BASE + 0xAA,
  "full-width digits sit where the Latin digits do (A1-AA)")
check(FrlgFont.glyphId("Ｐ") == BASE + 0xCA and FrlgFont.glyphId("ｃ") == BASE + 0xD7,
  "full-width letters too (BB-EE)")
check(FrlgFont.glyphId("「") == BASE + 0xB3 and FrlgFont.glyphId("』") == BASE + 0xB2,
  "and the Japanese quotes (B1-B4)")
check(FrlgFont.glyphId("A") == 0xBB and FrlgFont.glyphId("0") == 0xA1 and FrlgFont.glyphId("é") ~= nil
  and FrlgFont.glyphId("é") < BASE, "Latin text keeps the Latin font")

-- pokefirered/src/text.c:1391 small Japanese glyphs are 8px; :1492 normal ones read
-- the width table, which is 10px for every kana (the space included, text.c:1493).
check(FrlgFont.advance(FrlgFont.glyphId("あ"), { small = true }) == 8, "a small kana is 8px wide")
check(FrlgFont.measure("ポケモン") == 40, "four normal kana are 40px wide (got " .. FrlgFont.measure("ポケモン") .. ")")

-- The extractor reads the glyphs the way DecompressGlyph_Normal/_Small lay them out.
local TextChromeExtract = require("src.import.gba.text_chrome_extract")
local bytes = {}
local rom = { get = function(_, off) return bytes[off] or 0 end }
-- normal glyph 9 (row 1, column 1): top-left tile at 0x207500 + 0x200 + 0x20,
-- bottom-right at +0x110.  A 2bpp tile's first row is two bytes, pixel 0 in the
-- high bits of the second byte; 0x40 there sets pixel 0 to colour 1.
local g = 0x207500 + 0x200 + 0x20
bytes[g + 1] = 0x40
bytes[g + 0x110 + 1] = 0x40
local sheet = TextChromeExtract.extractJapaneseNormal(rom)
local function alpha(rgba, w, x, y) return rgba:byte((y * w + x) * 4 + 4) end
check(alpha(sheet.fgRgba, 256, 9 * 16, 0) == 255, "normal glyph 9's top-left pixel comes from its top tile")
check(alpha(sheet.fgRgba, 256, 9 * 16 + 8, 8) == 255, "and its bottom-right quarter from 0x110 bytes on")
check(alpha(sheet.fgRgba, 256, 8 * 16, 0) == 0, "while glyph 8 stays empty")
-- small glyph 17 (row 1, column 1): top tile at 0x1EF100 + 0x200 + 0x10, bottom 0x100 on
local s = 0x1EF100 + 0x200 + 0x10
bytes[s + 1] = 0x40
bytes[s + 0x100 + 1] = 0x40
local small = TextChromeExtract.extractJapaneseSmall(rom)
check(alpha(small.fgRgba, 256, 1 * 16, 16) == 255 and alpha(small.fgRgba, 256, 1 * 16, 24) == 255,
  "small glyph 17 is its top tile over the tile 0x100 bytes on")

T.finish("game3_japanese_font_test")
