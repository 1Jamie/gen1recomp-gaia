package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
local K = require("tests.save_compat._codec")

if not K.gen1Available() then
  print("gen1_state skipped (needs data/generated/ for the Gen 1 save codec)")
  os.exit(0)
end

local GenSave = require("src.save_convert.GenSave")
local G1 = require("tests.fixtures.save.gen1_build")

local O = GenSave.OFFSETS
local byId = {}
for _, c in ipairs(G1.cases()) do byId[c.id] = c end

local function import(id)
  local c = byId[id]
  return assert(K.import(1, c.version, c.bytes)), c
end

local function export(save, version)
  return assert(K.export(1, version, save))
end

local function bitOf(bytes, base, idx)
  return math.floor(bytes:byte(base + math.floor(idx / 8) + 1) / 2 ^ (idx % 8)) % 2 == 1
end

do
  local s, c = import("g1.red.daycare")
  local dc = s.daycare
  eq(dc.mon.species, "EEVEE", "day care: the boarded species")
  eq(dc.mon.nickname, "FLUFFY", "day care: nickname")
  eq(dc.mon.ot, "RED", "day care: OT name")
  eq(dc.mon.level, 12, "day care: the box level is the level it was left at")
  eq(dc.depositLevel, 12, "day care: depositLevel mirrors wDayCareMonBoxLevel")
  eq(dc.mon.exp, 1900, "day care: exp as the steps left it")
  eq(dc.steps, 0, "day care: no pending steps")
  eq(export(s, "red"), c.bytes, "day care: a fresh import exports the cart back untouched")
  dc.steps = 25
  local out = export(s, "red")
  local reread = assert(K.import(1, "red", out))
  eq(reread.daycare.mon.exp, 1925, "day care: pending steps are folded into exp on export")
  eq(reread.daycare.steps, 0, "day care: and none are pending afterwards")
  eq(out:byte(O.dayCare + 1), 1, "day care: wDayCareInUse")
  s.daycare = nil
  eq(export(s, "red"):byte(O.dayCare + 1), 0, "day care: retrieving the mon clears wDayCareInUse")
  s.daycare = { mon = s.party[1], steps = 3, depositLevel = s.party[1].level }
  local out2 = export(s, "red")
  local again = assert(K.import(1, "red", out2))
  eq(again.daycare.mon.species, s.party[1].species, "day care: depositing a party mon exports it")
  eq(again.daycare.mon.exp, s.party[1].exp + 3, "day care: with the pending steps")
end

do
  local s = import("g1.red.daycare_default_name")
  eq(s.daycare.mon.nickname, nil, "day care: a default-named mon has no nickname")
  eq(s.daycare.mon.ot, "JOE", "day care: another trainer's mon keeps its OT")
end

do
  local s, c = import("g1.red.daycare_carrier")
  check(s.daycare.cartRaw ~= nil and s.daycare.mon == nil, "day care: an unknown species rides as raw bytes")
  eq(export(s, "red"):sub(O.dayCare + 1, O.dayCare + 56), c.bytes:sub(O.dayCare + 1, O.dayCare + 56),
    "day care: and comes back byte for byte")
end

do
  local s, c = import("g1.red.safari_in_game")
  eq(s.safari.balls, 17, "safari: balls")
  eq(s.safari.steps, 300, "safari: steps")
  eq(s.flags.EVENT_IN_SAFARI_ZONE, true, "safari: the event stays set")
  local out = export(s, "red")
  eq(out:sub(O.safariBalls + 1, O.safariBalls + 1), c.bytes:sub(O.safariBalls + 1, O.safariBalls + 1), "safari: balls reproduce")
  s.safari.steps = 299
  s.safari.balls = 16
  out = export(s, "red")
  eq(out:byte(O.safariSteps + 2), 299 % 256, "safari: a step is written")
  eq(out:byte(O.safariBalls + 1), 16, "safari: a thrown ball is written")
  eq(out:byte(O.safariGateScript + 1), 5, "safari: the gate is in its LEAVING_SAFARI script while the game runs")
  s.safari = nil
  out = export(s, "red")
  local evIdx = K.gen1Data("red").eventFlags.byName.EVENT_IN_SAFARI_ZONE
  eq(bitOf(out, O.eventFlags, evIdx), false, "safari: leaving the zone clears EVENT_IN_SAFARI_ZONE")
  eq(out:byte(O.safariGateScript + 1), 0, "safari: and returns the gate to its default script")
  s.safariGameOver = true
  out = export(s, "red")
  local overIdx = K.gen1Data("red").eventFlags.byName.EVENT_SAFARI_GAME_OVER
  eq(bitOf(out, O.eventFlags, overIdx), true, "safari: the game-over event follows safariGameOver")
  eq(out:byte(O.safariGateScript + 1), 5, "safari: and the gate script is LEAVING_SAFARI")
end

do
  local s = import("g1.red.safari_game_over")
  eq(s.safari, nil, "safari: a finished game imports with no live state")
  eq(s.flags.EVENT_SAFARI_GAME_OVER, true, "safari: the finished-game event is kept")
  local out = export(s, "red")
  eq(bitOf(out, O.eventFlags, K.gen1Data("red").eventFlags.byName.EVENT_SAFARI_GAME_OVER), true, "safari: and written back")
  s.safari = { balls = 30, steps = 502 }
  s.flags.EVENT_SAFARI_GAME_OVER = nil
  out = export(s, "red")
  eq(bitOf(out, O.eventFlags, K.gen1Data("red").eventFlags.byName.EVENT_SAFARI_GAME_OVER), false, "safari: a new game resets it")
end

do
  local s = import("g1.red.safari_stale_balls")
  eq(s.safari, nil, "safari: leftover bytes outside a game are not a game")
end

do
  local s = import("g1.red.fossil_in_lab")
  eq(s.labFossilMon, "KABUTO", "fossil: the lab's Pokemon")
  s.labFossilMon = "OMANYTE"
  local out = export(s, "red")
  eq(out:byte(O.fossilMon + 1), 0x62, "fossil: wFossilMon")
  eq(out:byte(O.fossilItem + 1), 0x2A, "fossil: wFossilItem follows the species")
  s.labFossilMon = "AERODACTYL"
  eq(export(s, "red"):byte(O.fossilItem + 1), 0x1F, "fossil: OLD_AMBER")
  eq(import("g1.red.fossil_stale").labFossilMon, nil, "fossil: stale bytes without the lab event are not a fossil")
end

do
  local s = import("g1.red.trash_cans")
  eq(s.trashPuzzle.first, 6, "trash cans: first")
  eq(s.trashPuzzle.second, 8, "trash cans: second")
  s.trashPuzzle = { first = 14, second = 0 }
  local out = export(s, "red")
  eq(out:byte(O.trashFirst + 1), 14, "trash cans: first exports")
  eq(out:byte(O.trashSecond + 1), 0, "trash cans: second exports")
  local z = import("g1.red.trash_first_zero")
  eq(z.trashPuzzle.first, 0, "trash cans: a zero first index with a second one still imports")
  eq(z.trashPuzzle.second, 5, "trash cans: second")
end

do
  local s = import("g1.red.hidden_coins")
  local want = { [0] = true, [2] = true, [4] = true, [6] = true, [9] = true, [11] = true }
  for i, row in ipairs(require("src.save_convert.data.hidden_coins")) do
    eq(s.hiddenTaken[row[1] .. "_" .. row[2] .. "_" .. row[3]] == true, want[i - 1] == true, "hidden coins: spot " .. i)
  end
  s.hiddenTaken.GAME_CORNER_0_8 = nil
  s.hiddenTaken.GAME_CORNER_15_8 = true
  local out = export(s, "red")
  eq(out:byte(O.hiddenCoinFlags + 1), 0x54, "hidden coins: first byte after taking one back")
  eq(out:byte(O.hiddenCoinFlags + 2), 0x0E, "hidden coins: second byte after a new pickup")
end

do
  local s = import("g1.red.forced_bike")
  eq(s.forcedBike, true, "forced bike: BIT_ALWAYS_ON_BIKE imports")
  eq(s.onBike, true, "forced bike: with the bike")
  s.forcedBike = nil
  local out = export(s, "red")
  eq(out:byte(O.statusFlags6 + 1), 0x01, "forced bike: leaving the road clears bit 5 and keeps the clock bit")
  s.forcedBike = true
  eq(export(s, "red"):byte(O.statusFlags6 + 1), 0x21, "forced bike: entering sets it")
end

do
  local s = import("g1.red.basic")
  s.flags.EVENT_GOT_STARTER = true
  eq(export(s, "red"):byte(O.statusFlags4 + 1), 0x08, "starter: EVENT_GOT_STARTER also sets BIT_GOT_STARTER that Mom's heal reads")
  s.flags.EVENT_GOT_STARTER = nil
  eq(export(s, "red"):byte(O.statusFlags4 + 1), byId["g1.red.basic"].bytes:byte(O.statusFlags4 + 1),
    "starter: and a cart that never had it keeps its bytes")
  local t = import("g1.red.used_pokecenter")
  eq(export(t, "red"):byte(O.statusFlags4 + 1), 0x0C, "starter: an odd cart bit 3 without the event survives an untouched export")
  t.flags.EVENT_GOT_STARTER = true
  eq(export(t, "red"):byte(O.statusFlags4 + 1), 0x0C, "starter: and gaining the starter keeps it set")
  local y = import("g1.yellow.basic")
  y.flags.EVENT_GOT_STARTER = true
  eq(export(y, "yellow"):byte(O.statusFlags4 + 1), 0x08, "starter: Yellow reads the same bit in OaksLab")
end

do
  local s = import("g1.red.used_pokecenter")
  eq(s.usedPokecenter, true, "pokecenter: BIT_USED_POKECENTER imports")
  s.usedPokecenter = nil
  eq(export(s, "red"):byte(O.statusFlags4 + 1), 0x08, "pokecenter: and exports clear, leaving the starter bit")
end

do
  local dark = import("g1.red.dark_cave")
  eq(dark.flashLit, nil, "dark cave: wMapPalOffset 6 is dark")
  local lit = import("g1.red.dark_cave_lit")
  eq(lit.flashLit, true, "dark cave: wMapPalOffset 0 is lit by Flash")
  eq(export(lit, "red"):byte(O.mapPalOffset + 1), 0, "dark cave: lit exports 0")
  eq(export(dark, "red"):byte(O.mapPalOffset + 1), 6, "dark cave: dark exports 6")
  lit.flashLit = nil
  eq(export(lit, "red"):byte(O.mapPalOffset + 1), 6, "dark cave: a Flash that wore off exports dark")
  dark.flashLit = true
  eq(export(dark, "red"):byte(O.mapPalOffset + 1), 0, "dark cave: using Flash exports lit")
  dark.player.map, dark.player.x, dark.player.y = "PEWTER_CITY", 13, 17
  eq(export(dark, "red"):byte(O.mapPalOffset + 1), 0, "dark cave: walking outside resets it")
end

do
  local s = import("g1.yellow.surf_score")
  eq(s.surfingHighScore, 1234, "surfing: the hi score is little-endian BCD")
  s.surfingHighScore = 9999
  local out = export(s, "yellow")
  eq(out:byte(O.surfHiScore + 1), 0x99, "surfing: low byte")
  eq(out:byte(O.surfHiScore + 2), 0x99, "surfing: high byte")
  s.surfingHighScore = 10050
  eq(export(s, "yellow"):byte(O.surfHiScore + 2), 0x99, "surfing: the score saturates at 9999")
  local bad = import("g1.yellow.surf_score_invalid_bcd")
  eq(bad.surfingHighScore, nil, "surfing: invalid BCD is not a score")
  eq(export(bad, "yellow"):byte(O.surfHiScore + 1), 0xFA, "surfing: and is carried untouched")
  local red = import("g1.red.basic")
  red.surfingHighScore = 77
  eq(export(red, "red"):byte(O.surfHiScore + 1), byId["g1.red.basic"].bytes:byte(O.surfHiScore + 1),
    "surfing: Red/Blue bytes at 0x2741 are map scratch and never written")
end

do
  local s, c = import("g1.red.beat_gym_mismatch")
  eq(export(s, "red"):byte(O.beatGymFlags + 1), 0x03, "gym flags: an odd cart value survives")
  s.inventory.CASCADEBADGE = 1
  eq(export(s, "red"):byte(O.beatGymFlags + 1), 0x03, "gym flags: a badge that was already counted changes nothing")
  s.inventory.THUNDERBADGE = 1
  eq(export(s, "red"):byte(O.beatGymFlags + 1), 0x07, "gym flags: a new badge sets its own bit")
  s.inventory.BOULDERBADGE = nil
  eq(export(s, "red"):byte(O.beatGymFlags + 1), 0x06, "gym flags: and losing one clears only that bit")
end

T.finish()
