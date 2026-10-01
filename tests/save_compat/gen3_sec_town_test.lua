package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local H = require("tests.save_compat._gen3_sections")
local G3 = require("tests.fixtures.save.gen3_build")
local B = require("tests.fixtures.save.bytes")

local EM = "emerald"
local OLD, LADY, HILL, TIMES = 0x2E28, 0x3B58, 0x3D64, 0x3718
local MINI = { emerald = { 0x1EC, 0x1FC, 0x20C }, frlg = { 0xAF0, 0xB00, 0xB10 } }
local U16, U32 = 0xFFFF, 0xFFFFFFFF

local function u8(s, o) return s:byte(o + 1) end
local function u16(s, o) return u8(s, o) + u8(s, o + 1) * 256 end
local function u32(s, o) return u16(s, o) + u16(s, o + 2) * 65536 end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

local function same(a, b, msg)
  local diffs = H.deepEqual(a, b)
  check(#diffs == 0, msg .. (#diffs > 0 and (" (" .. table.concat(diffs, "; ", 1, math.min(#diffs, 4)) .. ")") or ""))
end

local function text(codec, s, off, len)
  local zero = true
  for i = 0, len - 1 do if u8(s, off + i) ~= 0 then zero = false end end
  if zero then return "" end
  return codec.decodeString(s, off, len)
end

local function list(s, off, n, size)
  local out = {}
  for i = 1, n do
    local o = off + (i - 1) * size
    out[i] = size == 1 and u8(s, o) or size == 2 and u16(s, o) or u32(s, o)
  end
  return out
end

-- pokeemerald/include/global.h:651
local function decOldMan(s, codec)
  local b = OLD
  local id = u8(s, b)
  local m = { id = id }
  if id == 0 then
    m.songLyrics, m.newSongLyrics = list(s, b + 2, 6, 2), list(s, b + 0x0E, 6, 2)
    m.playerName = text(codec, s, b + 0x1A, 8)
    m.playerTrainerId = u8(s, b + 0x25) + u8(s, b + 0x26) * 256
    m.hasChangedSong, m.language = u8(s, b + 0x29) ~= 0, u8(s, b + 0x2A)
  elseif id == 1 then
    m.taughtWord, m.language = u8(s, b + 1) ~= 0, u8(s, b + 2)
  elseif id == 2 then
    m.decorations, m.playerNames = list(s, b + 1, 4, 1), {}
    for i = 1, 4 do m.playerNames[i] = text(codec, s, b + 5 + (i - 1) * 11, 11) end
    m.alreadyTraded, m.language = u8(s, b + 0x31) ~= 0, list(s, b + 0x32, 4, 1)
  elseif id == 3 then
    m.alreadyRecorded, m.gameStatIDs, m.trainerNames = u8(s, b + 1) ~= 0, list(s, b + 4, 4, 1), {}
    for i = 1, 4 do m.trainerNames[i] = text(codec, s, b + 8 + (i - 1) * 7, 7) end
    m.statValues, m.language = list(s, b + 0x24, 4, 4), list(s, b + 0x34, 4, 1)
  elseif id == 4 then
    m.taleCounter, m.questionNum = u8(s, b + 1), u8(s, b + 2)
    m.randomWords, m.questionList, m.language = list(s, b + 4, 10, 2), list(s, b + 0x18, 8, 1), u8(s, b + 0x20)
  end
  return m
end

-- pokeemerald/include/global.h:797
local function decLady(s, codec)
  local b = LADY
  local id = u8(s, b)
  local l = { id = id }
  if id == 0 then
    l.quiz = { id = 0, state = u8(s, b + 1), question = list(s, b + 2, 9, 2), correctAnswer = u16(s, b + 0x14),
      playerAnswer = u16(s, b + 0x16), playerName = text(codec, s, b + 0x18, 8),
      playerTrainerId = u16(s, b + 0x20) % 256 + (u16(s, b + 0x22) % 256) * 256, prize = u16(s, b + 0x28),
      waitingForChallenger = u8(s, b + 0x2A) ~= 0, questionId = u8(s, b + 0x2B), prevQuestionId = u8(s, b + 0x2C),
      language = u8(s, b + 0x2D) }
  elseif id == 1 then
    l.favor = { id = 1, state = u8(s, b + 1), likedItem = u8(s, b + 2) ~= 0, numItemsGiven = u8(s, b + 3),
      playerName = text(codec, s, b + 4, 8), favorId = u8(s, b + 0x0C), itemId = u16(s, b + 0x0E),
      bestItem = u16(s, b + 0x10), language = u8(s, b + 0x12) }
  elseif id == 2 then
    l.contest = { id = 2, givenPokeblock = u8(s, b + 1) ~= 0, numGoodPokeblocksGiven = u8(s, b + 2),
      numOtherPokeblocksGiven = u8(s, b + 3), playerName = text(codec, s, b + 4, 8), maxSheen = u8(s, b + 0x0C),
      category = u8(s, b + 0x0D), language = u8(s, b + 0x0E) }
  end
  return l
end

-- pokeemerald/include/global.h:865
local function decHill(s)
  local f = u16(s, HILL + 0xA)
  local function bitf(sh, w) return math.floor(f / 2 ^ sh) % 2 ^ w end
  return { timer = u32(s, HILL), bestTime = u32(s, HILL + 4), unk_3D6C = u8(s, HILL + 8),
    receivedPrize = bitf(0, 1), checkedFinalTime = bitf(1, 1), spokeToOwner = bitf(2, 1), hasLost = bitf(3, 1),
    maybeECardScanDuringChallenge = bitf(4, 1), field_3D6E_0f = bitf(5, 1), mode = bitf(6, 2) }
end

-- pokeemerald/include/global.h:219
local function decMini(s, fam)
  local c, j, p = MINI[fam][1], MINI[fam][2], MINI[fam][3]
  return {
    berryCrushPressingSpeeds = list(s, c, 4, 2),
    pokemonJumpRecords = { jumpsInRow = u16(s, j), excellentsInRow = u16(s, j + 4),
      gamesWithMaxPlayers = u16(s, j + 6), bestJumpScore = u32(s, j + 0xC) },
    dodrioBerryPickingRecords = { bestScore = u32(s, p), berriesPicked = u16(s, p + 4),
      berriesPickedInRow = u16(s, p + 6) },
  }
end

local function decTown(blocks, version, codec)
  local fam = H.family(version)
  local out = decMini(blocks.sb2, fam)
  if fam == "emerald" then
    out.oldMan, out.lilycoveLady = decOldMan(blocks.sb1, codec), decLady(blocks.sb1, codec)
    out.trainerHill, out.trainerHillTimes = decHill(blocks.sb1), list(blocks.sb1, TIMES, 4, 4)
  end
  return out
end

local KEYS = { "oldMan", "lilycoveLady", "trainerHill", "trainerHillTimes", "berryCrushPressingSpeeds",
  "pokemonJumpRecords", "dodrioBerryPickingRecords" }

local function engineView(save)
  local out = {}
  for _, k in ipairs(KEYS) do out[k] = copy(save[k]) end
  return out
end

local REGIONS = {
  emerald = { { "sb1", OLD, 64 }, { "sb1", LADY, 64 }, { "sb1", HILL, 12 }, { "sb1", TIMES, 16 },
    { "sb2", 0x1EC, 8 }, { "sb2", 0x1F8, 4 }, { "sb2", 0x1FC, 32 } },
  frlg = { { "sb2", 0xAF0, 8 }, { "sb2", 0xAFC, 4 }, { "sb2", 0xB00, 32 } },
}

local function regionsSame(a, b, fam)
  for _, r in ipairs(REGIONS[fam]) do
    if not H.sameBytes(a, b, r[1], r[2], r[3]) then return false, ("%s+0x%X"):format(r[1], r[2]) end
  end
  return true
end

local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local function randName(rng, maxLen, minLen)
  local n = (minLen or 0) + rng(maxLen - (minLen or 0) + 1)
  local t = {}
  for i = 1, n do
    local k = rng(#LETTERS) + 1
    t[i] = LETTERS:sub(k, k)
  end
  return table.concat(t)
end

local function putName(w, block, off, len, name, rng)
  local enc = G3.text(name, len)
  for i = 1, len do w[block][off + i - 1] = enc[i] end
  local style = rng(3)
  if name == "" and style == 0 then
    B.fill(w[block], off, len, 0)
  elseif #name + 1 < len then
    for i = #name + 1, len - 1 do
      w[block][off + i] = style == 0 and 0 or style == 1 and 0xFF or rng(256)
    end
  end
end

local function bool8(w, off, rng) w.sb1[off] = rng(2) end

local function randOldMan(w, id, rng)
  local b = OLD
  H.randomize(w, "sb1", b, 64, rng)
  w.sb1[b] = id
  if id == 0 then
    putName(w, "sb1", b + 0x1A, 8, randName(rng, 7), rng)
    bool8(w, b + 0x29, rng)
  elseif id == 1 then
    bool8(w, b + 1, rng)
  elseif id == 2 then
    for i = 0, 3 do putName(w, "sb1", b + 5 + i * 11, 11, randName(rng, 10), rng) end
    bool8(w, b + 0x31, rng)
  elseif id == 3 then
    bool8(w, b + 1, rng)
    for i = 0, 3 do putName(w, "sb1", b + 8 + i * 7, 7, randName(rng, 7), rng) end
  end
end

local function randLady(w, id, rng)
  local b = LADY
  H.randomize(w, "sb1", b, 64, rng)
  w.sb1[b] = id
  if id == 0 then
    putName(w, "sb1", b + 0x18, 8, randName(rng, 7), rng)
    for i = 0, 3 do w.sb1[b + 0x21 + i * 2] = 0 end
    bool8(w, b + 0x2A, rng)
  elseif id == 1 then
    bool8(w, b + 2, rng)
    putName(w, "sb1", b + 4, 8, randName(rng, 7), rng)
  elseif id == 2 then
    bool8(w, b + 1, rng)
    putName(w, "sb1", b + 4, 8, randName(rng, 7), rng)
    w.sb1[b + 0x0D] = rng(5)
  end
end

local function randMini(w, fam, rng)
  local c = MINI[fam][1]
  H.randomize(w, "sb2", c, 8, rng)
  H.randomize(w, "sb2", c + 0xC, 4, rng)
  H.randomize(w, "sb2", MINI[fam][2], 32, rng)
end

local function randCart(version, seed, ids)
  local rng = H.rng(seed)
  local fam = H.family(version)
  local w = G3.base(version)
  randMini(w, fam, rng)
  if fam == "emerald" then
    local om = ids and ids.oldMan or rng(6)
    if om == 5 then om = 5 + rng(251) end
    local ld = ids and ids.lady or rng(4)
    if ld == 3 then ld = 3 + rng(253) end
    randOldMan(w, om, rng)
    randLady(w, ld, rng)
    H.randomize(w, "sb1", HILL, 12, rng)
    H.randomize(w, "sb1", TIMES, 16, rng)
  end
  return G3.emit(w)
end

local function modeled(save, fam)
  local v = engineView(save)
  if fam ~= "emerald" then v.oldMan, v.lilycoveLady, v.trainerHill, v.trainerHillTimes = nil, nil, nil, nil end
  return v
end

for _, version in ipairs({ "emerald", "firered", "leafgreen" }) do
  local fam, codec = H.family(version), H.codec(version)
  local bad = { import = 0, tmpl = 0, fresh = 0 }
  local firstBad
  for seed = 1, 60 do
    local bytes = randCart(version, seed * 7919 + #version)
    local src = H.blocks(bytes, version)
    local want = decTown(src, version, codec)
    local s = H.import(version, bytes)
    if #H.deepEqual(modeled(s, fam), want) > 0 then
      bad.import = bad.import + 1
      firstBad = firstBad or ("import seed " .. seed .. ": " .. table.concat(H.deepEqual(modeled(s, fam), want), "; "))
    end
    local out = H.blocks(H.withTemplate(version, s, bytes), version)
    local ok, where = regionsSame(src, out, fam)
    if not ok then
      bad.tmpl = bad.tmpl + 1
      firstBad = firstBad or ("template seed " .. seed .. " at " .. where)
    end
    local fresh = H.blocks(H.fresh(version, H.import(version, bytes)), version)
    local diffs = H.deepEqual(decTown(fresh, version, codec), want)
    if #diffs > 0 then
      bad.fresh = bad.fresh + 1
      firstBad = firstBad or ("fresh seed " .. seed .. ": " .. table.concat(diffs, "; ", 1, math.min(3, #diffs)))
    end
  end
  eq(bad.import, 0, version .. " R1 import decodes every modeled field (" .. tostring(firstBad) .. ")")
  eq(bad.tmpl, 0, version .. " R1 export with template keeps the region bytes (" .. tostring(firstBad) .. ")")
  eq(bad.fresh, 0, version .. " R1 templateless export keeps every modeled value (" .. tostring(firstBad) .. ")")
end

local function engineOldMan(id, rng)
  if id == 0 then
    local m = { id = 0, songLyrics = {}, newSongLyrics = {}, playerName = randName(rng, 7),
      playerTrainerId = rng(65536), hasChangedSong = rng(2) == 1, language = rng(256) }
    for i = 1, 6 do m.songLyrics[i], m.newSongLyrics[i] = rng(65536), rng(65536) end
    return m
  elseif id == 1 then
    return { id = 1, taughtWord = rng(2) == 1, language = rng(256) }
  elseif id == 2 then
    local m = { id = 2, decorations = {}, playerNames = {}, alreadyTraded = rng(2) == 1, language = {} }
    for i = 1, 4 do m.decorations[i], m.playerNames[i], m.language[i] = rng(256), randName(rng, 10), rng(256) end
    return m
  elseif id == 3 then
    local m = { id = 3, alreadyRecorded = rng(2) == 1, gameStatIDs = {}, trainerNames = {}, statValues = {}, language = {} }
    for i = 1, 4 do
      m.gameStatIDs[i], m.trainerNames[i], m.statValues[i], m.language[i] = rng(256), randName(rng, 7), rng(65536) + rng(65536) * 65536,
        rng(256)
    end
    return m
  elseif id == 4 then
    local m = { id = 4, taleCounter = rng(256), questionNum = rng(256), randomWords = {}, questionList = {}, language = rng(256) }
    for i = 1, 10 do m.randomWords[i] = rng(65536) end
    for i = 1, 8 do m.questionList[i] = rng(256) end
    return m
  end
  return { id = id }
end

local function engineLady(id, rng)
  if id == 0 then
    local q = { id = 0, state = rng(256), question = {}, correctAnswer = rng(65536), playerAnswer = rng(65536),
      playerName = randName(rng, 7), playerTrainerId = rng(65536), prize = rng(65536),
      waitingForChallenger = rng(2) == 1, questionId = rng(256), prevQuestionId = rng(256), language = rng(256) }
    for i = 1, 9 do q.question[i] = rng(65536) end
    return { id = 0, quiz = q }
  elseif id == 1 then
    return { id = 1, favor = { id = 1, state = rng(256), likedItem = rng(2) == 1, numItemsGiven = rng(256),
      playerName = randName(rng, 7), favorId = rng(256), itemId = rng(65536), bestItem = rng(65536), language = rng(256) } }
  elseif id == 2 then
    return { id = 2, contest = { id = 2, givenPokeblock = rng(2) == 1, numGoodPokeblocksGiven = rng(256),
      numOtherPokeblocksGiven = rng(256), playerName = randName(rng, 7), maxSheen = rng(256), category = rng(256),
      language = rng(256) } }
  end
  return { id = id }
end

local function engineHill(rng)
  return { timer = rng(65536) + rng(65536) * 65536, bestTime = rng(65536) + rng(65536) * 65536, unk_3D6C = rng(256),
    receivedPrize = rng(2), checkedFinalTime = rng(2), spokeToOwner = rng(2), hasLost = rng(2),
    maybeECardScanDuringChallenge = rng(2), field_3D6E_0f = rng(2), mode = rng(4) }
end

local function engineMini(save, rng)
  save.berryCrushPressingSpeeds = { rng(65536), rng(65536), rng(65536), rng(65536) }
  save.pokemonJumpRecords = { jumpsInRow = rng(65536), excellentsInRow = rng(65536), gamesWithMaxPlayers = rng(65536),
    bestJumpScore = rng(65536) + rng(65536) * 65536 }
  save.dodrioBerryPickingRecords = { bestScore = rng(65536) + rng(65536) * 65536, berriesPicked = rng(65536),
    berriesPickedInRow = rng(65536) }
end

for _, version in ipairs({ "emerald", "firered", "leafgreen" }) do
  local fam, codec = H.family(version), H.codec(version)
  local base = H.cart(version)
  local bad, firstBad = 0, nil
  for seed = 1, 60 do
    local rng = H.rng(seed * 104729 + 17)
    local s = H.import(version, base)
    engineMini(s, rng)
    if fam == "emerald" then
      local om = rng(7)
      s.oldMan = engineOldMan(om <= 4 and om or 5 + rng(251), rng)
      local ld = rng(5)
      s.lilycoveLady = engineLady(ld <= 2 and ld or 3 + rng(253), rng)
      s.trainerHill = engineHill(rng)
      s.trainerHillTimes = { rng(65536) + rng(65536) * 65536, rng(215999 + 1), 215999, 0 }
    end
    local want = modeled(s, fam)
    local out1 = H.fresh(version, s)
    local b1 = H.blocks(out1, version)
    local d = H.deepEqual(decTown(b1, version, codec), want)
    local back = H.import(version, out1)
    local d2 = H.deepEqual(modeled(back, fam), want)
    local b2 = H.blocks(H.fresh(version, back), version)
    local ok, where = regionsSame(b1, b2, fam)
    if #d > 0 or #d2 > 0 or not ok then
      bad = bad + 1
      firstBad = firstBad or ("seed " .. seed .. ": " .. table.concat(d, "; ", 1, math.min(#d, 3)) .. " | "
        .. table.concat(d2, "; ", 1, math.min(#d2, 3)) .. " | " .. tostring(where))
    end
  end
  eq(bad, 0, version .. " R2 engine values -> fresh export -> decode/re-import/fixed point (" .. tostring(firstBad) .. ")")
end

local function changedOffsets(a, b)
  local out = {}
  for _, blk in ipairs({ "sb2", "sb1", "storage" }) do
    local x, y = a[blk], b[blk]
    for i = 1, math.max(#x, #y) do
      if x:byte(i) ~= y:byte(i) then out[#out + 1] = { blk, i - 1 } end
    end
  end
  return out
end

local function mutate(version, bytes, label, edit, allowed, verify)
  local src = H.blocks(bytes, version)
  local s = H.import(version, bytes)
  edit(s)
  local want = engineView(s)
  local outBytes = H.withTemplate(version, s, bytes)
  local out = H.blocks(outBytes, version)
  local ch = changedOffsets(src, out)
  local stray
  for _, c in ipairs(ch) do
    local okc = false
    for _, a in ipairs(allowed) do
      if c[1] == a[1] and c[2] >= a[2] and c[2] < a[2] + a[3] then okc = true end
    end
    if not okc then stray = stray or ("%s+0x%X"):format(c[1], c[2]) end
  end
  check(#ch > 0, version .. " mutation " .. label .. " changes cart bytes")
  check(stray == nil, version .. " mutation " .. label .. " touches only its bytes (" .. tostring(stray) .. ")")
  local back = H.import(version, outBytes)
  local fam = H.family(version)
  same(modeled(back, fam), modeled(want, fam), version .. " mutation " .. label .. " re-imports")
  if verify then verify(out, back) end
end

local function bump(v, mod) return (v + 1) % mod end

-- pokeemerald/include/global.h:656
local OLD_FIELDS = {
  [0] = {
    { "songLyrics", 0x02, 12, 2 }, { "newSongLyrics", 0x0E, 12, 2 }, { "playerName", 0x1A, 8, "name" },
    { "playerTrainerId", 0x25, 2, "tid" }, { "hasChangedSong", 0x29, 1, "bool" }, { "language", 0x2A, 1, 1 },
  },
  [1] = { { "taughtWord", 0x01, 1, "bool" }, { "language", 0x02, 1, 1 } },
  [2] = { { "decorations", 0x01, 4, 1 }, { "playerNames", 0x05, 44, "names", 11 }, { "alreadyTraded", 0x31, 1, "bool" },
    { "language", 0x32, 4, 1 } },
  [3] = { { "alreadyRecorded", 0x01, 1, "bool" }, { "gameStatIDs", 0x04, 4, 1 }, { "trainerNames", 0x08, 28, "names", 7 },
    { "statValues", 0x24, 16, 4 }, { "language", 0x34, 4, 1 } },
  [4] = { { "taleCounter", 0x01, 1, 1 }, { "questionNum", 0x02, 1, 1 }, { "randomWords", 0x04, 20, 2 },
    { "questionList", 0x18, 8, 1 }, { "language", 0x20, 1, 1 } },
}
local LADY_FIELDS = {
  [0] = { key = "quiz", { "state", 0x01, 1, 1 }, { "question", 0x02, 18, 2 }, { "correctAnswer", 0x14, 2, 2 },
    { "playerAnswer", 0x16, 2, 2 }, { "playerName", 0x18, 8, "name" }, { "playerTrainerId", 0x20, 4, "tid" },
    { "prize", 0x28, 2, 2 }, { "waitingForChallenger", 0x2A, 1, "bool" }, { "questionId", 0x2B, 1, 1 },
    { "prevQuestionId", 0x2C, 1, 1 }, { "language", 0x2D, 1, 1 } },
  [1] = { key = "favor", { "state", 0x01, 1, 1 }, { "likedItem", 0x02, 1, "bool" }, { "numItemsGiven", 0x03, 1, 1 },
    { "playerName", 0x04, 8, "name" }, { "favorId", 0x0C, 1, 1 }, { "itemId", 0x0E, 2, 2 }, { "bestItem", 0x10, 2, 2 },
    { "language", 0x12, 1, 1 } },
  [2] = { key = "contest", { "givenPokeblock", 0x01, 1, "bool" }, { "numGoodPokeblocksGiven", 0x02, 1, 1 },
    { "numOtherPokeblocksGiven", 0x03, 1, 1 }, { "playerName", 0x04, 8, "name" }, { "maxSheen", 0x0C, 1, 1 },
    { "category", 0x0D, 1, 1 }, { "language", 0x0E, 1, 1 } },
}

local function editField(t, f, rng)
  local name, kind = f[1], f[4]
  local cur = t[name]
  if kind == "bool" then t[name] = not cur
  elseif kind == "name" then t[name] = cur == "ZQX" and "QZ" or "ZQX"
  elseif kind == "names" then t[name][2] = t[name][2] == "Mxy" and "Myx" or "Mxy"
  elseif kind == "tid" then t[name] = bump(cur, 65536) == 0x8484 and 0x1234 or bump(cur, 65536)
  elseif type(cur) == "table" then
    local k = rng(#cur) + 1
    cur[k] = bump(cur[k], 256 ^ kind)
  else t[name] = bump(cur, 256 ^ kind) end
end

do
  for id = 0, 4 do
    for k, f in ipairs(OLD_FIELDS[id]) do
      local bytes = randCart(EM, 900 + id * 31 + k, { oldMan = id, lady = 0 })
      mutate(EM, bytes, "oldMan[" .. id .. "]." .. f[1], function(s) editField(s.oldMan, f, H.rng(id * 7 + k)) end,
        { { "sb1", OLD + f[2], f[3] } })
    end
  end
  for id = 0, 2 do
    for k, f in ipairs(LADY_FIELDS[id]) do
      local bytes = randCart(EM, 700 + id * 31 + k, { oldMan = 2, lady = id })
      mutate(EM, bytes, "lilycoveLady[" .. id .. "]." .. f[1],
        function(s) editField(s.lilycoveLady[LADY_FIELDS[id].key], f, H.rng(id * 5 + k)) end,
        { { "sb1", LADY + f[2], f[3] } })
    end
  end
  local tid = u16(H.blocks(H.cart(EM), EM).sb2, 0x0A)
  mutate(EM, randCart(EM, 41, { oldMan = 0, lady = 0 }), "bard owner = player",
    function(s) s.oldMan.playerTrainerId = tid end, { { "sb1", OLD + 0x25, 4 } },
    function(out) eq(out.sb1:sub(OLD + 0x25 + 1, OLD + 0x29), out.sb2:sub(0x0A + 1, 0x0E),
      "SaveBardSongLyrics copies all four trainer id bytes") end)
  mutate(EM, randCart(EM, 42, { oldMan = 0, lady = 0 }), "quiz owner = player",
    function(s) s.lilycoveLady.quiz.playerTrainerId = tid end, { { "sb1", LADY + 0x20, 8 } },
    function(out)
      for i = 0, 3 do
        eq(u16(out.sb1, LADY + 0x20 + i * 2), u8(out.sb2, 0x0A + i), "QuizLadyRecordCustomQuizData id[" .. i .. "]")
      end
    end)
  local hillBits = { "receivedPrize", "checkedFinalTime", "spokeToOwner", "hasLost", "maybeECardScanDuringChallenge",
    "field_3D6E_0f" }
  local HF = { { "timer", 0, 4, 2 ^ 32 }, { "bestTime", 4, 4, 2 ^ 32 }, { "unk_3D6C", 8, 1, 256 }, { "mode", 0xA, 1, 4 } }
  for _, b in ipairs(hillBits) do HF[#HF + 1] = { b, 0xA, 1, 2 } end
  for k, f in ipairs(HF) do
    mutate(EM, randCart(EM, 500 + k), "trainerHill." .. f[1], function(s)
      s.trainerHill[f[1]] = bump(s.trainerHill[f[1]], f[4])
    end, { { "sb1", HILL + f[2], f[3] } })
  end
  for i = 1, 4 do
    mutate(EM, randCart(EM, 600 + i), "trainerHillTimes[" .. i .. "]", function(s)
      s.trainerHillTimes[i] = bump(s.trainerHillTimes[i], 4294967296)
    end, { { "sb1", TIMES + (i - 1) * 4, 4 } })
  end
  for _, version in ipairs({ "emerald", "firered", "leafgreen" }) do
    local m = MINI[H.family(version)]
    for i = 1, 4 do
      mutate(version, randCart(version, 300 + i), "berryCrushPressingSpeeds[" .. i .. "]", function(s)
        s.berryCrushPressingSpeeds[i] = bump(s.berryCrushPressingSpeeds[i], 65536)
      end, { { "sb2", m[1] + (i - 1) * 2, 2 } })
    end
    for k, f in ipairs({ { "jumpsInRow", 0, 2 }, { "excellentsInRow", 4, 2 }, { "gamesWithMaxPlayers", 6, 2 },
      { "bestJumpScore", 0xC, 4 } }) do
      mutate(version, randCart(version, 320 + k), "pokemonJumpRecords." .. f[1], function(s)
        s.pokemonJumpRecords[f[1]] = bump(s.pokemonJumpRecords[f[1]], 256 ^ f[3])
      end, { { "sb2", m[2] + f[2], f[3] } })
    end
    for k, f in ipairs({ { "bestScore", 0, 4 }, { "berriesPicked", 4, 2 }, { "berriesPickedInRow", 6, 2 } }) do
      mutate(version, randCart(version, 340 + k), "dodrioBerryPickingRecords." .. f[1], function(s)
        s.dodrioBerryPickingRecords[f[1]] = bump(s.dodrioBerryPickingRecords[f[1]], 256 ^ f[3])
      end, { { "sb2", m[3] + f[2], f[3] } })
    end
    local base = H.cart(version)
    local s = H.import(version, base)
    s.berryCrushPressingSpeeds, s.pokemonJumpRecords, s.dodrioBerryPickingRecords = nil, nil, nil
    check(regionsSame(H.blocks(base, version), H.blocks(H.withTemplate(version, s, base), version), H.family(version)),
      version .. " nil minigame records keep the template bytes")
    s = H.import(version, base)
    engineMini(s, H.rng(5))
    local out = H.blocks(H.withTemplate(version, s, base), version)
    eq(out.sb2:sub(m[1] + 9, m[1] + 16), H.blocks(base, version).sb2:sub(m[1] + 9, m[1] + 16),
      version .. " berry powder and BerryCrush.unk stay template-carried")
  end

  for from = 0, 4 do
    for to = 0, 4 do
      if from ~= to then
        local bytes = randCart(EM, 1000 + from * 5 + to, { oldMan = from, lady = 0 })
        local m = engineOldMan(to, H.rng(from * 11 + to))
        mutate(EM, bytes, ("oldMan variant %d -> %d"):format(from, to), function(s) s.oldMan = copy(m) end,
          { { "sb1", OLD, 64 } }, function(out)
            same(decOldMan(out.sb1, H.codec(EM)), m, ("oldMan %d -> %d decodes the new variant"):format(from, to))
          end)
      end
    end
  end
  for from = 0, 2 do
    for to = 0, 2 do
      if from ~= to then
        local bytes = randCart(EM, 1100 + from * 3 + to, { oldMan = 2, lady = from })
        local l = engineLady(to, H.rng(from * 13 + to))
        mutate(EM, bytes, ("lilycoveLady variant %d -> %d"):format(from, to), function(s) s.lilycoveLady = copy(l) end,
          { { "sb1", LADY, 64 } }, function(out)
            same(decLady(out.sb1, H.codec(EM)), l, ("lilycoveLady %d -> %d decodes the new variant"):format(from, to))
          end)
      end
    end
  end
end

do
  local codec = H.codec(EM)
  local base = H.cart(EM)
  local s = H.import(EM, base)
  s.oldMan = { id = 3, alreadyRecorded = true, gameStatIDs = { 255, 1, 0, 50 }, trainerNames = { "ABCDEFG", "", "Z", "abcdefg" },
    statValues = { U32, 0, 1, 0x80000000 }, language = { 255, 0, 2, 1 } }
  s.lilycoveLady = { id = 0, quiz = { id = 0, state = 255, question = { U16, 0, U16, 1, 2, 3, 4, 5, U16 }, correctAnswer = U16,
    playerAnswer = 0, playerName = "ABCDEFG", playerTrainerId = U16, prize = U16, waitingForChallenger = true,
    questionId = 255, prevQuestionId = 0, language = 255 } }
  s.trainerHill = { timer = U32, bestTime = U32, unk_3D6C = 255, receivedPrize = 1, checkedFinalTime = 1, spokeToOwner = 1,
    hasLost = 1, maybeECardScanDuringChallenge = 1, field_3D6E_0f = 1, mode = 3 }
  s.trainerHillTimes = { U32, 0, 215999, U32 }
  s.berryCrushPressingSpeeds = { U16, 0, U16, 1 }
  s.pokemonJumpRecords = { jumpsInRow = U16, excellentsInRow = U16, gamesWithMaxPlayers = 0, bestJumpScore = U32 }
  s.dodrioBerryPickingRecords = { bestScore = U32, berriesPicked = U16, berriesPickedInRow = 0 }
  local want = engineView(s)
  local out = H.fresh(EM, s)
  local b = H.blocks(out, EM)
  same(decTown(b, EM, codec), want, "max values survive a fresh export")
  same(engineView(H.import(EM, out)), want, "max values re-import")
  eq(b.sb1:sub(OLD + 9, OLD + 15), string.char(0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0xC1),
    "a 7-letter storyteller name fills the slot with no terminator")
  eq(b.sb1:sub(OLD + 16, OLD + 22), string.rep("\0", 7), "an empty unrecorded storyteller slot stays zero")
  eq(u16(b.sb1, HILL + 0xA), 0xFF, "every hill flag and mode packs into the low byte")
  eq(u8(b.sb1, LADY + 0x18 + 7), 0xFF, "a 7-letter quiz author keeps its EOS")

  local s2 = H.import(EM, base)
  s2.oldMan = { id = 0, songLyrics = { 1, 2, 3, 4, 5, 6 }, newSongLyrics = { 0, 0, 0, 0, 0, 0 }, playerName = "",
    playerTrainerId = 0, hasChangedSong = false, language = 2 }
  local b2 = H.blocks(H.fresh(EM, s2), EM)
  eq(b2.sb1:sub(OLD + 0x1A + 1, OLD + 0x1A + 8), string.rep("\0", 8), "an empty bard name stays zero like SetupBard")

  local function tagged(oid, lid)
    return H.cart(EM, function(w)
      H.randomize(w, "sb1", OLD, 64, H.rng(oid))
      H.randomize(w, "sb1", LADY, 64, H.rng(lid))
      w.sb1[OLD], w.sb1[LADY] = oid, lid
    end)
  end
  for _, ids in ipairs({ { 5, 3 }, { 255, 255 }, { 128, 7 } }) do
    local bytes = tagged(ids[1], ids[2])
    local si = H.import(EM, bytes)
    same(si.oldMan, { id = ids[1] }, "unknown old man tag " .. ids[1] .. " imports as a bare id")
    same(si.lilycoveLady, { id = ids[2] }, "unknown lady tag " .. ids[2] .. " imports as a bare id")
    check(regionsSame(H.blocks(bytes, EM), H.blocks(H.withTemplate(EM, si, bytes), EM), "emerald"),
      "unknown tags keep the template union bytes")
    local f = H.blocks(H.fresh(EM, H.import(EM, bytes)), EM)
    eq(u8(f.sb1, OLD), ids[1], "templateless export keeps the unknown old man tag")
    eq(u8(f.sb1, LADY), ids[2], "templateless export keeps the unknown lady tag")
    eq(f.sb1:sub(OLD + 2, OLD + 64), string.rep("\0", 63), "an unknown old man tag carries no other bytes")
  end

  local ff = H.cart(EM, function(w)
    w.sb1[OLD] = 2
    for i = 0, 3 do B.fill(w.sb1, OLD + 5 + i * 11, 11, 0xFF) end
  end)
  local sf = H.import(EM, ff)
  same(sf.oldMan.playerNames, { "", "", "", "" }, "0xFF-filled trader names import empty")
  check(regionsSame(H.blocks(ff, EM), H.blocks(H.withTemplate(EM, sf, ff), EM), "emerald"),
    "0xFF-filled names keep their bytes")
end

local function zeroUnion() local t = {} for i = 0, 63 do t[i] = 0 end return t end

local function pretImage(codec, kind, v)
  local t = zeroUnion()
  local function name(off, len, str)
    local enc = codec.encodeString(str, len, 0)
    for i = 1, len do
      t[off + i - 1] = enc:byte(i)
      if enc:byte(i) == 0xFF then break end
    end
  end
  local function w16(o, x) t[o], t[o + 1] = x % 256, math.floor(x / 256) end
  if kind == "oldMan" then
    t[0] = v.id
    -- pokeemerald/src/mauville_old_man.c:74
    if v.id == 0 then
      for i = 1, 6 do w16(2 + (i - 1) * 2, v.songLyrics[i]) end
      t[0x2A] = v.language
    elseif v.id == 1 then
      t[2] = v.language
    -- pokeemerald/src/trader.c:34
    elseif v.id == 2 then
      for i = 1, 4 do t[i] = v.decorations[i]; name(5 + (i - 1) * 11, 11, v.playerNames[i]); t[0x31 + i] = v.language[i] end
    -- pokeemerald/src/mauville_old_man.c:1201
    elseif v.id == 3 then
      for i = 0, 3 do t[8 + i] = 0xFF end
    elseif v.id == 4 then
      t[0x20] = v.language
    end
  else
    t[0] = v.id
    -- pokeemerald/src/lilycove_lady.c:314
    if v.id == 0 then
      local q = v.quiz
      for i = 1, 9 do w16(2 + (i - 1) * 2, q.question[i]) end
      w16(0x14, q.correctAnswer); w16(0x16, q.playerAnswer); t[0x18] = 0xFF; w16(0x28, q.prize)
      t[0x2B], t[0x2C], t[0x2D] = q.questionId, q.prevQuestionId, q.language
    -- pokeemerald/src/lilycove_lady.c:139
    elseif v.id == 1 then
      local f = v.favor
      t[4], t[0x0C], t[0x12] = 0xFF, f.favorId, f.language
      w16(0x10, f.bestItem)
    -- pokeemerald/src/lilycove_lady.c:607
    elseif v.id == 2 then
      local c = v.contest
      t[4], t[0x0D], t[0x0E] = 0xFF, c.category, c.language
    end
  end
  return t
end

local function unionDiff(s, off, img)
  local out = {}
  for i = 0, 63 do if u8(s, off + i) ~= img[i] then out[#out + 1] = i end end
  return out
end

do
  love = love or require("tests.love_stub")
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set("emerald")
  require("src.import.gba.versions").select("emerald")
  local Dataset = require("src.core.game3.dataset")
  if not Dataset.cache():read("data/generated/gba/native/manifest.lua") then
    print("[skip] gen3_sec_town_test: emerald engine consumption (no Emerald cache for identity "
      .. tostring(os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d") .. ")")
  else
    Dataset.mountExtractRoots()
    Dataset.hydrate({ data = {} })
    local Schema = require("src.core.game3.save_schema_firered")
    local SaveConvert = require("src.save_convert.SaveConvert")
    local OldMan = require("src.core.game3.rse.old_man")
    local Lady = require("src.core.game3.rse.lilycove_lady")
    local Hill = require("src.core.game3.rse.trainer_hill")
    local Records = require("src.ui.game3.minigame_records")
    local codec = H.codec(EM)

    local bytes = randCart(EM, 4242, { oldMan = 3, lady = 2 })
    local src = H.blocks(bytes, EM)
    local want = decTown(src, EM, codec)
    local sess = Schema.fromSaveTable(H.import(EM, bytes))
    eq(OldMan.current(sess), 3, "engine sees the storyteller from the cart")
    local _, statValue, trainer = OldMan.story(1, sess)
    eq(statValue, want.oldMan.statValues[2], "OldMan.story reads the cart stat value")
    eq(trainer, want.oldMan.trainerNames[2], "OldMan.story reads the cart trainer name")
    eq(Lady.id(sess), 2, "engine sees the contest lady from the cart")
    eq(Lady.contest(sess).maxSheen, want.lilycoveLady.contest.maxSheen, "Lady.contest reads the cart sheen")
    eq(Lady.contestLadyTvData(sess).playerName, want.lilycoveLady.contest.playerName, "contest TV data reads the cart name")
    same(Hill.state(sess), want.trainerHill, "Hill.state reads the cart hill save")
    same(sess.trainerHillTimes, want.trainerHillTimes, "the hill time board reads the cart times")
    local speeds = sess.berryCrushPressingSpeeds
    check(not Records.updateBerryCrush(sess, 2, 0), "a zero berry crush speed is never a record")
    same(sess.berryCrushPressingSpeeds, want.berryCrushPressingSpeeds, "berry crush records survive the session")
    check(speeds ~= nil, "berry crush records reach the session")
    eq(sess.pokemonJumpRecords.bestJumpScore, want.pokemonJumpRecords.bestJumpScore, "jump record reaches the session")
    eq(sess.dodrioBerryPickingRecords.bestScore, want.dodrioBerryPickingRecords.bestScore, "dodrio record reaches the session")
    local back = Schema.toSaveTable(sess)
    check(regionsSame(src, H.blocks(H.withTemplate(EM, back, bytes), EM), "emerald"),
      "a session round trip keeps the cart bytes")

    local notes = {}
    for _, tid in ipairs({ 0, 2, 4, 6, 8, 10 }) do
      local ns = Schema.newGame({ version = "emerald", name = "BRENDAN", gender = 0, trainerIdLower = tid })
      local save = Schema.toSaveTable(ns)
      local out = assert(SaveConvert.exportSav(save, "emerald", nil))
      local b = H.blocks(out, EM)
      local om, ld = save.oldMan, save.lilycoveLady
      local od = unionDiff(b.sb1, OLD, pretImage(codec, "oldMan", om))
      local skip = {}
      if om.id == 0 then
        for i = 0x0E, 0x19 do skip[i] = true end
        notes[#notes + 1] = "bard newSongLyrics"
      elseif om.id == 3 then
        for i = 0x34, 0x37 do skip[i] = true end
        notes[#notes + 1] = "storyteller language"
      end
      local real = {}
      for _, i in ipairs(od) do if not skip[i] then real[#real + 1] = ("0x%X"):format(i) end end
      eq(#real, 0, ("new game tid %d old man %d matches SetMauvilleOldMan (%s)"):format(tid, om.id, table.concat(real, ",")))
      local lbad = unionDiff(b.sb1, LADY, pretImage(codec, "lady", ld))
      eq(#lbad, 0, ("new game tid %d lady %d matches InitLilycoveLady"):format(tid, ld.id))
      eq(b.sb1:sub(HILL + 1, HILL + 12), string.rep("\0", 12), "new game trainer hill save is zero")
      for i = 0, 3 do eq(u32(b.sb1, TIMES + i * 4), 215999, "new game hill time " .. i .. " is HILL_MAX_TIME") end
      eq(b.sb2:sub(0x1EC + 1, 0x1EC + 8) .. b.sb2:sub(0x1F8 + 1, 0x21C), string.rep("\0", 44),
        "new game minigame records are zero like ResetMiniGamesRecords")
      local again = H.import(EM, out)
      same(engineView(again).oldMan, om, ("new game tid %d old man re-imports"):format(tid))
      same(engineView(again).lilycoveLady, ld, ("new game tid %d lady re-imports"):format(tid))
    end
    print("[note] gen3_sec_town_test: engine new-game state differs from pret on: " .. table.concat(notes, ", "))
  end
end

do
  local Cache = require("tests.game3_cache")
  require("src.core.GameVersion").set("firered")
  require("src.import.gba.versions").select("firered")
  local root = os.getenv("POKEPORT_IDENTITY") and Cache.mount()
  if not root then
    print("[skip] gen3_sec_town_test: FireRed engine consumption (no FireRed cache)")
  else
    local Schema = require("src.core.game3.save_schema_firered")
    local Records = require("src.ui.game3.minigame_records")
    for _, version in ipairs({ "firered", "leafgreen" }) do
      local bytes = randCart(version, 77)
      local src = H.blocks(bytes, version)
      local want = decMini(src.sb2, "frlg")
      local ok, sess = pcall(Schema.fromSaveTable, H.import(version, bytes))
      check(ok, version .. " cart loads into a session (" .. tostring(not ok and sess or "") .. ")")
      if ok then
        same(sess.berryCrushPressingSpeeds, want.berryCrushPressingSpeeds, version .. " session berry crush records")
        same(sess.pokemonJumpRecords, want.pokemonJumpRecords, version .. " session jump records")
        same(sess.dodrioBerryPickingRecords, want.dodrioBerryPickingRecords, version .. " session dodrio records")
        local top = want.dodrioBerryPickingRecords.bestScore
        Records.updateDodrio(sess, top + 1, 0, 0)
        local back = Schema.toSaveTable(sess)
        local out = H.blocks(H.withTemplate(version, back, bytes), version)
        local best = math.min(top + 1, Records.MAX_DODRIO_SCORE)
        eq(u32(out.sb2, 0xB10), best > top and best or top, version .. " a new dodrio record reaches the cart")
      end
    end
  end
end

T.finish("gen3_sec_town")
