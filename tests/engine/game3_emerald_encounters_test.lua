package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local before = GameVersion.get()
GameVersion.set("emerald")

local C = require("src.core.game3.constants").of("emerald")
local session = { version = "emerald", party = {}, flags = {}, vars = {} }
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }

local Rng = require("src.core.game3.rng")
local Pokemon = require("src.core.game3.pokemon")
local Encounters = require("src.core.game3.encounters")

-- pokeemerald/src/data/wild_encounters.h:6
local R101 = {
  { species = 290, minLevel = 2, maxLevel = 2 }, { species = 286, minLevel = 2, maxLevel = 2 },
  { species = 290, minLevel = 2, maxLevel = 2 }, { species = 290, minLevel = 3, maxLevel = 3 },
  { species = 286, minLevel = 3, maxLevel = 3 }, { species = 286, minLevel = 3, maxLevel = 3 },
  { species = 290, minLevel = 3, maxLevel = 3 }, { species = 286, minLevel = 3, maxLevel = 3 },
  { species = 288, minLevel = 2, maxLevel = 2 }, { species = 288, minLevel = 2, maxLevel = 2 },
  { species = 288, minLevel = 3, maxLevel = 3 }, { species = 288, minLevel = 3, maxLevel = 3 },
}
Encounters._tables = {
  EM_ROUTE101 = { land = { rate = 20, slots = R101 } },
  EM_ROUTE_STEEL = { land = { rate = 20, slots = {
    { species = 81, minLevel = 5, maxLevel = 5 }, { species = 16, minLevel = 5, maxLevel = 5 },
    { species = 16, minLevel = 5, maxLevel = 5 }, { species = 16, minLevel = 5, maxLevel = 5 },
    { species = 16, minLevel = 5, maxLevel = 5 }, { species = 16, minLevel = 5, maxLevel = 5 },
    { species = 16, minLevel = 5, maxLevel = 5 }, { species = 16, minLevel = 5, maxLevel = 5 },
    { species = 16, minLevel = 5, maxLevel = 5 }, { species = 16, minLevel = 5, maxLevel = 5 },
    { species = 16, minLevel = 5, maxLevel = 5 }, { species = 16, minLevel = 5, maxLevel = 5 },
  } } },
  EM_SOOTOPOLIS_CITY = { water = { rate = 1, slots = { { species = 129, minLevel = 5, maxLevel = 10 } } } },
}
Encounters._loaded = true

Pokemon._types = { [290] = { 6, 6 }, [286] = { 17, 17 }, [288] = { 0, 0 }, [81] = { 13, 8 }, [16] = { 0, 2 } }
Pokemon._speciesMeta = {
  [290] = { genderRatio = 127 }, [286] = { genderRatio = 127 }, [288] = { genderRatio = 127 },
  [81] = { genderRatio = 255 }, [16] = { genderRatio = 127 },
  [300] = { genderRatio = 127, itemCommon = 139, itemRare = 142 },
}
Pokemon._abilities = { [1] = { 0, 0 } }
Pokemon._names = { [1] = "X" }

local queue
local realRandom = Rng.Random
local function script(list)
  queue = list
  Rng.Random = function()
    local v = table.remove(queue, 1)
    assert(v ~= nil, "scripted Random() ran dry")
    return v
  end
end
local function unscript()
  Rng.Random = realRandom
end

local function lead(ability, level, personality, extra)
  local mon = { species = 1, level = level or 5, hp = 10, abilityId = ability and C:require("abilities", ability) or 0,
    personality = personality or 0 }
  for k, v in pairs(extra or {}) do mon[k] = v end
  session.party = { mon }
  return mon
end

local rules = Encounters.rules()
check(rules.everyStep == true, "RSE rules check every step")

print("[test] immunity steps (pokeemerald/src/field_control_avatar.c:668)")
Encounters.resetRateModifiers()
script({})
for i = 1, 4 do
  eq(Encounters.onStep("EM_ROUTE101", "land", { behavior = 1 }), nil, "immune step " .. i)
end
eq(#queue, 0, "immune steps consume no RNG")
unscript()

print("[test] WildEncounterCheck rate (pokeemerald/src/wild_encounter.c:502)")
lead(nil)
eq(Encounters.encounterRate(20), 320, "rate * 16")
eq(Encounters.encounterRate(200), 2880, "capped at 2880 (wild_encounter.c:27)")
lead("ABILITY_STENCH")
eq(Encounters.encounterRate(20), 160, "Stench halves")
lead("ABILITY_ILLUMINATE")
eq(Encounters.encounterRate(20), 640, "Illuminate doubles")
lead("ABILITY_ARENA_TRAP")
eq(Encounters.encounterRate(20), 640, "Arena Trap doubles")
lead("ABILITY_WHITE_SMOKE")
eq(Encounters.encounterRate(20), 160, "White Smoke halves")
lead("ABILITY_ILLUMINATE", 5, 0, { isEgg = true })
eq(Encounters.encounterRate(20), 320, "egg lead ignores ability")
lead(nil, 5, 0, { item = C:require("items", "ITEM_CLEANSE_TAG") })
eq(Encounters.encounterRate(20), 213, "Cleanse Tag * 2 / 3 (wild_encounter.c:963)")

print("[test] a Route 101 step rolls a Wurmple (pokeemerald/src/wild_encounter.c:552)")
lead(nil)
Encounters._immunitySteps = 4
Encounters._rsePrevBehavior = 1
script({ 100, 0, 0, 7, 7, 0 })
local enc = Encounters.onStep("EM_ROUTE101", "land", { behavior = 1 })
unscript()
check(enc ~= nil, "encounter")
eq(enc and enc.species, 290, "Wurmple")
eq(enc and enc.level, 2, "level 2")
eq(enc and enc.personality, 7, "personality from CreateMonWithNature")
eq(#queue, 0, "exact RNG use")
eq(Encounters._immunitySteps, 0, "immunity restarts after an encounter")

print("[test] new metatile gate (pokeemerald/src/wild_encounter.c:533)")
Encounters._immunitySteps = 4
Encounters._rsePrevBehavior = 2
script({ 60 })
eq(Encounters.onStep("EM_ROUTE101", "land", { behavior = 1 }), nil, "40% skip on a new metatile")
unscript()
eq(Encounters._rsePrevBehavior, 1, "previous behavior updated")

print("[test] slot distribution matches pret chances")
Encounters._immunitySteps = 4
local slotWant = { [0] = 1, [19] = 1, [20] = 2, [39] = 2, [40] = 3, [50] = 4, [60] = 5, [70] = 6,
  [80] = 7, [85] = 8, [90] = 9, [94] = 10, [98] = 11, [99] = 12 }
for rand, idx in pairs(slotWant) do
  Encounters._immunitySteps = 4
  Encounters._rsePrevBehavior = 1
  script({ 0, rand, 0, 0, 0, 0 })
  local e = Encounters.onStep("EM_ROUTE101", "land", { behavior = 1 })
  unscript()
  eq(e and e.species, R101[idx].species, "rand " .. rand .. " -> slot " .. idx)
end

print("[test] Keen Eye (pokeemerald/src/wild_encounter.c:897)")
lead("ABILITY_KEEN_EYE", 10)
Encounters._immunitySteps = 4
Encounters._rsePrevBehavior = 1
script({ 0, 0, 0, 0 })
eq(Encounters.onStep("EM_ROUTE101", "land", { behavior = 1 }), nil, "weak wild mon scared off")
unscript()
lead("ABILITY_KEEN_EYE", 10)
Encounters._immunitySteps = 4
script({ 0, 0, 0, 1, 3, 3, 0 })
local keen = Encounters.onStep("EM_ROUTE101", "land", { behavior = 1 })
unscript()
eq(keen and keen.species, 290, "coin flip lets it through")

print("[test] Hustle forces max level (pokeemerald/src/wild_encounter.c:268)")
lead("ABILITY_HUSTLE")
local sp = rules.tryGenerate
script({ 0, 0 })
eq(rules.chooseLevel({ minLevel = 20, maxLevel = 25 }), 25, "Random()%2 == 0 -> max")
unscript()
script({ 3, 1 })
eq(rules.chooseLevel({ minLevel = 20, maxLevel = 25 }), 22, "else rand - 1")
unscript()
check(sp ~= nil, "tryGenerate exported")

print("[test] Magnet Pull picks a Steel slot (pokeemerald/src/wild_encounter.c:938)")
lead("ABILITY_MAGNET_PULL")
Encounters._immunitySteps = 4
Encounters._rsePrevBehavior = 1
script({ 0, 0, 0, 0, 0, 0, 0 })
local mp = Encounters.onStep("EM_ROUTE_STEEL", "land", { behavior = 1 })
unscript()
eq(mp and mp.species, 81, "Magnemite from the only Steel slot")

print("[test] Synchronize (pokeemerald/src/wild_encounter.c:335)")
lead("ABILITY_SYNCHRONIZE", 5, 13)
script({ 0, 13, 0 })
local syn = rules.createWild(290, 3)
unscript()
eq(syn.personality % 25, 13, "nature follows the lead")

print("[test] Cute Charm (pokeemerald/src/wild_encounter.c:379)")
lead("ABILITY_CUTE_CHARM", 5, 0)
Pokemon._speciesMeta[1] = { genderRatio = 127 }
script({ 1, 5, 205, 0 })
local cc = rules.createWild(290, 3)
unscript()
eq(cc.personality % 25, 5, "nature kept")
eq((cc.personality % 256) < 127 and "F" or "M", "M", "opposite of the female lead")

print("[test] Sootopolis legendaries block water encounters (pokeemerald/src/wild_encounter.c:541)")
lead(nil)
session.flags[C:require("flags", "FLAG_LEGENDARIES_IN_SOOTOPOLIS")] = true
Encounters._immunitySteps = 4
Encounters._rsePrevBehavior = 1
script({})
eq(Encounters.onStep("EM_SOOTOPOLIS_CITY", "water", { behavior = 1 }), nil, "no water encounter")
unscript()

print("[test] held item odds (pokeemerald/src/pokemon.c:6678)")
lead(nil)
script({ 44 })
eq(rules.wildHeldItem(300), nil, "rnd < 45 -> none")
script({ 45 })
eq(rules.wildHeldItem(300), 139, "rnd < 95 -> common")
script({ 95 })
eq(rules.wildHeldItem(300), 142, "else rare")
lead("ABILITY_COMPOUND_EYES")
script({ 20 })
eq(rules.wildHeldItem(300), 139, "Compound Eyes lowers the no-item band to 20")
unscript()

print("[test] Feebas spots (pokeemerald/src/wild_encounter.c:113)")
lead(nil)
local realLoad = Encounters.loadCacheFile
Encounters.loadCacheFile = function(file)
  if file == "wild_extra.lua" then
    return {
      feebas = {
        mon = { species = 328, minLevel = 20, maxLevel = 25 },
        sections = { { yMin = 0, yMax = 45, spotBase = 0 }, { yMin = 46, yMax = 91, spotBase = 131 },
          { yMin = 92, yMax = 139, spotBase = 298 } },
      },
      alteringCaveHeldItems = { { species = 0, item = 0 } },
    }
  end
  return realLoad(file)
end
package.loaded["src.core.game3.scripting.collision_rse"] = { _tileBits = { [5] = 3 } }
Encounters._tables.EM_ROUTE119 = { fishing = { rate = 30, slots = {
  { species = 129, minLevel = 5, maxLevel = 10 }, { species = 129, minLevel = 5, maxLevel = 10 },
  { species = 129, minLevel = 5, maxLevel = 10 }, { species = 129, minLevel = 5, maxLevel = 10 },
  { species = 129, minLevel = 5, maxLevel = 10 }, { species = 129, minLevel = 5, maxLevel = 10 },
  { species = 129, minLevel = 5, maxLevel = 10 }, { species = 129, minLevel = 5, maxLevel = 10 },
  { species = 129, minLevel = 5, maxLevel = 10 }, { species = 129, minLevel = 5, maxLevel = 10 },
} } }
session.dewfordTrends = { { rand = 2 } }
local water = function() return 5 end
script({ 0, 3, 0, 0, 0 })
local fb = Encounters.rollFishing("EM_ROUTE119", "old", { x = 0, y = 19, behaviorAt = water, mapWidth = 1 })
unscript()
eq(fb and fb.species, 328, "seed 2 puts a Feebas spot on fishing spot 20")
eq(fb and fb.level, 23, "Feebas level 20 + 3")
script({ 0 })
check(not rules.checkFeebas("EM_ROUTE119", { x = 0, y = 18, behaviorAt = water, mapWidth = 1 }),
  "spot 19 is not a Feebas spot")
unscript()
script({ 50 })
check(not rules.checkFeebas("EM_ROUTE119", { x = 0, y = 19, behaviorAt = water, mapWidth = 1 }),
  "Random() % 100 > 49 fails the 50% roll")
unscript()
script({ 69, 0, 0, 0, 0 })
local old = Encounters.rollFishing("EM_ROUTE101", "old", {})
unscript()
eq(old, nil, "no fishing table off Route 119")
package.loaded["src.core.game3.scripting.collision_rse"] = nil
Encounters.loadCacheFile = realLoad

print("[test] FireRed keeps its own rules")
GameVersion.set("firered")
session.version = "firered"
check(Encounters.rules().everyStep == nil, "FR rules are the cooldown model")
eq(Encounters.mapBaseCooldown("land", 21), 6, "FR cooldown still answers")

GameVersion.set(before)
package.loaded["src.core.game3.runtime"] = nil
T.finish("game3_emerald_encounters_test")
