-- Deterministic JSON writer for cache artifacts.
--
-- Json.encode (src/link/Json.lua) emits object keys in Lua's pairs order.
-- That order varies between processes on this build, so two identical fresh
-- imports of the same ROM produced different bytes for every JSON object
-- (917 map_tree files + census + meta/maps).  This wrapper keeps Json's exact
-- value formatting (scalars and string escaping are delegated to Json.encode)
-- and mirrors its array rule (contiguous [1..n]; empty table -> []), but emits
-- OBJECT KEYS IN SORTED ORDER so the bytes are stable run to run.
--
-- Used by src/import/gba/map_tree_extract.lua and src/import/RomExtractorGen3.lua.

local Json = require("src.link.Json")

local Canon = {}

local function encode(v, out)
  local t = type(v)
  if t ~= "table" then
    out[#out + 1] = Json.encode(v) -- null / boolean / number / string
    return
  end
  -- array rule copied from Json.encodeValue: contiguous [1..n], empty -> []
  local n = #v
  local isArray = n > 0
  if not isArray then isArray = next(v) == nil end
  if isArray then
    out[#out + 1] = "["
    for i = 1, n do
      if i > 1 then out[#out + 1] = "," end
      encode(v[i], out)
    end
    out[#out + 1] = "]"
    return
  end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  -- tostring comparator keeps number/string hybrid keys sortable (Json emits
  -- every key through tostring too).
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  out[#out + 1] = "{"
  for i = 1, #keys do
    if i > 1 then out[#out + 1] = "," end
    out[#out + 1] = Json.encode(tostring(keys[i]))
    out[#out + 1] = ":"
    encode(v[keys[i]], out)
  end
  out[#out + 1] = "}"
end

function Canon.encode(v)
  local out = {}
  encode(v, out)
  return table.concat(out)
end

return Canon
