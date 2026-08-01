-- NX raw fallback indices measured on OLED hardware (SWNX-11).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local eq = T.eq

local GamepadMap = require("src.core.GamepadMap")

GamepadMap._setForceNXForTests(true)

-- Phase 0 / naming diagnosis: Y→#3→a, X→#4→b; Nintendo B/A at #1/#2.
eq(GamepadMap.mapRawButton(3), "a", "NX raw Y (#3) maps to GB A")
eq(GamepadMap.mapRawButton(4), "b", "NX raw X (#4) maps to GB B")
eq(GamepadMap.mapRawToGamepadButton(3), "a", "NX raw #3 routes to gamepad a")
eq(GamepadMap.mapRawToGamepadButton(4), "b", "NX raw #4 routes to gamepad b")
eq(GamepadMap.mapRawButton(9), "select", "NX minus (#9) -> select")
eq(GamepadMap.mapRawButton(10), "start", "NX plus (#10) -> start")

GamepadMap._setForceNXForTests(false)

T.finish()
