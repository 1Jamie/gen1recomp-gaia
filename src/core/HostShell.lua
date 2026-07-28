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

return HostShell
