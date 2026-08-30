package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local LPS = require("src.core.PresentProbe")

LPS.reset()
T.eq(LPS.needsSoftwareCap(), false, "fresh module does not force a software cap")

-- classifyGated: fast presents are ungated, panel-period presents are gated
local fast = {}
for i = 1, 20 do fast[i] = 0.001 end
T.eq(LPS._testClassifyGated(fast), false, "sub-ms presents count as ungated")

local function withHz(hz, fn)
  package.loaded["src.core.RefreshRate"] = {
    hz = function() return hz end,
    period = function() return 1 / hz end,
    mismatch = function() return nil end,
    sample = function() return false end,
    reset = function() end,
  }
  local ok, err = pcall(fn)
  package.loaded["src.core.RefreshRate"] = nil
  if not ok then error(err) end
end

withHz(60, function()
  local locked60 = {}
  for i = 1, 20 do locked60[i] = 1 / 60 end
  T.eq(LPS._testClassifyGated(locked60), true, "1/60 presents count as gated")
  local half60 = {}
  for i = 1, 20 do half60[i] = 2 / 60 end
  T.eq(LPS._testClassifyGated(half60), true, "half-rate 30Hz on 60Hz counts as gated")
  local ambiguous = {}
  for i = 1, 20 do ambiguous[i] = 0.010 end
  T.eq(LPS._testClassifyGated(ambiguous), false,
    "10ms CPU-bound presents are ungated (not evidence of sync)")
end)

withHz(90, function()
  local locked90 = {}
  for i = 1, 20 do locked90[i] = 1 / 90 end
  T.eq(LPS._testClassifyGated(locked90), true, "1/90 presents count as gated")
end)

-- Unknown panel Hz: a 90Hz-looking block is NOT trusted (safe FrameCap fallback)
local locked90unknown = {}
for i = 1, 20 do locked90unknown[i] = 1 / 90 end
T.eq(LPS._testClassifyGated(locked90unknown), false,
  "without a panel Hz, 1/90 is inconclusive and prefers FrameCap")

withHz(60, function()
  local jittery = {}
  -- Median near 1/60 but IQR > 20% of mid → non-deterministic, fail closed.
  for i = 1, 10 do jittery[i] = 0.008 end
  for i = 11, 20 do jittery[i] = 0.024 end
  T.eq(LPS._testClassifyGated(jittery), false,
    "high present-time variance fails closed to ungated")
end)

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

-- Probe measures present() block time, not inter-frame gaps: FrameCap sleep
-- after notePresent must not make a broken swap look gated.
LPS.reset()
LPS._testSetState({ osLinux = false, ready = true, nest = "windows", clearGated = true })
local t = 0
love.timer = love.timer or {}
local savedGetTime = love.timer.getTime
love.timer.getTime = function() return t end
withHz(60, function()
  for i = 1, 45 do
    -- Instant present() (broken vsync), then a fake 16ms FrameCap sleep afterward.
    LPS.waitBeforePresent()
    t = t + 0.001
    LPS.notePresent()
    t = t + 1 / 60
  end
  local st = LPS.status()
  T.eq(st.gated, false,
    "instant present() stays ungated even when FrameCap sleeps 16ms after")
  T.eq(LPS.needsSoftwareCap(), true, "so FrameCap remains the thermal net")

  LPS.reset()
  LPS._testSetState({ osLinux = false, ready = true, nest = "windows", clearGated = true })
  t = 0
  for i = 1, 45 do
    LPS.waitBeforePresent()
    t = t + 1 / 60  -- present() itself blocks a full panel period
    LPS.notePresent()
    t = t + 1 / 60  -- trailing FrameCap sleep is ignored by the probe
  end
  st = LPS.status()
  T.eq(st.gated, true, "a present() that blocks a panel period counts as gated")
  T.eq(LPS.needsSoftwareCap(), false, "and does not force FrameCap")
end)

-- A bound wait that overruns abandons to FrameCap instead of wedging.
LPS.reset()
LPS._testSetState({
  osLinux = true, ready = true, nest = "x11", gated = true,
  strategy = "oml", needsSoftwareCap = false,
  waitFn = function()
    t = t + 0.2  -- > WAIT_ABORT_S
  end,
})
t = 0
LPS.waitBeforePresent()
T.eq(LPS.needsSoftwareCap(), true, "an overrunning GLX wait falls back to FrameCap")
T.eq(LPS.status().strategy, "none", "and clears the wait strategy")

love.timer.getTime = savedGetTime

-- status() on non-Linux stays inert (whatever OS the harness reports)
LPS.reset()
local status = LPS.status()
T.eq(type(status.strategy), "string", "status always reports a strategy string")
T.eq(type(status.linux), "boolean", "and whether this process is Linux")

LPS.reset()
T.finish("present probe")
