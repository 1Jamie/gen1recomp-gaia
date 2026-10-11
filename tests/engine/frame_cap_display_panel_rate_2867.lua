package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
love = love or {}
love.window = love.window or {}
_G.POKEPORT_LOOP_PANEL_SYNC = true
local FrameCap = require("src.core.FrameCap")
local RefreshRate = require("src.core.RefreshRate")
local VSync = require("src.core.VSync")
local PresentSync = require("src.core.PresentSync")
local PresentProbe = require("src.core.PresentProbe")

local before = FrameCap.current
local savedGet, savedSet = love.window.getVSync, love.window.setVSync

local function measure(hz)
  RefreshRate.reset()
  for _ = 1, 31 do RefreshRate.sample(1 / hz) end
end

local function vsync(mode)
  VSync.reset()
  love.window.getVSync = function() return mode == "on" and 1 or 0 end
  love.window.setVSync = function() end
  VSync.apply(mode)
end

local function shellCap()
  local cap = FrameCap.current
  if cap == FrameCap.DISPLAY and not VSync.isOn() then
    cap = FrameCap.DEFAULT
  elseif cap == FrameCap.DISPLAY and PresentSync.needsSoftwareCap() then
    cap = FrameCap.DEFAULT
  end
  return cap
end

PresentProbe.reset()
measure(240)
T.eq(RefreshRate.hz(), 240, "a 240Hz panel reads as 240")

vsync("off")
FrameCap.apply(FrameCap.DISPLAY)
T.eq(shellCap(), 240, "DISPLAY with vsync off paces to the 240Hz panel, not 60")
T.eq(FrameCap.selected(), FrameCap.DISPLAY, "while the selected cap still reads DISPLAY")
T.eq(PresentSync.logicRefreshPeriod(), nil,
  "and logic still does not snap to the panel with vsync off (#1958)")

vsync("on")
T.eq(shellCap(), FrameCap.DISPLAY,
  "turning vsync on drops the soft cap so the probe sees the raw swapchain")
T.check(PresentSync.probingDisplaySync(), "and the DISPLAY probe is live")

PresentProbe._testSetState({ osLinux = false, ready = true, gated = false,
  needsSoftwareCap = true, nest = "windows" })
PresentSync.applyFixedStepPeriod()
T.eq(shellCap(), 240, "an ungated probe software-caps DISPLAY at the panel rate")
T.check(not PresentSync.hardwarePacesCap(shellCap()),
  "and the loop sleeps that budget instead of trusting vsync")

PresentProbe._testSetState({ osLinux = false, ready = true, gated = true,
  needsSoftwareCap = false, nest = "windows" })
PresentSync.applyFixedStepPeriod()
T.eq(shellCap(), FrameCap.DISPLAY, "confirmed sync leaves DISPLAY to the swapchain")
T.eq(PresentSync.logicRefreshPeriod(), 1 / 240, "and logic tracks the 240Hz panel")

PresentProbe._testSetState({ osLinux = false, ready = true, gated = false,
  needsSoftwareCap = true, nest = "windows" })
FrameCap.clampToPerformance(60)
T.eq(FrameCap.current, 60, "the LOW tier still clamps a 240Hz DISPLAY to 60")
FrameCap.apply(144)
PresentSync.applyFixedStepPeriod()
T.eq(FrameCap.current, 144, "a numeric cap is never rewritten by the refresh")

RefreshRate.reset()
vsync("off")
FrameCap.apply(FrameCap.DISPLAY)
T.eq(shellCap(), FrameCap.DEFAULT, "an unknown panel rate falls back to the default cap")
measure(240)
PresentSync.applyFixedStepPeriod()
T.eq(shellCap(), 240, "and picks up the panel rate once it is known")

_G.POKEPORT_LOOP_PANEL_SYNC = nil
FrameCap.applyOptions({ fpsCap = FrameCap.DISPLAY })
T.eq(FrameCap.current, FrameCap.DEFAULT,
  "a stored DISPLAY applied before the loop marker paces safely")
_G.POKEPORT_LOOP_PANEL_SYNC = true
FrameCap.bootPanelSync()
T.eq(FrameCap.selected(), FrameCap.DISPLAY,
  "and the loop restores DISPLAY once it announces panel sync")
T.eq(shellCap(), 240, "pacing at the panel rate")

FrameCap.apply(60)
_G.POKEPORT_LOOP_PANEL_SYNC = nil
FrameCap.apply(60)
_G.POKEPORT_LOOP_PANEL_SYNC = true
FrameCap.bootPanelSync()
T.eq(FrameCap.current, 60, "an explicit 60 is never promoted to DISPLAY")

love.window.getVSync, love.window.setVSync = savedGet, savedSet
VSync.reset()
PresentProbe.reset()
RefreshRate.reset()
FrameCap.apply(before)

T.finish("frame cap display panel rate #2867")
