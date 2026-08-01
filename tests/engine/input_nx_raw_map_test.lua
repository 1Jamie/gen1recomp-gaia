-- NX raw fallback indices measured on OLED hardware (SWNX-11).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local eq = T.eq

local GamepadMap = require("src.core.GamepadMap")

GamepadMap._setForceNXForTests(true)

-- Phase 0 probe: Y→#3, X→#4; Nintendo B/A at #1/#2.
eq(GamepadMap.mapRawButton(3), "b", "NX raw Y (#3) maps to GB B")
eq(GamepadMap.mapRawButton(4), "a", "NX raw X (#4) maps to GB A")
eq(GamepadMap.mapRawToGamepadButton(3), "y", "NX raw #3 routes to gamepad y")
eq(GamepadMap.mapRawToGamepadButton(4), "x", "NX raw #4 routes to gamepad x")
eq(GamepadMap.mapRawButton(9), "select", "NX minus (#9) -> select")
eq(GamepadMap.mapRawButton(10), "start", "NX plus (#10) -> start")

GamepadMap._setForceNXForTests(false)

T.finish()
