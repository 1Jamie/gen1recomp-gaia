-- Minimal logger; warnings are collected so debug overlays can show them.

local Logger = { history = {} }

-- A log call must never take the game down: when the arguments don't fit
-- the format (a nil where %d wants a number, say), every directive becomes
-- %s over tostring'd arguments and the error rides along on the line.
local function format(fmt, ...)
  local n = select("#", ...)
  if n == 0 then return tostring(fmt) end
  local ok, msg = pcall(string.format, fmt, ...)
  if ok then return msg end
  local plain, wanted = tostring(fmt):gsub("%%%%", "\0")
    :gsub("%%[-+ #0]*%d*%.?%d*%a", "%%s")
  local args = { ... }
  n = math.max(n, wanted)
  for i = 1, n do args[i] = tostring(args[i]) end
  local okPlain, text = pcall(string.format, plain:gsub("%z", "%%%%"),
    (table.unpack or unpack)(args, 1, n))
  if not okPlain then
    text = tostring(fmt) .. " " .. table.concat(args, " ", 1, n)
  end
  return string.format("%s (bad log format: %s)", text, tostring(msg))
end

local function emit(level, fmt, ...)
  local msg = format(fmt, ...)
  local line = string.format("[%s] %s", level, msg)
  print(line)
  table.insert(Logger.history, line)
  if #Logger.history > 200 then
    table.remove(Logger.history, 1)
  end
end

function Logger.info(fmt, ...) emit("info", fmt, ...) end
function Logger.warn(fmt, ...) emit("warn", fmt, ...) end
function Logger.error(fmt, ...) emit("error", fmt, ...) end

return Logger
