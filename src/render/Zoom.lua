-- Overworld survey zoom: integer pixels-per-world-pixel scales stepped
-- by the mouse wheel, Options ZOOM row, or hotkey `4`.  Stored as an
-- offset from the window fit scale S so a resize keeps the relative
-- zoom.  Persisted as save.options.zoom (default 0 = FIT).
-- Spec: docs/new-features.md (survey zoom)

local Zoom = {}

Zoom.offset = 0

-- effective integer scale s' in [1, 2*S]
function Zoom.scale(S)
  return math.max(1, math.min(2 * S, S + Zoom.offset))
end

-- legal offset range for a given fit scale
function Zoom.offsetRange(S)
  S = math.max(1, math.floor(tonumber(S) or 1))
  return 1 - S, S
end

function Zoom.clampOffset(offset, S)
  local lo, hi = Zoom.offsetRange(S)
  offset = math.floor(tonumber(offset) or 0)
  if offset < lo then return lo end
  if offset > hi then return hi end
  return offset
end

function Zoom.step(delta, S)
  Zoom.offset = Zoom.clampOffset(Zoom.offset + delta, S)
  return Zoom.offset
end

-- Advance one zoom level toward max close-up, then wrap to full survey.
-- Returns the new offset.
function Zoom.cycle(S)
  local lo, hi = Zoom.offsetRange(S)
  local next = Zoom.offset + 1
  if next > hi then next = lo end
  Zoom.offset = next
  return Zoom.offset
end

function Zoom.reset()
  Zoom.offset = 0
end

function Zoom.applyOptions(opts)
  Zoom.offset = math.floor(tonumber(opts and opts.zoom) or 0)
end

-- FIT / OUT1 / OUT2 / … / IN1 / IN2 / …
function Zoom.offsetLabel(offset)
  offset = math.floor(tonumber(offset) or 0)
  if offset == 0 then return "FIT" end
  if offset < 0 then return "OUT" .. tostring(-offset) end
  return "IN" .. tostring(offset)
end

-- world pixels covered by a w x h letterbox viewport at fit scale S
-- (legacy GB-framed size; prefer fillViewSize for the live world pass)
function Zoom.viewSize(S, w, h)
  local s = Zoom.scale(S)
  return math.ceil(w * S / s), math.ceil(h * S / s)
end

-- world pixels needed to fill a ww x wh window at the current zoom scale
-- (fills letterbox "black voids" with more map,  phones, tall windows)
function Zoom.fillViewSize(s, ww, wh)
  return math.ceil(ww / s), math.ceil(wh / s)
end

-- zoom input is honored only while free-roaming the overworld
function Zoom.gateOK(top, overworld)
  if top == nil or top ~= overworld then return false end
  if top.transitioning then return false end
  if top.runner and top.runner.isRunning and top.runner:isRunning() then
    return false
  end
  return true
end

return Zoom
