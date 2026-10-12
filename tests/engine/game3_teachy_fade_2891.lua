-- pokefirered/src/teachy_tv.c:499

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.game3.audio"] = { restoreMapSong = function() end }

local shown = 0
local reshown = 0
local bagOpen = false
local TeachyTvCore = require("src.core.game3.teachy_tv")
TeachyTvCore.show = function() shown = shown + 1 return true end
package.loaded["src.ui.game3.bag_menu"] = {
  isOpen = function() return bagOpen end,
  reshowFromTeachyTv = function() reshown = reshown + 1 end,
}

local Ui = require("src.ui.game3.teachy_tv")
local Fade = require("src.ui.game3.fade")
local ItemUse = require("src.core.game3.item_use")
local ItemsData = require("src.core.game3.items_data")
ItemsData.info = function() return { fieldUseName = "FieldUseFunc_TeachyTv" } end
ItemUse.fieldUseKind = function() return "teachy_tv" end

local rects = {}
love.graphics.rectangle = function(_, x, y, w, h)
  local r, _, _, a = love.graphics.getColor()
  rects[#rects + 1] = { x = x, y = y, w = w, h = h, r = r, a = a }
end

local function overlay()
  rects = {}
  Ui.draw()
  local last = rects[#rects]
  if last and last.x == 0 and last.y == 0 and last.w == 240 and last.h == 160 and last.r == 0 then
    return last.a
  end
  return 0
end

local function frames(n)
  for _ = 1, n do Fade.tick(1 / 60) end
end

Ui.open = true
Ui.state = "lesson"
Ui._pages = {}
Ui.page = 1

Fade.begin(Fade.MODE.FROM_BLACK, 1)
eq(overlay(), 1, "TV opens fully black under BeginNormalPaletteFade(0x10 -> 0)")
frames(8)
eq(overlay(), 0.5, "TV is half faded in after 8 frames")
frames(8)
eq(overlay(), 0, "TV fade-in clears after 16 frames")

Ui.closing = false
Ui.close()
frames(8)
eq(overlay(), 0.5, "quit fade covers the TV halfway after 8 frames")
check(Ui.isOpen(), "TV stays up until the quit fade ends")

Ui._bagUnder = true
bagOpen = true
frames(8)
check(not Ui.isOpen(), "TV closes once the quit fade ends")
eq(reshown, 1, "closing over the bag hands the fade-in to the bag")
check(not Fade.isActive(), "no hidden global fade is left running over the bag")

Fade.clear()
local session = { bag = {}, party = {} }
bagOpen = false
shown = 0
ItemUse.useField(session, session.bag, 366, nil)
eq(shown, 0, "registered Teachy TV on the field fades out before the TV opens")
check(Fade.isActive() and Fade.mode == Fade.MODE.TO_BLACK, "field use starts FadeScreen(FADE_TO_BLACK)")
frames(16)
eq(shown, 1, "TV opens once the field fade-out ends")

Fade.clear()
bagOpen = true
shown = 0
ItemUse.useField(session, session.bag, 366, nil)
eq(shown, 1, "from the bag the TV opens after the bag's own exit fade")

T.finish()
