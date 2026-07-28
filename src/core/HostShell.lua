-- Helpers for calling host tools (curl, zenity/kdialog, ...).

local HostShell = {}

-- Our AppRun exports LD_LIBRARY_PATH="$APPDIR/lib:..." so every subprocess we
-- spawn tries to link against the libraries we're shipping instead of the
-- system ones. We want to unset the var so that any system tools can find
-- their proper libraries. Only needed when running in an AppImage.
function HostShell.envPrefix()
  if os.getenv("APPIMAGE") then
    return "env -u LD_LIBRARY_PATH "
  end
  return ""
end

-- Wraps io.popen with the AppImage env fix applied and lua errors swallowed
function HostShell.popen(command, mode)
  local ok, pipe = pcall(io.popen, HostShell.envPrefix() .. command, mode or "r")
  if not ok or not pipe then return nil end
  return pipe
end

-- Restart the whole app. The obvious love.event.quit("restart") re-runs LÖVE's
-- boot in-process, which calls love.filesystem.init a second time -- and inside
-- an AppImage physfs is already initialized, so that second init throws
-- ("Failed to initialize filesystem: already initialized") and the relaunch
-- crashes. So on an AppImage we relaunch the executable; the fresh process's
-- Boot step mounts any downloaded update exactly as a manual relaunch would.
-- On every other platform the in-process restart works, so keep it.
function HostShell.restart()
  if not (love and love.event and love.event.quit) then return end
  local appimage = os.getenv("APPIMAGE")
  if not appimage then
    love.event.quit("restart")
    return
  end

  -- We have to restart the process with this cursed execv call to prevent the
  -- PID from changing, which might cause SteamOS and other Linux launchers to
  -- think the app has crashed.
  local ffi = require("ffi")
  pcall(ffi.cdef, [[
    int execv(const char *path, char *const argv[]);
    int unsetenv(const char *name);
  ]])
  ffi.C.unsetenv("LD_LIBRARY_PATH")
  local argv = ffi.new("const char *[2]", appimage, nil)
  ffi.C.execv(appimage, ffi.cast("char *const *", argv))
end

return HostShell
