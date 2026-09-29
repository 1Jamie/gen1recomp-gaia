package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = love or require("tests.love_stub")

local UiPass = require("src.ui.game3.ui_pass")
local base = 0
UiPass.drawUi = function() base = base + 1 end
UiPass._frontierRecords = nil

local Display = require("src.core.game3.display")
Display.drawUiPass()
eq(base, 1, "the UI pass draws before any late hook exists")

local Records = require("src.ui.game3.rse.frontier_records")
local drawn = 0
local origDraw = Records.drawWindow
Records.drawWindow = function() drawn = drawn + 1 end

-- pokeemerald/data/scripts/cable_club.inc:623
Records.showWindow({ left = 1, top = 1, width = 28, height = 18, prints = {} })
check(Records.isOpen(), "ShowLinkBattleRecords opens the records window")
Display.drawUiPass()
eq(base, 2, "the hooked pass still draws the base UI")
eq(drawn, 1, "a records window hooked after the first frame is drawn by the display")

Records.remove()
Display.drawUiPass()
eq(drawn, 1, "RemoveRecordsWindow stops the draw")

Records.drawWindow = origDraw
T.finish("game3_ui_pass_late_hook_test")
