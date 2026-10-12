#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local eq = T.eq

package.loaded["src.core.game3.rom_text"] = {
  plain = function(key)
    return ({
      gSaveStatName_Player = "PLAYER", gSaveStatName_Badges = "BADGES",
      gSaveStatName_Pokedex = "POKeDEX", gSaveStatName_Time = "TIME",
    })[key] or key
  end,
}
package.loaded["src.ui.game3.window"] = {
  template = function(l, t, w, h) return { left = l, top = t, width = w, height = h } end,
  fixedStdFrame = function() end, stdFrame = function() end, cursorPx = function() end,
}
package.loaded["src.ui.game3.chrome"] = { dialogueFrame = function() end }

local FrlgFont = require("src.ui.game3.frlg_font")
local SMALL_W = { PLAYER = 29, BADGES = 30, POKeDEX = 35, TIME = 18 }
FrlgFont.measure = function(text, opts)
  if opts and opts.small then return SMALL_W[text] or 5 * #text end
  return 6 * #text
end
local calls = {}
FrlgFont.draw = function(text, x, y, opts)
  calls[text] = { x = x, y = y, small = opts and opts.small == true or false, colors = opts and opts.colors }
  return 0
end

local SaveMenu = require("src.ui.game3.save_menu")
SaveMenu.locationName = function() return "VIRIDIAN CITY" end
SaveMenu.countBadges = function() return 0 end
SaveMenu.hasDex = function() return true end
SaveMenu.countDex = function() return 7 end

SaveMenu.open = true
SaveMenu._layout = "frlg"
SaveMenu._rse = false
SaveMenu._phase = "confirm"
SaveMenu._session = { name = "RED", playtime = { hours = 0, minutes = 5 } }
SaveMenu.draw()

local header = calls["VIRIDIAN CITY"]
eq(header and header.colors and header.colors.fg, FrlgFont.STDPAL[8], "location header is stdpal blue")
eq(header and header.colors and header.colors.shadow, FrlgFont.STDPAL[9], "location header shadow is light blue")
eq(header and header.y, 8, "location header at window y 0")
eq(header and header.small, false, "location header in the normal font")
eq(header and header.x, 8 + math.floor((112 - 6 * 13) / 2), "location header centred in 112 px")

local rows = { { "PLAYER", 14 }, { "BADGES", 28 }, { "POKeDEX", 42 }, { "TIME", 56 } }
for _, r in ipairs(rows) do
  local c = calls[r[1]]
  eq(c and c.small, true, r[1] .. " label in the small font")
  eq(c and c.x, 8 + 2, r[1] .. " label at window x 2")
  eq(c and c.y, 8 + r[2], r[1] .. " label at pret y")
  eq(c and c.colors, FrlgFont.COLOR.NORMAL, r[1] .. " label gray")
end

local name = calls["RED"]
eq(name and name.small, false, "player name stays in the normal font")
eq(name and name.x, 8 + 60, "player name at window x 60")
eq(name and name.y, 8 + 14, "player name at window y 14")

for _, v in ipairs({ { "0", 28 }, { "7", 42 }, { "0:05", 56 } }) do
  local c = calls[v[1]]
  eq(c and c.small, true, v[1] .. " value in the small font")
  eq(c and c.x, 8 + 60, v[1] .. " value at window x 60")
  eq(c and c.y, 8 + v[2], v[1] .. " value at pret y")
end

T.finish("game3 FRLG save stats window #2889")
