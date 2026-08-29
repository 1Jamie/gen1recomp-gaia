-- The built-in GAME SPEED hotkeys on controller: the shoulder buttons
-- (L1/R1) and the analog triggers (L2/R2) all cycle the engine speed
-- ladder, R-side faster and L-side slower, exactly like keyboard hotkey
-- No pokered cite: port-only (gap C2).
--   luajit tests/engine/speed_shoulders_triggers_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Game = require("src.core.Game")
local Input = require("src.core.Input")
Input:init()

local dirs = {}
local game = {
  save = { options = { speed = 1 } },
  _cycleSpeed = function(self, dir)
    dirs[#dirs + 1] = dir
    self.save.options.speed = self.save.options.speed + dir
  end,
  stack = { top = function() return nil end },
}
function game:writeOptions() end

local function last()
  return dirs[#dirs]
end

-- ---- shoulders ----------------------------------------------------------
dirs = {}
Game.gamepadpressed(game, nil, "rightshoulder")
eq(last(), 1, "R1 speeds up")
Game.gamepadpressed(game, nil, "leftshoulder")
eq(last(), -1, "L1 slows down")

-- ---- analog triggers ----------------------------------------------------
dirs = {}
Game.gamepadpressed(game, nil, "righttrigger")
eq(last(), 1, "R2 speeds up")
Game.gamepadpressed(game, nil, "lefttrigger")
eq(last(), -1, "L2 slows down")

local routed = nil
game.stack.top = function()
  return { onGamepadPressed = function(_, b) routed = b end }
end
Game.gamepadpressed(game, nil, "a")
eq(routed, "a", "a normal button still reaches the top-state pad routing")
routed = nil
Game.gamepadpressed(game, nil, "rightshoulder")
eq(routed, "rightshoulder",
   "a screen owning pad input sees L1/R1 too, so CONTROLS can capture them")
Game.gamepadpressed(game, nil, "lefttrigger")
eq(routed, "lefttrigger", "and the trigger names alongside them")
check(#dirs == 2, "a captured shoulder never touches the speed ladder")

game.stack.top = function() return nil end
local forwarded = nil
local origPad = Input.gamepadpressed
function Input:gamepadpressed(joystick, button) forwarded = button end
Game.gamepadpressed(game, nil, "rightshoulder")
check(forwarded == nil, "the speed buttons never reach the GB button map")
eq(#dirs, 3, "and they still cycle the ladder")
Game.gamepadpressed(game, nil, "a")
eq(forwarded, "a", "everything else does reach it")
Input.gamepadpressed = origPad

T.finish("speed_shoulders_triggers")
