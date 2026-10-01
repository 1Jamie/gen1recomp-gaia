package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local H = require("tests.save_compat._gen3_sections")
local G3 = require("tests.fixtures.save.gen3_build")

local V = "emerald"
local codec = H.codec(V)
-- pokeemerald/include/global.h:1036
local BASE, SIZE, COUNT = 0x27CC, 36, 25

-- pokeemerald/include/global.tv.h:31
local DESC = {
  [1] = "u16 species 02, u16x6 words 04, t8 playerName 10, u8 language 18",
  [2] = "u16 species 02, u16x6 words 04, t8 playerName 10, u8 language 18",
  [3] = "u16 species 02, f0.4 friendshipHighNybble 04, f4.4 questionAsked 04, t8 playerName 05, u8 language 0D,"
    .. " u8 pokemonNameLanguage 0E, t8 nickname 10, u16x2 words 1C",
  [4] = "u16x2 words 02, u16 species 06",
  [5] = "u16 species 02, t11 pokemonName 04, t8 trainerName 0F, u8 random 1A, u8 random2 1B, u16 randomSpecies 1C,"
    .. " u8 language 1E, u8 pokemonNameLanguage 1F",
  [6] = "u16 species 02, u16x2 words 04, t11 pokemonNickname 08, f0.3 contestCategory 13, f3.2 contestRank 13,"
    .. " f5.2 contestResult 13, u16 move 14, t8 playerName 16, u8 language 1E, u8 pokemonNameLanguage 1F",
  [7] = "t8 playerName 02, u16 species 0A, t8 opponentName 0C, u16 defeatedSpecies 14, u16 numFights 16,"
    .. " u16x1 words 18, u8 btLevel 1A, u8 interviewResponse 1B, b8 wonTheChallenge 1C, u8 playerLanguage 1D,"
    .. " u8 opponentLanguage 1E",
  [8] = "u16 losingSpecies 02, t8 losingTrainerName 04, u8 loserAppealFlag 0C, u8 round1Placing 0D,"
    .. " u8 round2Placing 0E, u8 winnerAppealFlag 0F, u16 move 10, u16 winningSpecies 12, t8 winningTrainerName 14,"
    .. " u8 category 1C, u8 winningTrainerLanguage 1D, u8 losingTrainerLanguage 1E",
  [9] = "u8 sheen 02, f0.3 flavor 03, f3.2 color 03, t8 worstBlenderName 04, t8 playerName 0C, u8 language 14,"
    .. " u8 worstBlenderLanguage 15",
  [10] = "u16 speciesOpponent 02, t8 playerName 04, t8 linkOpponentName 0C, u16 move 14, u16 speciesPlayer 16,"
    .. " u8 battleType 18, u8 language 19, u8 linkOpponentLanguage 1A",
  [11] = "t8 playerName 02, u8 idLo 0A, u8 idHi 0B, t8 idolName 0C, u16x1 words 14, u8 score 16, u8 language 17,"
    .. " u8 idolNameLanguage 18",
  [12] = "t8 playerName 02, u8 contestCategory 0A, t11 nickname 0B, u8 pokeblockState 16, u8 language 17,"
    .. " u8 pokemonNameLanguage 18",
  [21] = "u8 language 02, u8 language2 03, t11 nickname 04, u8 ball 0F, u16 species 10, u8 nBallsUsed 12,"
    .. " t8 playerName 13",
  [22] = "u8 priceReduced 02, u8 language 03, u16x3 itemIds 06, u16x3 itemAmounts 0C, u8 shopLocation 12,"
    .. " t8 playerName 13",
  [23] = "u8 language 02, u16 species 0C, u16 species2 0E, u8 nBallsUsed 10, u8 outcome 11, u8 location 12,"
    .. " t8 playerName 13",
  [24] = "u8 nBites 02, u8 nFails 03, u16 species 04, u8 language 06, t8 playerName 13",
  [25] = "u16 numPokeCaught 02, u16 caughtPoke 04, u16 steps 06, u16 species 08, u8 location 0A, u8 language 0B,"
    .. " t8 playerName 13",
  [26] = "u16 dexCount 02, u8 badgeCount 04, u8 nSilverSymbols 05, u8 nGoldSymbols 06, u8 location 07,"
    .. " u16 battlePoints 08, u16 mapLayoutId 0A, u8 language 0C, t8 playerName 13",
  [27] = "u16x2 words 04, u8 gender 08, u8 language 09, t8 playerName 13",
  [28] = "u16 item 02, u8 location 04, u8 language 05, u16 mapLayoutId 06, t8 playerName 13",
  [29] = "b8 won 02, u8 whichGame 03, u16 nCoins 04, u8 language 08, t8 playerName 13",
  [30] = "u16 lastOpponentSpecies 02, u8 location 04, u8 outcome 05, u16 caughtMonBall 06, u16 balls 08,"
    .. " u16 poke1Species 0A, u16 lastUsedMove 0C, u8 language 0E, t8 playerName 13",
  [31] = "u8 avgLevel 02, u8 numDecorations 03, u8x4 decorations 04, u16 species 08, u16 move 0A, u8 language 0C,"
    .. " t8 playerName 13",
  [32] = "u16 item 02, u8 whichPrize 04, u8 language 05, t8 playerName 13",
  [33] = "u16 move 02, u16 foeSpecies 04, u16 species 06, u16x3 otherMoves 08, u16 betterMove 0E, u8 nOtherMoves 10,"
    .. " u8 language 11, t8 playerName 13",
  [34] = "u16x2 words 04, u8 language 08, t8 playerName 13",
  [35] = "u8 nRibbons 02, u8 selectedRibbon 03, t11 nickname 04, u8 language 0F, u8 pokemonNameLanguage 10,"
    .. " t8 playerName 13",
  [36] = "u16 winStreak 02, u16 species1 04, u16 species2 06, u16 species3 08, u16 species4 0A, u8 language 0C,"
    .. " u8 facilityAndMode 0D, t8 playerName 13",
  [37] = "u16 count 02, u8 actionIdx 04, u8 language 05, t8 playerName 13",
  [38] = "u16 stepsInBase 02, t8 baseOwnersName 04, u32 flags 0C, u16 item 10, u8 savedState 12, t8 playerName 13,"
    .. " u8 language 1B, u8 baseOwnersNameLanguage 1C",
  [39] = "u8 monsCaught 02, u8 pokeblocksUsed 03, u8 language 04, t8 playerName 13",
  [41] = "u8 unused1 02, u8 unused3 03, u16x4 moves 04, u16 species 0C, u16 unused2 0E, u8 locationMapNum 10,"
    .. " u8 locationMapGroup 11, u8 unused4 12, u8 probability 13, u8 level 14, u8 unused5 15,"
    .. " u16 daysBeforeOutbreak 16, u8 language 18",
}
local COMMON_DESC = "u8x28 raw 02"
-- pokeemerald/include/global.tv.h:15
local IDS = { { "srcTrainerId2Lo", 0x1E, "srcTrainerId2Hi" }, { "srcTrainerIdLo", 0x20, "srcTrainerIdHi" },
  { "trainerIdLo", 0x22, "trainerIdHi" } }
local UNKNOWN = { 13, 14, 15, 16, 17, 18, 19, 20, 40, 42, 60, 61, 128, 200, 255 }

local function parse(desc)
  local rows, used = {}, {}
  for item in desc:gmatch("[^,]+") do
    local ty, name, off = item:match("^%s*(%S+)%s+(%S+)%s+(%x+)%s*$")
    off = tonumber(off, 16)
    local r = { name = name, off = off }
    local base, n = ty:match("^(u%d+)x(%d+)$")
    if base then r.t, r.n = base, tonumber(n)
    elseif ty:match("^t%d+$") then r.t, r.len = "t", tonumber(ty:sub(2))
    elseif ty:match("^f") then
      local sh, w = ty:match("^f(%d+)%.(%d+)$")
      r.t, r.shift, r.width = "f", tonumber(sh), tonumber(w)
    else r.t = ty end
    local width = ({ u8 = 1, b8 = 1, u16 = 2, u32 = 4, f = 1 })[r.t] or r.len
    r.size = width * (r.n or 1)
    rows[#rows + 1] = r
    for o = off, off + r.size - 1 do used[o] = true end
  end
  for _, p in ipairs(IDS) do
    if not used[p[2]] and not used[p[2] + 1] then
      rows[#rows + 1] = { name = p[1], off = p[2], t = "u8", size = 1 }
      rows[#rows + 1] = { name = p[3], off = p[2] + 1, t = "u8", size = 1 }
    end
  end
  table.insert(rows, 1, { name = "active", off = 1, t = "b8", size = 1 })
  return rows
end

local ROWS = {}
for k, d in pairs(DESC) do ROWS[k] = parse(d) end
local COMMON_ROWS = parse(COMMON_DESC)
local function rowsOf(kind) return ROWS[kind] or COMMON_ROWS end
local MODELED = {}
for k in pairs(DESC) do MODELED[#MODELED + 1] = k end
table.sort(MODELED)

local function b(s, o) return s:byte(o + 1) end
local function le(s, o, n)
  local v = 0
  for i = n - 1, 0, -1 do v = v * 256 + b(s, o + i) end
  return v
end

local function decodeSlot(s)
  local kind = b(s, 0)
  local zero = true
  for i = 1, SIZE - 1 do if b(s, i) ~= 0 then zero = false end end
  if kind == 0 and zero then return { kind = 0, active = false } end
  local out = { kind = kind }
  for _, r in ipairs(rowsOf(kind)) do
    local w = ({ u8 = 1, u16 = 2, u32 = 4 })[r.t]
    if r.t == "b8" then out[r.name] = b(s, r.off) ~= 0
    elseif r.t == "t" then out[r.name] = codec.decodeString(s, r.off, r.len)
    elseif r.t == "f" then out[r.name] = math.floor(b(s, r.off) / 2 ^ r.shift) % 2 ^ r.width
    elseif r.n then
      local list = {}
      for i = 1, r.n do list[i] = le(s, r.off + (i - 1) * w, w) end
      out[r.name] = list
    else out[r.name] = le(s, r.off, w) end
  end
  return out
end

local function putLE(t, o, v, n)
  for i = 0, n - 1 do t[o + i] = math.floor(v / 256 ^ i) % 256 end
end

local function canonical(show)
  local t = {}
  for i = 0, SIZE - 1 do t[i] = 0 end
  local kind = show.kind or 0
  if not (kind == 0 and show.active ~= true and show.raw == nil and show.trainerIdLo == nil) then
    t[0] = kind
    for _, r in ipairs(rowsOf(kind)) do
      local v = show[r.name]
      local w = ({ u8 = 1, u16 = 2, u32 = 4 })[r.t]
      if r.t == "b8" then t[r.off] = v and 1 or 0
      elseif r.t == "t" then
        local e = codec.encodeString(v, r.len, 0)
        for i = 1, r.len do t[r.off + i - 1] = e:byte(i) end
      elseif r.t == "f" then t[r.off] = t[r.off] + (v or 0) * 2 ^ r.shift
      elseif r.n then for i = 1, r.n do putLE(t, r.off + (i - 1) * w, (v or {})[i] or 0, w) end
      else putLE(t, r.off, v or 0, w) end
    end
  end
  local s = {}
  for i = 0, SIZE - 1 do s[i + 1] = string.char(t[i]) end
  return table.concat(s)
end

local ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
local function randText(rng, len)
  local n, out = rng(len), {}
  for i = 1, n do
    local k = rng(#ALPHA) + 1
    out[i] = ALPHA:sub(k, k)
  end
  return table.concat(out)
end

local function u32(rng) return rng(65536) * 65536 + rng(65536) end

local function randValue(rng, r)
  if r.t == "b8" then return rng(2) == 1 end
  if r.t == "t" then return randText(rng, r.len) end
  if r.t == "f" then return rng(2 ^ r.width) end
  local function one()
    if r.t == "u8" then return rng(256) end
    if r.t == "u16" then return rng(65536) end
    return u32(rng)
  end
  if r.n then
    local list = {}
    for i = 1, r.n do list[i] = one() end
    return list
  end
  return one()
end

local function randKind(rng, group)
  if group == "unknown" then return UNKNOWN[rng(#UNKNOWN) + 1] end
  if group == "raw0" then return 0 end
  return group
end

local function randShow(rng, group)
  if group == "blank" then return { kind = 0, active = false } end
  local kind = randKind(rng, group)
  local show = { kind = kind }
  for _, r in ipairs(rowsOf(kind)) do show[r.name] = randValue(rng, r) end
  if group == "raw0" then show.raw[1] = 1 + rng(255) end
  return show
end

local function randSlotBytes(rng, group)
  local t = {}
  if group == "blank" then
    for i = 0, SIZE - 1 do t[i] = 0 end
  else
    for i = 0, SIZE - 1 do t[i] = rng(256) end
    t[0] = randKind(rng, group)
    if group == "raw0" then t[2] = 1 + rng(255) end
    t[1] = rng(2)
    for _, r in ipairs(rowsOf(t[0])) do
      if r.t == "b8" then t[r.off] = rng(2)
      elseif r.t == "t" then
        local e = codec.encodeString(randText(rng, r.len + 1), r.len, 0)
        local ended = false
        for i = 1, r.len do
          if ended then t[r.off + i - 1] = rng(256) else t[r.off + i - 1] = e:byte(i) end
          if e:byte(i) == 0xFF then ended = true end
        end
      end
    end
  end
  return t
end

local GROUPS = {}
for _, k in ipairs(MODELED) do GROUPS[#GROUPS + 1] = k end
GROUPS[#GROUPS + 1] = "unknown"
GROUPS[#GROUPS + 1] = "raw0"
GROUPS[#GROUPS + 1] = "blank"

local function label(g) return type(g) == "number" and ("kind " .. g) or g end

local function slotStr(blk, i) return blk.sb1:sub(BASE + i * SIZE + 1, BASE + (i + 1) * SIZE) end
local function region(blk) return blk.sb1:sub(BASE + 1, BASE + COUNT * SIZE) end

local function buildCart(slots)
  return H.cart(V, function(w)
    for i = 0, COUNT - 1 do
      for k = 0, SIZE - 1 do w.sb1[BASE + i * SIZE + k] = slots[i][k] end
    end
  end)
end

local function layout(seed, part)
  local out = {}
  for i = 0, COUNT - 1 do
    local idx = (seed + part * COUNT + i) % #GROUPS + 1
    out[i] = GROUPS[idx]
  end
  return out
end

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local o = {}
  for k, x in pairs(v) do o[k] = deepCopy(x) end
  return o
end

local function diffs(a, b) return #H.deepEqual(a, b) end

local r1Tpl, r1Fresh, r1Seen = {}, {}, {}
for seed = 1, 50 do
  local rng = H.rng(seed * 7919)
  for part = 0, 1 do
    local groups = layout(seed, part)
    local slots = {}
    for i = 0, COUNT - 1 do slots[i] = randSlotBytes(rng, groups[i]) end
    local bytes = buildCart(slots)
    local src = H.blocks(bytes, V)
    local save = H.import(V, bytes)
    local tpl = H.blocks(H.withTemplate(V, save, bytes), V)
    local fresh = H.blocks(H.fresh(V, save), V)
    for i = 0, COUNT - 1 do
      local g = groups[i]
      r1Seen[g] = (r1Seen[g] or 0) + 1
      local a = slotStr(src, i)
      if slotStr(tpl, i) ~= a and not r1Tpl[g] then r1Tpl[g] = ("seed %d slot %d"):format(seed, i) end
      local want = decodeSlot(a)
      local f = slotStr(fresh, i)
      if (diffs(decodeSlot(f), want) > 0 or f ~= canonical(want)) and not r1Fresh[g] then
        r1Fresh[g] = ("seed %d slot %d: %s"):format(seed, i, table.concat(H.deepEqual(decodeSlot(f), want), "; "))
      end
    end
  end
end
for _, g in ipairs(GROUPS) do
  check((r1Seen[g] or 0) >= 50, "R1 " .. label(g) .. " covered by at least 50 random slots (" .. tostring(r1Seen[g]) .. ")")
  check(r1Tpl[g] == nil, "R1 " .. label(g) .. " template export keeps the slot bytes " .. tostring(r1Tpl[g] or ""))
  check(r1Fresh[g] == nil, "R1 " .. label(g) .. " templateless export writes the canonical decoded slot "
    .. tostring(r1Fresh[g] or ""))
end

local baseBytes = H.cart(V)
local r2Dec, r2Back, r2Fix, r2Can = {}, {}, {}, {}
for seed = 1, 50 do
  local rng = H.rng(seed * 104729)
  for part = 0, 1 do
    local groups = layout(seed, part)
    local save = H.import(V, baseBytes)
    save.tvShows = {}
    for i = 0, COUNT - 1 do save.tvShows[i] = randShow(rng, groups[i]) end
    local want = deepCopy(save.tvShows)
    local out1 = H.fresh(V, save)
    local blk1 = H.blocks(out1, V)
    local back = H.import(V, out1)
    local blk2 = H.blocks(H.fresh(V, back), V)
    for i = 0, COUNT - 1 do
      local g = groups[i]
      local s = slotStr(blk1, i)
      if diffs(decodeSlot(s), want[i]) > 0 and not r2Dec[g] then
        r2Dec[g] = table.concat(H.deepEqual(decodeSlot(s), want[i]), "; ")
      end
      if s ~= canonical(want[i]) and not r2Can[g] then r2Can[g] = ("seed %d slot %d"):format(seed, i) end
      if diffs(back.tvShows[i], want[i]) > 0 and not r2Back[g] then
        r2Back[g] = table.concat(H.deepEqual(back.tvShows[i], want[i]), "; ")
      end
      if slotStr(blk2, i) ~= s and not r2Fix[g] then r2Fix[g] = ("seed %d slot %d"):format(seed, i) end
    end
  end
end
for _, g in ipairs(GROUPS) do
  check(r2Dec[g] == nil, "R2 " .. label(g) .. " fresh export decodes to the engine values " .. tostring(r2Dec[g] or ""))
  check(r2Can[g] == nil, "R2 " .. label(g) .. " fresh export is the canonical cleared-slot encoding " .. tostring(r2Can[g] or ""))
  check(r2Back[g] == nil, "R2 " .. label(g) .. " re-import is deep-equal " .. tostring(r2Back[g] or ""))
  check(r2Fix[g] == nil, "R2 " .. label(g) .. " second fresh export is byte-identical " .. tostring(r2Fix[g] or ""))
end

local function mutate(rng, r, v)
  if r.t == "b8" then return not v end
  if r.t == "t" then
    local nv = v
    while nv == v do nv = randText(rng, r.len) end
    return nv
  end
  if r.t == "f" then return (v + 1 + rng(2 ^ r.width - 1)) % 2 ^ r.width end
  local mod = ({ u8 = 256, u16 = 65536, u32 = 4294967296 })[r.t]
  if r.n then
    local list = deepCopy(v)
    local k = rng(r.n) + 1
    list[k] = (list[k] + 1 + rng(mod - 1)) % mod
    return list, k
  end
  return (v + 1 + rng(mod - 1)) % mod
end

local function changedOffsets(a, b)
  local out = {}
  for _, blk in ipairs({ "sb2", "sb1", "storage" }) do
    local x, y = a[blk], b[blk]
    for o = 1, math.max(#x, #y) do
      if x:byte(o) ~= y:byte(o) then out[#out + 1] = { blk, o - 1 } end
    end
  end
  return out
end

for gi, g in ipairs(GROUPS) do
  if g ~= "blank" then
    local rng = H.rng(gi * 31337)
    local P = gi % COUNT
    local slots = {}
    for i = 0, COUNT - 1 do slots[i] = randSlotBytes(rng, i == P and g or GROUPS[rng(#GROUPS) + 1]) end
    local bytes = buildCart(slots)
    local save = H.import(V, bytes)
    local baseOut = H.blocks(H.withTemplate(V, deepCopy(save), bytes), V)
    local kind = save.tvShows[P].kind
    local bad = {}
    for _, r in ipairs(rowsOf(kind)) do
      local s2 = deepCopy(save)
      local nv, k = mutate(rng, r, s2.tvShows[P][r.name])
      s2.tvShows[P][r.name] = nv
      local out = H.withTemplate(V, s2, bytes)
      local got = H.blocks(out, V)
      local lo, hi = BASE + P * SIZE + r.off, BASE + P * SIZE + r.off + r.size - 1
      if k then
        local w = r.size / r.n
        lo, hi = lo + (k - 1) * w, lo + k * w - 1
      end
      local ch = changedOffsets(baseOut, got)
      local okRange = #ch > 0
      for _, c in ipairs(ch) do
        if c[1] ~= "sb1" or c[2] < lo or c[2] > hi then okRange = false end
      end
      local back = H.import(V, out)
      local want = deepCopy(save.tvShows[P])
      want[r.name] = nv
      if not okRange then bad[#bad + 1] = r.name .. " (bytes outside its range changed or none changed)" end
      if diffs(back.tvShows[P], want) > 0 then bad[#bad + 1] = r.name .. " (re-import differs)" end
    end
    check(#bad == 0, "mutation " .. label(g) .. " (kind " .. kind .. ") each field touches only its own bytes and re-imports: "
      .. table.concat(bad, ", "))
  end
end

do
  local rng = H.rng(4242)
  local slots = {}
  for i = 0, COUNT - 1 do slots[i] = randSlotBytes(rng, MODELED[i % #MODELED + 1]) end
  local bytes = buildCart(slots)
  local src = H.blocks(bytes, V)
  local save = H.import(V, bytes)
  local bad = {}
  for i = 0, COUNT - 1 do
    local s2 = deepCopy(save)
    local other = MODELED[(i + 7) % #MODELED + 1]
    local show = randShow(rng, other)
    s2.tvShows[i] = show
    local out = H.blocks(H.withTemplate(V, s2, bytes), V)
    if slotStr(out, i) ~= canonical(show) then bad[#bad + 1] = i end
    for j = 0, COUNT - 1 do
      if j ~= i and slotStr(out, j) ~= slotStr(src, j) then bad[#bad + 1] = i .. "/" .. j end
    end
  end
  check(#bad == 0, "a kind change clears the whole slot like DeleteTVShowInArrayByIdx before writing: " .. table.concat(bad, ","))

  local s3 = deepCopy(save)
  s3.tvShows[2] = { kind = 0, active = false }
  local out = H.blocks(H.withTemplate(V, s3, bytes), V)
  eq(slotStr(out, 2), string.rep("\0", SIZE), "a deleted show exports as an all-zero slot")

  local s4 = deepCopy(save)
  s4.tvShows[5], s4.tvShows[6], s4.tvShows[7] = s4.tvShows[6], s4.tvShows[7], { kind = 0, active = false }
  local moved = H.blocks(H.withTemplate(V, s4, bytes), V)
  check(slotStr(moved, 5) == slotStr(src, 6) and slotStr(moved, 6) == slotStr(src, 7),
    "CompactTVShowArray moves carry the whole 36-byte slot including unmodeled bytes")
  eq(slotStr(moved, 7), string.rep("\0", SIZE), "the vacated compacted slot is cleared")
end

do
  local blankCart = buildCart((function()
    local t = {}
    for i = 0, COUNT - 1 do
      t[i] = {}
      for k = 0, SIZE - 1 do t[i][k] = 0 end
    end
    return t
  end)())
  local s = H.import(V, blankCart)
  local bad = 0
  for i = 0, COUNT - 1 do
    if diffs(s.tvShows[i], { kind = 0, active = false }) > 0 then bad = bad + 1 end
  end
  eq(bad, 0, "all-zero cart slots import as exactly { kind = TVSHOW_OFF_AIR, active = false }")
  local save = H.import(V, blankCart)
  save.tvShows = {}
  for i = 0, COUNT - 1 do save.tvShows[i] = { kind = 0, active = false } end
  eq(region(H.blocks(H.fresh(V, save), V)), string.rep("\0", SIZE * COUNT),
    "templateless export of 25 blank shows is the ClearTVShowData all-zero region")
  local save2 = H.import(V, blankCart)
  save2.tvShows = nil
  save2.modData = save2.modData or {}
  eq(region(H.blocks(H.fresh(V, save2), V)), string.rep("\0", SIZE * COUNT),
    "a save without tvShows exports the cleared region")
end

do
  local shows, i = {}, 0
  for _, k in ipairs(MODELED) do
    local hi, lo = { kind = k, active = true }, { kind = k, active = false }
    for _, r in ipairs(ROWS[k]) do
      if r.name ~= "active" then
        if r.t == "b8" then hi[r.name], lo[r.name] = true, false
        elseif r.t == "t" then hi[r.name], lo[r.name] = string.rep("Z", r.len), ""
        elseif r.t == "f" then hi[r.name], lo[r.name] = 2 ^ r.width - 1, 0
        else
          local max = ({ u8 = 255, u16 = 65535, u32 = 4294967295 })[r.t]
          if r.n then
            hi[r.name], lo[r.name] = {}, {}
            for j = 1, r.n do hi[r.name][j], lo[r.name][j] = max, 0 end
          else
            hi[r.name], lo[r.name] = max, 0
          end
        end
      end
    end
    shows[#shows + 1] = hi
    shows[#shows + 1] = lo
  end
  for _, k in ipairs(UNKNOWN) do
    local raw = {}
    for j = 1, 28 do raw[j] = (j * 37 + k) % 256 end
    shows[#shows + 1] = { kind = k, active = true, raw = raw, srcTrainerId2Lo = 255, srcTrainerId2Hi = 0,
      srcTrainerIdLo = 1, srcTrainerIdHi = 254, trainerIdLo = 255, trainerIdHi = 255 }
  end
  local bad = {}
  for start = 1, #shows, COUNT do
    local save = H.import(V, baseBytes)
    save.tvShows = {}
    for j = 0, COUNT - 1 do save.tvShows[j] = shows[start + j] or { kind = 0, active = false } end
    local want = deepCopy(save.tvShows)
    local out = H.fresh(V, save)
    local blk = H.blocks(out, V)
    local back = H.import(V, out)
    for j = 0, COUNT - 1 do
      if diffs(decodeSlot(slotStr(blk, j)), want[j]) > 0 or diffs(back.tvShows[j], want[j]) > 0 then
        bad[#bad + 1] = tostring(want[j].kind)
      end
    end
  end
  check(#bad == 0, "boundary values (max u8/u16/u32/bits, full-length names, empty names, unknown kinds) round-trip: "
    .. table.concat(bad, ","))

  local slots = {}
  for j = 0, COUNT - 1 do slots[j] = randSlotBytes(H.rng(j + 1), 1) end
  for k = 0, 7 do slots[0][0x10 + k] = 0xFF end
  for k = 0, 7 do slots[1][0x10 + k] = 0xBB + k end
  local bytes = buildCart(slots)
  local save = H.import(V, bytes)
  eq(save.tvShows[0].playerName, "", "an all-0xFF name decodes empty")
  eq(#save.tvShows[1].playerName, 8, "an unterminated 8-byte name decodes all 8 characters")
  local src, tpl = H.blocks(bytes, V), H.blocks(H.withTemplate(V, save, bytes), V)
  check(slotStr(tpl, 0) == slotStr(src, 0) and slotStr(tpl, 1) == slotStr(src, 1), "0xFF and unterminated names keep template bytes")
  local fresh = H.blocks(H.fresh(V, save), V)
  eq(slotStr(fresh, 1):sub(0x11, 0x18), slotStr(src, 1):sub(0x11, 0x18), "an unterminated name re-encodes without a terminator")
  eq(slotStr(fresh, 0):sub(0x11, 0x18), "\255" .. string.rep("\0", 7), "an empty name exports EOS then the cleared slot zeros")
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
require("src.import.gba.versions").select("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
if not cache:read("data/generated/gba/native/manifest.lua") or not cache:read("data/generated/gba/pokemon/national.lua") then
  print("[skip] gen3_sec_tv_test engine consumption: no Emerald cache for identity "
    .. tostring(os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d"))
else
  Dataset.mountExtractRoots()
  Dataset.hydrate({ data = {} })
  local Tv = require("src.core.game3.rse.tv")
  local Schema = require("src.core.game3.save_schema_firered")
  local SaveConvert = require("src.save_convert.SaveConvert")
  local rng = H.rng(99)
  local slots = {}
  local kinds = { 1, 6, 11, 41, 0, 0, 21, 29, 38, 13, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 25 }
  for i = 0, COUNT - 1 do slots[i] = randSlotBytes(rng, kinds[i + 1] == 0 and "blank" or kinds[i + 1]) end
  slots[0][1], slots[1][1], slots[9][1] = 1, 1, 0
  local bytes = buildCart(slots)
  local save = assert(SaveConvert.importSav(bytes, "emerald", "emerald"))
  local ok, sess = pcall(Schema.fromSaveTable, save)
  check(ok, "imported TV shows load into a session (" .. tostring(not ok and sess or "") .. ")")
  if ok then
    local list = Tv.state(sess).tvShows
    eq(Tv.selectedShowKind(sess, 0), 1, "the session sees the cart fan club letter in slot 0")
    eq(list[0].playerName, codec.decodeString(slotStr(H.blocks(bytes, V), 0), 0x10, 8), "letter player name reaches the engine")
    check(Tv.isShowAlreadyInQueue(sess, 6), "IsTVShowAlreadyInQueue finds the cart bravo trainer show")
    eq(Tv.firstActiveNotOutbreak(sess), 0, "the first active non-outbreak show is the cart letter")
    eq(Tv.groupOf(list[9].kind), Tv.TVGROUP.NORMAL, "an unknown kind 13 keeps its tag in the engine")
    local mixed = Tv.copy(list)
    Tv.deleteShow(mixed, 9)
    check(mixed[9].raw == nil and mixed[9].kind == 0 and list[9].raw ~= nil, "deleteShow clears a raw-carrying show")
    Tv.compactShows(mixed)
    eq(mixed[6].kind, 29, "compactShows moves record-mix shows past cleared slots")
    local back = Schema.toSaveTable(sess)
    eq(#H.deepEqual(back.tvShows, save.tvShows), 0, "toSaveTable returns the imported shows unchanged")
    local out = assert(SaveConvert.exportSav(back, "emerald", bytes))
    eq(region(H.blocks(out, V)), region(H.blocks(bytes, V)), "session round-trip keeps the TV region byte-identical")
  end
end

T.finish()
