package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local H = require("tests.save_compat._gen3_sections")
local G3 = require("tests.fixtures.save.gen3_build")
local B = require("tests.fixtures.save.bytes")
local MysteryGift = require("src.core.game3.mystery_gift")
local VsSeeker = require("src.core.game3.vs_seeker")
local Tower = require("src.core.game3.trainer_tower")
local bit = require("bit")

local FRLG = { "firered", "leafgreen" }
local ALL = { "firered", "leafgreen", "emerald" }
local SEEDS = 50
local U32 = 4294967296

local VS, VS_SIZE = 0x638, 102
local TOWER, TOWER_SIZE = 0x3D34, 52
local MG_SIZE, RS_SIZE = 0x36C, 1004
local MG_AT = { firered = { 0x3120, 0x361C }, leafgreen = { 0x3120, 0x361C }, emerald = { 0x322C, 0x3728 } }
local KEY_OFF = { firered = 0xF20, leafgreen = 0xF20, emerald = 0xAC }
local MAX_TIME = 215999

local function crcBitwise(s)
  local crc = 0x1121
  for i = 1, #s do
    crc = bit.bxor(crc, s:byte(i))
    for _ = 1, 8 do
      if bit.band(crc, 1) == 1 then crc = bit.bxor(bit.rshift(crc, 1), 0x8408) else crc = bit.rshift(crc, 1) end
    end
  end
  return bit.band(bit.bnot(crc), 0xFFFF)
end

local function rnd32(rng) return rng(65536) * 65536 + rng(65536) end
local function g8(s, o) return s:byte(o + 1) end
local function g16(s, o) return s:byte(o + 1) + s:byte(o + 2) * 256 end
local function g32(s, o) return g16(s, o) + g16(s, o + 2) * 65536 end

local function sub(s, o, n) return s:sub(o + 1, o + n) end
local function arrStr(a, o, n)
  local t = {}
  for i = 0, n - 1 do t[i + 1] = string.char(a[o + i]) end
  return table.concat(t)
end

local function changed(a, b)
  local out = {}
  for i = 1, #a do if a:byte(i) ~= b:byte(i) then out[#out + 1] = i - 1 end end
  return out
end

local function within(list, lo, hi)
  for _, o in ipairs(list) do if o < lo or o >= hi then return false, o end end
  return true
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = copy(x) end
  return o
end

local function codecOf(v) return H.codec(v) end

local GOOD
local function goodCodes(v)
  if GOOD then return GOOD end
  local c = codecOf(v)
  GOOD = {}
  for code = 0, 0xF6 do
    local s = string.char(code, 0xFF)
    local d = c.decodeString(s, 0, 2)
    if d ~= "" and not d:find("{", 1, true) and c.encodeString(d, 2, 0xFF) == s then GOOD[#GOOD + 1] = code end
  end
  return GOOD
end

local function randText(rng, v, max)
  local codes, c = goodCodes(v), codecOf(v)
  while true do
    local n = rng(max + 1)
    local t = {}
    for i = 1, n do t[i] = codes[rng(#codes) + 1] end
    local s = {}
    for i = 1, n do s[i] = string.char(t[i]) end
    local raw = table.concat(s)
    local str = c.decodeString(raw .. "\255", 0, n + 1)
    if c.encodeString(str, max, 0xFF):sub(1, n) == raw then return t, str end
  end
end

local function putText(a, o, codes, len, rng)
  for i = 0, len - 1 do a[o + i] = rng(256) end
  for i, code in ipairs(codes) do a[o + i - 1] = code end
  if #codes < len then a[o + #codes] = 0xFF end
end

local function readText(v, s, o, len) return codecOf(v).decodeString(s, o, len) end

local function decodeNews(v, s, o)
  local n = { id = g16(s, o), sendType = g8(s, o + 2), bgType = g8(s, o + 3), titleText = readText(v, s, o + 4, 40), bodyText = {} }
  for i = 1, 10 do n.bodyText[i] = readText(v, s, o + 44 + (i - 1) * 40, 40) end
  return n
end

local function decodeCard(v, s, o)
  local b = g8(s, o + 8)
  local c = { flagId = g16(s, o), iconSpecies = g16(s, o + 2), idNumber = g32(s, o + 4), type = b % 4,
    bgType = math.floor(b / 4) % 16, sendType = math.floor(b / 64), maxStamps = g8(s, o + 9),
    titleText = readText(v, s, o + 10, 40), subtitleText = readText(v, s, o + 50, 40), bodyText = {},
    footerLine1Text = readText(v, s, o + 250, 40), footerLine2Text = readText(v, s, o + 290, 40) }
  for i = 1, 4 do c.bodyText[i] = readText(v, s, o + 90 + (i - 1) * 40, 40) end
  return c
end

local function decodeMeta(s, o)
  local m = { cardMetadataCrc = g32(s, o + 0x310), cardMetadata = { battlesWon = g16(s, o + 0x314),
    battlesLost = g16(s, o + 0x316), numTrades = g16(s, o + 0x318), iconSpecies = g16(s, o + 0x31A),
    stampData = { species = {}, ids = {} } }, questionnaireWords = {}, trainerIds = { {}, {} } }
  for i = 1, 7 do
    m.cardMetadata.stampData.species[i] = g16(s, o + 0x31C + (i - 1) * 2)
    m.cardMetadata.stampData.ids[i] = g16(s, o + 0x32A + (i - 1) * 2)
  end
  for i = 1, 4 do m.questionnaireWords[i] = g16(s, o + 0x338 + (i - 1) * 2) end
  local nb = g8(s, o + 0x340)
  m.newsMetadata = { newsType = nb % 4, sentRewardCounter = math.floor(nb / 4) % 8, rewardCounter = math.floor(nb / 32),
    berry = g8(s, o + 0x341) }
  for k = 1, 2 do for i = 1, 5 do m.trainerIds[k][i] = g32(s, o + 0x344 + ((k - 1) * 5 + i - 1) * 4) end end
  return m
end

local function decodeVs(s)
  local rem = {}
  for i = 0, 99 do if g8(s, VS + 2 + i) ~= 0 then rem[i] = g8(s, VS + 2 + i) end end
  return { steps = g8(s, VS), charging = g8(s, VS + 1), rematches = rem }
end

local function decodeTower(s, key)
  local t = { challengeId = g32(s, TOWER), records = {} }
  for i = 1, 4 do
    local o = TOWER + 4 + (i - 1) * 12
    local f = g8(s, o + 10)
    t.records[i] = { timer = g32(s, o), bestTime = bit.bxor(g32(s, o + 4), key) % U32, floorsCleared = g8(s, o + 8),
      setId = g8(s, o + 9), receivedPrize = f % 2 == 1, checkedFinalTime = math.floor(f / 2) % 2 == 1,
      spokeToOwner = math.floor(f / 4) % 2 == 1, hasLost = math.floor(f / 8) % 2 == 1,
      statusUnk = math.floor(f / 16) % 2 == 1, validated = math.floor(f / 32) % 2 == 1 }
  end
  return t
end

local function setCrc(a, crcOff, dataOff, n)
  B.le(a, crcOff, crcBitwise(arrStr(a, dataOff, n)), 4)
end

local function writeNews(a, o, rng, v)
  B.le(a, o + 4, rng(65535) + 1, 2)
  a[o + 6], a[o + 7] = rng(256), rng(256)
  putText(a, o + 8, (randText(rng, v, 40)), 40, rng)
  for i = 0, 9 do putText(a, o + 48 + i * 40, (randText(rng, v, 40)), 40, rng) end
  setCrc(a, o, o + 4, 444)
end

local function writeCard(a, o, r, rng, v)
  local c = o + 0x1C4
  B.le(a, c, rng(65535) + 1, 2)
  B.le(a, c + 2, rng(65536), 2)
  B.le(a, c + 4, rnd32(rng), 4)
  a[c + 8] = rng(3) + rng(8) * 4 + rng(3) * 64
  a[c + 9] = rng(8)
  for _, off in ipairs({ 10, 50, 90, 130, 170, 210, 250, 290 }) do putText(a, c + off, (randText(rng, v, 40)), 40, rng) end
  a[c + 330], a[c + 331] = rng(256), rng(256)
  setCrc(a, o + 0x1C0, c, 332)
  a[r + 4], a[r + 5], a[r + 6], a[r + 7] = 51, 0xFF, 0xFF, 0xFF
  for i = 8, 1002 do a[r + i] = rng(256) end
  a[r + 1003] = rng(256)
  setCrc(a, r, r + 4, 999)
end

local function writeMeta(a, o, rng)
  B.le(a, o + 0x310, rnd32(rng), 4)
  for i = 0, 17 do B.le(a, o + 0x314 + i * 2, rng(65536), 2) end
  for i = 0, 3 do B.le(a, o + 0x338 + i * 2, rng(65535) + 1, 2) end
  for i = 0, 3 do a[o + 0x340 + i] = rng(256) end
  for i = 0, 9 do B.le(a, o + 0x344 + i * 4, rnd32(rng), 4) end
end

local function randomCart(v, seed, tweak)
  local rng = H.rng(seed)
  return H.cart(v, function(w)
    local a = w.sb1
    local o, r = MG_AT[v][1], MG_AT[v][2]
    writeNews(a, o, rng, v)
    writeCard(a, o, r, rng, v)
    writeMeta(a, o, rng)
    if v ~= "emerald" then
      a[VS], a[VS + 1] = rng(256), rng(256)
      for i = 0, 99 do a[VS + 2 + i] = rng(3) == 0 and rng(256) or 0 end
      B.le(a, TOWER, rnd32(rng), 4)
      for i = 0, 3 do
        local t = TOWER + 4 + i * 12
        B.le(a, t, rnd32(rng), 4)
        B.le(a, t + 4, bit.bxor(rng(MAX_TIME + 1), w.key) % U32, 4)
        for k = 8, 11 do a[t + k] = rng(256) end
      end
    end
    if tweak then tweak(w) end
  end)
end

local function failures(list, label)
  check(#list == 0, label .. (#list > 0 and (": " .. list[1]) or ""))
end

local function regionsSame(a, b, v)
  local o, r = MG_AT[v][1], MG_AT[v][2]
  local bad = {}
  if sub(a.sb1, o, MG_SIZE) ~= sub(b.sb1, o, MG_SIZE) then bad[#bad + 1] = "mysteryGift" end
  if sub(a.sb1, r, RS_SIZE) ~= sub(b.sb1, r, RS_SIZE) then bad[#bad + 1] = "ramScript" end
  if v ~= "emerald" then
    if sub(a.sb1, VS, VS_SIZE) ~= sub(b.sb1, VS, VS_SIZE) then bad[#bad + 1] = "vsSeeker" end
    if sub(a.sb1, TOWER, TOWER_SIZE) ~= sub(b.sb1, TOWER, TOWER_SIZE) then bad[#bad + 1] = "trainerTower" end
  end
  return bad
end

local function sessionOf(save) return { modData = save.modData } end

for _, v in ipairs(ALL) do
  local o, r = MG_AT[v][1], MG_AT[v][2]
  local bad1, bad2, bad3 = {}, {}, {}
  for seed = 1, SEEDS do
    local cart = randomCart(v, seed * 7919 + #v)
    local src = H.blocks(cart, v)
    local save = H.import(v, cart)
    local out = H.withTemplate(v, save, cart)
    for _, name in ipairs(regionsSame(src, H.blocks(out, v), v)) do bad1[#bad1 + 1] = "seed " .. seed .. " " .. name end
    local rec = save.modData.mysteryGift
    if not (MysteryGift.validateSavedCard(sessionOf(save)) and MysteryGift.validateSavedNews(sessionOf(save))) then
      bad3[#bad3 + 1] = "seed " .. seed .. " engine validators reject the imported card/news"
    end
    local d = H.deepEqual(rec.news, decodeNews(v, src.sb1, o + 4))
    local cardWant = decodeCard(v, src.sb1, o + 0x1C4)
    cardWant.gift = { kind = "none", quantity = 1, level = 5, moves = {}, setFlags = {}, haveFlags = {} }
    H.deepEqual(rec.card, cardWant, "card", d)
    local meta = decodeMeta(src.sb1, o)
    for k, want in pairs(meta) do H.deepEqual(rec[k], want, k, d) end
    if v ~= "emerald" then
      H.deepEqual(save.vsSeeker, decodeVs(src.sb1), "vsSeeker", d)
      local tw = decodeTower(src.sb1, g32(src.sb2, KEY_OFF[v]))
      H.deepEqual(save.modData.trainerTower, tw, "trainerTower", d)
    end
    if #d > 0 then bad3[#bad3 + 1] = "seed " .. seed .. " import " .. d[1] end

    local fresh = H.blocks(H.fresh(v, H.import(v, cart)), v)
    local f = H.deepEqual(decodeNews(v, fresh.sb1, o + 4), decodeNews(v, src.sb1, o + 4), "news")
    if g32(fresh.sb1, o) ~= crcBitwise(sub(fresh.sb1, o + 4, 444)) then f[#f + 1] = "newsCrc invalid" end
    H.deepEqual(decodeMeta(fresh.sb1, o), meta, "meta", f)
    if sub(fresh.sb1, o + 0x1C0, 336) ~= string.rep("\0", 336) then f[#f + 1] = "templateless card not cleared" end
    if sub(fresh.sb1, r, RS_SIZE) ~= string.rep("\0", RS_SIZE) then f[#f + 1] = "templateless ram script not cleared" end
    if v ~= "emerald" then
      H.deepEqual(decodeVs(fresh.sb1), decodeVs(src.sb1), "vs", f)
      H.deepEqual(decodeTower(fresh.sb1, g32(fresh.sb2, KEY_OFF[v])), decodeTower(src.sb1, g32(src.sb2, KEY_OFF[v])), "tower", f)
    end
    if #f > 0 then bad2[#bad2 + 1] = "seed " .. seed .. " " .. f[1] end
  end
  failures(bad1, v .. " R1: template export keeps every modeled region byte-identical over " .. SEEDS .. " seeds")
  failures(bad3, v .. " R1: import decodes every modeled field and the engine validators accept it")
  failures(bad2, v .. " R1: templateless export reproduces the modeled values, card and ram script cleared")
end

local function randomNews(rng, v)
  local n = { id = rng(65535) + 1, sendType = rng(256), bgType = rng(256), bodyText = {} }
  n.titleText = select(2, randText(rng, v, 40))
  for i = 1, 10 do n.bodyText[i] = select(2, randText(rng, v, 40)) end
  return n
end

local function randomRecord(rng, v, withNews)
  local session = { modData = {} }
  local rec = MysteryGift.ensure(session)
  if withNews then check(MysteryGift.saveNews(session, randomNews(rng, v)), "engine saveNews accepts the news") end
  rec.cardMetadataCrc = rnd32(rng)
  local md = rec.cardMetadata
  md.battlesWon, md.battlesLost, md.numTrades, md.iconSpecies = rng(65536), rng(65536), rng(65536), rng(65536)
  for i = 1, 7 do md.stampData.species[i], md.stampData.ids[i] = rng(65536), rng(65536) end
  rec.questionnaireWords = { rng(65535) + 1, rng(65535) + 1, rng(65535) + 1, rng(65535) + 1 }
  rec.newsMetadata = { newsType = rng(4), sentRewardCounter = rng(8), rewardCounter = rng(8), berry = rng(256) }
  rec.trainerIds = { {}, {} }
  for k = 1, 2 do for i = 1, 5 do rec.trainerIds[k][i] = rnd32(rng) end end
  return rec
end

for _, v in ipairs(ALL) do
  local o = MG_AT[v][1]
  local bad = {}
  for seed = 1, SEEDS do
    local rng = H.rng(seed * 104729 + #v)
    local save = H.import(v, H.cart(v))
    local rec = randomRecord(rng, v, seed % 5 ~= 0)
    save.modData.mysteryGift = copy(rec)
    local want = { vsSeeker = nil, tower = nil }
    if v ~= "emerald" then
      local rem = {}
      for i = 0, 99 do if rng(4) == 0 then rem[i] = rng(255) + 1 end end
      save.vsSeeker = { steps = rng(101), charging = rng(101), rematches = rem }
      local tw = { challengeId = rng(4), records = {} }
      for i = 1, 4 do
        tw.records[i] = { timer = rnd32(rng), bestTime = rng(MAX_TIME + 1), floorsCleared = rng(256), setId = rng(256),
          receivedPrize = rng(2) == 1, checkedFinalTime = rng(2) == 1, spokeToOwner = rng(2) == 1, hasLost = rng(2) == 1,
          statusUnk = rng(2) == 1, validated = rng(2) == 1 }
      end
      save.modData.trainerTower = tw
      want.vsSeeker, want.tower = copy(save.vsSeeker), copy(tw)
    end
    local out = H.fresh(v, save)
    local b = H.blocks(out, v)
    local d = {}
    if rec.news then
      H.deepEqual(decodeNews(v, b.sb1, o + 4), rec.news, "news", d)
      if g32(b.sb1, o) ~= crcBitwise(sub(b.sb1, o + 4, 444)) then d[#d + 1] = "cart newsCrc invalid" end
    elseif sub(b.sb1, o, 448) ~= string.rep("\0", 448) then
      d[#d + 1] = "absent news is not zero"
    end
    local meta = decodeMeta(b.sb1, o)
    for k, val in pairs(meta) do H.deepEqual(val, rec[k], k, d) end
    if v ~= "emerald" then
      H.deepEqual(decodeVs(b.sb1), want.vsSeeker, "vs", d)
      H.deepEqual(decodeTower(b.sb1, g32(b.sb2, KEY_OFF[v])), want.tower, "tower", d)
    end
    local back = H.import(v, out)
    local brec = back.modData.mysteryGift
    for _, k in ipairs({ "news", "newsCrc", "cardCrc", "cardMetadataCrc", "cardMetadata", "questionnaireWords",
      "newsMetadata", "trainerIds" }) do
      H.deepEqual(brec[k], rec[k], "reimport." .. k, d)
    end
    if brec.card ~= nil then d[#d + 1] = "reimport has a card" end
    if v ~= "emerald" then
      H.deepEqual(back.vsSeeker, want.vsSeeker, "reimport.vsSeeker", d)
      H.deepEqual(back.modData.trainerTower, want.tower, "reimport.trainerTower", d)
    end
    local again = H.blocks(H.fresh(v, back), v)
    for _, name in ipairs(regionsSame(b, again, v)) do d[#d + 1] = "second export differs in " .. name end
    if #d > 0 then bad[#bad + 1] = "seed " .. seed .. " " .. d[1] end
  end
  failures(bad, v .. " R2: engine values export, decode independently, reimport deep-equal and reach a fixed point")
end

local function engineCrcFor(card)
  local probe = { modData = { mysteryGift = { card = card } } }
  for c = 0, 65535 do
    probe.modData.mysteryGift.cardCrc = c
    if MysteryGift.validateSavedCard(probe) then return c end
  end
  return nil
end

local function mutate(v, cart, edit)
  local base = H.blocks(H.withTemplate(v, H.import(v, cart), cart), v)
  local save = H.import(v, cart)
  edit(save)
  local out = H.withTemplate(v, save, cart)
  local b = H.blocks(out, v)
  return changed(base.sb1, b.sb1), changed(base.sb2, b.sb2), b, H.import(v, out)
end

for _, v in ipairs(FRLG) do
  local cart = randomCart(v, 4242)
  local rows = {
    { "steps", function(s) s.vsSeeker.steps = (s.vsSeeker.steps + 1) % 256 end, VS, VS + 1,
      function(b, s) return b.vsSeeker.steps == s.vsSeeker.steps end },
    { "charging", function(s) s.vsSeeker.charging = (s.vsSeeker.charging + 1) % 256 end, VS + 1, VS + 2,
      function(b, s) return b.vsSeeker.charging == s.vsSeeker.charging end },
    { "rematches[37]", function(s) s.vsSeeker.rematches[37] = ((s.vsSeeker.rematches[37] or 0) + 1) % 256 end, VS + 2 + 37, VS + 3 + 37,
      function(b, s) return VsSeeker.getRematch(b.vsSeeker, 37) == VsSeeker.getRematch(s.vsSeeker, 37) end },
    { "rematches string key", function(s) s.vsSeeker.rematches[99] = nil; s.vsSeeker.rematches["99"] = 200 end, VS + 2 + 99, VS + 3 + 99,
      function(b) return b.vsSeeker.rematches[99] == 200 end },
    { "challengeId", function(s) s.modData.trainerTower.challengeId = (s.modData.trainerTower.challengeId + 1) % U32 end, TOWER, TOWER + 4,
      function(b, s) return b.modData.trainerTower.challengeId == s.modData.trainerTower.challengeId end },
  }
  local fields = { { "timer", 0, 4 }, { "floorsCleared", 8, 1 }, { "setId", 9, 1 }, { "receivedPrize", 10, 1 },
    { "checkedFinalTime", 10, 1 }, { "spokeToOwner", 10, 1 }, { "hasLost", 10, 1 }, { "statusUnk", 10, 1 }, { "validated", 10, 1 } }
  for i = 1, 4 do
    for _, f in ipairs(fields) do
      local at = TOWER + 4 + (i - 1) * 12 + f[2]
      rows[#rows + 1] = { "records[" .. i .. "]." .. f[1], function(s)
        local rec = s.modData.trainerTower.records[i]
        if type(rec[f[1]]) == "boolean" then rec[f[1]] = not rec[f[1]]
        elseif f[1] == "timer" then rec.timer = (rec.timer + 1) % U32
        else rec[f[1]] = (rec[f[1]] + 1) % 256 end
      end, at, at + f[3], function(b, s)
        return b.modData.trainerTower.records[i][f[1]] == s.modData.trainerTower.records[i][f[1]]
      end }
    end
  end
  for _, row in ipairs(rows) do
    local edited
    local c1, c2, _, back = mutate(v, cart, function(s) row[2](s); edited = s end)
    local ok, off = within(c1, row[3], row[4])
    check(#c1 > 0 and ok and #c2 == 0, v .. " mutation " .. row[1] .. " touches only its bytes (" .. #c1 .. " changed, stray " .. tostring(off) .. ")")
    check(row[5](back, edited), v .. " mutation " .. row[1] .. " survives reimport")
  end
end

for _, v in ipairs(ALL) do
  local o, r = MG_AT[v][1], MG_AT[v][2]
  local cart = randomCart(v, 777)
  local function words(s) return s.modData.mysteryGift.questionnaireWords end
  local rows = {
    { "news.titleText", function(s) s.modData.mysteryGift.news.titleText = "WONDER" end, o, o + 448 },
    { "cardMetadataCrc", function(s) s.modData.mysteryGift.cardMetadataCrc = (s.modData.mysteryGift.cardMetadataCrc + 1) % U32 end, o + 0x310, o + 0x314 },
    { "cardMetadata.battlesWon", function(s) local m = s.modData.mysteryGift.cardMetadata; m.battlesWon = (m.battlesWon + 1) % 65536 end, o + 0x314, o + 0x316 },
    { "cardMetadata.numTrades", function(s) local m = s.modData.mysteryGift.cardMetadata; m.numTrades = (m.numTrades + 1) % 65536 end, o + 0x318, o + 0x31A },
    { "stampData.ids[7]", function(s) local m = s.modData.mysteryGift.cardMetadata.stampData; m.ids[7] = (m.ids[7] + 1) % 65536 end, o + 0x336, o + 0x338 },
    { "questionnaireWords[2]", function(s) words(s)[2] = (words(s)[2] % 65535) + 1 end, o + 0x33A, o + 0x33C },
    { "newsMetadata.rewardCounter", function(s) local m = s.modData.mysteryGift.newsMetadata; m.rewardCounter = (m.rewardCounter + 1) % 8 end, o + 0x340, o + 0x341 },
    { "newsMetadata.berry", function(s) local m = s.modData.mysteryGift.newsMetadata; m.berry = (m.berry + 1) % 256 end, o + 0x341, o + 0x342 },
    { "trainerIds[2][5]", function(s) local t = s.modData.mysteryGift.trainerIds[2]; t[5] = (t[5] + 1) % U32 end, o + 0x368, o + 0x36C },
  }
  for _, row in ipairs(rows) do
    local edited
    local c1, c2, b, back = mutate(v, cart, function(s)
      row[2](s)
      if s.modData.mysteryGift.news then
        local ses = { modData = {} }
        MysteryGift.saveNews(ses, s.modData.mysteryGift.news)
        s.modData.mysteryGift.newsCrc = ses.modData.mysteryGift.newsCrc
      end
      edited = s
    end)
    local ok, off = within(c1, row[3], row[4])
    check(#c1 > 0 and ok and #c2 == 0, v .. " mutation " .. row[1] .. " touches only its bytes (" .. #c1 .. " changed, stray " .. tostring(off) .. ")")
    local d = H.deepEqual(back.modData.mysteryGift, edited.modData.mysteryGift)
    failures(d, v .. " mutation " .. row[1] .. " survives reimport")
    check(g32(b.sb1, o) == crcBitwise(sub(b.sb1, o + 4, 444)), v .. " mutation " .. row[1] .. " leaves a news CRC the game accepts")
  end

  local function cartCardOk(b)
    return g32(b.sb1, o + 0x1C0) == crcBitwise(sub(b.sb1, o + 0x1C4, 332))
      and g32(b.sb1, r) == crcBitwise(sub(b.sb1, r + 4, 999)) and g8(b.sb1, r + 4) == 51
  end

  local c1, c2, b, back = mutate(v, cart, function(s)
    local rec = s.modData.mysteryGift
    rec.card.sendType = (rec.card.sendType + 1) % 3
    rec.card.bgType = (rec.card.bgType + 1) % 8
    rec.card.titleText = "EVENT"
    rec.cardCrc = engineCrcFor(rec.card)
  end)
  local ok, off = within(c1, o + 0x1C0, o + 0x310)
  check(#c1 > 0 and ok and #c2 == 0, v .. " same card, edited fields: only the card struct and its CRC change (stray " .. tostring(off) .. ")")
  check(cartCardOk(b), v .. " same card, edited fields: the game accepts the CRC and the ram script")
  check(back.modData.mysteryGift.card and back.modData.mysteryGift.card.titleText == "EVENT", v .. " same card, edited fields survive reimport")
  check(sub(b.sb1, r, RS_SIZE) == sub(H.blocks(cart, v).sb1, r, RS_SIZE), v .. " same card, edited fields: the ram script is carried from the template")

  c1, c2, b, back = mutate(v, cart, function(s)
    local rec = s.modData.mysteryGift
    rec.card, rec.cardCrc = nil, 0
  end)
  local clearedCard = sub(b.sb1, o + 0x1C0, 336) == string.rep("\0", 336)
  local clearedScript = sub(b.sb1, r, RS_SIZE) == string.rep("\0", RS_SIZE)
  check(clearedCard and clearedScript and #c2 == 0, v .. " engine cleared the card: card, CRC and ram script are zeroed")
  check(back.modData.mysteryGift.card == nil and back.modData.mysteryGift.cardCrc == 0, v .. " engine cleared the card: reimport has no card")
  local stray = {}
  for _, x in ipairs(c1) do
    if not ((x >= o + 0x1C0 and x < o + 0x310) or (x >= r and x < r + RS_SIZE)) then stray[#stray + 1] = x end
  end
  check(#stray == 0, v .. " engine cleared the card: no other byte changes")

  for _, mode in ipairs({ "new card", "invalid engine crc" }) do
    c1, c2, b, back = mutate(v, cart, function(s)
      local rec = s.modData.mysteryGift
      if mode == "new card" then
        rec.card.idNumber = (rec.card.idNumber + 1) % U32
        rec.cardCrc = engineCrcFor(rec.card)
      else
        rec.cardCrc = (rec.cardCrc + 1) % 65536
      end
    end)
    check(sub(b.sb1, o + 0x1C0, 336) == string.rep("\0", 336) and sub(b.sb1, r, RS_SIZE) == string.rep("\0", RS_SIZE),
      v .. " " .. mode .. ": the replaced cartridge card and its ram script are cleared, never left with a foreign script")
    check(back.modData.mysteryGift.card == nil, v .. " " .. mode .. ": reimport has no card")
  end

  local save = H.import(v, cart)
  local notes = {}
  local Rse = require("src.save_convert.gen3_port.rse")
  local sec = (v == "emerald" and Rse.SECTIONS or Rse.FRLG_SECTIONS).mysteryGiftCard
  local codec = H.codec(v)
  local blocks = H.blocks(cart, v)
  local w1, w2 = codec.newBuf(#blocks.sb1, blocks.sb1), codec.newBuf(#blocks.sb2, blocks.sb2)
  local rec = copy(save.modData.mysteryGift)
  rec.card.flagId = rec.card.flagId % 65535 + 1
  rec.cardCrc = engineCrcFor(rec.card)
  sec.write({ L = codec.L, codec = codec, sb1 = blocks.sb1, sb2 = blocks.sb2, w1 = w1, w2 = w2, notes = notes }, { modData = { mysteryGift = rec } })
  check(#notes == 1, v .. " a card the cartridge cannot carry reports a note through the section context")

  local fresh = H.import(v, H.cart(v))
  fresh.modData.mysteryGift = copy(save.modData.mysteryGift)
  local out = H.blocks(H.fresh(v, fresh), v)
  check(sub(out.sb1, o + 0x1C0, 336) == string.rep("\0", 336) and sub(out.sb1, r, RS_SIZE) == string.rep("\0", RS_SIZE),
    v .. " no template: an engine card is not written without its script")

  local badScript = H.cart(v, function(w)
    local rng = H.rng(99)
    writeNews(w.sb1, o, rng, v)
    writeCard(w.sb1, o, r, rng, v)
    w.sb1[r + 7] = 0
  end)
  local imp = H.import(v, badScript)
  check(imp.modData.mysteryGift.card == nil and imp.modData.mysteryGift.cardCrc == 0, v .. " a card whose ram script fails ValidateRamScript imports as no card")
  local same = H.blocks(H.withTemplate(v, imp, badScript), v)
  check(#regionsSame(same, H.blocks(badScript, v), v) == 0, v .. " an invalid cartridge card is carried byte-identical")

  local badNews = H.cart(v, function(w)
    local rng = H.rng(98)
    writeNews(w.sb1, o, rng, v)
    w.sb1[o] = (w.sb1[o] + 1) % 256
  end)
  imp = H.import(v, badNews)
  check(imp.modData.mysteryGift.news == nil and imp.modData.mysteryGift.newsCrc == 0, v .. " news with a bad CRC imports as no news")
  check(#regionsSame(H.blocks(H.withTemplate(v, imp, badNews), v), H.blocks(badNews, v), v) == 0, v .. " invalid news is carried byte-identical")

  local zeroWords = H.cart(v, function(w)
    for i = 0, 7 do w.sb1[o + 0x338 + i] = 0 end
    w.sb1[o + 0x341] = 3
  end)
  imp = H.import(v, zeroWords)
  eq(imp.modData.mysteryGift.questionnaireWords[1], 0, v .. " a zero questionnaire word imports raw")
  check(#regionsSame(H.blocks(H.withTemplate(v, imp, zeroWords), v), H.blocks(zeroWords, v), v) == 0, v .. " zero questionnaire words stay zero with a template")
  local newGame = H.import(v, H.cart(v))
  newGame.modData.mysteryGift = nil
  newGame.modData.mysteryGift = MysteryGift.ensure({ modData = {} })
  local ng = H.blocks(H.fresh(v, newGame), v)
  local wantNg = string.rep("\0", 0x338) .. string.rep("\255", 8) .. string.rep("\0", MG_SIZE - 0x340)
  check(sub(ng.sb1, o, MG_SIZE) == wantNg, v .. " a fresh engine record exports the ClearMysteryGift + InitQuestionnaireWords bytes")
  local absent = H.import(v, H.cart(v))
  absent.modData.mysteryGift = nil
  local ab = H.blocks(H.fresh(v, absent), v)
  check(sub(ab.sb1, o, MG_SIZE) == wantNg, v .. " no engine record and no template exports the new-game bytes")
  local legacy = H.import(v, cart)
  legacy.modData.mysteryGift = nil
  check(#regionsSame(H.blocks(H.withTemplate(v, legacy, cart), v), H.blocks(cart, v), v) == 0,
    v .. " no engine record with a template keeps the cartridge bytes")
end

do
  local v = "firered"
  local o = MG_AT[v][1]
  local cart = randomCart(v, 1234)
  local gifts = {
    { kind = "item", item = 371, quantity = 1, level = 5, moves = {}, setFlags = { 0x84B, 0x2A7 }, haveFlags = { 0x2A7 } },
    { kind = "egg", species = 172, level = 5, quantity = 1, moves = { [3] = 57, [1] = 33 }, setFlags = {}, haveFlags = {},
      slotVar = 0x40B5, doneFlag = 0x3D8, nickname = "PICHU", personality = 12345, otName = "GF", otId = 99, heldItem = 13 },
    { kind = "var", slotVar = 0x4024, varAdd = 1, varWrap = 10, requireStat = 0, requireValue = 3, script = "eon",
      quantity = 1, level = 5, moves = {}, setFlags = {}, haveFlags = {} },
  }
  for i, gift in ipairs(gifts) do
    local _, _, b, back = mutate(v, cart, function(s)
      local rec = s.modData.mysteryGift
      rec.card.gift = gift
      rec.card.titleText = "GIFT " .. i
      rec.cardCrc = engineCrcFor(rec.card)
    end)
    check(b.sb1:sub(o + 0x1C4 + 11, o + 0x1C4 + 16) == H.codec(v).encodeString("GIFT " .. i, 6, 0xFF),
      "the section's engine CRC agrees with MysteryGift.validateSavedCard for gift " .. gift.kind)
    check(back.modData.mysteryGift.card.titleText == "GIFT " .. i, "gift " .. gift.kind .. " card edit survives reimport")
  end
end

for _, v in ipairs(ALL) do
  local o = MG_AT[v][1]
  local save = H.import(v, H.cart(v))
  local ses = { modData = {} }
  check(MysteryGift.saveNews(ses, { id = 65535, sendType = 255, bgType = 255, titleText = string.rep("A", 40),
    bodyText = { "", string.rep("Z", 40) } }), v .. " boundary news is accepted by the engine")
  local rec = ses.modData.mysteryGift
  rec.cardMetadataCrc = U32 - 1
  rec.cardMetadata.battlesWon = 65535
  rec.questionnaireWords = { 0xFFFF, 1, 0xFFFF, 0xFFFE }
  rec.newsMetadata = { newsType = 3, sentRewardCounter = 7, rewardCounter = 7, berry = 255 }
  rec.trainerIds = { { U32 - 1, 0, 0, 0, 0 }, { 0, 0, 0, 0, U32 - 1 } }
  save.modData.mysteryGift = rec
  local out = H.fresh(v, save)
  local b = H.blocks(out, v)
  eq(g8(b.sb1, o + 4 + 4 + 39) ~= 0xFF and true, true, v .. " a 40-character title has no terminator")
  eq(g8(b.sb1, o + 48), 0xFF, v .. " an empty body line is just the terminator")
  eq(g8(b.sb1, o + 0x340), 0xFF, v .. " newsMetadata bitfields pack into one byte")
  local back = H.import(v, out).modData.mysteryGift
  failures(H.deepEqual(back.news, rec.news, "news"), v .. " boundary news survives")
  eq(back.cardMetadataCrc, U32 - 1, v .. " u32 max cardMetadataCrc survives")
  eq(back.trainerIds[2][5], U32 - 1, v .. " u32 max trainer id survives")
  check(MysteryGift.validateSavedNews(sessionOf(H.import(v, out))), v .. " engine validates the boundary news after reimport")
end

for _, v in ipairs(FRLG) do
  local save = H.import(v, H.cart(v))
  save.vsSeeker = { steps = 255, charging = 255, rematches = { [0] = 255, [99] = 1, [100] = 7, [200] = 9 } }
  local back = H.import(v, H.fresh(v, save))
  failures(H.deepEqual(back.vsSeeker, { steps = 255, charging = 255, rematches = { [0] = 255, [99] = 1 } }),
    v .. " u8 max VS Seeker counters survive and localIds past MAX_REMATCH_ENTRIES are dropped")
  save = H.import(v, H.cart(v))
  save.modData.trainerTower = { challengeId = U32 - 1, records = { { timer = U32 - 1, floorsCleared = 255, setId = 255 } } }
  local out = H.fresh(v, save)
  local tw = H.import(v, out).modData.trainerTower
  check(tw.challengeId == U32 - 1 and tw.records[1].timer == U32 - 1 and tw.records[1].floorsCleared == 255
    and tw.records[1].setId == 255 and tw.records[1].bestTime == MAX_TIME, v .. " u32 max tower fields survive, missing bestTime exports as TRAINER_TOWER_MAX_TIME")
  local b = H.blocks(out, v)
  for i = 2, 4 do
    local at = TOWER + 4 + (i - 1) * 12
    eq(sub(b.sb1, at, 4) .. sub(b.sb1, at + 8, 4), string.rep("\0", 8), v .. " missing tower record " .. i .. " exports new-game zeros")
  end
end

for _, v in ipairs(FRLG) do
  local cart = randomCart(v, 31337)
  local save = H.import(v, cart)
  local src = H.blocks(cart, v).sb1
  local s = VsSeeker.state(save)
  eq(VsSeeker.getBattery(save), g8(src, VS), v .. " engine VsSeeker.getBattery reads the cartridge charge steps")
  eq(s.charging, g8(src, VS + 1), v .. " engine VsSeeker.state reads the cartridge charging counter")
  local lid
  for i = 0, 99 do if g8(src, VS + 2 + i) ~= 0 then lid = i break end end
  eq(VsSeeker.getRematch(s, lid), g8(src, VS + 2 + lid), v .. " engine VsSeeker.getRematch reads trainerRematches[localId]")
  local rawId = g32(src, TOWER)
  eq(save.modData.trainerTower.challengeId, rawId, v .. " the raw cartridge challenge id is imported")
  local session = { modData = save.modData }
  local st = Tower.state(session)
  eq(st.challengeId, rawId < 4 and rawId or 0, v .. " engine Tower.state normalizes the cartridge challenge id")
  eq(Tower.record(session, 1).timer, g32(src, TOWER + 4 + 12), v .. " engine Tower.record reads the cartridge timer")
  eq(Tower.isTimerRunning(session), false, v .. " the timer is not running after load (VBlank counter pointer is RAM-only)")
  local key = g32(H.blocks(cart, v).sb2, KEY_OFF[v])
  eq(Tower.bestTime(session, 2), bit.bxor(g32(src, TOWER + 4 + 24 + 4), key) % U32, v .. " engine Tower.bestTime reads the decrypted cartridge best time")
end

for _, v in ipairs(ALL) do
  local o = MG_AT[v][1]
  local cart = randomCart(v, 2718)
  local save = H.import(v, cart)
  local src = H.blocks(cart, v).sb1
  local ses = sessionOf(save)
  eq(MysteryGift.getCardFlagId(ses), g16(src, o + 0x1C4), v .. " engine getCardFlagId reads the cartridge card")
  local ct = g8(src, o + 0x1C4 + 8) % 4
  MysteryGift.ensure(ses).card.type = MysteryGift.CARD_TYPE_LINK_STAT
  eq(MysteryGift.getCardStat(ses, MysteryGift.CARD_STAT_BATTLES_WON), g16(src, o + 0x314), v .. " engine getCardStat reads the cartridge metadata")
  MysteryGift.ensure(ses).card.type = ct
  eq(MysteryGift.questionnaireWords(ses)[1], g16(src, o + 0x338), v .. " engine questionnaireWords reads the cartridge words")
end

do
  local rng = H.rng(5)
  local f = io.open("../pokefirered/src/util.c", "rb")
  if f then
    local src = f:read("*a")
    f:close()
    local body = src:match("gCrc16Table%[%]%s*=%s*{(.-)}")
    local tbl = {}
    for hex in body:gmatch("0x(%x+)") do tbl[#tbl + 1] = tonumber(hex, 16) end
    eq(#tbl, 256, "pret gCrc16Table has 256 entries")
    local function pret(s)
      local crc = 0x1121
      for i = 1, #s do
        local byte = bit.rshift(crc, 8)
        crc = bit.bxor(crc, s:byte(i))
        crc = bit.band(bit.bxor(byte, tbl[bit.band(crc, 0xFF) + 1]), 0xFFFF)
      end
      return bit.band(bit.bnot(crc), 0xFFFF)
    end
    local bad = 0
    for _ = 1, 200 do
      local t = {}
      for i = 1, rng(1100) do t[i] = string.char(rng(256)) end
      local s = table.concat(t)
      if pret(s) ~= MysteryGift.crc16(s) or pret(s) ~= crcBitwise(s) then bad = bad + 1 end
    end
    eq(bad, 0, "MysteryGift.crc16 equals pret CalcCRC16WithTable (src/util.c:250) on 200 random inputs")
  else
    print("[skip] ../pokefirered/src/util.c not found; CRC equivalence checked against the bitwise reference only")
    local bad = 0
    for _ = 1, 200 do
      local t = {}
      for i = 1, rng(1100) do t[i] = string.char(rng(256)) end
      if MysteryGift.crc16(table.concat(t)) ~= crcBitwise(table.concat(t)) then bad = bad + 1 end
    end
    eq(bad, 0, "MysteryGift.crc16 equals the bitwise CRC-16 reference")
  end
end

do
  local Cache = require("tests.game3_cache")
  local root = Cache.mount and Cache.mount()
  if not root then
    print("[skip] gen3_sec_frextra engine session round trip: no FireRed cache for identity " .. tostring(os.getenv("POKEPORT_IDENTITY")))
  else
    love = love or require("tests.love_stub")
    require("src.core.GameVersion").set("firered")
    require("src.import.gba.versions").select("firered")
    local Dataset = require("src.core.game3.dataset")
    Dataset.mountExtractRoots()
    Dataset.hydrate({ data = {} })
    local Schema = require("src.core.game3.save_schema_firered")
    local cart = randomCart("firered", 1618, function(w) B.le(w.sb1, TOWER, 2, 4) end)
    local save = H.import("firered", cart)
    local ok, sess = pcall(Schema.fromSaveTable, save)
    check(ok, "FireRed session loads the imported save (" .. tostring(ok or sess) .. ")")
    if ok then
      local back = Schema.toSaveTable(sess)
      failures(H.deepEqual(back.vsSeeker, save.vsSeeker), "FireRed session keeps the cartridge VS Seeker state")
      check(MysteryGift.validateSavedCard(sess) and MysteryGift.validateSavedNews(sess), "FireRed session validates the cartridge card and news")
      eq(Tower.record(sess, 0).timer, save.modData.trainerTower.records[1].timer, "FireRed session reads the cartridge tower timer")
      local out = H.blocks(H.withTemplate("firered", back, cart), "firered")
      local diff = regionsSame(out, H.blocks(cart, "firered"), "firered")
      check(#diff == 0, "FireRed session save exports the modeled regions byte-identical (" .. table.concat(diff, ",") .. ")")
    end
  end
end

T.finish("gen3_sec_frextra")
