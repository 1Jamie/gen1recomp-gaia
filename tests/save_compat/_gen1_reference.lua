local R = {}

local function u8(s, o) return s:byte(o + 1) or 0 end
local function be(s, o, n)
  local v = 0
  for i = 0, n - 1 do v = v * 256 + u8(s, o + i) end
  return v
end
local function hex(s, o, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = ("%02X"):format(u8(s, o + i)) end
  return table.concat(t)
end
local function name(s, o)
  local t = {}
  for i = 0, 10 do
    local b = u8(s, o + i)
    if b == 0x50 then break end
    t[#t + 1] = ("%02X"):format(b)
  end
  return table.concat(t)
end
local function bcd(s, o, n)
  local v = 0
  for i = 0, n - 1 do
    local b = u8(s, o + i)
    v = v * 100 + math.floor(b / 16) * 10 + b % 16
  end
  return v
end

local function mon(s, o, party)
  local m = {
    species = u8(s, o), hp = be(s, o + 1, 2), boxLevel = u8(s, o + 3), status = u8(s, o + 4),
    types = hex(s, o + 5, 2), catchRate = u8(s, o + 7), moves = hex(s, o + 8, 4),
    otId = be(s, o + 12, 2), exp = be(s, o + 14, 3), statExp = hex(s, o + 17, 10),
    dvs = hex(s, o + 27, 2), pp = hex(s, o + 29, 4),
  }
  if party then
    m.level = u8(s, o + 33)
    m.stats = hex(s, o + 34, 10)
  end
  return m
end

local function list(s, base, cap, size, party)
  local out = { count = u8(s, base) }
  if out.count > cap then out.invalid = true; return out end
  local monsAt = base + 2 + cap
  local otAt = monsAt + cap * size
  local nickAt = otAt + cap * 11
  for i = 0, out.count - 1 do
    local m = mon(s, monsAt + i * size, party)
    m.listSpecies = u8(s, base + 1 + i)
    m.ot = name(s, otAt + i * 11)
    m.nick = name(s, nickAt + i * 11)
    out[#out + 1] = m
  end
  return out
end

local function rows(s, at, cap)
  local out = {}
  for i = 0, cap - 1 do
    local id = u8(s, at + i * 2)
    if id == 0xFF then break end
    out[#out + 1] = ("%02X:%02X"):format(id, u8(s, at + i * 2 + 1))
  end
  return table.concat(out, ",")
end

function R.decode(s)
  local d = {
    playerName = name(s, 0x2598), rivalName = name(s, 0x25F6), playerId = be(s, 0x2605, 2),
    money = bcd(s, 0x25F3, 3), coins = bcd(s, 0x2850, 2), badges = u8(s, 0x2602), options = u8(s, 0x2601),
    dexOwned = hex(s, 0x25A3, 19), dexSeen = hex(s, 0x25B6, 19),
    bag = rows(s, 0x25CA, 20), bagCount = u8(s, 0x25C9), pc = rows(s, 0x27E7, 50), pcCount = u8(s, 0x27E6),
    curMap = u8(s, 0x260A), y = u8(s, 0x260D), x = u8(s, 0x260E), lastMap = u8(s, 0x2611),
    boxByte = u8(s, 0x284C), numHoF = u8(s, 0x284E), toggles = hex(s, 0x2852, 32),
    hiddenItems = hex(s, 0x299C, 14), walk = u8(s, 0x29AC), townVisited = be(s, 0x29B7, 2),
    rivalStarter = u8(s, 0x29C1), playerStarter = u8(s, 0x29C3), blackout = u8(s, 0x29C5),
    statusFlags = hex(s, 0x29D4, 13), events = hex(s, 0x29F3, 320),
    playTime = hex(s, 0x2CED, 5),
    tradeFlags = hex(s, 0x29E3, 2), hiddenCoins = hex(s, 0x29AA, 2), safariSteps = be(s, 0x29B9, 2),
    safariBalls = u8(s, 0x2CF3), safariGate = u8(s, 0x28CB), fossil = hex(s, 0x29BB, 2),
    trash = hex(s, 0x29EF, 2), palOffset = u8(s, 0x2609), surfHi = hex(s, 0x2741, 2),
    yellowPikachu = hex(s, 0x271C, 2), emotion = u8(s, 0x2748),
    dayCareInUse = u8(s, 0x2CF4), dayCareName = name(s, 0x2CF5), dayCareOt = name(s, 0x2D00),
    dayCareMon = mon(s, 0x2D0B, false),
    party = list(s, 0x2F2C, 6, 44, true),
    boxes = {},
    hof = {},
  }
  local cur = d.boxByte % 128
  local init = d.boxByte >= 128
  for b = 0, 11 do
    local base = b < 6 and (0x4000 + b * 0x462) or (0x6000 + (b - 6) * 0x462)
    if b == cur then
      d.boxes[b + 1] = list(s, 0x30C0, 20, 33, false)
    elseif init then
      d.boxes[b + 1] = list(s, base, 20, 33, false)
    else
      d.boxes[b + 1] = { count = 0 }
    end
  end
  for t = 0, math.min(d.numHoF, 50) - 1 do
    local team = {}
    for m = 0, 5 do
      local at = 0x0598 + t * 96 + m * 16
      if u8(s, at) == 0xFF then break end
      team[#team + 1] = ("%02X/%d/%s"):format(u8(s, at), u8(s, at + 1), name(s, at + 2))
    end
    d.hof[#d.hof + 1] = table.concat(team, ",")
  end
  return d
end

local function walk(a, b, path, out)
  if type(a) ~= "table" or type(b) ~= "table" then
    if a ~= b then out[#out + 1] = ("%s: %s -> %s"):format(path, tostring(a), tostring(b)) end
    return
  end
  local keys = {}
  for k in pairs(a) do keys[k] = true end
  for k in pairs(b) do keys[k] = true end
  local sorted = {}
  for k in pairs(keys) do sorted[#sorted + 1] = k end
  table.sort(sorted, function(x, y) return tostring(x) < tostring(y) end)
  for _, k in ipairs(sorted) do walk(a[k], b[k], path .. "." .. tostring(k), out) end
end

function R.compare(a, b, skip)
  local out = {}
  walk(a, b, "", out)
  if skip then
    local kept = {}
    for _, line in ipairs(out) do
      local drop = false
      for _, p in ipairs(skip) do if line:match(p) then drop = true end end
      if not drop then kept[#kept + 1] = line end
    end
    out = kept
  end
  return out
end

return R
