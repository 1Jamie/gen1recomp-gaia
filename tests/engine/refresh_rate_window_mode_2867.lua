package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
love = love or {}
love.window = love.window or {}
love.timer = love.timer or {}
_G.POKEPORT_LOOP_PANEL_SYNC = true
local FrameCap = require("src.core.FrameCap")
local RefreshRate = require("src.core.RefreshRate")
local VSync = require("src.core.VSync")
local PresentSync = require("src.core.PresentSync")
local PresentProbe = require("src.core.PresentProbe")

local before = FrameCap.current
local savedGetMode = love.window.getMode
local savedGet, savedSet = love.window.getVSync, love.window.setVSync
local savedTime = love.timer.getTime

local clock = 0
love.timer.getTime = function() return clock end
local function tick() clock = clock + 2 end

local panel = nil
love.window.getMode = function()
  return 1024, 768, { refreshrate = panel or 0, display = 1, vsync = 1 }
end

local function vsync(mode)
  VSync.reset()
  love.window.getVSync = function() return mode == "on" and 1 or 0 end
  love.window.setVSync = function() end
  VSync.apply(mode)
end

local function loopCadence(hz)
  for _ = 1, 31 do RefreshRate.sample(1 / hz) end
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
RefreshRate.reset()
panel = 240
tick()
T.eq(RefreshRate.hz(), 240, "the window's display mode reports the panel rate")
T.eq(RefreshRate.queried(), 240, "and the query alone reports it")

loopCadence(60)
tick()
T.eq(RefreshRate.hz(), 240, "a 60fps software-paced loop never masquerades as the panel")

vsync("off")
FrameCap.apply(FrameCap.DISPLAY)
T.eq(shellCap(), 240, "DISPLAY with vsync off on Windows paces to the 240Hz panel")

RefreshRate.reset()
panel = nil
tick()
loopCadence(600)
T.eq(RefreshRate.queried(), nil, "no display mode means no queried rate")
local fast = {}
for i = 1, 20 do fast[i] = 1 / 600 end
T.eq(PresentProbe._testClassifyGated(fast), false,
  "600fps presents are ungated even when the loop measured 600 itself")

RefreshRate.reset()
panel = 120
tick()
local locked = {}
for i = 1, 20 do locked[i] = 1 / 120 end
T.eq(PresentProbe._testClassifyGated(locked), true, "1/120 presents on a 120Hz panel are gated")
T.eq(PresentProbe._testClassifyGated(fast), false, "600fps presents on a 120Hz panel are ungated")

vsync("off")
PresentProbe._testSetState({ osLinux = false, ready = true, gated = true,
  needsSoftwareCap = false, nest = "windows" })
FrameCap.apply(60)
T.check(not PresentSync.displaySyncConfirmed(), "vsync off is never confirmed display sync")
T.check(not PresentSync.hardwarePacesCap(60), "so a 60 cap keeps the software pacer with vsync off")
vsync("on")
PresentProbe._testSetState({ osLinux = false, ready = true, gated = true,
  needsSoftwareCap = false, nest = "windows" })
FrameCap.apply(120)
T.check(PresentSync.hardwarePacesCap(120), "a 120 cap on a gated 120Hz panel with vsync on skips the pacer")

love.window.getMode = savedGetMode
love.window.getVSync, love.window.setVSync = savedGet, savedSet
love.timer.getTime = savedTime
VSync.reset()
PresentProbe.reset()
RefreshRate.reset()
FrameCap.apply(before)

T.finish("refresh rate window mode #2867")
