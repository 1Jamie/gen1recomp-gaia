local P = {}

function P.root(version)
  local dir = version == "yellow" and "../pokeyellow" or "../pokered"
  local f = io.open(dir .. "/data/maps/special_warps.asm", "r")
  if not f then return nil end
  f:close()
  return dir
end

local function lines(path)
  local f = assert(io.open(path, "r"))
  local out = {}
  for l in f:lines() do out[#out + 1] = l end
  f:close()
  return out
end

function P.flyWarpData(root)
  local order, label, coords = {}, {}, {}
  for _, l in ipairs(lines(root .. "/data/maps/special_warps.asm")) do
    local map, lab = l:match("^%s*fly_warp_spec%s+([%w_]+),%s*%.(%w+)")
    if map then
      order[#order + 1] = map
      label[lab] = map
    end
    local lab2, map2, x, y = l:match("^%.(%w+):%s*fly_warp%s+([%w_]+),%s*(%d+),%s*(%d+)")
    if lab2 then coords[map2] = { tonumber(x), tonumber(y), label = lab2 } end
  end
  return order, coords
end

function P.mapIndexes(root)
  local idx, n = {}, 0
  for _, l in ipairs(lines(root .. "/constants/map_constants.asm")) do
    local name = l:match("^%s*map_const%s+([%w_]+),")
    if name then
      idx[name] = n
      n = n + 1
    elseif l:match("^%s*const_skip") then
      n = n + (tonumber(l:match("const_skip%s+(%d+)")) or 1)
    end
  end
  return idx
end

function P.warpDestinations(root, mapConst)
  local headers = io.popen("ls " .. root .. "/data/maps/headers")
  local camel
  for file in headers:lines() do
    for _, l in ipairs(lines(root .. "/data/maps/headers/" .. file)) do
      local name, const = l:match("^%s*map_header%s+(%w+),%s*([%w_]+),")
      if const == mapConst then camel = name end
    end
  end
  headers:close()
  if not camel then return {} end
  local dests = {}
  local f = io.open(root .. "/data/maps/objects/" .. camel .. ".asm", "r")
  if not f then return dests end
  f:close()
  for _, l in ipairs(lines(root .. "/data/maps/objects/" .. camel .. ".asm")) do
    local dest = l:match("^%s*warp_event%s+%d+,%s*%d+,%s*([%w_]+),")
    if dest then dests[#dests + 1] = dest end
  end
  return dests
end

function P.constants(path)
  local byName, byIndex = {}, {}
  local n = 0
  local tm, hm = 0, 0
  for _, l in ipairs(lines(path)) do
    if l:match("^%s*const_def") then
      n = tonumber(l:match("const_def%s+(%d+)")) or 0
    elseif l:match("^%s*const_skip") then
      n = n + (tonumber(l:match("const_skip%s+(%d+)")) or 1)
    elseif l:match("^%s*const_next") then
      local v = l:match("const_next%s+(%$?%x+)")
      n = v:sub(1, 1) == "$" and tonumber(v:sub(2), 16) or tonumber(v)
    else
      local name = l:match("^%s*const%s+([%w_]+)")
      if name then
        byName[name] = n
        byIndex[n] = byIndex[n] or name
        n = n + 1
      end
    end
  end
  return byName, byIndex
end

function P.machines(path)
  local out = {}
  local kind, n = nil, 0
  for _, l in ipairs(lines(path)) do
    if l:match("^DEF HM01 EQU") then kind, n = "HM", 0xC4 end
    if l:match("^DEF TM01 EQU") then kind, n = "TM", 0xC9 end
    local name = l:match("^%s*add_hm%s+([%w_]+)")
    if name then out["HM_" .. name] = n; n = n + 1 end
    name = l:match("^%s*add_tm%s+([%w_]+)")
    if name then out["TM_" .. name] = n; n = n + 1 end
  end
  return out
end

function P.charmap(root)
  local out = {}
  for _, l in ipairs(lines(root .. "/constants/charmap.asm")) do
    local token, byte = l:match('^%s*charmap%s+"(.-)",%s*%$(%x+)')
    if token then out[token] = tonumber(byte, 16) end
  end
  return out
end

function P.dexOrder(root)
  local order = {}
  for _, l in ipairs(lines(root .. "/data/pokemon/dex_order.asm")) do
    local name = l:match("^%s*db%s+DEX_([%w_]+)")
    if name then
      order[#order + 1] = name
    elseif l:match("^%s*db%s+0") then
      order[#order + 1] = false
    end
  end
  return order
end

return P
