package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local PRET = os.getenv("POKEPORT_PRET_EMERALD") or "../pokeemerald"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_match_call_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()
if data:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_match_call_test: skipped (" .. ROM_PATH .. " is not Emerald)")
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

local K = require("src.import.gba.rse.boot_gfx")
local ROOT = "data/generated/gba"
local MCX = require("src.import.gba.rse.match_call_extract")
local PNX = require("src.import.gba.rse.pokenav_extract")

for _, M in ipairs({ MCX, PNX }) do
  check(not M.ready(cache, ROOT), M.SUB .. " not ready before run")
  local ok = M.run(rom, cache, { cacheRoot = ROOT })
  eq(ok, true, M.SUB .. " extractor ran")
  check(M.ready(cache, ROOT), M.SUB .. " ready after run")
  for _, rel in ipairs(M.REQUIRED) do check(files[ROOT .. "/" .. rel] ~= nil, rel .. " written") end
end

local function manifestOf(sub)
  return assert(load(files[ROOT .. "/" .. sub .. "/manifest.lua"], "@m", "t", {}))()
end
local mc = manifestOf(MCX.SUB)
local nav = manifestOf(PNX.SUB)

local C = require("src.core.game3.constants").of("emerald")

local function readPret(rel)
  local h = io.open(PRET .. "/" .. rel, "rb")
  if not h then return nil end
  local s = h:read("*a")
  h:close()
  return s
end

-- pokeemerald/src/match_call.c:171
local src = readPret("src/match_call.c")
if src then
  local body = src:match("sMatchCallTrainers%[%]%s*=%s*(%b{})")
  local ids = {}
  for name in (body or ""):gmatch("%.trainerId%s*=%s*(TRAINER_[%w_]+)") do ids[#ids + 1] = name end
  eq(#ids, 64, "sMatchCallTrainers parsed from pret")
  local n = 0
  while mc.trainers[n] do n = n + 1 end
  eq(n, #ids, "sMatchCallTrainers row count")
  for i, name in ipairs(ids) do
    eq(mc.trainers[i - 1].trainerId, C.trainers.byName[name], "sMatchCallTrainers[" .. (i - 1) .. "] " .. name)
  end
end
eq(#mc.battleTopics, 3, "three battle topics")
eq(#mc.battleTopics[1], 15, "sMatchCallWildBattleTexts has 15 rows")
eq(mc.battleTopics[1][1].text, "MatchCall_WildBattleText1", "wild battle text 1 by symbol")
eq(table.concat(mc.battleTopics[1][1].vars, ","), "0,2,-1", "STRS_WILD_BATTLE string var ids")
eq(#mc.generalTopics, 6, "six general topics")
eq(#mc.generalTopics[1], 64, "64 personalized texts")
local headerNames = {}
local hsrc = readPret("src/pokenav_match_call_data.c")
if hsrc then
  local body = hsrc:match("sMatchCallHeaders%[%]%s*=%s*(%b{})")
  for kind in (body or ""):gmatch("{%s*%.(%a+)%s*=") do headerNames[#headerNames + 1] = kind end
  local n = 0
  while mc.headers[n] do n = n + 1 end
  eq(n, #headerNames, "sMatchCallHeaders count (" .. #headerNames .. ")")
  for i, kind in ipairs(headerNames) do
    eq(mc.headers[i - 1].type, kind == "leader" and "leader" or kind, "sMatchCallHeaders[" .. (i - 1) .. "] type " .. kind)
  end
end
eq(mc.headers[0].name, "gText_MrStoneMatchCallName", "header 0 is Mr. Stone")
eq(mc.headers[9].rematchTableIdx, 65, "Roxanne header points at REMATCH_ROXANNE")
eq(#mc.checkPageOverrides, 4, "four check page overrides")
eq(#mc.gymLeaderRematchesAfterNewMauville, 8, "GymLeaderRematches_AfterNewMauville")
eq(#mc.gymLeaderRematchesBeforeNewMauville, 7, "GymLeaderRematches_BeforeNewMauville")

local VT = require("src.import.gba.versions_text_emerald")
local have = {}
for _, n in ipairs(VT.NAMED_TEXTS) do have[n] = true end
local missing = {}
local function need(k) if k and not have[k] then missing[#missing + 1] = k end end
for _, list in ipairs({ mc.battleTopics, mc.requestTopics, mc.generalTopics }) do
  for _, t in ipairs(list) do for _, r in ipairs(t) do need(r.text) end end
end
local hi = 0
while mc.headers[hi] do
  local h = mc.headers[hi]
  need(h.desc); need(h.name)
  for _, d in ipairs(h.textData or {}) do need(d.text) end
  hi = hi + 1
end
for i = 0, 77 do for _, t in ipairs(mc.flavorTexts[i] or {}) do need(t) end end
for i = 0, #nav.pageDescriptions do need(nav.pageDescriptions[i]) end
for i = 0, #nav.helpBarTexts do need(nav.helpBarTexts[i]) end
for _, row in ipairs(nav.landmarks) do for _, l in ipairs(row.landmarks) do need(l.name) end end
eq(#missing, 0, "every match call / pokenav text key is in the ROM text bundle (" .. table.concat(missing, ",") .. ")")

eq(nav.menus[1].yStart, 42, "UNLOCK_MC option labels start at y 42")
eq(#nav.menus[4].items, 6, "condition search menu has six labels")
eq(#nav.cityMaps, 22, "22 PokeNav city maps")
eq(nav.pageDescriptions[0], "gText_CheckMapOfHoenn", "HOENN MAP description")

local tmp = os.tmpname()
os.remove(tmp)
os.execute('mkdir -p "' .. tmp .. '"')
local function dump(rel, name)
  local h = assert(io.open(tmp .. "/" .. name, "wb"))
  h:write(files[ROOT .. "/" .. rel])
  h:close()
end
dump("rse/pokenav/spin.png", "spin.png")
dump("rse/pokenav/blue_light.png", "blue_light.png")
dump("rse/pokenav/cursor_large.png", "cursor_large.png")
dump("rse/pokenav/lh_match_call.png", "lh_match_call.png")
dump("rse/pokenav/lh_hoenn_map.png", "lh_hoenn_map.png")
dump("rse/pokenav/options.png", "options.png")
dump("rse/match_call/window.png", "window.png")
dump("rse/match_call/nav_icon.png", "mc_nav_icon.png")
local script = [[
import sys
from PIL import Image
tmp, pret = sys.argv[1], sys.argv[2] + "/graphics/pokenav/"
def idx(p): return Image.open(p).convert("P")
def diff(a, b, box=None, off=(0, 0)):
    A, B = idx(a), idx(b)
    w, h = A.size if box is None else (box[2], box[3])
    n = 0
    for y in range(h):
        for x in range(w):
            ax, ay = (x, y) if box is None else (box[0] + x, box[1] + y)
            if A.getpixel((ax, ay)) != B.getpixel((off[0] + x, off[1] + y)): n += 1
    return n
out = {}
out["spin"] = diff(tmp + "/spin.png", pret + "nav_icon.png")
out["blue_light"] = diff(tmp + "/blue_light.png", pret + "blue_light.png")
out["cursor_large"] = diff(tmp + "/cursor_large.png", pret + "region_map/cursor_large.png")
out["lh_match_call"] = diff(tmp + "/lh_match_call.png", pret + "left_headers/match_call.png")
out["lh_hoenn_map"] = diff(tmp + "/lh_hoenn_map.png", pret + "left_headers/hoenn_map.png")
out["mc_window"] = diff(tmp + "/window.png", pret + "match_call/window.png")
out["mc_nav_icon"] = diff(tmp + "/mc_nav_icon.png", pret + "match_call/nav_icon.png")
n = 0
for j in range(4):
    n += diff(tmp + "/options.png", pret + "options/hoenn_map.png", (j * 32, 0, 32, 16), (0, j * 16))
out["option_hoenn_map"] = n
print(" ".join("%s=%d" % (k, out[k]) for k in sorted(out)))
]]
local sf = io.open(tmp .. "/cmp.py", "wb")
sf:write(script)
sf:close()
local py = io.popen("python3 -c 'import PIL' 2>/dev/null && echo yes")
local havePil = py and py:read("*l") == "yes"
if py then py:close() end
if havePil and readPret("graphics/pokenav/nav_icon.png") then
  local p = io.popen('python3 "' .. tmp .. '/cmp.py" "' .. tmp .. '" "' .. PRET .. '" 2>&1')
  local line = p and p:read("*a") or ""
  if p then p:close() end
  print("emerald_match_call_test: differing pixels " .. line:gsub("%s+$", ""))
  for _, key in ipairs({ "spin", "blue_light", "cursor_large", "lh_match_call", "lh_hoenn_map", "mc_window", "mc_nav_icon",
      "option_hoenn_map" }) do
    eq(tonumber(line:match(key .. "=(%d+)")), 0, key .. " matches pret graphics/pokenav pixel for pixel")
  end
else
  print("emerald_match_call_test: PIL or pret graphics missing, pixel compare skipped")
end
os.execute('rm -f "' .. tmp .. '"/*.png "' .. tmp .. '"/cmp.py; rmdir "' .. tmp .. '"')

package.loaded["src.core.game3.dataset"] = {
  cache = function() return cache end,
}
local trainerRows = {}
local rematches = {}
local bsrc = readPret("src/battle_setup.c")
local ok = bsrc ~= nil
if ok then
  local body = bsrc:match("gRematchTable%[REMATCH_TABLE_ENTRIES%]%s*=%s*(%b{})")
  local i = 0
  for a1, a2, a3, a4, a5, map in (body or ""):gmatch("REMATCH%((TRAINER_[%w_]+),%s*(TRAINER_[%w_]+),%s*(TRAINER_[%w_]+),%s*(TRAINER_[%w_]+),%s*(TRAINER_[%w_]+),%s*(MAP_[%w_]+)%)") do
    local m = C.map_groups.byName[map]
    rematches[i] = { trainers = { C.trainers.byName[a1], C.trainers.byName[a2], C.trainers.byName[a3],
      C.trainers.byName[a4], C.trainers.byName[a5] }, mapGroup = m.group, mapNum = m.num }
    i = i + 1
  end
  eq(i, 78, "gRematchTable parsed from pret (78)")
end
local Trainers = require("src.core.game3.scripting.trainers")
local CINDY, CINDY_3, CINDY_4 = C.trainers.byName.TRAINER_CINDY_1, C.trainers.byName.TRAINER_CINDY_3,
  C.trainers.byName.TRAINER_CINDY_4
trainerRows[CINDY] = { name = "CINDY", class = 1, className = "LADY", party = { { species = 1, level = 7 } } }
trainerRows[CINDY_3] = { name = "CINDY", class = 1, className = "LADY", party = { { species = 2, level = 20 } } }
Trainers._pack = { trainers = trainerRows, rematches = rematches }

local Rematch = require("src.core.game3.rse.rematch")
local MatchCall = require("src.core.game3.rse.match_call")
local Flags = require("src.core.game3.scripting.flags")
local session = { version = "emerald", flags = {}, vars = {}, party = {}, trainerId = 0x1234, gameStats = {} }
local function setFlag(name, on) Rematch.setFlag(session, name, on) end

eq(Rematch.count(), 78, "rematch table size")
local idx = Rematch.firstBattleTableId(CINDY)
eq(idx, 10, "Cindy is REMATCH_CINDY")
eq(Rematch.tableIdOf(CINDY_3), 10, "CINDY_3 resolves to the same row")
check(not Rematch.shouldTryRematchBattle(session, CINDY), "no rematch before Cindy wants one")
setFlag(Flags.trainerFlagId(CINDY), true)
eq(Rematch.rematchTrainerId(session, CINDY), CINDY_3, "GetRematchTrainerId: first rematch is CINDY_3")
Rematch.set(session, idx, 1)
check(Rematch.shouldTryRematchBattle(session, CINDY), "ShouldTryRematchBattle once trainerRematches is set")
check(Rematch.isTrainerReadyForRematch(session, CINDY_3), "IsTrainerReadyForRematch for the rematch party")
Rematch.onRematchBattleWon(session, CINDY_3)
eq(Rematch.get(session, idx), 0, "rematch win clears trainerRematches")
check(Rematch.hasTrainerBeenFought(session, CINDY_3), "rematch win sets TRAINER_CINDY_3")
eq(Rematch.rematchTrainerId(session, CINDY), CINDY_4, "next rematch climbs to CINDY_4")
check(Rematch.shouldTryRematchBattle(session, CINDY), "WasSecondRematchWon keeps ShouldTryRematchBattle true")

Rematch.registerTrainerInMatchCall(session, CINDY)
check(not Rematch.flag(session, Rematch.registeredFlagId(session, idx)), "no registration without FLAG_HAS_MATCH_CALL")
setFlag("FLAG_HAS_MATCH_CALL", true)
Rematch.onTrainerBattleWon(session, CINDY)
check(Rematch.flag(session, Rematch.registeredFlagId(session, idx)), "trainer win registers the trainer in Match Call")

for _ = 1, 300 do Rematch.incrementStepCounter(session) end
eq(session.trainerRematchStepCounter, 0, "rematch step counter needs five badges")
for i = 1, 5 do setFlag(string.format("FLAG_BADGE%02d_GET", i), true) end
for _ = 1, 300 do Rematch.incrementStepCounter(session) end
eq(session.trainerRematchStepCounter, 255, "rematch step counter caps at 255")
local r104 = C.map_groups.byName.MAP_ROUTE104
Rematch.rng = function() return 0 end
check(Rematch.tryUpdateRandomTrainerRematches(session, r104.group, r104.num), "maxed counter rolls Route 104 rematches")
eq(Rematch.get(session, idx), 2, "SetRematchIdForTrainer picks the first unfought team (index 2)")
eq(session.trainerRematchStepCounter, 0, "rolling a rematch resets the step counter")

local mapsec = { EM_ROUTE104 = 17, EM_PETALBURG_CITY = 7 }
MatchCall.mapsecOfMap = function(_, mapId) return mapsec[mapId] or 99 end
local current = { mapType = 2, regionMapSectionId = 7 }
MatchCall.currentDef = function() return current end
MatchCall.mapName = function(sec) return "SEC" .. tostring(sec) end
local rolls = {}
MatchCall.rng = function() return table.remove(rolls, 1) or 0 end
local started = {}
MatchCall.startCall = function(_, _, opts) started[#started + 1] = opts return true end
local Rtc = require("src.core.game3.rtc")
Rtc.setFixed("2005-06-01T09:30:00")
MatchCall.initCounters(session)
for _ = 1, 9 do MatchCall.tryStartMatchCall(session, nil) end
eq(#started, 0, "no call before the tenth step")
rolls = { 0, 0 }
check(MatchCall.tryStartMatchCall(session, nil), "tenth step with a winning roll rings")
eq(started[1] and started[1].trainerId, CINDY, "the registered trainer calls")
for _ = 1, 10 do MatchCall.tryStartMatchCall(session, nil) end
eq(#started, 1, "the minute counter blocks a second call in the same ten minutes")
Rtc.advance(10)
for _ = 1, 10 do rolls = { 0, 0 } MatchCall.tryStartMatchCall(session, nil) end
eq(#started, 2, "ten minutes later the next tenth step can ring again")
current.mapType = 8
for _ = 1, 10 do rolls = { 0, 0 } Rtc.advance(10) MatchCall.tryStartMatchCall(session, nil) end
eq(#started, 2, "indoor maps never ring (Overworld_MapTypeAllowsTeleportAndFly)")
current.mapType = 2

Rematch.set(session, idx, 0)
setFlag(Flags.trainerFlagId(CINDY_4), false)
rolls = { 0 }
local msg = MatchCall.selectMessage(session, CINDY)
local cindyRow = mc.trainers[MatchCall.matchCallId(CINDY)]
local wantKey = mc.requestTopics[2][cindyRow.differentRouteTextId % 256].text
eq(msg.key, wantKey, "five badges on another route: different-route battle request")
check(msg.newRematchRequest, "the call is flagged as a new rematch request")
eq(Rematch.get(session, idx), 2, "UpdateRematchIfDefeated arms Cindy's rematch")
eq(msg.ctx.stringVars[1], "CINDY", "STR_TRAINER_NAME fills the trainer name")
eq(msg.ctx.stringVars[2], "SEC17", "STR_MAP_NAME fills Cindy's route")
current.regionMapSectionId = 17
msg = MatchCall.selectMessage(session, CINDY)
eq(msg.key, mc.requestTopics[1][cindyRow.sameRouteTextId % 256].text, "same route + eligible: same-route request")

-- pokeemerald/src/pokenav_match_call_list.c:205
setFlag("FLAG_ENABLE_MOM_MATCH_CALL", true)
local list = MatchCall.buildList(session)
eq(list[1].headerId, 0, "list starts with Mr. Stone")
eq(list[2].headerId, 6, "Mom follows when FLAG_ENABLE_MOM_MATCH_CALL is set")
eq(list[3].isSpecialTrainer, false, "registered trainers come after the special callers")
eq(list[3].headerId, idx, "Cindy's rematch index is listed")
check(MatchCall.showRematchIcon(session, list[3]), "pokeball icon for a trainer that wants a rematch")
local d, n = MatchCall.entryNameAndDesc(list[3])
eq(d .. "/" .. n, "LADY/CINDY", "trainer entries show class and name")
eq(MatchCall.entryFlavorText(session, list[3], 1), mc.flavorTexts[idx][1], "check page strategy text by rematch index")
check(not MatchCall.headerHasCheckPage(6), "Mom has no check page")
check(MatchCall.headerHasCheckPage(7), "Steven has a check page through sCheckPageOverrides")

-- pokeemerald/src/pokenav_match_call_data.c:1022
setFlag("FLAG_SYS_GAME_CLEAR", true)
local rox = mc.headers[9]
Rematch.set(session, rox.rematchTableIdx, 1)
local rm = MatchCall.headerMessage(session, 9)
eq(rm.key, "MatchCall_Text_Roxanne_RematchReady", "game clear + rematch ready: Roxanne asks for the rematch")
Rematch.set(session, rox.rematchTableIdx, 0)
eq(MatchCall.headerMessage(session, 9).key, "MatchCall_Text_Roxanne_PreparingPostGame", "no rematch yet: preparing post game")
local stone = MatchCall.headerMessage(session, 0)
eq(stone.key, "MatchCall_Text_MrStone11", "Mr. Stone picks the last available line")

Rtc.setFixed(nil)
T.finish()
