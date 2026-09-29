package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local TextBox = require("src.render.TextBox")

local oak = "Just throw a POKé\nBALL at it and try\nto catch it!"

local g1 = TextBox.paginate(oak, 18, true)
eq(#g1, 1, "gen1: one page")
eq(#g1[1], 2, "gen1: third plain line does not become a scrolled line")
eq(g1[1][1], "Just throw a POKé", "gen1: first row unchanged")
eq(g1[1][2], "to catch it!nd try", "gen1: second line overwrites row 2")

local g2 = TextBox.paginate(oak, 18)
eq(#g2[1], 3, "default (gen2/3, mods): three lines kept")
eq(g2[1][3], "to catch it!", "default: third line intact")

local cont = TextBox.paginate("a\nb\vc", 18, true)
eq(#cont[1], 3, "gen1: cont scroll unchanged")
eq(cont.contBefore[1][3], true, "gen1: cont mark kept")

local two = TextBox.paginate("a\nb", 18, true)
eq(#two[1], 2, "gen1: plain two-line page unchanged")
eq(two[1][2], "b", "gen1: two-line second row")

local multi = TextBox.paginate("x\ny\f" .. oak, 18, true)
eq(#multi, 2, "gen1: page break kept")
eq(#multi[2], 2, "gen1: overwrite applies per page")

local wide = TextBox.paginate("abc\ndef\nghi", 18, true)
eq(wide[1][2], "ghi", "gen1: equal-length overwrite replaces the row")

local pageText = "\012When a wild\nPOKéMON appears,\011it's fair game.\012Just throw a POKé\nBALL at it and try\nto catch it!\012This won't always\nwork, though.{DONE}"
local function box(save, text)
  local game = { data = { text = { _OaksLabGivePokeballsExplanationText = pageText } },
    save = save, input = {} }
  return TextBox.new(game, text)
end

local v = box({}, pageText)
eq(#v.pages[2], 2, "TextBox.new: vanilla Oak text overwrites in Gen 1")
eq(v.pages[2][2], "to catch it!nd try", "TextBox.new: cart row 2")

local g2box = box({ generation = 2 }, pageText)
eq(#g2box.pages[2], 3, "TextBox.new: Gen 2 save unchanged")
local g3box = box({ generation = 3 }, pageText)
eq(#g3box.pages[2], 3, "TextBox.new: Gen 3 save unchanged")

local other = box({}, "What?\nx is\nevolving!")
eq(#other.pages[1], 3, "TextBox.new: other 3-line text unchanged")

T.finish()
