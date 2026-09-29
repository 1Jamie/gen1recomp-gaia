-- engine/gfx/screen_effects.asm:2-12, home/overworld.asm:317 (#2557)

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check, eq = T.check, T.eq

T.fixtures.fresh()

local OW = require("src.world.OverworldController")

local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end

local down = { a = true }
local pressed = {}
local input = {
  wasPressed = function(_, k) return pressed[k] == true end,
  isDown = function(_, k) return down[k] == true end,
}
local stack = { top = function() return nil end }
local game = { input = input, stack = stack, data = {}, save = {} }
setUpvalue(OW.handleInput, "Game", game)
setUpvalue(OW.poisonFlashLive, "Game", game)

local interacts = 0
local ow = setmetatable({
  player = { moving = false, facing = "up" },
  poisonFlash = 4,
  dirHeld = function() return false end,
  interact = function() interacts = interacts + 1 end,
}, { __index = OW })
stack.top = function() return ow end

pressed.a = true
ow:handleInput()
eq(interacts, 0, "A pressed during the poison flash does not interact")
check(ow.joyLatch and ow.joyLatch.a, "and is latched for the poll after the flash")

pressed.a = false
for i = 3, 1, -1 do
  ow:tickPoisonFlash()
  eq(ow.poisonFlash, i, "flash frame counts down")
  ow:handleInput()
  eq(interacts, 0, "held A still waits out flash frame " .. i)
end
check(ow.joyLatch and ow.joyLatch.a, "latch survives the whole flash")

ow:tickPoisonFlash()
eq(ow.poisonFlash, 0, "flash spent")
ow:handleInput()
eq(interacts, 1, "the still-held A talks on the first poll after the flash")
eq(ow.joyLatch, nil, "and the latch is consumed")

down.a = false
ow.poisonFlash = 2
ow.joyLatch = nil
pressed.a = true
ow:handleInput()
pressed.a = false
ow.poisonFlash = 0
ow:handleInput()
eq(interacts, 1, "an A released before the poll is lost, as on the cart")
