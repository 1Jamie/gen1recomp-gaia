-- Measures the real present rate under the DISPLAY frame cap on the host
-- panel.  Standalone (no util.lua) so it runs from an unpacked game.love.
--
--   POKEPORT_DRIVER=<abs path> POKEPORT_VERSION=red lovec.exe <game dir>

return function()
  local FrameCap = require("src.core.FrameCap")
  local VSync = require("src.core.VSync")
  local PresentSync = require("src.core.PresentSync")
  local RefreshRate = require("src.core.RefreshRate")

  local fails = 0

  local function wait(seconds)
    local t0 = love.timer.getTime()
    while love.timer.getTime() - t0 < seconds do coroutine.yield() end
  end

  local function measure(seconds)
    local t0 = love.timer.getTime()
    local frames = 0
    while love.timer.getTime() - t0 < seconds do
      coroutine.yield()
      frames = frames + 1
    end
    return frames / (love.timer.getTime() - t0)
  end

  local function selected()
    if type(FrameCap.selected) == "function" then return FrameCap.selected() end
    return FrameCap.current
  end

  local function status(tag, fps)
    local s = PresentSync.status()
    print(string.format(
      "%s fps=%.1f hz=%s current=%s selected=%s vsyncWant=%s vsyncEff=%s swap=%s gated=%s softcap=%s strategy=%s nest=%s",
      tag, fps or -1, tostring(RefreshRate.hz()), tostring(FrameCap.current),
      tostring(selected()), tostring(VSync.isOn()),
      tostring(VSync.effective()), tostring(love.window.getVSync()),
      tostring(s.gated), tostring(s.needsSoftwareCap),
      tostring(s.strategy), tostring(s.nest)))
  end

  local function run(label, vsyncMode, cap, expect, tolerance)
    VSync.apply(vsyncMode)
    FrameCap.apply(cap)
    wait(4)
    local fps = measure(3)
    status(label, fps)
    local want = type(expect) == "function" and expect() or expect
    local ok = want ~= nil and math.abs(fps - want) <= want * tolerance
    print(string.format("%s %s fps=%.1f want=%s", ok and "PASS" or "FAIL", label, fps, tostring(want)))
    if not ok then fails = fails + 1 end
  end

  local function hostProbe()
    local w, h, flags = love.window.getMode()
    print(string.format("window %dx%d display=%s refreshrate=%s vsync=%s fullscreen=%s",
      w, h, tostring(flags.display), tostring(flags.refreshrate), tostring(flags.vsync),
      tostring(flags.fullscreen)))
    local count = love.window.getDisplayCount()
    for i = 1, count do
      local dw, dh = love.window.getDesktopDimensions(i)
      print(string.format("desktop %d: %dx%d name=%s", i, dw, dh, tostring(love.window.getDisplayName(i))))
    end
    local okFfi, ffi = pcall(require, "ffi")
    if not okFfi then print("ffi unavailable") return end
    pcall(ffi.cdef, [[
      typedef struct { uint32_t format; int w; int h; int refresh_rate; void *driverdata; } PP_SDL_DisplayMode;
      int SDL_GetCurrentDisplayMode(int displayIndex, PP_SDL_DisplayMode *mode);
    ]])
    local okC, errC = pcall(function()
      local mode = ffi.new("PP_SDL_DisplayMode")
      local rc = ffi.C.SDL_GetCurrentDisplayMode(0, mode)
      return rc .. " hz=" .. mode.refresh_rate
    end)
    print("ffi.C SDL_GetCurrentDisplayMode: " .. tostring(errC) .. (okC and " (ok)" or " (failed)"))
    local okL, errL = pcall(function()
      local lib = ffi.load("SDL2")
      local mode = ffi.new("PP_SDL_DisplayMode")
      local rc = lib.SDL_GetCurrentDisplayMode(0, mode)
      return rc .. " hz=" .. mode.refresh_rate .. " " .. mode.w .. "x" .. mode.h
    end)
    print("ffi.load(SDL2) SDL_GetCurrentDisplayMode: " .. tostring(errL) .. (okL and " (ok)" or " (failed)"))
  end

  wait(2)
  hostProbe()
  status("boot", nil)
  print("os=" .. tostring(love.system.getOS()) .. " panel hz=" .. tostring(RefreshRate.hz()))

  local function panel() return RefreshRate.hz() end
  run("display-vsync-off", "off", FrameCap.DISPLAY, panel, 0.1)
  run("display-vsync-on", "on", FrameCap.DISPLAY, panel, 0.1)
  run("cap60-vsync-off", "off", 60, 60, 0.1)
  run("cap60-vsync-on", "on", 60, 60, 0.1)
  run("display-again-vsync-off", "off", FrameCap.DISPLAY, panel, 0.1)

  print(fails == 0 and "PASS display cap paces at the panel rate" or ("FAIL " .. fails .. " checks"))
  love.event.quit(fails == 0 and 0 or 1)
end
