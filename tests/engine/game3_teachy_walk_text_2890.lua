-- pokefirered/src/teachy_tv.c:782

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.game3.audio"] = { restoreMapSong = function() end, playSong = function() end }

local TeachyTv = require("src.core.game3.teachy_tv")
local Ui = require("src.ui.game3.teachy_tv")
local Timing = TeachyTv.TIMING

local session = { modData = {}, options = { textSpeed = 1 } }
Ui.open = true
Ui.suspended = false
Ui.closing = false
Ui._session = session
Ui.state = "lesson"
Ui.step = 3
eq(Ui.stepName(), "npc_move_and_setup_text_printer", "step 3 is the dude walking in")
Ui.frames = Timing.NPC_WAIT
Ui.hostX = Timing.DUDE_X_START
Ui.hostY = Timing.DUDE_Y
Ui.hostFacing = "right"
Ui.hostWalk = true
Ui.hostVisible = true
Ui.hostAnim = 0

local seq = {}
for _ = 1, 32 do
  Ui.tick()
  local walk, stepA = Ui.hostPose()
  seq[#seq + 1] = walk == 1 and (stepA and "A" or "B") or "S"
end
local cycle = table.concat(seq)
eq(cycle:sub(1, 8), "AAAAAAAS", "ANIM_STD_GO_EAST starts on the first step frame for 8 frames")
check(cycle:find("SSSSSSSS", 1, true) ~= nil, "a full 8-frame stand frame follows the step")
check(cycle:find("BBBBBBBB", 1, true) ~= nil, "then the other foot for 8 frames")
local stands = select(2, cycle:gsub("S", ""))
eq(stands, 16, "half of the 32-frame walk cycle is the standing frame")
eq(Ui.hostX, Timing.DUDE_X_START + 32, "he moves one pixel per frame meanwhile")

Ui.step = 4
eq(Ui.stepName(), "idle_if_text_printer_active", "step 4 waits on the text printer")
Ui._pages = { "Hey, all you" }
Ui.page = 0
Ui.nextPage()
check(Ui.typing(), "a new page starts typing")
check(not Ui.waitingForKey(), "no prompt while the text types")
check(Ui.printerActive(), "RunTextPrinters_CheckActive is true while typing")
Ui.tick()
eq(Ui._revealed, 1, "the first character prints on the first frame")
for _ = 1, 3 do Ui.tick() end
eq(Ui._revealed, 1, "mid text speed waits 3 more frames per character")
Ui.tick()
eq(Ui._revealed, 2, "then the next character prints")
for _ = 1, 100 do
  if not Ui.typing() then break end
  Ui.tick()
end
check(not Ui.typing(), "the page finishes typing")
check(not Ui.printerActive(), "and the printer goes idle on the last page")

session.options.textSpeed = 2
Ui.step = 4
Ui._pages = { "Hey, all you" }
Ui.page = 0
Ui.nextPage()
Ui.tick()
Ui.tick()
eq(Ui._revealed, 2, "fast text speed prints a character every frame")

T.finish()
