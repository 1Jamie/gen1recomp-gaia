package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

local Typer = require("src.ui.gen2.Typer")

-- pokegold home/joypad.asm:430
local screen = { game = { save = { options = {} } } }
eq(Typer.arrowOn(screen), true, "phase 0 shows the cursor")
for _ = 1, 15 do Typer.step(screen) end
eq(Typer.arrowOn(screen), true, "still on through frame 15")
Typer.step(screen)
eq(Typer.arrowOn(screen), false, "off from frame 16")
for _ = 1, 15 do Typer.step(screen) end
eq(Typer.arrowOn(screen), false, "off through frame 31")
Typer.step(screen)
eq(Typer.arrowOn(screen), true, "back on at frame 32")
eq(screen.arrowBlink, 0, "the counter wraps at 32")

Typer.say(screen, { "HELLO", "WORLD" })
Typer.step(screen)
eq(screen.arrowBlink, 1, "step keeps counting while a typer runs")

T.finish()
