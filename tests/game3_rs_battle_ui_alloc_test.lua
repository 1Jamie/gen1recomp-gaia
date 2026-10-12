#!/usr/bin/env luajit
-- ROM-free: R/S battle UI per-frame colour/opts tables are cached and reused,
-- keep their values, and refresh when palette / profile inputs change.
package.path = "./?.lua;./?/init.lua;" .. package.path
local failed = 0
local function check(cond, msg)
  if cond then print("[ok] " .. msg) else failed = failed + 1; print("[FAIL] " .. msg) end
end
local function near(a, b) return math.abs(a - b) < 1e-9 end
local function same(c, v)
  return near(c[1], v[1]) and near(c[2], v[2]) and near(c[3], v[3]) and c[4] == v[4]
end
local function bgr(v)
  local function c5to8(x) return (x * 8 + math.floor(x / 4)) / 255 end
  return { c5to8(v % 32), c5to8(math.floor(v / 32) % 32), c5to8(math.floor(v / 1024) % 32), 1 }
end
local function c5(v) return math.floor(v * 255 / 31 + 0.5) / 255 end
local function hbc(v) return { c5(v % 32), c5(math.floor(v / 32) % 32), c5(math.floor(v / 1024) % 32), 1 } end

love = { graphics = {
  getScissor = function() return nil end, setScissor = function() end,
  setColor = function() end, rectangle = function() end, draw = function() end,
} }

-- Switchable profile rows (game switch).
local rowA = { id = "a", ui = { healthbox = { layout = "rs", doublesCenters = {} } }, font = { module = "test.font_a" } }
local rowB = { id = "b", ui = {}, font = { module = "test.font_b" } }
local current = rowA
package.loaded["src.core.game3.profile"] = {
  forSession = function() return current end,
  family = function() return "frlg" end,
}
local drawn = {}
package.loaded["test.font_a"] = { tag = "a", draw = function(t, x, y, o) drawn[#drawn + 1] = { t, o } end,
  measure = function(t) return #t * 5 end }
package.loaded["test.font_b"] = { tag = "b" }

local FrlgFont = { CHAR_LV_2 = 1, CHAR_MALE = 2, CHAR_FEMALE = 3, COLOR = { WHITE = { w = true } },
  draw = function(t, x, y, o) drawn[#drawn + 1] = { t, o } end,
  drawGlyph = function() end, measure = function(t) return #tostring(t) * 5 end,
  advance = function() return 6 end }
package.loaded["src.ui.game3.frlg_font"] = FrlgFont

local BattleChrome = require("src.ui.game3.battle_chrome")
local HB_PAL = { 0, 0x0421, 0x7fff, 0x2529, 0, 0, 0, 0, 0, 0, 0x03ff, 0x7c00 }
local BAR_PAL = { 0, 0x1111, 0, 0x2222 }
BattleChrome._manifest = { healthboxPal = HB_PAL, healthbarPal = BAR_PAL,
  textboxPal = { 0, 1, 2, 3, 4, 5, 6, 7, 0x0842 }, windowTextPal = {}, ppTextPal = {} }
for i = 1, 16 do BattleChrome._manifest.windowTextPal[i] = i * 100 end
for i = 1, 8 do BattleChrome._manifest.ppTextPal[i] = i * 50 end

---- BattleChrome.textboxColors
print("[test] textboxColors memoized")
local t1 = BattleChrome.textboxColors(1, 8)
local t2 = BattleChrome.textboxColors(1, 8)
check(t1 == t2, "same (pal,fg,shadow) returns same table")
check(same(t1.fg, bgr(1)) and same(t1.shadow, bgr(0x0842)) and t1.bg[4] == 0, "values match bgr555 decode")
check(BattleChrome.textboxColors(1, 6) ~= t1, "different shadow index -> different table")
BattleChrome._manifest.textboxPal = { 0, 9, 2, 3, 4, 5, 6, 7, 0x0842 }
local t3 = BattleChrome.textboxColors(1, 8)
check(t3 ~= t1 and same(t3.fg, bgr(9)), "new palette table -> fresh values")
BattleChrome._manifest.textboxPal[2] = 10
local t4 = BattleChrome.textboxColors(1, 8)
check(same(t4.fg, bgr(10)), "in-place palette edit is picked up")
BattleChrome._manifest.textboxPal = nil
check(BattleChrome.textboxColors(1, 8) == FrlgFont.COLOR.WHITE, "no palette -> FrlgFont WHITE")

---- Healthbox (R/S rows)
print("[test] healthbox RS opts cached")
package.loaded["src.core.game3.battle.state"] = { displayName = function(b) return b.name end }
package.loaded["src.core.game3.battle.anim"] = {
  displayHpRatio = function(_, b) return 1, b.mon.hp, b.mon.maxHp end,
}
package.loaded["src.ui.game3.summary_chrome"] = { drawStatusIcon = function() end }
package.loaded["src.core.game3.summary_data"] = { statusAilment = function() return 0 end }
package.loaded["src.core.game3.pokemon"] = { gender = function() return nil end }
package.loaded["src.core.game3.battle.experience"] = { progress = function() return { progressPercent = 0 } end }
for _, fn in ipairs({ "drawPlayerBox", "drawEnemyBox", "drawHpBar", "drawExpBar", "drawElementTile" }) do
  BattleChrome[fn] = function() end
end
local Healthbox = require("src.core.game3.battle.healthbox")
local function frame()
  drawn = {}
  Healthbox.draw("player", { name = "BOB", mon = { species = 52, level = 50, hp = 12, maxHp = 34, gender = "X" } })
end
frame()
local cur
for _, d in ipairs(drawn) do if d[1]:find("12/", 1, true) then cur = d[2] end end
check(cur and cur.font == "native_4" and cur.textMode == 0, "HP row opts carry native_4/textMode 0")
check(cur and same(cur.colors.fg, hbc(0x0421)) and same(cur.colors.shadow, hbc(0x2529)) and cur.colors.bg[4] == 0,
  "HP row colours: fg/shadow from healthbox palette, bg clear")
frame()
local cur2
for _, d in ipairs(drawn) do if d[1]:find("12/", 1, true) then cur2 = d[2] end end
check(cur == cur2, "HP row opts table reused across frames")
-- palette change -> fresh values
BattleChrome._manifest.healthboxPal = { 0, 0x0001, 0x7fff, 0x0002, 0, 0, 0, 0, 0, 0, 0x03ff, 0x7c00 }
frame()
local cur3
for _, d in ipairs(drawn) do if d[1]:find("12/", 1, true) then cur3 = d[2] end end
check(cur3 ~= cur and same(cur3.colors.fg, hbc(1)) and same(cur3.colors.shadow, hbc(2)),
  "healthbox palette change -> fresh opts/colours")
-- game switch to non-RS row
current = rowB
check(Healthbox.center({ double = true }, 0).x == 159, "profile switch -> rs_layout follows (FRLG centres)")
current = rowA
check(Healthbox.center({ double = true }, 0) == nil, "switch back -> RS layout again")

---- battle/ui.lua helpers
print("[test] battle ui helpers cached")
local Ui = require("src.core.game3.battle.ui")
local P = Ui._cacheProbe
check(P.battleFont() == package.loaded["test.font_a"] and P.battleFont() == P.battleFont(), "battle_font cached")
current = rowB
check(P.battleFont() == package.loaded["test.font_b"], "battle_font follows profile switch")
current = rowA

local m1, m2 = P.rsMenuColors(), P.rsMenuColors()
check(m1 == m2, "rs_menu_colors is a shared constant")
check(same(m1.fg, bgr(0x2529)) and same(m1.shadow, bgr(0x675a)) and m1.bg[4] == 0, "rs_menu_colors values (0x2529/0x675a)")
local h1, h2 = P.rsSwapHighlight(m1), P.rsSwapHighlight(m1)
check(h1 == h2 and same(h1.fg, bgr(0x7fe0)) and h1.shadow == m1.shadow and h1.bg == m1.bg, "swap highlight cached + values")

local W = BattleChrome._manifest.windowTextPal
local PP = BattleChrome._manifest.ppTextPal
local p1, p2 = P.rsePpColors(1, 20), P.rsePpColors(1, 20)
check(p1 == p2, "rse_pp_colors reused for same state")
local st = Ui.ppColorState(1, 20)
check(same(p1.fg, bgr(PP[st * 2 + 1])) and same(p1.shadow, bgr(PP[st * 2 + 2])), "pp colours from ppTextPal")
check(same(p1.bg, { 0, 0, 0, 0 }) and p1.bg[4] == 0, "pp bg clear")
check(P.rsePpColors(20, 20) ~= p1, "different PP state -> different table")
BattleChrome._manifest.ppTextPal = { 7, 7, 7, 7, 7, 7, 7, 7 }
local p3 = P.rsePpColors(1, 20)
check(p3 ~= p1 and same(p3.fg, bgr(7)), "ppTextPal change -> fresh values")
PP = BattleChrome._manifest.ppTextPal
PP[st * 2 + 1] = 11
check(same(P.rsePpColors(1, 20).fg, bgr(11)), "in-place ppTextPal edit picked up")
check(W ~= nil, "windowTextPal present")

local base = { fg = { 1, 0, 0, 1 }, shadow = { 0, 1, 0, 1 }, bg = { 0, 0, 0, 0 } }
local s29a, s29b = P.swapCursorColors(29, base), P.swapCursorColors(29, base)
local s27 = P.swapCursorColors(27, base)
check(s29a == s29b and s29a.fg == base.shadow and s29a.bg == base.bg and same(s29a.shadow, { 0, 0, 0, 0 }), "swap cursor 29 cached/values")
check(s27 ~= s29a and s27.fg == base.fg, "swap cursor 27 distinct, fg = base.fg")

if failed > 0 then print(failed .. " FAILED"); os.exit(1) end
print("all passed")
