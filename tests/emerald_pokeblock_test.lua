package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local PRET = os.getenv("POKEPORT_PRET_EMERALD") or "../pokeemerald"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_pokeblock_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_pokeblock_test: skipped (" .. ROM_PATH .. " is not Emerald)")
  os.exit(0)
end

local rom = { id = "emerald", size = #data }
function rom.get(_, o) return data:byte(o + 1) end
function rom.u16(_, o) local a, b = data:byte(o + 1, o + 2); return a + b * 256 end
function rom.u32(_, o)
  local a, b, c, d = data:byte(o + 1, o + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end
function rom.readString(_, o, n) return data:sub(o + 1, o + n) end

local files = {}
local cache = {
  write = function(_, rel, bytes) files[rel] = bytes; return true end,
  read = function(_, rel) return files[rel] end,
}

local ROOT = "data/generated/gba"
local PBX = require("src.import.gba.rse.pokeblock_extract")
local BTX = require("src.import.gba.rse.berry_tag_extract")

for _, M in ipairs({ PBX, BTX }) do
  check(not M.ready(cache, ROOT), M.SUB .. " not ready before run")
  local ok = M.run(rom, cache, { cacheRoot = ROOT })
  eq(ok, true, M.SUB .. " extractor ran")
  check(M.ready(cache, ROOT), M.SUB .. " ready after run")
  for _, rel in ipairs(M.REQUIRED) do check(files[ROOT .. "/" .. rel] ~= nil, rel .. " written") end
end

local function manifestOf(sub)
  return assert(load(files[ROOT .. "/" .. sub .. "/manifest.lua"], "@m", "t", {}))()
end
local pb = manifestOf(PBX.SUB)
local bt = manifestOf(BTX.SUB)

local function readPret(rel)
  local h = io.open(PRET .. "/" .. rel, "rb")
  if not h then return nil end
  local s = h:read("*a")
  h:close()
  return s
end

local function numbers(s)
  local out = {}
  for n in s:gmatch("%-?%d+") do out[#out + 1] = tonumber(n) end
  return out
end

local pokeblockC = readPret("src/pokeblock.c")
local compat = {}
if pokeblockC then
  -- pokeemerald/src/pokeblock.c:136
  local body = pokeblockC:match("gPokeblockFlavorCompatibilityTable%b[]%s*=%s*(%b{})")
  local rows = {}
  for line in body:gmatch("[^\n]+") do
    local vals = line:match("^%s*([%-%d,%s]+)//")
    if vals then for _, n in ipairs(numbers(vals)) do rows[#rows + 1] = n end end
  end
  eq(#rows, 125, "pret compatibility table has 25 x 5 entries")
  local S = require("src.import.gba.syms").of("emerald")
  local off = S.off("gPokeblockFlavorCompatibilityTable")
  local same = true
  for i = 0, 124 do
    local v = rom:get(off + i)
    if v >= 128 then v = v - 256 end
    compat[i] = v
    if v ~= rows[i + 1] then same = false end
  end
  check(same, "ROM gPokeblockFlavorCompatibilityTable equals pret source")

  -- pokeemerald/src/pokeblock.c:252
  local fav = pokeblockC:match("sFavoritePokeblocksTable%b[]%s*=%s*(%b{})")
  local favOk = fav ~= nil
  local i = 0
  for row in (fav or ""):gmatch("{([^{}]+)}") do
    i = i + 1
    local n = numbers(row)
    local got = pb.favorites[i]
    if not got or got.spicy ~= n[1] or got.dry ~= n[2] or got.sweet ~= n[3] or got.bitter ~= n[4]
        or got.sour ~= n[5] or got.feel ~= n[6] or got.color ~= i then
      favOk = false
    end
  end
  check(favOk and i == 5, "favorites equal sFavoritePokeblocksTable")
end

local menuC = readPret("src/menu_specialized.c")
if menuC then
  -- pokeemerald/src/menu_specialized.c:88
  local body = menuC:match("sConditionToLineLength%b[]%s*=%s*(%b{})")
  local rows = numbers(body)
  local same = #rows == 256
  for k = 1, 256 do if pb.lineLength[k] ~= rows[k] then same = false end end
  check(same, "condition line lengths equal pret sConditionToLineLength")
end

local feedC = readPret("src/pokeblock_feed.c")
if feedC then
  -- pokeemerald/src/pokeblock_feed.c:187
  local body = feedC:match("sMonPokeblockAnims%b[]%b[]%s*=%s*(%b{})")
  local rows = {}
  for row in body:gmatch("{([^{}]+)}") do
    local n = numbers(row:gsub("FALSE", "0"):gsub("TRUE", "1"))
    rows[#rows + 1] = n
  end
  eq(#rows, #pb.feedAnims, "feed anim stage count equals pret")
  local same = true
  for k, n in ipairs(rows) do
    for j = 1, 10 do if pb.feedAnims[k][j] ~= n[j] then same = false end end
  end
  check(same, "sMonPokeblockAnims rows equal pret")
  eq(#pb.natureAnims, 25, "one feed anim per nature")
  eq(pb.natureAnims[2][1], 3, "Lonely starts at ANIM_LONELY (3)")
  eq(pb.natureAnims[3][2], 1, "Brave turns up (AFFINE_TURN_UP)")
end

eq(#pb.affine.mon, 21, "sAffineAnims_Mon has 21 entries")
eq(pb.affine.caseThrow[1][1].xScale, -256, "case throw starts flipped")
eq(#pb.colors, 14, "14 pokeblock color palettes")
eq(bt.berryCount, 43, "43 berry pics")
eq(#bt.berryPals, 43, "43 berry palettes")
eq(bt.firmness[1], "gBerryFirmnessString_VerySoft", "firmness strings by name")

local Pokeblock = require("src.core.game3.rse.pokeblock")
Pokeblock.setCompatTable(compat)
Pokeblock.setFavoriteTable(pb.favorites)
local names = {}
for c = 0, 14 do names[c] = "C" .. c end
Pokeblock.setNames(names)

local s = { party = {} }
Pokeblock.clearAll(s)
eq(#s.pokeblocks, 40, "40 pokeblock slots")
eq(Pokeblock.firstFreeSlot(s), 0, "first free slot on an empty case")
check(Pokeblock.add(s, { color = 1, spicy = 20, feel = 20 }), "add a red block")
check(Pokeblock.add(s, { color = 2, dry = 30, feel = 5 }), "add a blue block")
check(Pokeblock.add(s, { color = 3, sweet = 40, feel = 120 }), "add a pink block")
eq(Pokeblock.firstFreeSlot(s), 3, "first free slot after three adds")
check(Pokeblock.tryClear(s, 1), "clear the middle block")
check(not Pokeblock.tryClear(s, 1), "clearing an empty slot fails")
eq(Pokeblock.firstFreeSlot(s), 1, "the cleared slot is free again")
Pokeblock.compact(s)
eq(Pokeblock.get(s, 0).color, 1, "compact keeps the first block")
eq(Pokeblock.get(s, 1).color, 3, "compact moves the pink block up")
eq(Pokeblock.count(s), 2, "two blocks after compaction")
eq(Pokeblock.feel(Pokeblock.get(s, 1)), 99, "feel caps at 99 for display")
eq(Pokeblock.highestFlavorLevel({ spicy = 3, dry = 9, sweet = 1, bitter = 0, sour = 7 }), 9, "highest flavor level")
eq(Pokeblock.flavorOf({ spicy = 3, dry = 9, sweet = 1, bitter = 0, sour = 7 }), 1, "strongest flavor is dry")
for c = 1, 40 do Pokeblock.slots(s)[c] = Pokeblock.new({ color = (c % 14) + 1 }) end
eq(Pokeblock.firstFreeSlot(s), -1, "a full case has no free slot")
check(not Pokeblock.add(s, { color = 1 }), "adding to a full case fails")

Pokeblock.clearAll(s)
for c = 1, 4 do Pokeblock.add(s, { color = c }) end
Pokeblock.move(s, 0, 3)
eq(Pokeblock.get(s, 0).color .. Pokeblock.get(s, 1).color .. Pokeblock.get(s, 2).color .. Pokeblock.get(s, 3).color,
  "2314", "moving slot 0 down to 3 lands above the target")
Pokeblock.move(s, 3, 0)
eq(Pokeblock.get(s, 0).color .. Pokeblock.get(s, 1).color, "42", "moving slot 3 up to 0")

-- pokeemerald/src/pokeblock.c:1407
local LONELY, HARDY, MODEST = 1, 0, 15
eq(Pokeblock.gain(LONELY, { spicy = 20 }), 20, "Lonely likes spicy")
eq(Pokeblock.gain(LONELY, { sour = 20 }), -20, "Lonely dislikes sour")
eq(Pokeblock.gain(HARDY, { spicy = 20, sour = 20 }), 0, "Hardy is neutral")
eq(Pokeblock.favoriteName(LONELY), "C1", "Lonely's favorite is the red block")
eq(Pokeblock.favoriteName(MODEST), "C2", "Modest's favorite is the blue block")
eq(Pokeblock.favoriteName(HARDY), nil, "Hardy has no favorite")

local mon = { personality = LONELY, species = 1, level = 5 }
local res = Pokeblock.feed({ color = 1, spicy = 30, sour = 10, feel = 20 }, mon)
eq(res.gain, 20, "feeding gain from nature")
eq(mon.contest.cool, 33, "liked flavor adds the rounded tenth (30 -> 33)")
eq(mon.contest.tough, 10, "disliked flavor adds the base amount")
eq(mon.contest.sheen, 20, "sheen rises by feel")
eq(res.enhancements[1], 33, "coolness enhancement")
eq(res.enhancements[3], 0, "no smartness change")

mon.contest.cool = 250
mon.contest.sheen = 250
Pokeblock.feed({ color = 1, spicy = 30, feel = 20 }, mon)
eq(mon.contest.cool, 255, "conditions clamp at 255")
eq(mon.contest.sheen, 255, "sheen clamps at 255")
check(Pokeblock.isSheenMaxed(mon), "sheen maxed")
local before = mon.contest.tough
check(not Pokeblock.applyToMon({ sour = 50, feel = 1 }, mon, 0), "a maxed-sheen mon won't eat")
eq(mon.contest.tough, before, "nothing changes once sheen is maxed")

local sad = { personality = LONELY }
Pokeblock.feed({ color = 1, spicy = 15, sour = 26, feel = 1 }, sad)
eq(sad.contest.tough, 23, "disliked-direction block trims the disliked stat (26 - 3)")
eq(sad.contest.cool, 15, "liked stat untouched when the gain is negative")

eq(Pokeblock.sparkles(0), 0, "no sheen, one sparkle")
eq(Pokeblock.sparkles(255), 9, "max sheen shows all sparkles")
eq(Pokeblock.sparkles(28), 0, "sheen 28 still one sparkle")
eq(Pokeblock.sparkles(29), 1, "sheen 29 adds a sparkle")

-- pokeemerald/src/safari_zone.c:203
Pokeblock.clearAll(s)
Pokeblock.add(s, { color = 5, sour = 20, feel = 10 })
Pokeblock.add(s, { color = 1, spicy = 20, feel = 10 })
s.safari = { feeders = {} }
eq(Pokeblock.activateFeeder(s, 0, 20, 20, 3), 0, "feeder 0 placed")
eq(Pokeblock.activateFeeder(s, 1, 30, 20, 3), 1, "feeder 1 placed")
eq((Pokeblock.feederInFront(s, 20, 20, 3)), 0, "feeder in front found")
eq((Pokeblock.feederInFront(s, 20, 21, 3)), -1, "no feeder one tile off")
eq((Pokeblock.feederInFront(s, 20, 20, 4)), -1, "feeder is per map number")
eq(Pokeblock.feederWithinRange(s, 22, 22, 3), 0, "within five steps of feeder 0")
eq(Pokeblock.feederWithinRange(s, 31, 20, 3), -1, "the running offset bug misses feeder 1")
eq(Pokeblock.activeFeederBlock(s, 22, 22, 3).color, 5, "active block is the placed copy")
for _ = 1, 99 do
  for _, row in ipairs(s.safari.feeders) do
    if row.stepCounter > 0 then row.stepCounter = row.stepCounter - 1 end
  end
end
eq((Pokeblock.feederInFront(s, 20, 20, 3)), 0, "feeder lasts 99 steps")
for _, row in ipairs(s.safari.feeders) do
  if row.stepCounter > 0 then row.stepCounter = row.stepCounter - 1 end
end
eq((Pokeblock.feederInFront(s, 20, 20, 3)), -1, "feeder clears after 100 steps")

local Graph = require("src.ui.game3.rse.condition_graph")
local g = Graph.new(pb)
local zero = g:calcPositions({ 0, 0, 0, 0, 0 }, {})
eq(zero[Graph.GRAPH.COOL].x, 155, "cool vertex on the center line")
eq(zero[Graph.GRAPH.COOL].y, 91 - 4, "cool vertex four pixels up at 0")
local max = g:calcPositions({ 255, 255, 255, 255, 255 }, {})
eq(max[Graph.GRAPH.COOL].y, 91 - 35, "cool vertex 35 up at 255")
check(max[Graph.GRAPH.BEAUTY].x > 155 and max[Graph.GRAPH.TOUGH].x < 155, "beauty right, tough left")
g:setNewPositions(zero, max)
local steps = 0
while g:tryUpdate() do steps = steps + 1 end
eq(steps, 9, "graph morphs over ten updates")
local spans = g:calcSpans()
check(spans and spans[0] ~= nil, "graph scanlines computed")
local sp = Graph.Sparkles.new(3, pb.sparkleCoords)
for _ = 1, 200 do sp:update() end
check(true, "sparkles cycle without error")

local Tag = require("src.ui.game3.rse.berry_tag")
local inches, frac = Tag.sizeParts(20)
eq(inches .. "." .. frac, "0.8", "Cheri 20 mm reads 0.8 inches")
inches, frac = Tag.sizeParts(285)
eq(inches .. "." .. frac, "11.2", "285 mm reads 11.2 inches")

T.finish("emerald_pokeblock_test")
