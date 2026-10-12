package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Rng = require("src.core.game3.rng")
local Roamer = require("src.core.game3.roamer")
local Runtime = require("src.core.game3.runtime")
local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")
local Sem = require("src.core.game3.field_semantics")

GameVersion.set("firered")
Space.store = Flags.newStore()

-- pokefirered/src/roamer.c:36
local SETS = {
  { "FR_ROUTE_1", "FR_ROUTE_2", "FR_ROUTE_21_NORTH", "FR_ROUTE_22", false, false, false },
  { "FR_ROUTE_2", "FR_ROUTE_1", "FR_ROUTE_3", "FR_ROUTE_22", false, false, false },
  { "FR_ROUTE_3", "FR_ROUTE_2", "FR_ROUTE_4", false, false, false, false },
  { "FR_ROUTE_22", "FR_ROUTE_1", "FR_ROUTE_2", "FR_ROUTE_23", false, false, false },
}

local function first_roll(seed, n)
  Rng.SeedRng(seed)
  return Rng.Random() % n
end

local function session()
  return { version = "firered", name = "RED", trainerId = 1, secretId = 2, vars = {}, flags = {}, party = {
    { species = 6, level = 40, hp = 100, maxHp = 100 } } }
end

local s = session()
local cfg = Roamer.config(s)
check(cfg ~= nil, "FireRed has a roamer profile row")
eq(Roamer.ADJACENCY, nil, "no hand-typed FireRed adjacency table")
eq(Roamer.LOCATIONS, nil, "no hand-typed FireRed location list")
eq(cfg and cfg.locations, "data/generated/gba/roamer/locations.lua", "FireRed roamer sets come from the cache")
Roamer._locations[cfg] = SETS

-- pokefirered/src/roamer.c:117
Rng.SeedRng(0x1234)
Rng.Random32()
Rng.Random()
Rng.Random()
local expectHead = SETS[(Rng.Random() % #SETS) + 1][1]
Rng.SeedRng(0x1234)
check(Roamer.init(s, 0), "InitRoamer runs")
local r = s.roamer
eq(r.species, Roamer.SPECIES_ENTEI, "Bulbasaur starter roams Entei")
eq(r.map, expectHead, "initial map is a set head drawn after the mon's personality and IVs")
check(r.history[1] == false and r.history[2] == false and r.history[3] == false, "InitRoamer clears the history")

-- pokefirered/src/roamer.c:161
local function expect_move(seed, from, hist3)
  Rng.SeedRng(seed)
  if Rng.Random() % 16 == 0 then
    while true do
      local head = SETS[(Rng.Random() % #SETS) + 1][1]
      if head ~= from then return head end
    end
  end
  for _, set in ipairs(SETS) do
    if set[1] == from then
      while true do
        local pick = set[(Rng.Random() % 6) + 2]
        if pick and pick ~= hist3 then return pick end
      end
    end
  end
  return from
end

local moved, otherSet = 0, 0
for seed = 1, 400 do
  r.map = "FR_ROUTE_2"
  r.history = { "FR_ROUTE_1", "FR_ROUTE_3", "FR_ROUTE_1" }
  local want = expect_move(seed, "FR_ROUTE_2", "FR_ROUTE_3")
  Rng.SeedRng(seed)
  Roamer.move(s, "connection", "FR_ROUTE_2")
  if r.map ~= want then
    check(false, "connection seed " .. seed .. " moves to " .. want .. " (got " .. tostring(r.map) .. ")")
    break
  end
  moved = moved + 1
  if first_roll(seed, 16) == 0 then otherSet = otherSet + 1 end
end
eq(moved, 400, "connection moves follow RoamerMove for 400 seeds")
check(otherSet > 0, "some seeds take the 1/16 jump to another set")
eq(r.history[1], "FR_ROUTE_2", "a map load records the new map in the history")

local avoided = true
for seed = 1, 200 do
  r.map = "FR_ROUTE_1"
  r.history = { false, "FR_ROUTE_21_NORTH", false }
  Rng.SeedRng(seed)
  Roamer.move(s, "connection", "FR_ROUTE_1")
  if not r.map or r.map == "FR_ROUTE_1" or (r.map == "FR_ROUTE_21_NORTH" and first_roll(seed, 16) ~= 0) then
    avoided = false
  end
end
check(avoided, "RoamerMove skips the map from two moves ago and the blank slots")

-- pokefirered/src/roamer.c:136
local warpOk = true
for seed = 1, 100 do
  r.map = "FR_ROUTE_3"
  Rng.SeedRng(seed)
  Roamer.move(s, "warp", "FR_ROUTE_3")
  local head = false
  for _, set in ipairs(SETS) do if set[1] == r.map then head = true end end
  if not head or r.map == "FR_ROUTE_3" then warpOk = false end
end
check(warpOk, "warps pick a different set head")

-- pokefirered/src/roamer.c:230
r.map, r.active = "FR_ROUTE_1", true
local hits, consumed = 0, true
for seed = 1, 400 do
  Rng.SeedRng(seed)
  local roll = Rng.Random() % 4
  local after = Rng.getState().value
  Rng.SeedRng(seed)
  local enc = Roamer.tryEncounter(s, "FR_ROUTE_1", "land")
  if (enc ~= nil) ~= (roll == 0) then
    check(false, "seed " .. seed .. " meets the roamer only on Random() % 4 == 0")
    break
  end
  if Rng.getState().value ~= after then consumed = false end
  if enc then hits = hits + 1 end
end
check(hits > 60 and hits < 140, "about one in four rate passes meet the roamer (" .. hits .. "/400)")
check(consumed, "the roamer gate draws exactly one Random()")
Rng.SeedRng(99)
local before = Rng.getState().value
eq(Roamer.tryEncounter(s, "FR_ROUTE_2", "land"), nil, "no roamer off its map")
eq(Rng.getState().value, before, "IsRoamerAt fails before Random() is drawn")

-- pokefirered/src/pokemon.c:3660
local full = { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 }
local cut = Roamer.instanceIvs(full, true)
eq(cut.hp, 31, "SetMonData keeps the HP IV")
eq(cut.atk, 7, "SetMonData keeps the low 3 Attack IV bits")
eq(cut.def + cut.spe + cut.spa + cut.spd, 0, "SetMonData zeroes the other IVs")
r.ivs = { hp = 20, atk = 13, def = 9, spe = 30, spa = 2, spd = 17 }
local seed = 1
while first_roll(seed, 4) ~= 0 do seed = seed + 1 end
Rng.SeedRng(seed)
local enc = Roamer.tryEncounter(s, "FR_ROUTE_1", "land")
eq(enc and enc.ivs.hp, 20, "FireRed battle roamer keeps HP IV 20")
eq(enc and enc.ivs.atk, 5, "FireRed battle roamer Attack IV is 13 & 7")
eq(enc and (enc.ivs.def + enc.ivs.spe + enc.ivs.spa + enc.ivs.spd), 0, "FireRed battle roamer other IVs are 0")
eq(r.ivs.spe, 30, "the stored FireRed roamer IVs stay intact")
check(Roamer.config({ version = "ruby" }).truncateIvs == true, "Ruby reads roamer IVs through the buggy SetMonData")
check(Roamer.config({ version = "sapphire" }).truncateIvs == true, "Sapphire reads roamer IVs through the buggy SetMonData")
check(not Roamer.config({ version = "emerald" }).truncateIvs, "Emerald SetMonData reads all four IV bytes")
check(Roamer.config({ version = "leafgreen" }).truncateIvs == true, "LeafGreen reads roamer IVs through the buggy SetMonData")

-- pokefirered/src/wild_encounter.c:381
local Encounters = require("src.core.game3.encounters")
Encounters._tables = { FR_ROUTE_1 = { land = { rate = 255, slots = { { species = 16, minLevel = 70, maxLevel = 70 } } } } }
Encounters._loaded = true
Runtime.session = s
Sem.setVar(s, "repelSteps", 200)
r.level, r.hp = 50, 100

local function roll_with_roamer()
  local sd = 1
  while first_roll(sd, 4) ~= 0 do sd = sd + 1 end
  Rng.SeedRng(sd)
  Encounters.resetRateModifiers()
  return Encounters.rollLand("FR_ROUTE_1", nil, false)
end

s.party = { { species = 6, level = 60, hp = 0, maxHp = 100 }, { species = 25, level = 40, hp = 50, maxHp = 50 } }
enc = roll_with_roamer()
check(enc and enc.roamer, "Repel skips a fainted Lv60 lead and lets the Lv50 roamer meet a Lv40 mon")
s.party = { { species = 6, level = 60, hp = 10, maxHp = 100 } }
enc = roll_with_roamer()
eq(enc, nil, "Repel with a healthy Lv60 lead ends the step without a wild battle")
s.party = { { species = 6, level = 50, hp = 10, maxHp = 100 } }
enc = roll_with_roamer()
check(enc and enc.roamer, "a Lv50 lead does not repel the Lv50 roamer")
Sem.setVar(s, "repelSteps", 0)

-- pokeemerald/include/constants/vars.h:51
GameVersion.set("emerald")
local em = { version = "emerald", vars = {}, flags = {}, party = { { species = 6, level = 60, hp = 10, maxHp = 100 } } }
Runtime.session = em
eq(Sem.var(em, "repelSteps"), 0x4021, "Emerald Repel steps live in VAR_REPEL_STEP_COUNT 0x4021")
em.vars[0x4020] = 200
check(Encounters._h.wild_level_allowed_by_repel(40), "Emerald VAR_RECYCLE_GOODS is not a Repel")
Sem.setVar(em, "repelSteps", 200)
check(not Encounters._h.wild_level_allowed_by_repel(40), "Emerald Repel blocks a Lv40 roamer under a Lv60 lead")
em.party[1].hp = 0
em.party[2] = { species = 25, level = 30, hp = 5, maxHp = 50 }
check(Encounters._h.wild_level_allowed_by_repel(40), "Emerald Repel skips a fainted lead")
Runtime.session = nil
GameVersion.set("firered")

T.finish("game3_roamer_cart_gates")
