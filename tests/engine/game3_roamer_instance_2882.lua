package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Rng = require("src.core.game3.rng")
local Roamer = require("src.core.game3.roamer")
local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")

local IVS = { "hp", "atk", "def", "spe", "spa", "spd" }

local function same_ivs(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for _, k in ipairs(IVS) do
    if a[k] ~= b[k] then return false end
  end
  return true
end

local function flat(enc)
  return type(enc) == "table" and enc.foe == nil and enc.personality ~= nil and enc.ivs ~= nil
end

local function meet(session, mapId, seed)
  for i = 1, 64 do
    Rng.SeedRng((seed or 1) * 64 + i)
    local enc = Roamer.tryEncounter(session, mapId, "land")
    if enc then return enc end
  end
end

local FR_SETS = { { "FR_ROUTE_1", "FR_ROUTE_2", false }, { "FR_ROUTE_2", "FR_ROUTE_1", false } }

-- pokefirered/src/roamer.c:99
GameVersion.set("firered")
Space.store = Flags.newStore()
Rng.SeedRng(0x2882)
local fr = { version = "firered", name = "RED", trainerId = 1, secretId = 2, party = {
  { species = 6, level = 40, hp = 100, maxHp = 100 } } }
local frCfg = Roamer.config(fr)
check(frCfg ~= nil, "FireRed has a roamer profile row")
Roamer._locations[frCfg] = FR_SETS
check(Roamer.init(fr, 1), "FireRed InitRoamer succeeds")
local r = fr.roamer
eq(r.species, Roamer.SPECIES_RAIKOU, "Squirtle starter roams Raikou")
check(type(r.personality) == "number" and r.pid == nil, "FireRed roamer stores personality")
check(type(r.ivs) == "table" and r.ivs.atk ~= nil and r.ivs.attack == nil, "FireRed roamer stores battle IV keys")
eq(r.status, 0, "FireRed roamer status word starts at 0")

-- pokefirered/src/roamer.c:206
local pid, ivs = r.personality, {}
for _, k in ipairs(IVS) do ivs[k] = r.ivs[k] end
for i = 1, 3 do
  local enc = meet(fr, r.map, i)
  check(flat(enc), "FireRed encounter " .. i .. " is a flat battle foe")
  eq(enc and enc.personality, pid, "FireRed encounter " .. i .. " reuses the stored personality")
  check(enc and same_ivs(enc.ivs, Roamer.instanceIvs(ivs, true)), "FireRed encounter " .. i .. " reuses the stored IVs")
  check(same_ivs(r.ivs, ivs), "FireRed encounter " .. i .. " leaves the stored IVs intact")
  eq(enc and enc.item, 0, "FireRed encounter " .. i .. " holds no item")
end

-- pokefirered/src/battle_main.c:3929
local maxHp = r.hp
local battler = { status = "SLP", sleepTurns = 3, mon = { hp = maxHp - 20, status = "SLP" } }
Roamer.onBattleEnd(fr, battler.mon, "run", nil, battler)
check(r.active, "player running keeps the FireRed roamer active")
eq(r.hp, maxHp - 20, "FireRed roamer keeps its damage")
eq(r.status, 3, "FireRed roamer keeps sleep with its counter")
local enc = meet(fr, r.map, 4)
eq(enc and enc.hp, maxHp - 20, "next FireRed encounter starts damaged")
eq(enc and enc.status, "SLP", "next FireRed encounter starts asleep")
eq(enc and enc.sleep, 3, "next FireRed encounter keeps the sleep counter")
eq(enc and enc.personality, pid, "personality survives a battle")

battler = { status = "TOX", mon = { hp = 50, status = "TOX" } }
Roamer.onBattleEnd(fr, battler.mon, "fled", nil, battler)
eq(r.status, 128, "toxic poison maps to STATUS1_TOXIC_POISON")
enc = meet(fr, r.map, 5)
eq(enc and enc.status, "TOX", "toxic poison comes back as TOX")

battler = { status = nil, mon = { hp = 50, status = "PAR" } }
Roamer.onBattleEnd(fr, battler.mon, "run", nil, battler)
eq(r.status, 0, "a status cured in battle is cleared")

-- pokefirered/src/battle_main.c:3933
Roamer.onBattleEnd(fr, { hp = 50, status = 0 }, "teleport_player")
check(not r.active, "non-BUGFIX: PLAYER_TELEPORTED deactivates the FireRed roamer")

-- include/global.h:417
local old = { version = "firered", party = {}, roamer = { active = true, species = 244, level = 50, hp = 120,
  maxHp = 180, status = 0, statusNum = 0x40, pid = 0x12345678,
  ivs = { hp = 31, attack = 30, defense = 29, speed = 28, spAtk = 27, spDef = 26 }, map = "FR_ROUTE_1" } }
enc = meet(old, "FR_ROUTE_1", 6)
eq(enc and enc.personality, 0x12345678, "an old save's pid is the battle personality")
check(same_ivs(old.roamer.ivs, { hp = 31, atk = 30, def = 29, spe = 28, spa = 27, spd = 26 }),
  "an old save's long IV keys are normalized to battle keys")
check(enc and same_ivs(enc.ivs, { hp = 31, atk = 6, def = 0, spe = 0, spa = 0, spd = 0 }),
  "an old save's IVs reach the battle through SetMonData")
eq(enc and enc.status, "PAR", "an imported numeric status word reaches the battle")
eq(enc and enc.hp, 120, "an old save's HP reaches the battle")
check(old.roamer.pid == nil and old.roamer.maxHp == nil, "an old roamer is normalized in place")

local bare = { version = "firered", party = {}, roamer = { active = true, species = 245, level = 50, hp = 90,
  status = 0, map = "FR_ROUTE_2" } }
enc = meet(bare, "FR_ROUTE_2", 7)
eq(enc and enc.personality, 0, "a roamer saved without a personality reads 0 like a cleared struct")
check(enc and same_ivs(enc.ivs, { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }),
  "a roamer saved without IVs reads all zero")
local again = meet(bare, "FR_ROUTE_2", 8)
eq(again and again.personality, 0, "the zero personality is stable across encounters")

-- pokeemerald/src/roamer.c:194
GameVersion.set("emerald")
local em = { version = "emerald", party = {}, roamer = { active = true, species = 407, level = 40, hp = 100,
  status = 0, ivs = { hp = 1, atk = 2, def = 3, spe = 4, spa = 5, spd = 6 }, personality = 0xCAFEBABE,
  map = "EM_ROUTE110", history = { false, false, false } } }
local cfg = Roamer.config(em)
check(cfg ~= nil, "Emerald has a roamer profile row")
if cfg then
  Roamer._locations[cfg] = { { "EM_ROUTE110", "EM_ROUTE111" }, { "EM_ROUTE111", "EM_ROUTE110" } }
  local got
  for i = 1, 64 do
    Rng.SeedRng(i)
    got = Roamer.tryEncounter(em, "EM_ROUTE110", "land")
    if got then break end
  end
  check(flat(got), "Emerald roamer encounter is a flat battle foe")
  eq(got and got.personality, 0xCAFEBABE, "Emerald roamer reuses its personality")
  check(got and same_ivs(got.ivs, em.roamer.ivs), "Emerald roamer reuses its IVs")
  battler = { status = "BRN", mon = { hp = 40, status = "BRN" } }
  Roamer.onBattleEnd(em, battler.mon, "run", nil, battler)
  eq(em.roamer.hp, 40, "Emerald roamer keeps its damage")
  eq(em.roamer.status, 16, "Emerald roamer keeps its burn")
  check(em.roamer.active, "Emerald roamer stays active after the player runs")
end

-- pokefirered/src/battle_main.c:3929
local Cache = require("tests.game3_cache")
GameVersion.set("firered")
require("src.import.gba.versions").select("firered")
if Cache.mount("pokemon/battle_moves.lua") then
  local Battle = require("src.core.game3.battle.init")
  Space.store = Flags.newStore()
  Rng.SeedRng(7)
  local s = { version = "firered", name = "RED", trainerId = 1, secretId = 2, party = {
    { species = 6, level = 40, hp = 120, maxHp = 120, moves = { 33, 0, 0, 0 }, pp = { 35, 0, 0, 0 } } } }
  Roamer.init(s, 2)
  s.roamer.hp, s.roamer.status = 33, Roamer.statusWord(s, "PAR")
  local foe = meet(s, s.roamer.map, 9)
  Battle.start({ headless = true, autoFight = false, session = s, playerParty = s.party, foe = foe, wild = true,
    roamer = true })
  local st = assert(Battle.getState())
  local m = st.enemy.mon
  eq(m.personality, s.roamer.personality, "battle foe personality is the roamer's")
  check(same_ivs(m.ivs, Roamer.instanceIvs(s.roamer.ivs, true)), "battle foe IVs are the roamer's, read through SetMonData")
  eq(m.hp, 33, "battle foe starts at the roamer's HP")
  eq(st.enemy.status, "PAR", "battle foe starts with the roamer's status")
  eq(m.level, 50, "battle foe level is the roamer's")
  Battle.reset()
else
  print("[skip] battle start section: " .. tostring(Cache.reason))
end

T.finish("game3_roamer_instance_2882")
