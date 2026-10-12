-- pokefirered/src/item_menu.c:301

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Extract = require("src.import.gba.bag_chrome_extract")
local Versions = require("src.import.gba.versions_frlg")

eq(Versions.BAG_SELECT_BUTTON, 0x452F7C, "sBlit_SelectButton offset (FireRed 1.0)")
eq(Versions.BAG_WINDOW_PAL, 0x453098, "sBagWindowPalF offset (FireRed 1.0)")
local lg = require("src.import.gba.editions.leafgreen_1_0")
eq(lg[0x452F7C], 0x45299C, "LeafGreen maps sBlit_SelectButton")
eq(lg[0x453098], 0x452AB8, "LeafGreen maps sBagWindowPalF")

check(type(Extract.bakeSelectButton) == "function", "the bag chrome extractor bakes the SELECT button")

local gfx = {}
for t = 0, 5 do
  for i = 1, 32 do gfx[t * 32 + i] = (t + 1) * 17 end
end
gfx[1] = 0
local pal = {}
for c = 0, 15 do
  local v = c * 2
  pal[c * 2 + 1] = v % 256
  pal[c * 2 + 2] = 0
end
local rgba = Extract.bakeSelectButton(gfx, pal)
eq(#rgba, 24 * 16 * 4, "24x16 RGBA")

local function px(x, y)
  local o = (y * 24 + x) * 4
  return rgba:byte(o + 1), rgba:byte(o + 4)
end
local function red5(idx) return math.floor(idx * 2 * 255 / 31 + 0.5) end
local _, a0 = px(0, 0)
eq(a0, 0, "color 0 is transparent")
for t = 0, 5 do
  local x, y = (t % 3) * 8 + 4, math.floor(t / 3) * 8 + 4
  local r, a = px(x, y)
  eq(a, 255, "tile " .. t .. " is opaque")
  eq(r, red5(t + 1), "tile " .. t .. " lands at column " .. (t % 3) .. " row " .. math.floor(t / 3))
end

T.finish()
