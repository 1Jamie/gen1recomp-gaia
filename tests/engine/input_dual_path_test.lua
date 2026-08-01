-- When isGamepad(), raw face presses must not stack on gamepad* (NamingScreen a+b).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local GamepadMap = require("src.core.GamepadMap")
local Input = require("src.core.Input")

local gamepadJoy = {
  isGamepad = function() return true end,
}
local rawJoy = {
  isGamepad = function() return false end,
}

check(GamepadMap.ignoreRawForJoystick(gamepadJoy), "ignore raw when isGamepad")
check(not GamepadMap.ignoreRawForJoystick(rawJoy), "allow raw when not gamepad")
check(not GamepadMap.ignoreRawForJoystick(nil), "nil joystick does not ignore raw")

GamepadMap._setForceNXForTests(true)
eq(GamepadMap.mapRawButton(3), "a", "NX raw Y (#3) -> GB A")
eq(GamepadMap.mapRawButton(4), "b", "NX raw X (#4) -> GB B")
GamepadMap._setForceNXForTests(false)

Input:init()
Input:gamepadpressed(gamepadJoy, "a")
Input:joystickpressed(gamepadJoy, 1) -- must no-op
Input:joystickpressed(gamepadJoy, 2) -- must no-op (would have set b)
Input:step()
check(Input:wasPressed("a"), "gamepad A edge present")
check(not Input:wasPressed("b"), "raw must not add B alongside gamepad A")
check(Input:isDown("a"), "A held from pad source only")

Input:init()
Input:joystickpressed(rawJoy, 1)
Input:step()
check(Input:wasPressed("a"), "non-gamepad raw #1 still maps to A")

T.finish()
