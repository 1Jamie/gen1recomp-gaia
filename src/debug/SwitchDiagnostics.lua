-- Opt-in Switch diagnostics: ring buffer + ≤1 Hz flush when switch-debug.txt exists.
-- Never logs ROM/save bytes — see spec SWNX-13/28.

local SwitchDiagnostics = {}

local MARKER = "switch-debug.txt"
local LOG_FILE = "switch.log"
local FLUSH_INTERVAL = 1.0
local RING_SIZE = 64

local enabled = nil
local buffer = {}
local bufCount = 0
local lastFlushAt = -math.huge
local identityLine = nil

local function fs()
  return love and love.filesystem
end

local function redactString(s)
  if type(s) ~= "string" then return s end
  for i = 1, #s do
    local b = s:byte(i)
    if b < 32 or b > 126 then return "<redacted>" end
  end
  return s
end

local function sanitize(value, depth)
  depth = depth or 0
  if depth > 4 then return "<deep>" end
  local t = type(value)
  if t == "string" then return redactString(value) end
  if t == "number" or t == "boolean" or value == nil then return value end
  if t == "table" then
    local out = {}
    for k, v in pairs(value) do
      local key = type(k) == "string" and k or tostring(k)
      if key:lower():find("rom") or key:lower():find("save") then
        out[key] = "<redacted>"
      else
        out[key] = sanitize(v, depth + 1)
      end
    end
    return out
  end
  return tostring(value)
end

local function encodePayload(payload)
  if payload == nil then return "" end
  if type(payload) == "string" then return redactString(payload) end
  local parts = {}
  for k, v in pairs(sanitize(payload)) do
    parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
  end
  table.sort(parts)
  return table.concat(parts, " ")
end

function SwitchDiagnostics._resetForTests()
  enabled = nil
  buffer = {}
  bufCount = 0
  lastFlushAt = -math.huge
  identityLine = nil
end

function SwitchDiagnostics.isEnabled()
  if enabled ~= nil then return enabled end
  local filesystem = fs()
  if not filesystem then
    enabled = false
    return false
  end
  enabled = filesystem.getInfo(MARKER) ~= nil
  return enabled
end

function SwitchDiagnostics.identityOverlay()
  if identityLine then return identityLine end
  local gitCommit = os.getenv("POKEPORT_GIT_COMMIT") or "unknown"
  local loveNxTag = "11.5-nx1"
  local buildVersion = "dev"
  local filesystem = fs()
  if filesystem then
    local raw = filesystem.read("build-info.json")
    if raw and raw ~= "" then
      local ver = raw:match('"version"%s*:%s*"([^"]+)"')
      if ver then buildVersion = ver end
      local tag = raw:match('"loveNxTag"%s*:%s*"([^"]+)"')
      if tag then loveNxTag = tag end
      local commit = raw:match('"gitCommit"%s*:%s*"([^"]+)"')
      if commit then gitCommit = commit end
    end
  end
  identityLine = ("gitCommit=%s loveNxTag=%s buildVersion=%s os=%s"):format(
    gitCommit, loveNxTag, buildVersion,
    love and love.system and love.system.getOS() or "unknown")
  return identityLine
end

function SwitchDiagnostics.onEvent(kind, payload)
  if not SwitchDiagnostics.isEnabled() then return end
  bufCount = bufCount + 1
  local slot = ((bufCount - 1) % RING_SIZE) + 1
  buffer[slot] = ("%s %s"):format(tostring(kind), encodePayload(payload))
end

function SwitchDiagnostics.onJoystickEvent(kind, joystick, button, extra)
  if not SwitchDiagnostics.isEnabled() then return end
  local payload = { button = button }
  if joystick then
    if joystick.getGUID then payload.guid = joystick:getGUID() end
    if joystick.isGamepad then payload.isGamepad = joystick:isGamepad() end
    if joystick.getName then payload.name = joystick:getName() end
  end
  if extra then
    for k, v in pairs(extra) do payload[k] = v end
  end
  SwitchDiagnostics.onEvent(kind, payload)
end

function SwitchDiagnostics.maybeFlush(force, now)
  if not SwitchDiagnostics.isEnabled() then return end
  now = now or (love and love.timer and love.timer.getTime() or 0)
  if not force and (now - lastFlushAt) < FLUSH_INTERVAL then return end
  lastFlushAt = now

  local filesystem = fs()
  if not filesystem then return end

  local lines = { SwitchDiagnostics.identityOverlay(), "---" }
  local start = math.max(1, bufCount - RING_SIZE + 1)
  for i = start, bufCount do
    local slot = ((i - 1) % RING_SIZE) + 1
    if buffer[slot] then lines[#lines + 1] = buffer[slot] end
  end
  filesystem.write(LOG_FILE, table.concat(lines, "\n") .. "\n")
end

return SwitchDiagnostics
