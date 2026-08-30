package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local FrameCap = require("src.core.FrameCap")
local RefreshRate = require("src.core.RefreshRate")
local VSync = require("src.core.VSync")
local PresentSync = require("src.core.PresentSync")
local FixedStep = require("src.core.FixedStep")
local PresentProbe = require("src.core.PresentProbe")

RefreshRate.reset()
VSync.reset()
PresentSync.reset()
PresentProbe.reset()

local function measure(hz)
  RefreshRate.reset()
  for _ = 1, 31 do RefreshRate.sample(1 / hz) end
end

measure(144)
T.eq(RefreshRate.mismatch(), 144, "144Hz is not a multiple of 60")

FrameCap.apply(FrameCap.DISPLAY)
VSync.reset()
love.window.getVSync = function() return 0 end
love.window.setVSync = function() end
VSync.apply("off")
T.eq(PresentSync.logicRefreshPeriod(), nil,
  "DISPLAY with vsync off does not snap logic to the panel (#1958)")

VSync.reset()
love.window.getVSync = function() return 1 end
VSync.apply("on")
PresentProbe._testSetState({ osLinux = false, ready = true, gated = false,
  needsSoftwareCap = true, nest = "windows" })
T.eq(PresentSync.logicRefreshPeriod(), nil,
  "DISPLAY with broken sync falls back to software cap, not panel snap")

PresentProbe._testSetState({ osLinux = false, ready = true, gated = true,
  needsSoftwareCap = false, nest = "windows" })
T.eq(PresentSync.logicRefreshPeriod(), 1 / 144,
  "DISPLAY with working sync tracks the panel")

FrameCap.apply(60)
T.eq(PresentSync.logicRefreshPeriod(), nil,
  "a 60 cap on a 144Hz panel leaves refresh snapping off")

FrameCap.apply(144)
T.eq(PresentSync.logicRefreshPeriod(), 1 / 144,
  "a 144 cap on a 144Hz panel may snap logic to the panel")

PresentSync.applyFixedStepPeriod()
T.eq(FixedStep.refreshPeriod, 1 / 144, "applyFixedStepPeriod writes the module field")

FrameCap.apply(FrameCap.DISPLAY)
VSync.apply("on")
PresentProbe._testSetState({ osLinux = false, ready = true, clearGated = true,
  needsSoftwareCap = false, nest = "windows" })
T.check(PresentSync.probingDisplaySync(), "DISPLAY+vsync probes before a verdict")
T.check(PresentSync.needsSoftwareCap(), "warmup uses FrameCap until the probe finishes")
T.eq(PresentSync.logicRefreshPeriod(), nil, "and does not snap logic during warmup")

PresentProbe._testSetState({ gated = true, needsSoftwareCap = false })
T.check(not PresentSync.probingDisplaySync(), "a finished probe clears warmup")
T.check(not PresentSync.needsSoftwareCap(), "so software cap stops once sync is confirmed")

VSync.apply("on")
PresentProbe._testSetState({ needsSoftwareCap = true })
T.check(PresentSync.vsyncEnableBlocked(), "broken sync blocks enabling vsync")
T.check(PresentSync.vsyncStepAllowed("on", 1), "but one step to OFF is allowed")
T.check(not PresentSync.vsyncStepAllowed("on", -1),
  "while a step that stays on/adaptive is not")

love.window.getVSync, love.window.setVSync = nil, nil
VSync.reset()
PresentSync.reset()
PresentProbe.reset()
RefreshRate.reset()
FrameCap.apply(FrameCap.DEFAULT)

T.finish("present sync logic")
