package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local PRET = os.getenv("POKEPORT_PRET_EMERALD") or "../pokeemerald"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_pokenav_condition_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_pokenav_condition_test: skipped (" .. ROM_PATH .. " is not Emerald)")
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
local X = require("src.import.gba.rse.pokenav_condition_extract")
check(not X.ready(cache, ROOT), "condition extractor not ready before run")
eq(X.run(rom, cache, { cacheRoot = ROOT }), true, "condition/ribbons extractor ran")
check(X.ready(cache, ROOT), "condition extractor ready after run")
for _, rel in ipairs(X.REQUIRED) do check(files[ROOT .. "/" .. rel] ~= nil, rel .. " written") end
local man = assert(load(files[ROOT .. "/" .. X.SUB .. "/manifest.lua"], "@m", "t", {}))()

local function readPret(rel)
  local h = io.open(PRET .. "/" .. rel, "rb")
  if not h then return nil end
  local s = h:read("*a")
  h:close()
  return s
end

-- pokeemerald/src/pokenav_ribbons_summary.c:123
local rs = readPret("src/pokenav_ribbons_summary.c")
if rs then
  local body = rs:match("sRibbonData%[%]%s*=%s*(%b{})")
  local rows = {}
  for bits, n, id, gift in (body or ""):gmatch("{(%d+),%s*(%d+),%s*([%w_]+),%s*(%u+)}") do
    rows[#rows + 1] = { tonumber(bits), tonumber(n), id, gift == "TRUE" }
  end
  eq(#rows, #man.ribbonData, "sRibbonData row count vs pret")
  local ids = { CHAMPION_RIBBON = 0, COOL_RIBBON_NORMAL = 1, BEAUTY_RIBBON_NORMAL = 5, CUTE_RIBBON_NORMAL = 9,
    SMART_RIBBON_NORMAL = 13, TOUGH_RIBBON_NORMAL = 17, WINNING_RIBBON = 21, VICTORY_RIBBON = 22, ARTIST_RIBBON = 23,
    EFFORT_RIBBON = 24, MARINE_RIBBON = 25, LAND_RIBBON = 26, SKY_RIBBON = 27, COUNTRY_RIBBON = 28,
    NATIONAL_RIBBON = 29, EARTH_RIBBON = 30, WORLD_RIBBON = 31 }
  for i, r in ipairs(rows) do
    local m = man.ribbonData[i]
    eq(m.numBits, r[1], "sRibbonData[" .. (i - 1) .. "].numBits")
    eq(m.ribbonId, ids[r[3]], "sRibbonData[" .. (i - 1) .. "] " .. r[3])
    eq(m.isGift, r[4], "sRibbonData[" .. (i - 1) .. "].isGiftRibbon")
  end
  -- pokeemerald/src/pokenav_ribbons_summary.c:1089
  local gfxBody = rs:match("sRibbonGfxData%[%]%s*=%s*(%b{})")
  local n = 0
  for _ in (gfxBody or ""):gmatch("%[[%w_]+%]%s*=") do n = n + 1 end
  eq(n, 32, "sRibbonGfxData has 32 rows in pret")
  eq(man.ribbonGfx[0].tile, 0, "CHAMPION uses icon 0")
  eq(man.ribbonGfx[4].tile, 4, "COOL MASTER uses the master icon")
  eq(man.ribbonGfx[5].pal, 1, "BEAUTY rows use palette 2")
  eq(man.ribbonGfx[31].tile, 11, "WORLD uses gift icon 3")
end
eq(man.ribbonDescriptions[0][1], "gRibbonDescriptionPart1_Champion", "CHAMPION description line 1")
eq(man.ribbonDescriptions[4][2], "gRibbonDescriptionPart2_MasterRank", "COOL MASTER description line 2")
eq(man.giftRibbonDescriptions[0][1], "gGiftRibbonDescriptionPart1_2003RegionalTourney", "gift ribbon 1 description")
local ms = readPret("src/menu_specialized.c")
if ms then
  local body = ms:match("sConditionToLineLength%[[^%]]*%]%s*=%s*(%b{})")
  local i, bad = 0, 0
  for v in (body or ""):gmatch("%d+") do
    if man.lineLength[i] ~= tonumber(v) then bad = bad + 1 end
    i = i + 1
  end
  eq(i, 256, "sConditionToLineLength parsed from pret")
  eq(bad, 0, "sConditionToLineLength matches the ROM")
end

local Graph = require("src.ui.game3.rse.pokenav.graph")
eq(Graph.CENTER_Y, 91, "CONDITION_GRAPH_CENTER_Y")
local zero = Graph.calcPositions(man, { [0] = 0, 0, 0, 0, 0 })
eq(zero[0].x .. "," .. zero[0].y, "155,87", "zero COOL vertex")
eq(zero[1].x .. "," .. zero[1].y, "159,90", "zero BEAUTY vertex")
eq(zero[2].x .. "," .. zero[2].y, "158,95", "zero CUTE vertex")
eq(zero[3].x .. "," .. zero[3].y, "152,95", "zero SMART vertex")
eq(zero[4].x .. "," .. zero[4].y, "151,90", "zero TOUGH vertex")
local max = Graph.calcPositions(man, { [0] = 255, 255, 255, 255, 255 })
eq(max[0].y, 91 - 35, "max COOL reaches the graph top")

-- pokeemerald/src/menu_specialized.c:418
local g = Graph.new(man)
g:setNewPositions(Graph.empty(), zero)
while g:tryUpdate() do end
g:draw()
local mask = g:mask()
local rows = {}
for y = 84, 96 do
  local s = {}
  for x = 145, 165 do s[#s + 1] = mask[y] and mask[y][x] and "G" or "." end
  rows[#rows + 1] = y .. " " .. table.concat(s)
end
local want = {
  "84 .....................", "85 .....................", "86 ..........G..........", "87 .........GGG.........",
  "88 .......GGGGGGG.......", "89 ......GGGGGGGGG......", "90 ......GGGGGGGGG......", "91 ......GGGGGGGGG......",
  "92 .......GGGGGGG.......", "93 .......GGGGGGG.......", "94 .......GGGGGGG.......", "95 .....................",
  "96 .....................",
}
eq(table.concat(rows, "\n"), table.concat(want, "\n"), "zero-condition polygon matches the pygba capture (ref/pn/out/11_graph_party.png)")

eq(Graph.numSparkles(0), 0, "sheen 0: no extra sparkles")
eq(Graph.numSparkles(28), 0, "sheen 28: none")
eq(Graph.numSparkles(29), 1, "sheen 29: one")
eq(Graph.numSparkles(254), 8, "sheen 254: eight")
eq(Graph.numSparkles(255), 9, "MAX_SHEEN: nine")

-- pokeemerald/src/menu_specialized.c:351
g:setNewPositions(zero, max)
eq(g.newPositions[9][0].y, max[0].y, "last transition step lands on the target")
eq(g.newPositions[0][0].y, zero[0].y, "first transition step is the origin")

local Ribbons = require("src.core.game3.rse.ribbons")
local mon = { species = 1, level = 5, ribbons = 0 }
Ribbons.set(mon, "cool", 4)
Ribbons.set(mon, "champion", 1)
Ribbons.set(mon, "world", 1)
eq(mon.ribbons, 4 + 2 ^ 15 + 2 ^ 26, "cart ribbon word bit layout (pokemon.h:150)")
eq(mon.championRibbon, true, "championRibbon mirror kept in sync")
eq(Ribbons.count(mon), 6, "MON_DATA_RIBBON_COUNT")
eq(Ribbons.packed(mon), 1 + 4 * 2 + 2 ^ 26, "MON_DATA_RIBBONS packing (pokemon.c:4046)")
local normal, gift = Ribbons.monRibbonIds(mon, man.ribbonData)
eq(table.concat(normal, ","), "0,1,2,3,4", "GetMonRibbons normal ids")
eq(table.concat(gift, ","), "31", "GetMonRibbons gift ids")
local legacy = { species = 1, ribbons = { effort = true }, championRibbon = true }
eq(Ribbons.count(legacy), 2, "legacy table ribbons and championRibbon counted")
eq(Ribbons.get(legacy, "effort"), 1, "legacy effort ribbon read")
eq(Ribbons.count({ species = 1, isEgg = true, ribbons = 4 }), 0, "eggs count no ribbons")
local c = { species = 1, ribbons = 0 }
eq(Ribbons.giveContestRibbon(c, 0, 0), true, "normal rank win gives COOL normal")
eq(Ribbons.giveContestRibbon(c, 0, 0), false, "second normal win gives nothing")
eq(Ribbons.giveContestRibbon(c, 0, 3), true, "master win steps the rank up")
eq(Ribbons.get(c, "cool"), 2, "one step per win (contest_util.c:2003)")
local sess = { party = { { species = 1 }, { species = 2, isEgg = true } } }
local flagged
eq(Ribbons.giveGiftRibbonToParty(sess, 0, 5, function(n) flagged = n end), true, "gift ribbon to party")
eq(sess.giftRibbons[1], 5, "giftRibbons[0] stored")
eq(Ribbons.get(sess.party[1], "marine"), 1, "slot 0 sets MARINE")
eq(Ribbons.get(sess.party[2], "marine"), 0, "eggs skipped")
eq(flagged, "FLAG_SYS_RIBBON_GET", "FLAG_SYS_RIBBON_GET set")
check(Ribbons.anyMonHasRibbon(sess), "AnyMonHasRibbon after the gift")
local SaveSections = require("src.core.game3.save_sections")
local fresh = {}
SaveSections.register("giftRibbons_probe", SaveSections.fields({ "giftRibbons" }))
local out = {}
SaveSections.fields({ "giftRibbons" }).export(sess, out)
eq(out.giftRibbons and out.giftRibbons[1], 5, "giftRibbons rides the save export")
SaveSections.unregister("giftRibbons_probe")
check(fresh ~= nil, "save section probe done")

-- pokeemerald/src/pokenav_conditions_search_results.c:341
local Search = require("src.ui.game3.rse.pokenav.condition_search")
local s2 = { party = {
  { species = 1, contest = { cool = 10 } }, { species = 4, contest = { cool = 50 } }, { species = 7, contest = { cool = 10 } },
  { species = 25, isEgg = true, contest = { cool = 200 } },
}, storage = { boxes = { { mons = { [3] = { species = 16, contest = { cool = 50 } } } } } } }
local res = Search.build(s2, 0)
local order, ranks = {}, {}
for i, it in ipairs(res.items) do
  order[i] = (it.boxId and ("b" .. it.boxId .. ":" .. it.monId) or ("p" .. it.monId))
  ranks[i] = it.data
end
eq(table.concat(order, ","), "p2,b1:3,p1,p3", "search order: value desc, stable insertion")
eq(table.concat(ranks, ","), "1,1,3,3", "ties share a rank, next rank skips")

local RList = require("src.ui.game3.rse.pokenav.ribbons")
local s3 = { party = { { species = 1, ribbons = 2 ^ 15 }, { species = 2, ribbons = 0 }, { species = 3, ribbons = 4 + 2 ^ 19 } } }
local rl = RList.build(s3)
eq(#rl.items, 2, "ribbon list skips mons without ribbons")
eq(rl.items[1].monId, 3, "most ribbons first")
eq(rl.items[1].data, 5, "ribbon count shown")

-- pokeemerald/src/pokenav_ribbons_summary.c:277
local Summary = require("src.ui.game3.rse.pokenav.ribbons_summary")
local sm = setmetatable({ selectedPos = 0 }, Summary)
sm.normalIds = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
sm.giftIds = { 25, 26 }
sm.normalLastRowStart = 9
check(not sm:tryUp(), "top row cannot move up")
check(sm:tryDown() and sm.selectedPos == 9, "down one row")
check(sm:tryRight() and sm.selectedPos == 10, "right within the last row")
check(not sm:tryRight(), "no ribbon past the last")
check(sm:tryDown() and sm.selectedPos == 28, "down to the gift row clamps to its length")
check(sm:tryUp() and sm.selectedPos == 10, "up from the gift row lands in the last normal row")
check(sm:tryLeft() and sm.selectedPos == 9, "left")
check(not sm:tryLeft(), "left edge")

T.finish()
