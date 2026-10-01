local bit = require("bit")
local B = require("tests.fixtures.save.bytes")
local Compat = require("src.save_convert.Compat")

local G3 = {}

G3.SIZE = 0x20000

G3.CHUNKS = {
  frlg = { [0] = 0xF24, 0xF80, 0xF80, 0xF80, 0xEE8, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0x7D0 },
  emerald = { [0] = 0xF2C, 0xF80, 0xF80, 0xF80, 0xF08, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0x7D0 },
}

G3.F = {
  frlg = { key = 0xF20, powder = 0xAF8, party = 0x38, partyCount = 0x34, money = 0x290, coins = 0x294,
           pcItems = { 0x298, 30 }, pockets = { { 0x310, 42 }, { 0x3B8, 30 }, { 0x430, 13 }, { 0x464, 58 }, { 0x54C, 43 } },
           dexSeen = { 0x5F8, 0x3A18 }, gameStats = 0x1200 },
  emerald = { key = 0xAC, powder = 0x1F4, party = 0x238, partyCount = 0x234, money = 0x490, coins = 0x494,
              pcItems = { 0x498, 50 }, pockets = { { 0x560, 30 }, { 0x5D8, 30 }, { 0x650, 16 }, { 0x690, 64 }, { 0x790, 46 } },
              dexSeen = { 0x988, 0x3B24 }, gameStats = 0x159C },
}

local ORDERS = {
  "GAEM", "GAME", "GEAM", "GEMA", "GMAE", "GMEA", "AGEM", "AGME", "AEGM", "AEMG", "AMGE", "AMEG",
  "EGAM", "EGMA", "EAGM", "EAMG", "EMGA", "EMAG", "MGAE", "MGEA", "MAGE", "MAEG", "MEGA", "MEAG",
}

function G3.text(s, len)
  local out = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    local v
    if c:match("%u") then v = 0xBB + c:byte() - 65
    elseif c:match("%l") then v = 0xD5 + c:byte() - 97
    elseif c:match("%d") then v = 0xA1 + c:byte() - 48
    elseif c == " " then v = 0x00
    else v = 0xAC end
    out[i] = v
  end
  out[#out + 1] = 0xFF
  while #out < len do out[#out + 1] = 0xFF end
  return out
end

local function u32(x) return x % 4294967296 end

function G3.mon(o)
  local m = {
    pid = 0x12345678, tid = 0x1234, sid = 0x5678, nick = "MON", lang = 2, egg = false, badEgg = false,
    ot = "RED", markings = 0, species = 4, item = 0, exp = 135, ppBonuses = 0, friendship = 70,
    moves = { 10, 45, 0, 0 }, pp = { 35, 40, 0, 0 }, evs = { 0, 0, 0, 0, 0, 0 }, contest = { 0, 0, 0, 0, 0, 0 },
    pokerus = 0, metLocation = 88, origins = 5 + 4 * 128 + 4 * 2048, ivs = { 1, 2, 3, 4, 5, 6 }, ability = 0,
    ribbons = 0, status = 0, level = 5, hp = 20, maxHp = 20, stats = { 11, 10, 12, 11, 10 }, mail = 0xFF,
    breakChecksum = false,
  }
  for k, v in pairs(o or {}) do m[k] = v end
  return m
end

function G3.encodeMon(m, party)
  local b = B.new(party and 100 or 80, 0)
  B.le(b, 0, m.pid, 4)
  B.le(b, 4, m.tid + m.sid * 65536, 4)
  local nick = G3.text(m.nick, 10)
  for i = 1, 10 do b[7 + i] = nick[i] end
  b[0x12] = m.lang
  b[0x13] = (m.badEgg and 1 or 0) + 2 + (m.egg and 4 or 0)
  local ot = G3.text(m.ot, 7)
  for i = 1, 7 do b[0x13 + i] = ot[i] end
  b[0x1B] = m.markings
  local sub = { G = B.new(12, 0), A = B.new(12, 0), E = B.new(12, 0), M = B.new(12, 0) }
  B.le(sub.G, 0, m.species, 2); B.le(sub.G, 2, m.item, 2); B.le(sub.G, 4, m.exp, 4)
  B.put(sub.G, 8, m.ppBonuses, m.friendship)
  for i = 1, 4 do B.le(sub.A, (i - 1) * 2, m.moves[i], 2); B.put(sub.A, 7 + i, m.pp[i]) end
  for i = 1, 6 do B.put(sub.E, i - 1, m.evs[i]); B.put(sub.E, 5 + i, m.contest[i]) end
  B.put(sub.M, 0, m.pokerus, m.metLocation)
  B.le(sub.M, 2, m.origins, 2)
  local iv = 0
  for i = 1, 6 do iv = iv + m.ivs[i] * 2 ^ ((i - 1) * 5) end
  iv = iv + (m.egg and 2 ^ 30 or 0) + (m.ability == 1 and 2 ^ 31 or 0)
  B.le(sub.M, 4, iv, 4)
  B.le(sub.M, 8, m.ribbons, 4)
  local order = ORDERS[m.pid % 24 + 1]
  local plain = B.new(48, 0)
  for i = 1, 4 do
    local s = sub[order:sub(i, i)]
    for k = 0, 11 do plain[(i - 1) * 12 + k] = s[k] end
  end
  local sum = 0
  for i = 0, 47, 2 do sum = (sum + plain[i] + plain[i + 1] * 256) % 65536 end
  if m.breakChecksum then sum = (sum + 1) % 65536 end
  B.le(b, 0x1C, sum, 2)
  local key = u32(bit.bxor(m.pid, m.tid + m.sid * 65536))
  for i = 0, 11 do
    local w = B.getLE(plain, i * 4, 4)
    B.le(b, 0x20 + i * 4, u32(bit.bxor(w, key)), 4)
  end
  if party then
    B.le(b, 80, m.status, 4)
    B.put(b, 84, m.level, m.mail)
    B.le(b, 86, m.hp, 2); B.le(b, 88, m.maxHp, 2)
    for i = 1, 5 do B.le(b, 88 + i * 2, m.stats[i], 2) end
  end
  local out = {}
  for i = 0, b.size - 1 do out[i + 1] = b[i] end
  return out
end

local function unrle(s)
  local out = {}
  for tok in s:gmatch("%S+") do
    local k, n = tok:match("^([ZF])(%x+)$")
    if k then out[#out + 1] = string.rep(k == "Z" and "\0" or "\255", tonumber(n, 16))
    else out[#out + 1] = (tok:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end)) end
  end
  return table.concat(out)
end

local BASES = {
  firered = { "tests.fixture_data.gen3_saves", "fr_rich_game", "frlg" },
  leafgreen = { "tests.fixture_data.gen3_saves", "lg_rich_game", "frlg" },
  emerald = { "tests.fixture_data.gen3_saves_emerald", "em_fresh", "emerald" },
}

function G3.base(version)
  local spec = BASES[version]
  local image = unrle(require(spec[1]).images[spec[2]])
  local family = spec[3]
  local blocks = assert(Compat.gen3Blocks(image, family))
  local w = {
    version = version, family = family, F = G3.F[family], trailer = image:sub(G3.SIZE + 1),
    image = B.fromString(image:sub(1, G3.SIZE)), at = blocks.slots[blocks.slot].at,
    sb2 = B.fromString(blocks.sb2), sb1 = B.fromString(blocks.sb1), storage = B.fromString(blocks.storage),
  }
  w.key = B.getLE(w.sb2, w.F.key, 4)
  return w
end

function G3.setMoney(w, money)
  B.le(w.sb1, w.F.money, u32(bit.bxor(money, w.key)), 4)
end

function G3.setPocket(w, which, list)
  local p = w.F.pockets[which]
  B.fill(w.sb1, p[1], p[2] * 4, 0)
  for i, it in ipairs(list) do
    B.le(w.sb1, p[1] + (i - 1) * 4, it[1], 2)
    B.le(w.sb1, p[1] + (i - 1) * 4 + 2, bit.bxor(it[2], w.key % 65536) % 65536, 2)
  end
end

function G3.setParty(w, mons)
  B.put(w.sb1, w.F.partyCount, #mons)
  B.fill(w.sb1, w.F.party, 600, 0)
  -- src/pokemon.c:1737
  for i = #mons + 1, 6 do w.sb1[w.F.party + (i - 1) * 100 + 85] = 0xFF end
  for i, m in ipairs(mons) do
    local bytes = G3.encodeMon(m, true)
    for k = 1, 100 do w.sb1[w.F.party + (i - 1) * 100 + k - 1] = bytes[k] end
  end
end

function G3.setBoxMon(w, box, slot, m)
  local at = 4 + ((box - 1) * 30 + slot - 1) * 80
  if not m then B.fill(w.storage, at, 80, 0) return end
  local bytes = G3.encodeMon(m, false)
  for k = 1, 80 do w.storage[at + k - 1] = bytes[k] end
end

function G3.setDexAll(w)
  for i = 0, 385 do
    B.setBit(w.sb2, 0x28, i, true)
    B.setBit(w.sb2, 0x5C, i, true)
    B.setBit(w.sb1, w.F.dexSeen[1], i, true)
    B.setBit(w.sb1, w.F.dexSeen[2], i, true)
  end
end

local function writeChunk(w, id, src, srcOff)
  local off = w.at[id]
  local size = G3.CHUNKS[w.family][id]
  for k = 0, size - 1 do w.image[off + k] = src[srcOff + k] end
  for k = size, 0xF7F do w.image[off + k] = 0 end
  local s = {}
  for k = 0, 0xF7F do s[k + 1] = string.char(w.image[off + k]) end
  B.le(w.image, off + 0xFF6, Compat.gen3SectorChecksum(table.concat(s), 0, size), 2)
end

function G3.emit(w, keepTrailer)
  writeChunk(w, 0, w.sb2, 0)
  local pos = 0
  for id = 1, 4 do writeChunk(w, id, w.sb1, pos); pos = pos + G3.CHUNKS[w.family][id] end
  pos = 0
  for id = 5, 13 do writeChunk(w, id, w.storage, pos); pos = pos + G3.CHUNKS[w.family][id] end
  if not keepTrailer then return B.pack(w.image) end
  return B.pack(w.image) .. (w.trailer ~= "" and w.trailer or string.rep("\0", 16))
end

function G3.writeHof(w, teams)
  local buf = B.new(0x2000, 0)
  for t = 0, teams - 1 do
    for s = 0, 5 do
      local at = t * 120 + s * 20
      B.le(buf, at, 0x1234 + 0x56780000, 4)
      B.le(buf, at + 4, 0x9ABC0000 + t * 6 + s, 4)
      B.le(buf, at + 8, (s + 1) + 5 * 512, 2)
      local nick = G3.text("HOF" .. s, 10)
      for k = 1, 10 do buf[at + 9 + k] = nick[k] end
    end
  end
  for half = 0, 1 do
    local off = 0x1C000 + half * 0x1000
    for k = 0, 0xF7F do w.image[off + k] = buf[half * 0xF80 + k] or 0 end
    for k = 0xF80, 0xFFF do w.image[off + k] = 0 end
    local s = {}
    for k = 0, 0xF7F do s[k + 1] = string.char(w.image[off + k]) end
    local ck = Compat.gen3SectorChecksum(table.concat(s), 0, 0xF80)
    B.le(w.image, off + 0xFF4, ck, 2)
    B.le(w.image, off + 0xFF6, ck, 2)
    B.le(w.image, off + 0xFF8, 0x08012025, 4)
  end
end

local function boxMon(i, family)
  return G3.mon({ pid = 0x01000193 * i % 4294967296, species = (i % 250) + 1, nick = "B" .. (i % 1000),
    exp = 100 + i, friendship = 70, tid = 0x1234, sid = 0x5678, ivs = { i % 32, (i * 3) % 32, 1, 2, 3, 4 },
    origins = 5 + (family == "emerald" and 3 or 4) * 128 + 4 * 2048 })
end

function G3.cases()
  local C = {}
  local function add(id, version, fn, extra)
    local w = G3.base(version)
    local keep = fn and fn(w)
    local c = { id = id, gen = 3, version = version, bytes = G3.emit(w, keep == "trailer") }
    for k, v in pairs(extra or {}) do c[k] = v end
    C[#C + 1] = c
  end
  for _, v in ipairs({ "firered", "leafgreen", "emerald" }) do
    local p = "g3." .. v .. "."
    C[#C + 1] = { id = p .. "fresh_cart", gen = 3, version = v, refuse = true, bytes = string.rep("\255", G3.SIZE) }
    add(p .. "basic", v, nil)
    add(p .. "full_party_statuses", v, function(w)
      local statuses = { 0, 3, 0x08, 0x10, 0x20, 0x40 }
      local mons = {}
      for i = 1, 6 do
        mons[i] = G3.mon({ pid = 0x0F0F0000 + i * 977, status = statuses[i], nick = "P" .. i, level = 30 + i,
          species = 1 + i * 3, pokerus = i == 2 and 0x13 or 0 })
      end
      G3.setParty(w, mons)
    end)
    add(p .. "toxic_counter", v, function(w)
      G3.setParty(w, { G3.mon({ status = 0x80 + 3 * 256, nick = "TOXIC" }) })
    end)
    add(p .. "full_boxes", v, function(w)
      for b = 1, 14 do for s = 1, 30 do G3.setBoxMon(w, b, s, boxMon(b * 30 + s, w.family)) end end
      w.storage[0] = 13
    end)
    add(p .. "eggs", v, function(w)
      G3.setParty(w, { G3.mon(), G3.mon({ pid = 0x2222, egg = true, nick = "EGG", friendship = 20, species = 172 }) })
      G3.setBoxMon(w, 3, 7, G3.mon({ pid = 0x3333, egg = true, nick = "EGG", friendship = 5, species = 175 }))
    end)
    add(p .. "bad_checksum_mon", v, function(w)
      G3.setBoxMon(w, 2, 1, G3.mon({ pid = 0x4444, breakChecksum = true }))
    end)
    add(p .. "hoenn_species", v, function(w)
      G3.setBoxMon(w, 1, 30, G3.mon({ pid = 0x5555, species = 300, nick = "HOENN" }))
    end)
    add(p .. "foreign_species", v, function(w)
      G3.setBoxMon(w, 1, 29, G3.mon({ pid = 0x6666, species = 500, nick = "HACK" }))
    end)
    add(p .. "max_stacks", v, function(w)
      local list = {}
      for i = 1, #w.F.pockets do
        list = {}
        for k = 1, w.F.pockets[i][2] do list[k] = { 13 + k, 999 } end
        G3.setPocket(w, i, list)
      end
      G3.setMoney(w, 999999)
    end)
    add(p .. "all_dex", v, G3.setDexAll)
    add(p .. "box_index_0", v, function(w) w.storage[0] = 0 end)
    add(p .. "wallpaper_collision", v, function(w) w.storage[0x83C2 + 4] = 4 end)
    add(p .. "hall_of_fame", v, function(w) G3.writeHof(w, 50) end)
    add(p .. "trailer", v, function() return "trailer" end)
  end
  return C
end

return G3
