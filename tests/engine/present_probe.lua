package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local LPS = require("src.core.PresentProbe")

LPS.reset()
T.eq(LPS.needsSoftwareCap(), false, "fresh module does not force a software cap")

-- classifyGated: fast presents are ungated, panel-period presents are gated
local fast = {}
for i = 1, 20 do fast[i] = 0.001 end
T.eq(LPS._testClassifyGated(fast), false, "sub-ms presents count as ungated")

local locked60 = {}
for i = 1, 20 do locked60[i] = 1 / 60 end
T.eq(LPS._testClassifyGated(locked60), true, "1/60 presents count as gated")

local locked90 = {}
for i = 1, 20 do locked90[i] = 1 / 90 end
T.eq(LPS._testClassifyGated(locked90), true, "1/90 presents count as gated")

T.eq(LPS._testClassifyGated({ 0.016, 0.017 }), nil,
  "too few samples stay unclassified")

-- Wayland: never bind GLX; ungated forces software cap
LPS._testSetState({
  osLinux = true,
  ready = true,
  nest = "wayland",
  gated = true,
  strategy = "none",
  needsSoftwareCap = false,
  waitFn = false,
})
do
  local strategy, soft, hasWait = LPS._testPickStrategy()
  T.eq(strategy, "sdl", "gated Wayland trusts SDL frame wait")
  T.eq(soft, false, "gated Wayland does not need FrameCap rescue")
  T.eq(hasWait, false, "and never installs a GLX waitFn")
end

LPS._testSetState({
  osLinux = true,
  ready = true,
  nest = "wayland",
  gated = false,
  waitFn = false,
})
do
  local strategy, soft, hasWait = LPS._testPickStrategy()
  T.eq(strategy, "none", "ungated Wayland does not invent a second frame wait")
  T.eq(soft, true, "so FrameCap becomes the thermal net")
  T.eq(hasWait, false, "still no GLX wait on Wayland")
end

-- While probing, pickStrategy must not keep a prior waitFn alive
LPS._testSetState({
  osLinux = true,
  ready = true,
  nest = "x11",
  clearGated = true,
  waitFn = function() error("must not wait while probing") end,
})
do
  local strategy, soft, hasWait = LPS._testPickStrategy()
  T.eq(strategy, "sdl", "while gated is nil, X11 stays on sdl and probes bare")
  T.eq(hasWait, false, "pickStrategy clears waitFn for the unassisted probe")
  T.eq(soft, false, "thermal net waits until the probe finishes")
end

-- XWayland ungated must never bind GLX waits (WaitForMsc can hard-hang)
LPS._testSetState({
  osLinux = true,
  ready = true,
  nest = "xwayland",
  gated = false,
  glxGen = 1,
  bindGen = -1,
  waitFn = false,
})
do
  local strategy, soft, hasWait = LPS._testPickStrategy()
  T.eq(strategy, "none", "ungated XWayland skips GLX waits")
  T.eq(soft, true, "and relies on FrameCap instead")
  T.eq(hasWait, false, "with no waitFn installed")
end

-- Windows ungated: probe only, FrameCap rescue (issue #1958 class)
LPS._testSetState({
  osLinux = false,
  ready = true,
  nest = "windows",
  gated = false,
  waitFn = false,
})
do
  local strategy, soft, hasWait = LPS._testPickStrategy()
  T.eq(strategy, "none", "ungated Windows does not invent a wait")
  T.eq(soft, true, "so FrameCap becomes the thermal net")
  T.eq(hasWait, false, "with no platform wait installed")
end

-- Windows gated: trust SDL swap interval
LPS._testSetState({
  osLinux = false,
  ready = true,
  nest = "windows",
  gated = true,
  waitFn = false,
})
do
  local strategy, soft, hasWait = LPS._testPickStrategy()
  T.eq(strategy, "sdl", "gated Windows trusts SDL")
  T.eq(soft, false, "without forcing FrameCap")
  T.eq(hasWait, false, "and needs no extra wait hook")
end

-- X11 ungated without a successful bind → software cap (bind fails headless)
LPS._testSetState({
  osLinux = true,
  ready = true,
  nest = "x11",
  gated = false,
  glxGen = 1,
  bindGen = -1,
  waitFn = false,
})
do
  local strategy, soft = LPS._testPickStrategy()
  T.eq(strategy, "none", "headless X11 cannot bind OML/SGI")
  T.eq(soft, true, "ungated X11 without a wait forces FrameCap")
end

-- X11 gated → sdl, no software cap
LPS._testSetState({
  osLinux = true,
  ready = true,
  nest = "x11",
  gated = true,
  waitFn = false,
})
do
  local strategy, soft, hasWait = LPS._testPickStrategy()
  T.eq(strategy, "sdl", "gated X11 leaves pacing to the GLX swap interval")
  T.eq(soft, false, "no thermal override when gated")
  T.eq(hasWait, false, "no extra wait when SDL/GLX already gates")
end

-- XWayland mirrors gated X11
LPS._testSetState({
  osLinux = true,
  ready = true,
  nest = "xwayland",
  gamescope = true,
  gated = true,
  waitFn = false,
})
do
  local strategy = LPS._testPickStrategy()
  T.eq(strategy, "sdl", "gated XWayland/Gamescope stays on the SDL present path")
end

-- onDisplayChange clears probe state
LPS._testSetState({
  osLinux = true,
  ready = true,
  nest = "xwayland",
  gated = false,
  strategy = "oml",
  needsSoftwareCap = false,
  glxGen = 3,
  bindGen = 3,
  waitFn = function() end,
})
LPS.onDisplayChange()
local st = LPS.status()
T.eq(st.gated, nil, "display change clears the gated probe")
T.eq(LPS.needsSoftwareCap(), false, "and clears the software-cap flag until re-probe")

LPS.reset()
LPS.waitBeforePresent()
T.eq(true, true, "waitBeforePresent tolerates a cold module")

-- status() on non-Linux stays inert (whatever OS the harness reports)
LPS.reset()
local status = LPS.status()
T.eq(type(status.strategy), "string", "status always reports a strategy string")
T.eq(type(status.linux), "boolean", "and whether this process is Linux")

T.finish("present probe")
