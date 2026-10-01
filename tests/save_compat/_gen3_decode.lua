local bit = require("bit")

local D = {}

local U32 = 4294967296

local function b(s, o) return s:byte(o + 1) or 0 end
local function w(s, o) return b(s, o) + b(s, o + 1) * 256 end
local function d(s, o) return w(s, o) + w(s, o + 2) * 65536 end
local function x32(a, k) return bit.bxor(a, k) % U32 end

D.SIZES = {
  frlg = { [0] = 0xF24, 0xF80, 0xF80, 0xF80, 0xEE8, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0x7D0 },
  emerald = { [0] = 0xF2C, 0xF80, 0xF80, 0xF80, 0xF08, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0x7D0 },
}

D.OFF = {
  frlg = { key = 0xF20, code = 0xAC, powder = 0xAF8, partyCount = 0x34, party = 0x38, money = 0x290, coins = 0x294,
    pockets = { { 0x310, 42 }, { 0x3B8, 30 }, { 0x430, 13 }, { 0x464, 58 }, { 0x54C, 43 } }, stats = 0x1200 },
  emerald = { key = 0xAC, code = 0xAC, powder = 0x1F4, partyCount = 0x234, party = 0x238, money = 0x490, coins = 0x494,
    pockets = { { 0x560, 30 }, { 0x5D8, 30 }, { 0x650, 16 }, { 0x690, 64 }, { 0x790, 46 } }, stats = 0x159C },
}

local function sum(s, off, size)
  local t = 0
  for o = off, off + size - 4, 4 do t = (t + d(s, o)) % U32 end
  return (t + math.floor(t / 65536)) % 65536
end

function D.blocks(s, family)
  local sizes = D.SIZES[family]
  local best
  for slot = 0, 1 do
    local found, counter, ok = {}, nil, true
    for i = 0, 13 do
      local base = (slot * 14 + i) * 0x1000
      if d(s, base + 0xFF8) == 0x08012025 then
        local id = w(s, base + 0xFF4)
        if sizes[id] and w(s, base + 0xFF6) == sum(s, base, sizes[id]) then
          found[id], counter = base, d(s, base + 0xFFC)
        end
      end
    end
    for id = 0, 13 do if not found[id] then ok = false end end
    if ok and (not best or counter > best.counter) then best = { found = found, counter = counter, slot = slot } end
  end
  if not best then return nil end
  local function join(a, z)
    local parts = {}
    for id = a, z do parts[#parts + 1] = s:sub(best.found[id] + 1, best.found[id] + sizes[id]) end
    return table.concat(parts)
  end
  return { sb2 = join(0, 0), sb1 = join(1, 4), storage = join(5, 13), counter = best.counter, slot = best.slot }
end

local ORDER = {
  "GAEM", "GAME", "GEAM", "GEMA", "GMAE", "GMEA", "AGEM", "AGME", "AEGM", "AEMG", "AMGE", "AMEG",
  "EGAM", "EGMA", "EAGM", "EAMG", "EMGA", "EMAG", "MGAE", "MGEA", "MAGE", "MAEG", "MEGA", "MEAG",
}

function D.mon(raw)
  local blank = true
  for i = 1, 80 do if raw:byte(i) ~= 0 then blank = false break end end
  if blank then return nil end
  local pid, otid = d(raw, 0), d(raw, 4)
  local key = bit.bxor(pid, otid)
  local plain = {}
  for i = 0, 11 do
    local v = x32(d(raw, 0x20 + i * 4), key)
    plain[#plain + 1] = string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216))
  end
  plain = table.concat(plain)
  local ck = 0
  for i = 0, 46, 2 do ck = (ck + w(plain, i)) % 65536 end
  local order = ORDER[pid % 24 + 1]
  local at = {}
  for i = 1, 4 do at[order:sub(i, i)] = (i - 1) * 12 end
  local moves = {}
  for i = 0, 3 do moves[i + 1] = w(plain, at.A + i * 2) end
  local ivw = d(plain, at.M + 4)
  return {
    pid = pid, otid = otid, nick = raw:sub(9, 18), ot = raw:sub(0x15, 0x1B), flags = b(raw, 0x13),
    checksumOk = ck == w(raw, 0x1C), species = w(plain, at.G), item = w(plain, at.G + 2), exp = d(plain, at.G + 4),
    moves = moves, ivWord = ivw, isEgg = math.floor(ivw / 2 ^ 30) % 2 == 1, metGame = math.floor(w(plain, at.M + 2) / 128) % 16,
    shiny = bit.bxor(bit.bxor(math.floor(otid / 65536), otid % 65536), bit.bxor(math.floor(pid / 65536), pid % 65536)) % 65536 < 8,
  }
end

function D.decode(s, family)
  local blk = D.blocks(s, family)
  if not blk then return nil end
  local O = D.OFF[family]
  local key = d(blk.sb2, O.key)
  local out = { key = key, counter = blk.counter, code = d(blk.sb2, O.code), powderWord = d(blk.sb2, O.powder),
    name = blk.sb2:sub(1, 8), tid = w(blk.sb2, 0x0A), sid = w(blk.sb2, 0x0C), gender = b(blk.sb2, 8),
    playHours = w(blk.sb2, 0x0E), playMinutes = b(blk.sb2, 0x10),
    money = x32(d(blk.sb1, O.money), key), coins = bit.bxor(w(blk.sb1, O.coins), key % 65536) % 65536,
    party = {}, boxes = {}, pockets = {}, stats = {}, currentBox = b(blk.storage, 0), wallpapers = {}, boxNames = {} }
  out.powder = x32(out.powderWord, key)
  for i = 0, math.min(b(blk.sb1, O.partyCount), 6) - 1 do
    out.party[i + 1] = D.mon(blk.sb1:sub(O.party + i * 100 + 1, O.party + i * 100 + 80))
    out.party[i + 1].level = b(blk.sb1, O.party + i * 100 + 84)
  end
  for bx = 0, 13 do
    out.boxes[bx + 1] = {}
    for sl = 0, 29 do
      local o = 4 + (bx * 30 + sl) * 80
      local m = D.mon(blk.storage:sub(o + 1, o + 80))
      if m and math.floor(m.flags / 2) % 2 == 1 then out.boxes[bx + 1][sl + 1] = m end
    end
    out.wallpapers[bx + 1] = b(blk.storage, 0x83C2 + bx)
    out.boxNames[bx + 1] = blk.storage:sub(0x8344 + bx * 9 + 1, 0x8344 + bx * 9 + 9)
  end
  for p, pk in ipairs(O.pockets) do
    out.pockets[p] = {}
    for i = 0, pk[2] - 1 do
      local id = w(blk.sb1, pk[1] + i * 4)
      if id ~= 0 then
        out.pockets[p][#out.pockets[p] + 1] = { id, bit.bxor(w(blk.sb1, pk[1] + i * 4 + 2), key % 65536) % 65536 }
      end
    end
  end
  for i = 0, 63 do out.stats[i] = x32(d(blk.sb1, O.stats + i * 4), key) end
  return out
end

function D.text(s, off, len)
  local out = {}
  for i = 0, len - 1 do
    local c = b(s, off + i)
    if c == 0xFF then break end
    local ch
    if c == 0 then ch = " "
    elseif c >= 0xBB and c <= 0xD4 then ch = string.char(65 + c - 0xBB)
    elseif c >= 0xD5 and c <= 0xEE then ch = string.char(97 + c - 0xD5)
    elseif c >= 0xA1 and c <= 0xAA then ch = string.char(48 + c - 0xA1)
    else ch = ("{%02X}"):format(c) end
    out[#out + 1] = ch
  end
  return table.concat(out)
end

D.FULL = {
  frlg = { flags = 0xEE0, flagBytes = 288, vars = 0x1000, pcItems = { 0x298, 30 }, profile = 0x2CA0, battle = 0x2CAC,
    mail = 0x2CD0, daycare = 0x2F80, roamer = 0x30D0, regItem = 0x296, seen2 = 0x3A18, seen1 = 0x5F8, rival = 0x3A4C,
    optionsHi = 0x14, dexOwned = 0x28, dexSeen = 0x5C, dexMagic = 0x1B, dexOrder = 0x18, dexMode = 0x19 },
  emerald = { flags = 0x1270, flagBytes = 300, vars = 0x139C, pcItems = { 0x498, 50 }, profile = 0x2BB0, battle = 0x2BBC,
    mail = 0x2BE0, daycare = 0x3030, roamer = 0x31DC, regItem = 0x496, seen2 = 0x3B24, seen1 = 0x988, rival = nil,
    optionsHi = 0x14, dexOwned = 0x28, dexSeen = 0x5C, dexMagic = 0x1A, dexOrder = 0x18, dexMode = 0x19 },
}

local function s16(s, o) local v = w(s, o); return v >= 32768 and v - 65536 or v end

local function bitList(s, off, nbytes)
  local out = {}
  for i = 0, nbytes * 8 - 1 do
    if math.floor(b(s, off + math.floor(i / 8)) / 2 ^ (i % 8)) % 2 == 1 then out[#out + 1] = i end
  end
  return out
end

function D.warp(s, o)
  local wid = b(s, o + 2)
  return { group = b(s, o), num = b(s, o + 1), warpId = wid >= 128 and wid - 256 or wid, x = s16(s, o + 4), y = s16(s, o + 6) }
end

function D.fullMon(raw, party)
  local m = D.mon(raw)
  if not m then return nil end
  local pid, otid = d(raw, 0), d(raw, 4)
  local key = bit.bxor(pid, otid)
  local plainParts = {}
  for i = 0, 11 do
    local v = x32(d(raw, 0x20 + i * 4), key)
    plainParts[#plainParts + 1] = string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216))
  end
  local plain = table.concat(plainParts)
  local at = {}
  local order = ORDER[pid % 24 + 1]
  for i = 1, 4 do at[order:sub(i, i)] = (i - 1) * 12 end
  m.nickText, m.otText = D.text(raw, 8, 10), D.text(raw, 0x14, 7)
  m.language, m.markings = b(raw, 0x12), b(raw, 0x1B)
  m.ppBonuses, m.friendship = b(plain, at.G + 8), b(plain, at.G + 9)
  m.pp, m.evs, m.contest = {}, {}, {}
  for i = 0, 3 do m.pp[i + 1] = b(plain, at.A + 8 + i) end
  for i = 0, 5 do m.evs[i + 1] = b(plain, at.E + i); m.contest[i + 1] = b(plain, at.E + 6 + i) end
  m.pokerus, m.metLocation = b(plain, at.M), b(plain, at.M + 1)
  local origins = w(plain, at.M + 2)
  m.metLevel, m.metGame = origins % 128, math.floor(origins / 128) % 16
  m.ball, m.otGender = math.floor(origins / 2048) % 16, math.floor(origins / 32768) % 2
  m.ivs = {}
  for i = 0, 5 do m.ivs[i + 1] = math.floor(m.ivWord / 2 ^ (5 * i)) % 32 end
  m.ability = math.floor(m.ivWord / 2 ^ 31) % 2
  m.ribbons = d(plain, at.M + 8)
  if party then
    m.status, m.level, m.mail = d(raw, 80), b(raw, 84), b(raw, 85)
    m.hp, m.maxHp = w(raw, 86), w(raw, 88)
    m.stats = {}
    for i = 1, 5 do m.stats[i] = w(raw, 88 + i * 2) end
  end
  return m
end

function D.deep(s, family)
  local blk = D.blocks(s, family)
  if not blk then return nil end
  local O, F = D.OFF[family], D.FULL[family]
  local key = d(blk.sb2, O.key)
  local out = {
    key = key, counter = blk.counter, slot = blk.slot,
    name = D.text(blk.sb2, 0, 8), gender = b(blk.sb2, 8), specialSaveWarpFlags = b(blk.sb2, 9),
    tid = w(blk.sb2, 0x0A), sid = w(blk.sb2, 0x0C),
    playHours = w(blk.sb2, 0x0E), playMinutes = b(blk.sb2, 0x10), playSeconds = b(blk.sb2, 0x11), playVBlanks = b(blk.sb2, 0x12),
    buttonMode = b(blk.sb2, 0x13), optionsWord = w(blk.sb2, 0x14),
    dexOrder = b(blk.sb2, F.dexOrder), dexMode = b(blk.sb2, F.dexMode), dexMagic = b(blk.sb2, F.dexMagic),
    dexOwned = bitList(blk.sb2, F.dexOwned, 52), dexSeen = bitList(blk.sb2, F.dexSeen, 52),
    dexSeen1 = bitList(blk.sb1, F.seen1, 52), dexSeen2 = bitList(blk.sb1, F.seen2, 52),
    gcnLinkFlags = d(blk.sb2, 0xA8),
    posX = s16(blk.sb1, 0), posY = s16(blk.sb1, 2),
    location = D.warp(blk.sb1, 4), continueGameWarp = D.warp(blk.sb1, 12), dynamicWarp = D.warp(blk.sb1, 20),
    lastHealLocation = D.warp(blk.sb1, 28), escapeWarp = D.warp(blk.sb1, 36),
    savedMusic = w(blk.sb1, 44), weather = b(blk.sb1, 46), flashLevel = b(blk.sb1, 48), mapLayoutId = w(blk.sb1, 50),
    money = x32(d(blk.sb1, O.money), key), coins = bit.bxor(w(blk.sb1, O.coins), key % 65536) % 65536,
    registeredItem = w(blk.sb1, F.regItem),
    flagsSet = bitList(blk.sb1, F.flags, F.flagBytes), vars = {}, stats = {},
    pcItems = {}, pockets = {}, party = {}, boxes = {}, wallpapers = {}, boxNames = {}, currentBox = b(blk.storage, 0),
    profile = {}, mail = {},
  }
  out.powder = x32(d(blk.sb2, O.powder), key)
  for i = 0, 255 do out.vars[0x4000 + i] = w(blk.sb1, F.vars + i * 2) end
  for i = 0, 63 do out.stats[i] = x32(d(blk.sb1, O.stats + i * 4), key) end
  for i = 0, F.pcItems[2] - 1 do
    local id = w(blk.sb1, F.pcItems[1] + i * 4)
    if id ~= 0 then out.pcItems[#out.pcItems + 1] = { id, w(blk.sb1, F.pcItems[1] + i * 4 + 2) } end
  end
  for p, pk in ipairs(O.pockets) do
    out.pockets[p] = {}
    for i = 0, pk[2] - 1 do
      local id = w(blk.sb1, pk[1] + i * 4)
      if id ~= 0 then out.pockets[p][#out.pockets[p] + 1] = { id, bit.bxor(w(blk.sb1, pk[1] + i * 4 + 2), key % 65536) % 65536 } end
    end
  end
  for i = 0, 5 do out.profile[i + 1] = w(blk.sb1, F.profile + i * 2) end
  for i = 0, math.min(b(blk.sb1, O.partyCount), 6) - 1 do
    out.party[i + 1] = D.fullMon(blk.sb1:sub(O.party + i * 100 + 1, O.party + i * 100 + 100), true)
  end
  for bx = 0, 13 do
    out.boxes[bx + 1] = {}
    for sl = 0, 29 do
      local o = 4 + (bx * 30 + sl) * 80
      local m = D.fullMon(blk.storage:sub(o + 1, o + 80), false)
      if m and math.floor(m.flags / 2) % 2 == 1 then out.boxes[bx + 1][sl + 1] = m end
    end
    out.wallpapers[bx + 1] = b(blk.storage, 0x83C2 + bx)
    out.boxNames[bx + 1] = D.text(blk.storage, 0x8344 + bx * 9, 9)
  end
  for i = 0, 15 do
    local o = F.mail + i * 36
    local words = {}
    for k = 0, 8 do words[k + 1] = w(blk.sb1, o + k * 2) end
    out.mail[i + 1] = { words = words, name = D.text(blk.sb1, o + 18, 8), trainerId = d(blk.sb1, o + 26),
      species = w(blk.sb1, o + 30), itemId = w(blk.sb1, o + 32) }
  end
  out.roamer = { ivs = d(blk.sb1, F.roamer), pid = d(blk.sb1, F.roamer + 4), species = w(blk.sb1, F.roamer + 8),
    hp = w(blk.sb1, F.roamer + 10), level = b(blk.sb1, F.roamer + 12), status = b(blk.sb1, F.roamer + 13) }
  return out
end

D.EXTRA = {
  frlg = { daycare = 0x2F80, offspringSize = 2, stepCounter = 0x11A, route5 = 0x3C98, roamerSize = 0x14,
    rival = 0x3A4C, dexUnown = 0x1C, dexSpinda = 0x20, battleStart = 0x2CAC, registeredTexts = 0x3AD4,
    gcn = 0xA8, flash = 0x30, weather = 0x2E, savedMusic = 0x2C },
  emerald = { daycare = 0x3030, offspringSize = 4, stepCounter = 0x11C, route5 = nil, roamerSize = 0x14,
    rival = nil, dexUnown = 0x1C, dexSpinda = 0x20, battleStart = 0x2BBC, registeredTexts = 0x3C88,
    gcn = 0xA8, flash = 0x30, weather = 0x2E, savedMusic = 0x2C },
}

local function rawBytes(s, off, n)
  local out = {}
  for i = 0, n - 1 do out[i + 1] = b(s, off + i) end
  return out
end
D.rawBytes = rawBytes

local function mailAt(s, o)
  local words = {}
  for k = 0, 8 do words[k + 1] = w(s, o + k * 2) end
  return { words = words, name = D.text(s, o + 18, 8), trainerId = d(s, o + 26), species = w(s, o + 30), itemId = w(s, o + 32) }
end
D.mailAt = mailAt

local function daycareMon(sb1, o)
  local m = D.fullMon(sb1:sub(o + 1, o + 80), false)
  return {
    mon = m,
    mail = mailAt(sb1, o + 80),
    otName = D.text(sb1, o + 80 + 36, 8),
    monName = D.text(sb1, o + 80 + 44, 11),
    steps = d(sb1, o + 0x88),
  }
end

function D.extra(s, family)
  local blk = D.blocks(s, family)
  if not blk then return nil end
  local X = D.EXTRA[family]
  local out = {
    unownPersonality = d(blk.sb2, X.dexUnown), spindaPersonality = d(blk.sb2, X.dexSpinda),
    gcnLinkFlags = d(blk.sb2, X.gcn), flashLevel = b(blk.sb1, X.flash), weather = b(blk.sb1, X.weather),
    daycare = {}, roamer = nil, hof = {},
  }
  if X.rival then out.rivalName = D.text(blk.sb1, X.rival, 8) end
  for i = 0, 1 do out.daycare[i + 1] = daycareMon(blk.sb1, X.daycare + i * 0x8C) end
  out.offspringPersonality = X.offspringSize == 4 and d(blk.sb1, X.daycare + 0x118) or w(blk.sb1, X.daycare + 0x118)
  out.daycareStepCounter = b(blk.sb1, X.daycare + X.stepCounter)
  if X.route5 then out.route5 = daycareMon(blk.sb1, X.route5) end
  local F = D.FULL[family]
  out.roamerRaw = rawBytes(blk.sb1, F.roamer, X.roamerSize)
  out.battleWords = {}
  for i = 0, 17 do out.battleWords[i + 1] = w(blk.sb1, X.battleStart + i * 2) end
  local hofParts = {}
  for _, sector in ipairs({ 28, 29 }) do
    hofParts[#hofParts + 1] = s:sub(sector * 0x1000 + 1, sector * 0x1000 + 0xF80)
  end
  local hof = table.concat(hofParts)
  out.hofSignatureOk = d(s, 28 * 0x1000 + 0xFF8) == 0x08012025 and d(s, 29 * 0x1000 + 0xFF8) == 0x08012025
  out.hofChecksumOk = out.hofSignatureOk and w(s, 28 * 0x1000 + 0xFF4) == sum(s, 28 * 0x1000, 0xF80)
    and w(s, 29 * 0x1000 + 0xFF4) == sum(s, 29 * 0x1000, 0xF80)
  out.registeredTexts = {}
  for i = 0, 9 do out.registeredTexts[i + 1] = D.text(blk.sb1, X.registeredTexts + i * 21, 21) end
  for t = 0, out.hofSignatureOk and 49 or -1 do
    local team = {}
    for i = 0, 5 do
      local o = (t * 6 + i) * 20
      local sl = w(hof, o + 8)
      if sl % 512 == 0 then break end
      team[#team + 1] = { tid = d(hof, o), personality = d(hof, o + 4), species = sl % 512,
        level = math.floor(sl / 512), nick = D.text(hof, o + 10, 10) }
    end
    if #team == 0 then break end
    out.hof[#out.hof + 1] = team
  end
  return out
end

function D.diff(a, b2)
  local out = {}
  local function walk(x, y, path)
    if type(x) ~= type(y) then out[#out + 1] = path return end
    if type(x) ~= "table" then
      if x ~= y then out[#out + 1] = path end
      return
    end
    for k, v in pairs(x) do walk(v, y[k], path .. "." .. tostring(k)) end
    for k in pairs(y) do if x[k] == nil then out[#out + 1] = path .. "." .. tostring(k) end end
  end
  walk(a, b2, "")
  return out
end

return D
