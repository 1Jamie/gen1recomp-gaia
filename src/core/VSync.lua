local VSync = {}

VSync.MODES = { "on", "off", "adaptive" }

local INTERVAL = { on = 1, off = 0, adaptive = -1 }
local LABELS = { on = "ON", off = "OFF", adaptive = "ADAPTIVE" }

local boot = nil
-- `wanted` is what the user/options asked for.  `live` is what the driver
-- reports after setVSync (may be "off" under vblank_mode=0 / Gamescope even
-- when we requested on -- PresentProbe still tries a real wait on native X11).
local wanted = nil
local live = nil

local function fromInterval(interval)
  interval = tonumber(interval)
  if not interval then return nil end
  if interval < 0 then return "adaptive" end
  if interval == 0 then return "off" end
  return "on"
end

local function query()
  if not (love and love.window and love.window.getVSync) then return nil end
  local ok, interval = pcall(love.window.getVSync)
  if not ok then return nil end
  return fromInterval(interval)
end

function VSync.default()
  if not boot then boot = query() or "on" end
  return boot
end

function VSync.normalize(mode)
  for _, m in ipairs(VSync.MODES) do
    if mode == m then return m end
  end
  return VSync.default()
end

function VSync.label(mode)
  return LABELS[VSync.normalize(mode)] or LABELS.on
end

function VSync.cycle(mode, dir)
  local cur = 1
  local normalized = VSync.normalize(mode)
  for i, m in ipairs(VSync.MODES) do
    if m == normalized then cur = i break end
  end
  return VSync.MODES[(cur - 1 + (dir or 1)) % #VSync.MODES + 1]
end

function VSync.apply(mode)
  mode = VSync.normalize(mode)
  wanted = mode
  live = mode
  if not (love and love.window and love.window.setVSync) then return mode end
  local ok = pcall(love.window.setVSync, INTERVAL[mode])
  if not ok and mode == "adaptive" then
    pcall(love.window.setVSync, INTERVAL.on)
    live = "on"
    wanted = "on"
  end
  local got = query()
  if got then live = got end
  -- Linux present-sync remeasures whether the swap interval actually gates
  -- presents after the driver call above (Gamescope/XWayland no-ops).
  local okLPS, PS = pcall(require, "src.core.PresentSync")
  if okLPS and PS.reprobe then pcall(PS.reprobe) end
  return mode
end

function VSync.applyOptions(opts)
  VSync.apply(opts and opts.vsync)
end

-- True when the user asked for sync (on/adaptive), even if the driver
-- reported the interval as 0 afterwards.
function VSync.isOn()
  if wanted then return wanted ~= "off" end
  if not live then live = query() or VSync.default() end
  return live ~= "off"
end

-- What getVSync currently reports (may disagree with isOn under mesa quirks).
function VSync.effective()
  if live then return live end
  return query() or VSync.default()
end

function VSync.reset()
  boot, wanted, live = nil, nil, nil
end

return VSync
