package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local check, eq = T.check, T.eq

local Ui = require("src.core.game3.battle.ui")
local Message = require("src.ui.game3.message")

local function settle()
  for _ = 1, 4 do
    Ui.pump()
    Message.skipReveal()
  end
end

Ui.reset({ headless = false })
Message.reset()
Ui.bindState({ player = { mon = {} } })
local seDone, closed = false, false
Ui.pushGated("Gotcha!\nPIDGEY was caught!", function() return not seDone end, nil, function() closed = true end)
settle()
check(Message.isOpen(), "gotcha text prints right away (battle_anim_special.c:1195)")
check(Ui.dialogPending(), "battle waits on the gotcha text")
Message.advance()
check(Message.isOpen() and not closed, "A does nothing while MUS_CAUGHT_INTRO plays ({WAIT_SE})")
for _ = 1, 30 do Ui.pump() end
check(Message.isOpen() and not closed, "text holds without input during the intro")
seDone = true
Ui.pump()
Message.advance()
check(closed and not Message.isOpen(), "after the SE ends A closes the text (\\p)")

Ui.reset({ headless = false })
Message.reset()
Ui.bindState({ oldManTutorial = true, player = { mon = {} } })
seDone, closed = false, false
Ui.pushGated("Gotcha!\nWEEDLE was caught!", function() return not seDone end, 127, function() closed = true end)
settle()
for _ = 1, 50 do Ui.pump() end
check(not closed, "GOTCHAPKMNCAUGHT2 waits for the SE")
seDone = true
local n = 0
while not closed and n < 400 do
  Ui.pump()
  n = n + 1
end
eq(n, 127, "then pauses 127 frames and continues on its own ({PAUSE 127})")

Ui.reset({ headless = false })
Message.reset()
Ui.bindState({ player = { mon = {} } })
local done = false
Ui.pushTimed("RED used\nPOKé BALL!", 0, function() done = true end)
settle()
check(done and not Ui.dialogPending(), "used-ball text does not wait for A (battle_scripts_2.s:57)")
check(Message.isOpen(), "and stays on screen during the throw")

T.finish()
