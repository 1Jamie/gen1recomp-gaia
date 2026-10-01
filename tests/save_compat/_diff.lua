local D = {}

local indexes = setmetatable({}, { __mode = "k" })

function D.regionsFor(gen, version)
  local mod = require("src.save_convert.regions.gen" .. gen)
  return mod.layouts[version] or mod.layouts.default
end

function D.index(regions, block)
  indexes[regions] = indexes[regions] or {}
  local key = block or "*"
  local idx = indexes[regions][key]
  if idx then return idx end
  local list = {}
  for _, r in ipairs(regions) do
    if (block == nil and r.block == nil) or r.block == block then list[#list + 1] = r end
  end
  table.sort(list, function(a, b) return a.size > b.size end)
  idx = {}
  for _, r in ipairs(list) do
    for o = r.offset, r.offset + r.size - 1 do idx[o] = r end
  end
  indexes[regions][key] = idx
  return idx
end

function D.regionAt(regions, offset, block)
  return D.index(regions, block)[offset]
end

local UNMAPPED = { name = "unmapped", tier = "?" }

function D.diff(a, b, regions, opts)
  opts = opts or {}
  local idx = D.index(regions, opts.block)
  local base = opts.base or 0
  local byName, order = {}, {}
  local n = math.max(#a, #b)
  for i = 1, n do
    local x, y = a:byte(i), b:byte(i)
    if x ~= y then
      local off = base + i - 1
      local r = idx[off] or UNMAPPED
      if opts.includeDerived or not r.derived then
        local e = byName[r.name]
        if not e then
          e = { name = r.name, tier = r.tier, ids = r.ids, count = 0, first = off, last = off,
                derived = r.derived, sample = {} }
          byName[r.name] = e
          order[#order + 1] = e
        end
        e.count = e.count + 1
        e.last = off
        if #e.sample < 4 then
          e.sample[#e.sample + 1] = ("%X:%s>%s"):format(off, x and ("%02X"):format(x) or "--",
            y and ("%02X"):format(y) or "--")
        end
      end
    end
  end
  return order
end

function D.format(entries, limit)
  local out = {}
  for i, e in ipairs(entries) do
    if limit and i > limit then
      out[#out + 1] = ("... +%d more regions"):format(#entries - limit)
      break
    end
    out[#out + 1] = ("%s[%s%s] %dB 0x%X-0x%X %s"):format(e.name, e.tier or "?", e.ids and (" " .. e.ids) or "",
      e.count, e.first, e.last, table.concat(e.sample, ","))
  end
  return table.concat(out, "; ")
end

return D
