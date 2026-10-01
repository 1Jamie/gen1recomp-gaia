package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local H = require("tests.save_compat._gen3_sections")
local G3 = require("tests.fixtures.save.gen3_build")
local Rse = require("src.save_convert.gen3_port.rse")

local V = "emerald"
local codec = H.codec(V)
local U32 = 4294967296
local SEEDS = tonumber(os.getenv("RECORDS_SEEDS")) or 50

-- pokeemerald/include/global.h:541
local FB = 0x64C
-- pokeemerald/include/global.h:1058
local CW = 0x2E90

local LEAVES, SUMMED = {}, {}

local function cat(p, ...)
  local t = {}
  for i, v in ipairs(p) do t[i] = v end
  for _, v in ipairs({ ... }) do t[#t + 1] = v end
  return t
end

local function add(path, block, off, k, o, elem)
  o = o or {}
  o.path, o.block, o.off, o.k, o.elem = path, block, off, k, elem
  LEAVES[#LEAVES + 1] = o
end

local function arr(path, block, off, k, n, size, elem)
  for i = 1, n do add(cat(path, i), block, off + (i - 1) * size, k, nil, elem) end
end

local function bitsLeaf(path, block, off, size, shift, width, bool, elem)
  add(path, block, off, "bits", { size = size, shift = shift, width = width, bool = bool }, elem)
end

local function textLeaf(path, block, off, len, elem, zeroEmpty)
  add(path, block, off, "text", { len = len, zeroEmpty = zeroEmpty }, elem)
end

-- pokeemerald/include/global.h:282
local function mon(path, off, elem)
  add(cat(path, "species"), "sb2", off, "u16", nil, elem)
  add(cat(path, "heldItem"), "sb2", off + 2, "u16", nil, elem)
  arr(cat(path, "moves"), "sb2", off + 4, "u16", 4, 2, elem)
  add(cat(path, "level"), "sb2", off + 12, "u8", nil, elem)
  add(cat(path, "ppBonuses"), "sb2", off + 13, "u8", nil, elem)
  for i, k in ipairs({ "hpEV", "attackEV", "defenseEV", "speedEV", "spAttackEV", "spDefenseEV" }) do
    add(cat(path, k), "sb2", off + 13 + i, "u8", nil, elem)
  end
  add(cat(path, "otId"), "sb2", off + 20, "u32", nil, elem)
  for i, k in ipairs({ "hpIV", "attackIV", "defenseIV", "speedIV", "spAttackIV", "spDefenseIV" }) do
    bitsLeaf(cat(path, k), "sb2", off + 24, 4, (i - 1) * 5, 5, false, elem)
  end
  bitsLeaf(cat(path, "abilityNum"), "sb2", off + 24, 4, 31, 1, false, elem)
  add(cat(path, "personality"), "sb2", off + 28, "u32", nil, elem)
  textLeaf(cat(path, "nickname"), "sb2", off + 32, 11, elem)
  add(cat(path, "friendship"), "sb2", off + 43, "u8", nil, elem)
end

-- pokeemerald/include/global.h:309
local function record(path, off, ereader)
  local size, mons = ereader and 188 or 236, ereader and 3 or 4
  local elem = { off = off, size = size }
  if ereader then add(cat(path, "unk0"), "sb2", off, "u8", nil, elem) else add(cat(path, "lvlMode"), "sb2", off, "u8", nil, elem) end
  add(cat(path, "facilityClass"), "sb2", off + 1, "u8", nil, elem)
  add(cat(path, "winStreak"), "sb2", off + 2, "u16", nil, elem)
  textLeaf(cat(path, "name"), "sb2", off + 4, 8, elem)
  arr(cat(path, "trainerId"), "sb2", off + 12, "u8", 4, 1, elem)
  local speech = ereader and { "greeting", "farewellPlayerLost", "farewellPlayerWon" } or { "greeting", "speechWon", "speechLost" }
  for i, k in ipairs(speech) do arr(cat(path, k), "sb2", off + 16 + (i - 1) * 12, "u16", 6, 2, elem) end
  if not ereader then add(cat(path, "language"), "sb2", off + 228, "u8", nil, elem) end
  for i = 1, mons do mon(cat(path, "party", i), off + 52 + (i - 1) * 44, elem) end
  SUMMED[#SUMMED + 1] = { kind = "record", path = path, off = off, size = size, mons = mons }
end

record({ "frontier", "towerPlayer" }, FB)
for i = 1, 5 do record({ "frontier", "towerRecords", i }, FB + 236 + (i - 1) * 236) end
do
  local p = { "frontier", "towerInterview" }
  add(cat(p, "playerSpecies"), "sb2", FB + 1416, "u16")
  add(cat(p, "opponentSpecies"), "sb2", FB + 1418, "u16")
  textLeaf(cat(p, "opponentName"), "sb2", FB + 1420, 8, nil, true)
  textLeaf(cat(p, "opponentMonNickname"), "sb2", FB + 1428, 11, nil, true)
  add(cat(p, "opponentLanguage"), "sb2", FB + 1439, "u8")
end
record({ "frontier", "ereaderTrainer" }, FB + 1440, true)
for i, k in ipairs({ "domeAttemptedSingles50", "domeAttemptedSinglesOpen", "domeHasWonSingles50", "domeHasWonSinglesOpen",
  "domeAttemptedDoubles50", "domeAttemptedDoublesOpen", "domeHasWonDoubles50", "domeHasWonDoublesOpen" }) do
  bitsLeaf({ "frontier", k }, "sb2", FB + 1724, 1, i - 1, 1)
end
add({ "frontier", "domeLvlMode" }, "sb2", FB + 1726, "u8")
add({ "frontier", "domeBattleMode" }, "sb2", FB + 1727, "u8")
for i = 1, 16 do
  local p, o = { "frontier", "domeTrainers", i }, FB + 1752 + (i - 1) * 2
  bitsLeaf(cat(p, "trainerId"), "sb2", o, 2, 0, 10)
  bitsLeaf(cat(p, "isEliminated"), "sb2", o, 2, 10, 1, true)
  bitsLeaf(cat(p, "eliminatedAt"), "sb2", o, 2, 11, 2)
  add(cat(p, "forfeited"), "sb2", o, "forfeit")
  arr({ "frontier", "domeMonIds", i }, "sb2", FB + 1816 + (i - 1) * 6, "u16", 3, 2)
end
bitsLeaf({ "frontier", "pikeHintedRoomIndex" }, "sb2", FB + 1988, 1, 0, 3)
bitsLeaf({ "frontier", "pikeHintedRoomType" }, "sb2", FB + 1988, 1, 3, 4)
bitsLeaf({ "frontier", "pikeHealingRoomsDisabled" }, "sb2", FB + 1988, 1, 7, 1)
arr({ "frontier", "pikeHeldItemsBackup" }, "sb2", FB + 1990, "u16", 3, 2)
arr({ "frontier", "pyramidRandoms" }, "sb2", FB + 2006, "u16", 4, 2)
add({ "frontier", "pyramidTrainerFlags" }, "sb2", FB + 2014, "u8")
for i = 1, 2 do
  arr({ "frontier", "pyramidBag", "itemId", i }, "sb2", FB + 2016 + (i - 1) * 20, "u16", 10, 2)
  arr({ "frontier", "pyramidBag", "quantity", i }, "sb2", FB + 2056 + (i - 1) * 10, "u8", 10, 1)
end
add({ "frontier", "pyramidLightRadius" }, "sb2", FB + 2076, "u8")
for i = 1, 6 do
  local p, o = { "frontier", "rentalMons", i }, FB + 2084 + (i - 1) * 12
  add(cat(p, "monId"), "sb2", o, "u16")
  add(cat(p, "personality"), "sb2", o + 4, "u32")
  add(cat(p, "ivs"), "sb2", o + 8, "u8")
  add(cat(p, "abilityNum"), "sb2", o + 9, "u8")
end
arr({ "frontier", "domeWinningMoves" }, "sb2", FB + 2164, "u16", 16, 2)
add({ "frontier", "trainerFlags" }, "sb2", FB + 2196, "u8")
for i = 1, 2 do
  textLeaf({ "frontier", "opponentNames", i }, "sb2", FB + 2197 + (i - 1) * 8, 8)
  arr({ "frontier", "opponentTrainerIds", i }, "sb2", FB + 2213 + (i - 1) * 4, "u8", 4, 1)
end
bitsLeaf({ "frontier", "unk_EF9" }, "sb2", FB + 2221, 1, 0, 7)
for i = 1, 3 do
  local p, o = { "frontier", "domePlayerPartyData", i }, FB + 2224 + (i - 1) * 16
  arr(cat(p, "moves"), "sb2", o, "u16", 4, 2)
  arr(cat(p, "evs"), "sb2", o + 8, "u8", 6, 1)
  add(cat(p, "nature"), "sb2", o + 14, "u8")
end

-- pokeemerald/include/global.h:473
do
  local p, o = { "playerApprentice" }, 0xB0
  add(cat(p, "id"), "sb2", o, "u8")
  bitsLeaf(cat(p, "lvlMode"), "sb2", o + 1, 1, 0, 2)
  bitsLeaf(cat(p, "questionsAnswered"), "sb2", o + 1, 1, 2, 4)
  bitsLeaf(cat(p, "leadMonId"), "sb2", o + 1, 1, 6, 2)
  bitsLeaf(cat(p, "party"), "sb2", o + 2, 1, 0, 3)
  bitsLeaf(cat(p, "saveId"), "sb2", o + 2, 1, 3, 2)
  arr(cat(p, "speciesIds"), "sb2", o + 4, "u8", 3, 1)
  for i = 1, 9 do
    local q, qo = cat(p, "questions", i), o + 8 + (i - 1) * 4
    bitsLeaf(cat(q, "questionId"), "sb2", qo, 1, 0, 2)
    bitsLeaf(cat(q, "monId"), "sb2", qo, 1, 2, 2)
    bitsLeaf(cat(q, "moveSlot"), "sb2", qo, 1, 4, 2)
    bitsLeaf(cat(q, "suggestedChange"), "sb2", qo, 1, 6, 2)
    add(cat(q, "data"), "sb2", qo + 2, "u16")
  end
end

-- pokeemerald/include/global.h:266
for i = 1, 4 do
  local p, o = { "apprentices", i }, 0xDC + (i - 1) * 68
  local elem = { off = o, size = 68 }
  bitsLeaf(cat(p, "id"), "sb2", o, 1, 0, 5, false, elem)
  bitsLeaf(cat(p, "lvlMode"), "sb2", o, 1, 5, 2, false, elem)
  add(cat(p, "numQuestions"), "sb2", o + 1, "u8", nil, elem)
  add(cat(p, "number"), "sb2", o + 2, "u8", nil, elem)
  for j = 1, 3 do
    local m, mo = cat(p, "party", j), o + 4 + (j - 1) * 12
    add(cat(m, "species"), "sb2", mo, "u16", nil, elem)
    arr(cat(m, "moves"), "sb2", mo + 2, "u16", 4, 2, elem)
    add(cat(m, "item"), "sb2", mo + 10, "u16", nil, elem)
  end
  arr(cat(p, "speechWon"), "sb2", o + 40, "u16", 6, 2, elem)
  arr(cat(p, "playerId"), "sb2", o + 52, "u8", 4, 1, elem)
  textLeaf(cat(p, "playerName"), "sb2", o + 56, 7, elem)
  add(cat(p, "language"), "sb2", o + 63, "u8", nil, elem)
  SUMMED[#SUMMED + 1] = { kind = "apprentice", path = p, off = o, size = 68 }
end

-- pokeemerald/include/global.h:488
for i = 1, 9 do
  for j = 1, 2 do
    for k = 1, 3 do
      local p, o = { "hallRecords1P", i, j, k }, 0x21C + (((i - 1) * 2 + (j - 1)) * 3 + (k - 1)) * 16
      arr(cat(p, "id"), "sb2", o, "u8", 4, 1)
      add(cat(p, "winStreak"), "sb2", o + 4, "u16")
      textLeaf(cat(p, "name"), "sb2", o + 6, 8)
      add(cat(p, "language"), "sb2", o + 14, "u8")
    end
  end
end
-- pokeemerald/include/global.h:497
for j = 1, 2 do
  for k = 1, 3 do
    local p, o = { "hallRecords2P", j, k }, 0x57C + ((j - 1) * 3 + (k - 1)) * 28
    arr(cat(p, "id1"), "sb2", o, "u8", 4, 1)
    arr(cat(p, "id2"), "sb2", o + 4, "u8", 4, 1)
    add(cat(p, "winStreak"), "sb2", o + 8, "u16")
    textLeaf(cat(p, "name1"), "sb2", o + 10, 8)
    textLeaf(cat(p, "name2"), "sb2", o + 18, 8)
    add(cat(p, "language"), "sb2", o + 26, "u8")
  end
end

-- pokeemerald/include/global.h:752
for i = 1, 13 do
  arr({ "contestWinners", i, "monName" }, "sb1", CW + (i - 1) * 32 + 11, "u8", 11, 1)
  arr({ "contestWinners", i, "trainerName" }, "sb1", CW + (i - 1) * 32 + 22, "u8", 8, 1)
end

local REGIONS = {
  { "sb2", 0xB0, 44 }, { "sb2", 0xDC, 272 }, { "sb2", 0x21C, 864 }, { "sb2", 0x57C, 168 },
  { "sb2", FB, 1628 }, { "sb2", FB + 1724, 1 }, { "sb2", FB + 1726, 2 }, { "sb2", FB + 1752, 160 },
  { "sb2", FB + 1988, 1 }, { "sb2", FB + 1990, 6 }, { "sb2", FB + 2006, 9 }, { "sb2", FB + 2016, 61 },
  { "sb2", FB + 2084, 72 }, { "sb2", FB + 2164, 58 }, { "sb2", FB + 2224, 48 },
}
for i = 0, 12 do REGIONS[#REGIONS + 1] = { "sb1", CW + i * 32 + 11, 19 } end

local function rd(s, o, n)
  local v = 0
  for i = n - 1, 0, -1 do v = v * 256 + s:byte(o + i + 1) end
  return v
end

local function wsum(s, off, words)
  local sum = 0
  for i = 0, words - 1 do sum = (sum + rd(s, off + i * 4, 4)) % U32 end
  return sum
end

local function zeroAt(s, off, n) return not s:sub(off + 1, off + n):find("[^%z]") end

local function getLeaf(s, l)
  if l.k == "u8" then return rd(s, l.off, 1) end
  if l.k == "u16" then return rd(s, l.off, 2) end
  if l.k == "u32" then return rd(s, l.off, 4) end
  if l.k == "forfeit" then return math.floor(rd(s, l.off, 2) / 8192) ~= 0 end
  if l.k == "text" then return (l.zeroEmpty and zeroAt(s, l.off, l.len)) and "" or codec.decodeString(s, l.off, l.len) end
  local v = math.floor(rd(s, l.off, l.size) / 2 ^ l.shift) % 2 ^ l.width
  if l.bool then return v ~= 0 end
  return v
end

local function setPath(t, path, v)
  for i = 1, #path - 1 do
    if t[path[i]] == nil then t[path[i]] = {} end
    t = t[path[i]]
  end
  t[path[#path]] = v
end

local function getPath(t, path, upto)
  for i = 1, (upto or #path) do
    if type(t) ~= "table" then return nil end
    t = t[path[i]]
  end
  return t
end

local function decode(b)
  local out = {}
  for _, l in ipairs(LEAVES) do setPath(out, l.path, getLeaf(b[l.block], l)) end
  for _, e in ipairs(SUMMED) do
    local s = b.sb2
    local valid = rd(s, e.off + e.size - 4, 4) == wsum(s, e.off, (e.size - 4) / 4)
    if e.kind == "record" then
      if zeroAt(s, e.off, e.size - 4) then
        setPath(out, e.path, {})
      else
        for m = 1, e.mons do
          if zeroAt(s, e.off + 52 + (m - 1) * 44, 44) then setPath(out, cat(e.path, "party", m), nil) end
        end
        if not valid then setPath(out, cat(e.path, "checksumValid"), false) end
      end
    elseif (getPath(out, cat(e.path, "playerName")) ~= "" or getPath(out, cat(e.path, "lvlMode")) ~= 0) and not valid then
      setPath(out, cat(e.path, "checksumValid"), false)
    end
  end
  return out
end

local KEYS = { "playerApprentice", "apprentices", "hallRecords1P", "hallRecords2P" }
local FKEYS, seenF = {}, {}
for _, l in ipairs(LEAVES) do
  if l.path[1] == "frontier" and not seenF[l.path[2]] then
    seenF[l.path[2]] = true
    FKEYS[#FKEYS + 1] = l.path[2]
  end
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = copy(x) end
  return o
end

local function pick(save)
  local out = { frontier = {}, contestWinners = {} }
  for _, k in ipairs(KEYS) do out[k] = copy(save[k]) end
  for _, k in ipairs(FKEYS) do out.frontier[k] = copy((save.frontier or {})[k]) end
  for i = 1, 13 do
    local w = (save.contestWinners or {})[i] or {}
    out.contestWinners[i] = { monName = copy(w.monName), trainerName = copy(w.trainerName) }
  end
  return out
end

local function apply(save, vals)
  for _, k in ipairs(KEYS) do save[k] = copy(vals[k]) end
  save.frontier = save.frontier or {}
  for _, k in ipairs(FKEYS) do save.frontier[k] = copy(vals.frontier[k]) end
  save.contestWinners = save.contestWinners or {}
  for i = 1, 13 do
    save.contestWinners[i] = save.contestWinners[i] or {}
    save.contestWinners[i].monName = copy(vals.contestWinners[i].monName)
    save.contestWinners[i].trainerName = copy(vals.contestWinners[i].trainerName)
  end
end

local function same(a, b, msg)
  local d = H.deepEqual(a, b)
  return check(#d == 0, msg .. (#d > 0 and (" (" .. #d .. " diffs, first " .. d[1] .. ")") or ""))
end

local function regionsEqual(a, b)
  for _, r in ipairs(REGIONS) do
    if a[r[1]]:sub(r[2] + 1, r[2] + r[3]) ~= b[r[1]]:sub(r[2] + 1, r[2] + r[3]) then
      for i = r[2], r[2] + r[3] - 1 do
        if a[r[1]]:byte(i + 1) ~= b[r[1]]:byte(i + 1) then return false, string.format("%s 0x%X", r[1], i) end
      end
    end
  end
  return true
end

local SAFE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

local function randText(r, len, n)
  n = n or r(len + 1)
  local t = {}
  for i = 1, n do
    local k = r(#SAFE) + 1
    t[i] = SAFE:sub(k, k)
  end
  return table.concat(t)
end

local function randLeaf(l, r)
  if l.k == "u8" then return r(256) end
  if l.k == "u16" then return r(65536) end
  if l.k == "u32" then return r(65536) * 65536 + r(65536) end
  if l.k == "forfeit" then return r(2) == 1 end
  if l.k == "text" then return randText(r, l.len) end
  if l.bool then return r(2) == 1 end
  return r(2 ^ l.width)
end

local function maxLeaf(l, even)
  if l.k == "u8" then return 255 end
  if l.k == "u16" then return 65535 end
  if l.k == "u32" then return U32 - 1 end
  if l.k == "forfeit" then return true end
  if l.k == "text" then return even and "" or string.rep("Z", l.len) end
  if l.bool then return true end
  return 2 ^ l.width - 1
end

local function engineValues(r, gen)
  local out = {}
  for i, l in ipairs(LEAVES) do setPath(out, l.path, gen(l, r, i)) end
  for _, e in ipairs(SUMMED) do
    if e.kind == "record" then
      if r(8) == 0 then
        setPath(out, e.path, {})
      else
        for m = 1, e.mons do
          if r(5) == 0 then setPath(out, cat(e.path, "party", m), nil) end
        end
        if r(4) == 0 then setPath(out, cat(e.path, "checksumValid"), false) end
      end
    elseif (getPath(out, cat(e.path, "playerName")) ~= "" or getPath(out, cat(e.path, "lvlMode")) ~= 0) and r(4) == 0 then
      setPath(out, cat(e.path, "checksumValid"), false)
    end
  end
  return out
end

local function setBytes(t, off, n, v)
  for i = 0, n - 1 do t[off + i] = math.floor(v / 256 ^ i) % 256 end
end

local function tsum(t, off, words)
  local sum = 0
  for i = 0, words - 1 do
    local o = off + i * 4
    sum = (sum + t[o] + t[o + 1] * 256 + t[o + 2] * 65536 + t[o + 3] * 16777216) % U32
  end
  return sum
end

local function randomCart(seed, textFill)
  local r = H.rng(seed)
  return H.cart(V, function(w)
    for _, reg in ipairs(REGIONS) do H.randomize(w, reg[1], reg[2], reg[3], r) end
    for _, e in ipairs(SUMMED) do
      if e.kind == "record" then
        if r(7) == 0 then
          for i = 0, e.size - 1 do w.sb2[e.off + i] = 0 end
        else
          for m = 1, e.mons do
            if r(5) == 0 then for i = 0, 43 do w.sb2[e.off + 52 + (m - 1) * 44 + i] = 0 end end
          end
        end
      elseif r(3) == 0 then
        w.sb2[e.off + 56] = 0xFF
      end
      if r(4) ~= 0 then setBytes(w.sb2, e.off + e.size - 4, 4, tsum(w.sb2, e.off, (e.size - 4) / 4)) end
    end
    if textFill then
      for _, l in ipairs(LEAVES) do
        if l.k == "text" then for i = 0, l.len - 1 do w[l.block][l.off + i] = textFill(i, l.len, r) end end
      end
    end
  end)
end

local function blocks(bytes) return H.blocks(bytes, V) end

local Contests = Rse.SECTIONS.contests
local contestsOwnsNames
do
  local b = blocks(H.cart(V))
  local got = Contests and Contests.read({ L = codec.L, codec = codec, sb1 = b.sb1, sb2 = b.sb2 })
  contestsOwnsNames = got and got.contestWinners and got.contestWinners[1] and got.contestWinners[1].monName ~= nil
end

check(Rse.SECTIONS.frontierRecords and Rse.SECTIONS.apprentices and Rse.SECTIONS.hallRecords and Rse.SECTIONS.contestNames,
  "records sections are registered for emerald")

local function r1(bytes, label)
  local save = H.import(V, bytes)
  local src = blocks(bytes)
  local ok, at = regionsEqual(src, blocks(H.withTemplate(V, save, bytes)))
  check(ok, label .. " R1 template export keeps every records byte" .. (at and (" (" .. at .. ")") or ""))
  same(pick(save), decode(src), label .. " import matches the independent decode")
  local fresh = blocks(H.fresh(V, H.import(V, bytes)))
  same(decode(fresh), decode(src), label .. " R1 templateless export decodes to the source values")
end

for seed = 1, SEEDS do r1(randomCart(seed), "seed " .. seed) end

r1(randomCart(9001, function() return 0xFF end), "all-FF text")
r1(randomCart(9002, function() return 0x00 end), "all-zero text")
r1(randomCart(9003, function(i, len, r) return i == 0 and 0xFF or r(256) end), "EOS-first text")
r1(randomCart(9004, function(i, len, r) return 0xBB + r(26) end), "full-length text")
r1(randomCart(9005, function(i, len, r) return ({ 0xFC, 0xFD, 0xF9, 0xFA, 0xFB, 0xFE })[r(6) + 1] end), "control-code text")
r1(H.cart(V), "base cart")

local base = H.import(V, H.cart(V))

local function r2(vals, label)
  local save = copy(base)
  apply(save, vals)
  local out1 = H.fresh(V, save)
  local b1 = blocks(out1)
  same(pick(decode(b1)), pick(vals), label .. " R2 fresh export decodes to the engine values")
  local back = H.import(V, out1)
  same(pick(back), pick(vals), label .. " R2 re-import returns the engine values")
  local ok, at = regionsEqual(b1, blocks(H.fresh(V, back)))
  check(ok, label .. " R2 second fresh export is byte-identical" .. (at and (" (" .. at .. ")") or ""))
  return b1
end

for seed = 1, SEEDS do r2(engineValues(H.rng(seed + 500), randLeaf), "seed " .. seed) end
r2(engineValues(H.rng(77), function(l, _, i) return maxLeaf(l, i % 2 == 0) end), "max values")
r2(engineValues(H.rng(78), function(l, _, i) return maxLeaf(l, i % 2 == 1) end), "max values alt")
r2(engineValues(H.rng(79), function(l)
  if l.k == "text" then return "" end
  if l.k == "forfeit" or l.bool then return false end
  return 0
end), "zeros")

do
  local vals = engineValues(H.rng(80), randLeaf)
  for _, e in ipairs(SUMMED) do
    if e.kind == "record" then setPath(vals, e.path, {}) end
  end
  local b = r2(vals, "empty records")
  for _, e in ipairs(SUMMED) do
    if e.kind == "record" then check(zeroAt(b.sb2, e.off, e.size), "empty record " .. table.concat(e.path, ".") .. " is all zero") end
  end
end

do
  local vals = engineValues(H.rng(81), randLeaf)
  for _, e in ipairs(SUMMED) do
    if e.kind == "record" then
      local rec = getPath(vals, e.path)
      if next(rec) == nil then setPath(vals, e.path, getPath(engineValues(H.rng(82), randLeaf), e.path)) end
      setPath(vals, cat(e.path, "checksumValid"), nil)
    elseif getPath(vals, cat(e.path, "playerName")) ~= "" then
      setPath(vals, cat(e.path, "checksumValid"), nil)
    end
  end
  local b = r2(vals, "valid checksums")
  for _, e in ipairs(SUMMED) do
    local name = getPath(vals, cat(e.path, "playerName"))
    if e.kind == "record" or name ~= "" or getPath(vals, cat(e.path, "lvlMode")) ~= 0 then
      eq(rd(b.sb2, e.off + e.size - 4, 4), wsum(b.sb2, e.off, (e.size - 4) / 4),
        table.concat(e.path, ".") .. " engine-made record carries the checksum the game recomputes")
    end
  end
end

do
  local vals = engineValues(H.rng(83), randLeaf)
  for i = 1, 4 do
    setPath(vals, { "apprentices", i, "playerName" }, "")
    setPath(vals, { "apprentices", i, "lvlMode" }, 0)
    setPath(vals, { "apprentices", i, "checksumValid" }, nil)
  end
  local b = r2(vals, "empty apprentices")
  for i = 1, 4 do eq(rd(b.sb2, 0xDC + (i - 1) * 68 + 64, 4), 0, "empty apprentice " .. i .. " keeps checksum 0 like ResetAllApprenticeData") end
end

do
  local save = copy(base)
  local rec = { lvlMode = 0, facilityClass = 0, winStreak = 0, name = "        ", trainerId = { 0, 0, 0, 0 },
    greeting = { 0, 0, 0, 0, 0, 0 }, speechWon = { 0, 0, 0, 0, 0, 0 }, speechLost = { 0, 0, 0, 0, 0, 0 }, language = 0,
    party = {}, checksumValid = false }
  save.frontier.towerRecords[1] = rec
  local b = blocks(H.fresh(V, save))
  check(zeroAt(b.sb2, FB + 236, 236), "an engine record that encodes to nothing is a cleared record with checksum 0")
  same(H.import(V, H.fresh(V, save)).frontier.towerRecords[1], {}, "a cleared record re-imports as an empty table")
end

local function pattern(path)
  local t = {}
  for i, p in ipairs(path) do t[i] = type(p) == "number" and "#" or p end
  return table.concat(t, ".")
end

local function mutate(l, cur, r)
  if l.k == "forfeit" or l.bool then return not cur end
  if l.k == "text" then
    local v
    repeat v = randText(r, l.len, r(l.len) + 1) until v ~= cur
    return v
  end
  local v
  repeat v = randLeaf(l, r) until v ~= cur
  return v
end

do
  local bytes = randomCart(4242)
  local src = blocks(bytes)
  local r = H.rng(4243)
  local done = {}
  local count = 0
  for _, l in ipairs(LEAVES) do
    local pat = pattern(l.path)
    local save = H.import(V, bytes)
    local parent = getPath(save, l.path, #l.path - 1)
    if not done[pat] and type(parent) == "table" and getPath(save, l.path) ~= nil then
      done[pat] = true
      count = count + 1
      local cur = getPath(save, l.path)
      local new = mutate(l, cur, r)
      setPath(save, l.path, new)
      local want = pick(save)
      local outBytes = H.withTemplate(V, save, bytes)
      local out = blocks(outBytes)
      local allowed = {}
      local width = l.k == "u16" and 2 or (l.k == "u32") and 4 or (l.k == "text") and l.len or (l.k == "bits") and l.size
        or (l.k == "forfeit") and 2 or 1
      for i = 0, width - 1 do allowed[l.block .. (l.off + i)] = true end
      if l.elem then for i = 0, 3 do allowed["sb2" .. (l.elem.off + l.elem.size - 4 + i)] = true end end
      local changed, stray = 0, nil
      for _, blk in ipairs({ "sb1", "sb2" }) do
        local a, b = src[blk], out[blk]
        if a ~= b then
          for i = 1, #a do
            if a:byte(i) ~= b:byte(i) then
              if allowed[blk .. (i - 1)] then changed = changed + 1 else stray = stray or string.format("%s 0x%X", blk, i - 1) end
            end
          end
        end
      end
      local name = table.concat((function() local t = {} for i, p in ipairs(l.path) do t[i] = tostring(p) end return t end)(), ".")
      check(changed > 0 and stray == nil, "mutating " .. name .. " changes only its own bytes"
        .. (stray and (" (stray " .. stray .. ")") or "") .. (changed == 0 and " (nothing changed)" or ""))
      local back = H.import(V, outBytes)
      eq(getPath(back, l.path), new, "mutated " .. name .. " re-imports")
      same(pick(back), want, "mutated " .. name .. " leaves the rest of the package intact")
    end
  end
  check(count > 150, "mutation sweep covered " .. count .. " field patterns")
end

if contestsOwnsNames then
  print("[skip] contest name string writes: the contests section in rse.lua still writes monName/trainerName (lead patch pending)")
else
  local bytes = randomCart(4300)
  local save = H.import(V, bytes)
  save.contestWinners[3].monName = "Zigzag"
  save.contestWinners[3].trainerName = "MAY"
  save.contestWinners[5].monName = {}
  local out = blocks(H.withTemplate(V, save, bytes))
  local src = blocks(bytes)
  local b3 = CW + 2 * 32
  eq(codec.decodeString(out.sb1, b3 + 11, 11), "Zigzag", "engine string monName reaches the cart")
  eq(codec.decodeString(out.sb1, b3 + 22, 8), "MAY", "engine string trainerName reaches the cart")
  eq(out.sb1:sub(b3 + 11 + 8, b3 + 22), src.sb1:sub(b3 + 11 + 8, b3 + 22), "StringCopy leaves the bytes after EOS")
  eq(out.sb1:byte(CW + 4 * 32 + 11 + 1), 0xFF, "an empty engine name writes EOS like sContestWinnerPicDummy")
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
require("src.import.gba.versions").select("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
if not cache:read("data/generated/gba/native/manifest.lua") or not cache:read("data/generated/gba/pokemon/national.lua") then
  print("[skip] gen3_sec_records engine checks: no Emerald cache for identity "
    .. tostring(os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d"))
else
  Dataset.mountExtractRoots()
  Dataset.hydrate({ data = {} })
  local SaveConvert = require("src.save_convert.SaveConvert")
  local Schema = require("src.core.game3.save_schema_firered")
  local Util = require("src.core.game3.rse.frontier.util")
  local Apprentice = require("src.core.game3.rse.frontier.apprentice")
  local D = require("src.core.game3.rse.frontier.trainers")
  local ContestUtil = require("src.core.game3.rse.contest_util")

  local bytes = randomCart(31337)
  do
    local b = blocks(bytes)
    local name = codec.encodeString("MAY", 8, 0)
    local sb1 = b.sb1:sub(1, CW + 32 + 22) .. name .. b.sb1:sub(CW + 32 + 22 + 9)
    local w = G3.base(V)
    for i = 0, #sb1 - 1 do w.sb1[i] = sb1:byte(i + 1) end
    for i = 0, #b.sb2 - 1 do w.sb2[i] = b.sb2:byte(i + 1) end
    bytes = G3.emit(w)
  end
  local src = decode(blocks(bytes))
  local save = assert(SaveConvert.importSav(bytes, "emerald", "emerald"))
  local sess = Schema.fromSaveTable(save)
  local f = Util.frontier(sess)
  for i = 1, 5 do
    local rec = src.frontier.towerRecords[i]
    if next(rec) ~= nil then
      eq(D.trainerName(sess, D.TRAINER_RECORD_MIXING_FRIEND + i - 1, 0), rec.name, "tower record " .. i .. " name reaches D.trainerName")
      eq(D.facilityClass(sess, D.TRAINER_RECORD_MIXING_FRIEND + i - 1, 0), rec.facilityClass, "tower record " .. i .. " class")
    end
  end
  same(f.towerInterview, src.frontier.towerInterview, "tower interview reaches the session")
  if next(src.frontier.ereaderTrainer) ~= nil then
    eq(D.trainerName(sess, D.TRAINER_EREADER, 0), src.frontier.ereaderTrainer.name, "e-reader trainer name reaches the session")
  end
  eq(Apprentice.saved(sess)[2].playerName, src.apprentices[2].playerName, "saved apprentice name reaches the session")
  eq(Apprentice.player(sess).questionsAnswered, src.playerApprentice.questionsAnswered, "player apprentice progress")
  eq(f.domeTrainers[4].trainerId, src.frontier.domeTrainers[4].trainerId, "dome trainer id reaches the session")
  eq(f.pyramidBag.itemId[2][7], src.frontier.pyramidBag.itemId[2][7], "pyramid bag reaches the session")
  eq(sess.hallRecords1P[3][2][1].name, src.hallRecords1P[3][2][1].name, "ranking hall name reaches the session")
  eq(ContestUtil.trainerName(sess.contestWinners[2]), "MAY",
    "contest winner trainer name decodes in the engine")
  local back = Schema.toSaveTable(sess)
  local out = assert(SaveConvert.exportSav(back, "emerald", bytes))
  local ok, at = regionsEqual(blocks(bytes), blocks(out))
  check(ok, "session round trip keeps every records byte" .. (at and (" (" .. at .. ")") or ""))

  local ng = Schema.newGame({ version = "emerald", name = "BRENDAN", gender = 0, trainerIdLower = 4321 })
  local fresh = blocks(assert(SaveConvert.exportSav(Schema.toSaveTable(ng), "emerald", nil)))
  for i = 1, 4 do
    local o = 0xDC + (i - 1) * 68
    eq(fresh.sb2:byte(o + 1), 16, "new game apprentice " .. i .. " id NUM_APPRENTICES")
    eq(rd(fresh.sb2, o + 40, 2), 0xFFFF, "new game apprentice " .. i .. " speech EC_EMPTY_WORD")
    eq(fresh.sb2:byte(o + 57), 0xFF, "new game apprentice " .. i .. " name EOS")
    eq(rd(fresh.sb2, o + 64, 4), 0, "new game apprentice " .. i .. " checksum 0")
  end
  check(zeroAt(fresh.sb2, FB, 1628), "new game tower records, interview and e-reader are zero")
  eq(fresh.sb2:byte(0x21C + 6 + 1), 0xFF, "new game hall name EOS")
  check(zeroAt(fresh.sb2, 0x21C + 7, 9), "new game hall record tail is zero")
  eq(fresh.sb2:byte(FB + 2197 + 1), 0xFF, "new game opponent name EOS")
  check(zeroAt(fresh.sb2, FB + 2198, 7), "new game opponent name tail is zero")
end

T.finish("gen3_sec_records")
