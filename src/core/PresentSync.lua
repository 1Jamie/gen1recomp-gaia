-- Cross-platform present sync: probe whether vsync actually gates presents,
-- delegate Linux-specific GLX waits to PresentProbe, and decide when FixedStep
-- may snap dt to the panel refresh (DISPLAY + working sync only).

local PresentSync = {}

local function probe()
  return require("src.core.PresentProbe")
end

function PresentSync.waitBeforePresent()
  probe().waitBeforePresent()
end

function PresentSync.notePresent()
  probe().notePresent()
end

-- True while the probe still has no gated/ungated verdict for DISPLAY+vsync.
function PresentSync.probingDisplaySync()
  local status = probe().status()
  if status.gated ~= nil then return false end
  local FrameCap = require("src.core.FrameCap")
  local VSync = require("src.core.VSync")
  return FrameCap.current == FrameCap.DISPLAY and VSync.isOn()
end

function PresentSync.needsSoftwareCap()
  if probe().needsSoftwareCap() then return true end
  return PresentSync.probingDisplaySync()
end

-- Vsync cannot be turned on usefully once the probe has failed; the row still
-- allows stepping to OFF.  Warmup (probingDisplaySync) does not block the row.
function PresentSync.vsyncEnableBlocked()
  local VSync = require("src.core.VSync")
  if not VSync.isOn() then return false end
  return probe().needsSoftwareCap()
end

function PresentSync.vsyncStepAllowed(mode, dir)
  if not PresentSync.vsyncEnableBlocked() then return true end
  local VSync = require("src.core.VSync")
  return VSync.cycle(mode, dir) == "off"
end

function PresentSync.onDisplayChange()
  probe().onDisplayChange()
end

function PresentSync.reprobe()
  probe().reprobe()
end

function PresentSync.reset()
  probe().reset()
end

function PresentSync.status()
  return probe().status()
end

-- FixedStep.refreshPeriod is only set when logic cadence should track the
-- display.  Snapping dt to 144Hz while software-pacing at 60 (#1958) or
-- with vsync off is what caused the irregular frame pacing regression.
function PresentSync.logicRefreshPeriod()
  local FrameCap = require("src.core.FrameCap")
  local VSync = require("src.core.VSync")
  local RefreshRate = require("src.core.RefreshRate")
  local cap = FrameCap.current

  if cap == FrameCap.DISPLAY then
    if not VSync.isOn() then return nil end
    if PresentSync.needsSoftwareCap() then return nil end
    return RefreshRate.period()
  end

  if not cap or cap <= 0 then return nil end

  local hz = RefreshRate.hz()
  if hz and cap == hz then return 1 / hz end
  return nil
end

function PresentSync.applyFixedStepPeriod()
  require("src.core.FixedStep").refreshPeriod = PresentSync.logicRefreshPeriod()
end

return PresentSync
