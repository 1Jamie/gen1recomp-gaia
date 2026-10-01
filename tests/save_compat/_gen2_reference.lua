local R = {}

local OFF = {
  gs = { time = 0x2053, money = 0x23DB, badges = 0x23E4, curBox = 0x2724, boxNames = 0x2727,
         party = 0x288A, caught = 0x2A4C, seen = 0x2A6C, active = 0x2D6C, sumEnd = 0x2D68,
         sum1 = 0x2D69, sum2 = 0x7E6D, tmhm = 0x23E6, item = 0x241F, key = 0x2449, ball = 0x2464,
         pc = 0x247E, event = 0x261F },
  crystal = { time = 0x2052, money = 0x23DC, badges = 0x23E5, curBox = 0x2700, boxNames = 0x2703,
              party = 0x2865, caught = 0x2A27, seen = 0x2A47, active = 0x2D10, sumEnd = 0x2B82,
              sum1 = 0x2D0D, sum2 = 0x1F0D, tmhm = 0x23E7, item = 0x2420, key = 0x244A, ball = 0x2465,
              pc = 0x247F, event = 0x2600, gender = 0x3E3D },
}

local CHARS = {}
for i = 0, 25 do
  CHARS[0x80 + i] = string.char(65 + i)
  CHARS[0xA0 + i] = string.char(97 + i)
end
for i = 0, 9 do CHARS[0xF6 + i] = string.char(48 + i) end
CHARS[0x7F], CHARS[0xE3], CHARS[0xE6], CHARS[0xE7], CHARS[0xE8] = " ", "-", "?", "!", "."
CHARS[0xE0], CHARS[0xE1], CHARS[0xE2], CHARS[0xEF], CHARS[0xF5] = "'", "PK", "MN", "♂", "♀"

local function byte(s, o) return s:byte(o + 1) or 0 end
local function beN(s, o, n)
  local v = 0
  for i = 0, n - 1 do v = v * 256 + byte(s, o + i) end
  return v
end

function R.text(s, o, n)
  local out = {}
  for i = 0, n - 1 do
    local c = byte(s, o + i)
    if c == 0x50 then break end
    out[#out + 1] = CHARS[c] or ("<%02X>"):format(c)
  end
  return table.concat(out)
end

local function list(s, at, cap, size)
  local count = byte(s, at)
  local out = { count = count, mons = {} }
  if count > cap then return out end
  local monsAt = at + 2 + cap
  local otAt = monsAt + cap * size
  local nickAt = otAt + cap * 11
  for i = 0, count - 1 do
    local o = monsAt + i * size
    local m = {
      listed = byte(s, at + 1 + i), species = byte(s, o), item = byte(s, o + 1),
      moves = { byte(s, o + 2), byte(s, o + 3), byte(s, o + 4), byte(s, o + 5) },
      otId = beN(s, o + 6, 2), exp = beN(s, o + 8, 3),
      dvAtk = math.floor(byte(s, o + 0x15) / 16), dvDef = byte(s, o + 0x15) % 16,
      dvSpe = math.floor(byte(s, o + 0x16) / 16), dvSpc = byte(s, o + 0x16) % 16,
      friendship = byte(s, o + 0x1B), pokerus = byte(s, o + 0x1C), level = byte(s, o + 0x1F),
      pp = { byte(s, o + 0x17), byte(s, o + 0x18), byte(s, o + 0x19), byte(s, o + 0x1A) },
      statExp = { beN(s, o + 0x0B, 2), beN(s, o + 0x0D, 2), beN(s, o + 0x0F, 2), beN(s, o + 0x11, 2), beN(s, o + 0x13, 2) },
      caught = beN(s, o + 0x1D, 2),
      ot = R.text(s, otAt + i * 11, 11), nick = R.text(s, nickAt + i * 11, 11),
    }
    if size == 48 then
      m.hp, m.maxHp = beN(s, o + 0x22, 2), beN(s, o + 0x24, 2)
      m.status = byte(s, o + 0x20)
      m.stats = { beN(s, o + 0x26, 2), beN(s, o + 0x28, 2), beN(s, o + 0x2A, 2), beN(s, o + 0x2C, 2), beN(s, o + 0x2E, 2) }
    end
    out.mons[#out.mons + 1] = m
  end
  return out
end

local function pocket(s, at, cap, pairs_)
  local out = {}
  local n = byte(s, at)
  if n > cap then n = cap end
  for i = 0, n - 1 do
    local id = byte(s, at + 1 + i * (pairs_ and 2 or 1))
    if id == 0 or id == 0xFF then break end
    out[#out + 1] = { id, pairs_ and byte(s, at + 2 + i * 2) or 1 }
  end
  return out
end

function R.decode(s, version)
  local which = version == "crystal" and "crystal" or "gs"
  local O = OFF[which]
  local sum = 0
  for i = 0x2009, O.sumEnd do sum = (sum + byte(s, i)) % 65536 end
  local stored1 = byte(s, O.sum1) + byte(s, O.sum1 + 1) * 256
  local stored2 = byte(s, O.sum2) + byte(s, O.sum2 + 1) * 256
  local out = {
    checksum1 = sum == stored1, checksum2 = sum == stored2,
    id = beN(s, 0x2009, 2), name = R.text(s, 0x200B, 11), rival = R.text(s, 0x2021, 11),
    money = beN(s, O.money, 3), johto = byte(s, O.badges), kanto = byte(s, O.badges + 1),
    curBox = byte(s, O.curBox) < 14 and byte(s, O.curBox) + 1 or 1,
    hours = beN(s, O.time, 2), minutes = byte(s, O.time + 2), seconds = byte(s, O.time + 3),
    frames = byte(s, O.time + 4),
    party = list(s, O.party, 6, 48), boxes = {}, boxNames = {},
    items = pocket(s, O.item, 20, true), keys = pocket(s, O.key, 25, false),
    balls = pocket(s, O.ball, 12, true), pc = pocket(s, O.pc, 50, true), tms = {},
    caught = 0, seen = 0, events = {},
  }
  for i = 0, 13 do
    local base = i < 7 and (0x4000 + i * 0x450) or (0x6000 + (i - 7) * 0x450)
    out.boxes[i + 1] = list(s, base, 20, 32)
    out.boxNames[i + 1] = R.text(s, O.boxNames + i * 9, 9)
  end
  for i = 0, 56 do out.tms[i + 1] = byte(s, O.tmhm + i) end
  for i = 0, 250 do
    local mask = 2 ^ (i % 8)
    if math.floor(byte(s, O.caught + math.floor(i / 8)) / mask) % 2 == 1 then out.caught = out.caught + 1 end
    if math.floor(byte(s, O.seen + math.floor(i / 8)) / mask) % 2 == 1 then out.seen = out.seen + 1 end
  end
  for i = 0, 255 do out.events[i] = byte(s, O.event + i) end
  if O.gender then out.female = byte(s, O.gender) % 2 == 1 end
  out.coins = beN(s, O.money + (which == "gs" and 7 or 7), 2)
  out.options = { byte(s, 0x2000), byte(s, 0x2001), byte(s, 0x2002), byte(s, 0x2003), byte(s, 0x2004), byte(s, 0x2005) }
  return out
end

return R
