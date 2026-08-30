-- Present sync: on every platform, measure whether love.window.setVSync
-- actually gates presents by timing present() itself (not the gap between
-- frames — that gap includes FrameCap sleeps and would false-trigger "gated"
-- during DISPLAY warmup).  Linux additionally binds a real wait (GLX OML /
-- SGI on native X11) when SDL's swap interval is a no-op (Gamescope /
-- XWayland).  Wayland: never duplicate wl_surface.frame.  drmWaitVBlank is
-- never used.  Ambiguous probe results prefer FrameCap over trusting sync.

local PresentProbe = {}

-- Probe present() block time (not inter-frame gaps).  Inter-frame gaps include
-- FrameCap sleeps and would always look "gated" during DISPLAY warmup.
local PROBE_FRAMES = 45
local INSTANT_MS = 0.0005
local BLOCK_MS = 0.002
-- If a bound GLX wait ever blocks longer than this, drop it and fall back to
-- FrameCap.  Covers a stalled compositor without wedging the game loop.
local WAIT_ABORT_S = 0.1

-- Hot-path: a single cached closure, no ffi.C / string work inside it.
local waitFn = nil

local state = {
  osLinux = false,
  ready = false,
  driver = nil,       -- "wayland" | "x11" | "kmsdrm" | ...
  nest = nil,         -- "wayland" | "x11" | "xwayland" | "kmsdrm" | "unknown"
  gamescope = false,
  gated = nil,        -- nil while probing, then true/false
  strategy = "none",  -- "none" | "sdl" | "oml" | "sgi"
  needsSoftwareCap = false,
  probeCount = 0,
  presentStart = nil, -- love.timer time entering present(), probe only
  intervals = nil,    -- present() block times while probing
  glxGen = 0,
  bindGen = -1,
}

local ffi = nil
local sdlLib = nil
local x11Lib = nil
local glLib = nil

local function isLinux()
  if not love or not love.system or not love.system.getOS then return false end
  return love.system.getOS() == "Linux"
end

local function envTruthy(name)
  local v = os.getenv(name)
  return v ~= nil and v ~= ""
end

local function loadSdl()
  if sdlLib ~= nil then return sdlLib or nil end
  if not ffi then
    local ok, f = pcall(require, "ffi")
    if not ok then sdlLib = false return nil end
    ffi = f
  end
  pcall(ffi.cdef, [[
    const char *SDL_GetCurrentVideoDriver(void);
    typedef struct SDL_Window SDL_Window;
    SDL_Window *SDL_GL_GetCurrentWindow(void);
  ]])
  local okLoad, lib = pcall(ffi.load, "SDL2")
  lib = okLoad and lib or ffi.C
  local okSym = pcall(function() return lib.SDL_GetCurrentVideoDriver end)
  sdlLib = okSym and lib or false
  return sdlLib or nil
end

local function videoDriver()
  local lib = loadSdl()
  if not lib then return nil end
  local ok, name = pcall(function()
    local p = lib.SDL_GetCurrentVideoDriver()
    if p == nil then return nil end
    return ffi.string(p)
  end)
  if not ok or not name or name == "" then return nil end
  return name
end

-- Prefer XQueryExtension("XWAYLAND") when we have a Display*; fall back to
-- session env heuristics when GLX is not up yet.
local function detectXWayland(dpy)
  if dpy ~= nil and x11Lib then
    local major = ffi.new("int[1]")
    local event = ffi.new("int[1]")
    local errCode = ffi.new("int[1]")
    local ok, present = pcall(x11Lib.XQueryExtension, dpy, "XWAYLAND",
      major, event, errCode)
    if ok and present ~= 0 then return true end
    if ok and present == 0 then return false end
  end
  -- SDL x11 driver under a Wayland session is almost always XWayland.
  return envTruthy("WAYLAND_DISPLAY") or envTruthy("WAYLAND_SOCKET")
    or envTruthy("GAMESCOPE_WAYLAND_DISPLAY")
end

local function detectNest(driver)
  if not driver then return "unknown" end
  if driver == "wayland" then return "wayland" end
  if driver == "kmsdrm" or driver == "rpi" then return "kmsdrm" end
  if driver == "x11" then
    return detectXWayland(nil) and "xwayland" or "x11"
  end
  return "unknown"
end

-- Classify from present() block times.  Prefer false (ungated → FrameCap)
-- whenever the signal is ambiguous: trusting a broken swap interval uncapped
-- is far worse than pacing in software.
local function classifyGated(intervals)
  if not intervals or #intervals < 10 then return nil end
  local sorted = {}
  for i = 1, #intervals do sorted[i] = intervals[i] end
  table.sort(sorted)
  local mid = sorted[math.floor(#sorted / 2) + 1]
  if not mid or mid <= 0 then return false end
  local hz = nil
  local okRR, RR = pcall(require, "src.core.RefreshRate")
  if okRR then hz = RR.hz() end
  local expect = hz and (1 / hz) or (1 / 60)
  -- Ungated: present returns well before a panel period (often < 2ms).
  if mid < expect * 0.45 then return false end
  -- Full-rate vsync: block time sits near the panel period.
  if mid >= expect * 0.7 and mid <= expect * 1.55 then return true end
  -- Half-rate vsync (e.g. 30Hz on a 60Hz panel).
  if mid >= expect * 1.7 and mid <= expect * 2.4 then return true end
  -- CPU-bound mid-range (e.g. 8–12ms on 60Hz) is not evidence of sync.
  return false
end

local function loadGlx()
  if glLib ~= nil then return glLib or nil end
  if not ffi then return nil end
  pcall(ffi.cdef, [[
    typedef unsigned long LPS_GLXDrawable;
    typedef struct LPS_XDisplay LPS_Display;
    typedef int LPS_Bool;
    void *glXGetProcAddress(const unsigned char *name);
    void *glXGetProcAddressARB(const unsigned char *name);
    LPS_Display *glXGetCurrentDisplay(void);
    LPS_GLXDrawable glXGetCurrentDrawable(void);
    LPS_Bool XQueryExtension(LPS_Display *display, const char *name,
      int *major_opcode, int *first_event, int *first_error);
  ]])
  local function tryLoad(name)
    local ok, lib = pcall(ffi.load, name)
    return ok and lib or nil
  end
  glLib = tryLoad("GL") or tryLoad("libGL.so.1") or tryLoad("libGLX.so.0") or false
  if x11Lib == nil then
    x11Lib = tryLoad("X11") or tryLoad("libX11.so.6") or false
  end
  return glLib or nil
end

local function procAddress(gl, name)
  local cname = ffi.cast("const unsigned char *", name)
  local p = nil
  if gl.glXGetProcAddress then
    p = gl.glXGetProcAddress(cname)
  end
  if (p == nil or p == ffi.NULL) and gl.glXGetProcAddressARB then
    p = gl.glXGetProcAddressARB(cname)
  end
  if p == nil or p == ffi.NULL then return nil end
  return p
end

local function verifyBlocks(fn)
  if not love or not love.timer or not love.timer.getTime then return false end
  local t0 = love.timer.getTime()
  local ok = pcall(fn)
  local dt = love.timer.getTime() - t0
  if not ok then return false end
  if dt < INSTANT_MS then return false end
  return dt >= BLOCK_MS or dt >= INSTANT_MS * 2
end

-- WaitForMsc / WaitVideoSync hang forever when the counter never advances
-- (vblank_mode=0, frozen CRTC).  Probe the counter with a short sleep first.
local function omlClockAlive(getSync, getDisplay, getDrawable)
  if not love or not love.timer or not love.timer.sleep then return false end
  local ust = ffi.new("long long[1]")
  local msc = ffi.new("long long[1]")
  local sbc = ffi.new("long long[1]")
  local d = getDisplay()
  if d == nil then return false end
  local drawable = getDrawable()
  if drawable == 0 then return false end
  if getSync(d, drawable, ust, msc, sbc) == 0 then return false end
  local first = msc[0]
  love.timer.sleep(0.05)
  if getSync(d, drawable, ust, msc, sbc) == 0 then return false end
  return msc[0] ~= first
end

local function sgiClockAlive(getVS)
  if not love or not love.timer or not love.timer.sleep then return false end
  local count = ffi.new("unsigned int[1]")
  count[0] = 0
  if getVS(count) ~= 0 then return false end
  local first = count[0]
  love.timer.sleep(0.05)
  if getVS(count) ~= 0 then return false end
  return count[0] ~= first
end

local function bindGlxWait(nest)
  local gl = loadGlx()
  if not gl then return nil, nil end

  local getDisplay = gl.glXGetCurrentDisplay
  local getDrawable = gl.glXGetCurrentDrawable
  if not getDisplay or not getDrawable then return nil, nil end

  local dpy = getDisplay()
  if dpy == nil then return nil, nil end
  -- Refine nest now that we have a Display*.
  if nest == "x11" or nest == "xwayland" then
    local refined = detectXWayland(dpy) and "xwayland" or "x11"
    nest = refined
    state.nest = refined
  end

  -- OML first.
  local pGetSync = procAddress(gl, "glXGetSyncValuesOML")
  local pWaitMsc = procAddress(gl, "glXWaitForMscOML")
  if pGetSync and pWaitMsc then
    local getSync = ffi.cast(
      "LPS_Bool (*)(LPS_Display *, LPS_GLXDrawable, long long *, long long *, long long *)",
      pGetSync)
    local waitMsc = ffi.cast(
      "LPS_Bool (*)(LPS_Display *, LPS_GLXDrawable, long long, long long, long long, long long *, long long *, long long *)",
      pWaitMsc)
    if omlClockAlive(getSync, getDisplay, getDrawable) then
      local ust = ffi.new("long long[1]")
      local msc = ffi.new("long long[1]")
      local sbc = ffi.new("long long[1]")
      local target = ffi.new("long long[1]")
      local zero = ffi.new("long long", 0)
      local one = ffi.new("long long", 1)
      ust[0], msc[0], sbc[0], target[0] = 0, 0, 0, 0
      -- Locals only — hot path must not touch ffi.C or string tables.
      local gd, gdrw, gs, wm = getDisplay, getDrawable, getSync, waitMsc
      local fn = function()
        local d = gd()
        if d == nil then return end
        local drawable = gdrw()
        if drawable == 0 then return end
        if gs(d, drawable, ust, msc, sbc) == 0 then return end
        -- Keep MSC arithmetic in 64-bit cdata; Lua numbers lose integers > 2^53.
        target[0] = msc[0] + one
        wm(d, drawable, target[0], zero, zero, ust, msc, sbc)
      end
      if verifyBlocks(fn) then return "oml", fn end
    end
  end

  -- SGI fallback.
  local pGet = procAddress(gl, "glXGetVideoSyncSGI")
  local pWait = procAddress(gl, "glXWaitVideoSyncSGI")
  if pGet and pWait then
    local getVS = ffi.cast("int (*)(unsigned int *)", pGet)
    local waitVS = ffi.cast("int (*)(int, int, unsigned int *)", pWait)
    if sgiClockAlive(getVS) then
      local count = ffi.new("unsigned int[1]")
      count[0] = 0
      local gv, wv = getVS, waitVS
      local divisor = 2
      local fn = function()
        count[0] = 0
        if gv(count) ~= 0 then return end
        -- Wait for the opposite parity of the current counter (next vblank).
        -- remainder must stay in [0, divisor); count is seeded before gv.
        local nextRem = (tonumber(count[0]) + 1) % divisor
        wv(divisor, nextRem, count)
      end
      if verifyBlocks(fn) then return "sgi", fn end
    end
  end

  return nil, nil
end

local function pickStrategy()
  -- Always drop any prior wait first.  While gated is nil we are probing
  -- unassisted present intervals — never re-bind mid-probe or the sample
  -- measures our own wait instead of the driver's raw behaviour.
  waitFn = nil
  state.needsSoftwareCap = false
  state.strategy = "none"

  local vsyncOn = true
  local okV, VSync = pcall(require, "src.core.VSync")
  if okV and VSync.isOn then vsyncOn = VSync.isOn() end
  if not vsyncOn then
    state.strategy = "none"
    return
  end

  if not state.osLinux then
    if state.gated == true then
      state.strategy = "sdl"
    elseif state.gated == false then
      state.needsSoftwareCap = true
      state.strategy = "none"
    else
      state.strategy = "sdl"
    end
    return
  end

  local nest = state.nest
  if nest == "wayland" then
    -- SDL owns wl_surface.frame.  Never duplicate it.
    state.strategy = "sdl"
    if state.gated == false then
      -- Vsync option is on but presents are ungated: thermal net only.
      state.needsSoftwareCap = true
      state.strategy = "none"
    end
    return
  end

  if nest == "kmsdrm" then
    state.strategy = "none"
    if state.gated == false then state.needsSoftwareCap = true end
    return
  end

  if nest == "x11" or nest == "xwayland" then
    if state.gated == true then
      state.strategy = "sdl"
      return
    end
    if state.gated == nil then
      -- Probing: leave waitFn nil so notePresent sees bare swap timing.
      state.strategy = "sdl"
      return
    end
    -- gated == false: SDL swap-interval is a no-op.
    --
    -- XWayland (and Gamescope-on-XWayland): GLX OML/SGI MSC can tick on a
    -- soft timer while WaitForMsc / WaitVideoSync block forever on a signal
    -- that never fires (reproduced with vblank_mode=0).  Never bind those
    -- waits here — FrameCap is the thermal net.
    if nest == "xwayland" then
      state.needsSoftwareCap = true
      state.strategy = "none"
      state.bindGen = state.glxGen
      return
    end
    -- Native X11 only: try a real GLX wait after confirming the counter moves.
    local kind, fn = bindGlxWait(nest)
    state.bindGen = state.glxGen
    if kind and fn then
      state.strategy = kind
      waitFn = fn
      state.needsSoftwareCap = false
      return
    end
    state.needsSoftwareCap = true
    state.strategy = "none"
    return
  end

  if state.gated == false then state.needsSoftwareCap = true end
  state.strategy = "none"
end

local function platformNest()
  if not love or not love.system or not love.system.getOS then return "unknown" end
  local osName = love.system.getOS()
  if osName == "Windows" then return "windows" end
  if osName == "OS X" or osName == "macOS" then return "macos" end
  if osName == "Linux" then return detectNest(state.driver) end
  return osName:lower()
end

local function ensureDetected()
  if state.ready then return end
  state.osLinux = isLinux()
  state.driver = videoDriver()
  state.gamescope = false
  if state.osLinux then
    state.gamescope = envTruthy("GAMESCOPE_WAYLAND_DISPLAY")
      or (os.getenv("XDG_CURRENT_DESKTOP") or ""):lower():find("gamescope", 1, true) ~= nil
    state.nest = detectNest(state.driver)
    if state.gamescope and state.nest == "x11" then
      state.nest = "xwayland"
    end
  else
    state.nest = platformNest()
  end
  state.ready = true
  state.intervals = {}
  state.probeCount = 0
  state.gated = nil
  pickStrategy()
end

function PresentProbe.reset()
  waitFn = nil
  state.ready = false
  state.driver = nil
  state.nest = nil
  state.gamescope = false
  state.gated = nil
  state.strategy = "none"
  state.needsSoftwareCap = false
  state.probeCount = 0
  state.presentStart = nil
  state.intervals = nil
  state.glxGen = state.glxGen + 1
  state.bindGen = -1
  sdlLib, x11Lib, glLib = nil, nil, nil
end

-- Fullscreen / resize / context loss: drop cached GLX entry points.
function PresentProbe.onDisplayChange()
  if not state.ready then ensureDetected() end
  waitFn = nil
  state.glxGen = state.glxGen + 1
  state.bindGen = -1
  state.gated = nil
  state.probeCount = 0
  state.intervals = {}
  state.presentStart = nil
  state.strategy = "none"
  state.needsSoftwareCap = false
  glLib = nil
  -- Keep driver/nest; re-probe effectiveness and rebind on next presents.
  pickStrategy()
end

function PresentProbe.reprobe()
  ensureDetected()
  state.gated = nil
  state.probeCount = 0
  state.intervals = {}
  state.presentStart = nil
  waitFn = nil
  state.glxGen = state.glxGen + 1
  state.bindGen = -1
  glLib = nil
  pickStrategy()
end

local function abandonWait()
  waitFn = nil
  state.strategy = "none"
  state.needsSoftwareCap = true
  state.gated = false
  state.bindGen = state.glxGen
end

-- Hot path: must stay allocation-free and avoid ffi.C / require.
-- Records presentStart AFTER any GLX wait so the probe measures SDL/GL
-- swap-interval block time alone (FrameCap sleep lives after notePresent).
function PresentProbe.waitBeforePresent()
  local fn = waitFn
  if fn then
    local t0 = love.timer and love.timer.getTime and love.timer.getTime()
    local ok = pcall(fn)
    local t1 = love.timer and love.timer.getTime and love.timer.getTime()
    if not ok or (t0 and t1 and (t1 - t0) > WAIT_ABORT_S) then
      abandonWait()
    end
  end
  if state.gated == nil and love.timer and love.timer.getTime then
    state.presentStart = love.timer.getTime()
  end
end

function PresentProbe.notePresent()
  if not state.ready then ensureDetected() end

  if state.gated ~= nil then
    if state.gated == false
       and waitFn == nil
       and state.bindGen ~= state.glxGen
       and (state.nest == "x11" or state.nest == "xwayland") then
      pickStrategy()
    end
    return
  end

  local start = state.presentStart
  state.presentStart = nil
  local now = love.timer and love.timer.getTime and love.timer.getTime()
  if not start or not now then return end
  local block = now - start
  -- Discard hitches / timer glitches; keep sampling until we have clean ones.
  if block <= 0 or block > 0.25 then return end
  local intervals = state.intervals
  if not intervals then
    intervals = {}
    state.intervals = intervals
  end
  intervals[#intervals + 1] = block
  state.probeCount = #intervals
  if #intervals < PROBE_FRAMES then return end

  state.gated = classifyGated(intervals)
  pickStrategy()
end

function PresentProbe.needsSoftwareCap()
  return state.needsSoftwareCap == true
end

function PresentProbe.status()
  ensureDetected()
  return {
    linux = state.osLinux,
    driver = state.driver,
    nest = state.nest,
    gamescope = state.gamescope,
    gated = state.gated,
    strategy = state.strategy,
    needsSoftwareCap = state.needsSoftwareCap,
    probeCount = state.probeCount,
  }
end

-- Test seams ---------------------------------------------------------------

function PresentProbe._testSetState(fields)
  fields = fields or {}
  for k, v in pairs(fields) do
    if k ~= "waitFn" and k ~= "clearGated" then state[k] = v end
  end
  -- pairs() skips nil values, so gated=nil alone cannot clear a prior probe.
  if fields.clearGated then state.gated = nil end
  if fields.waitFn ~= nil then
    waitFn = (fields.waitFn ~= false) and fields.waitFn or nil
  end
end

function PresentProbe._testClassifyGated(intervals)
  return classifyGated(intervals)
end

function PresentProbe._testPickStrategy()
  pickStrategy()
  return state.strategy, state.needsSoftwareCap, waitFn ~= nil
end

return PresentProbe
