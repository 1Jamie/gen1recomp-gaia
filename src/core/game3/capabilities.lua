-- Capability registry for the Game 3 feature sets (T3.1/T3.2).
--
-- Why: a gate written against a raw flag (`if not caps.famechecker`) fails
-- silently when the flag name is wrong, and a profile row can carry a typo the
-- engine never notices.  This module owns the legal flag names, the composed
-- per-game sets, and the feature -> capability map, so gating call sites ask by
-- FEATURE and the audit test proves every profile row is well formed.
--
-- The FireRed-only set is grounded in pret: each row below cites the
-- pokefirered source file (local clone, HEAD c75f35230) and the feature's
-- absence in pokeemerald/pokeruby (verified 2026-09-22).  RSE-only rows cite
-- pokeemerald.
--
-- Resolution reads src/core/game3/profile.lua, which already fails closed to
-- FireRed until profiles/ruby.lua etc. exist.  New file, unwired: the feature
-- gates are handoff patches in docs/game3/rse-seams.md section 4.

local Profile = require("src.core.game3.profile")

local Capabilities = {}

--- Every legal capability flag.  A profile row that sets anything else is a
-- bug the audit test catches.
Capabilities.NAMES = {
  -- shared GBA primitives (both FireRed and RSE implement them)
  easyChat = true,
  braille = true,
  mysteryGift = true,
  unionRoom = true,
  daycare = true,
  pokecenter = true,
  marts = true,
  moveRelearner = true,
  eggs = true,
  berries = true,
  sizeRecord = true, -- pokeemerald/src/pokemon_size_record.c exists; record DATA differs
  -- FireRed-only (absent from pokeemerald/pokeruby)
  helpSystem = true, -- pokefirered/src/help_system.c
  tmCase = true, -- pokefirered/src/tm_case.c
  fameChecker = true, -- pokefirered/src/fame_checker.c
  teachyTV = true, -- pokefirered/src/teachy_tv.c
  vsSeeker = true, -- pokefirered/src/vs_seeker.c
  trainerTower = true, -- pokefirered/src/trainer_tower.c
  seagallop = true, -- pokefirered/src/seagallop.c
  trainerFanClub = true, -- pokefirered/src/trainer_fan_club.c
  sevii = true, -- the Sevii region itself
  -- RSE-only (pokeemerald sources; declared now so rows can set them early)
  contests = true,
  secretBase = true,
  battleTower = true,
  berryPouch = true,
  matchCall = true,
  pokeNav = true,
}

-- Composed sets.  Profile rows inline their flags (data-only by design), so
-- these are the authored reference the tests compare rows against.
Capabilities.CORE = {
  easyChat = true, braille = true, mysteryGift = true, unionRoom = true,
  daycare = true, pokecenter = true, marts = true, moveRelearner = true,
  eggs = true, berries = true, sizeRecord = true,
}

Capabilities.FRLG = {
  -- core
  easyChat = true, braille = true, mysteryGift = true, unionRoom = true,
  daycare = true, pokecenter = true, marts = true, moveRelearner = true,
  eggs = true, berries = true, sizeRecord = true,
  -- FireRed-only
  helpSystem = true, tmCase = true, fameChecker = true, teachyTV = true,
  vsSeeker = true, trainerTower = true, seagallop = true,
  trainerFanClub = true, berryPouch = true, sevii = true,
}

Capabilities.RSE = {
  -- core
  easyChat = true, braille = true, mysteryGift = true, unionRoom = true,
  daycare = true, pokecenter = true, marts = true, moveRelearner = true,
  eggs = true, berries = true, sizeRecord = true,
  -- RSE-only
  battleTower = true, -- pokeemerald/src/battle_tower.c (FRLG's player tower is trainerTower)
  contests = true, secretBase = true, matchCall = true, pokeNav = true,
}

--- Feature -> capability + owning modules.  `source` is the authoritative pret
-- file for the feature (repo-relative, e.g. "pokefirered/src/fame_checker.c");
-- `counterpart` records the other-generation check.  Gating patches ask for the
-- feature id, never the raw flag.
Capabilities.FEATURES = {
  -- FireRed-only (source present in pokefirered, 404 in pokeemerald/pokeruby)
  fame_checker = {
    cap = "fameChecker",
    label = "Fame Checker",
    source = "pokefirered/src/fame_checker.c",
    counterpart = "absent from pokeemerald/pokeruby (ITEM_FAME_CHECKER is a leftover constant)",
    core = "src.core.game3.fame_checker",
    ui = "src.ui.game3.fame_checker",
    extractor = "fame_checker_extract",
    natives = "natives_fame",
  },
  teachy_tv = {
    cap = "teachyTV",
    label = "Teachy TV",
    source = "pokefirered/src/teachy_tv.c",
    counterpart = "absent from pokeemerald/pokeruby (ITEM_TEACHY_TV is a leftover constant)",
    core = "src.core.game3.teachy_tv",
    ui = "src.ui.game3.teachy_tv",
    extractor = "teachy_tv_extract",
  },
  vs_seeker = {
    cap = "vsSeeker",
    label = "VS Seeker",
    source = "pokefirered/src/vs_seeker.c",
    counterpart = "absent from pokeemerald/pokeruby (ITEM_VS_SEEKER is a leftover constant)",
    core = "src.core.game3.vs_seeker",
    data = "src.core.game3.vs_seeker_data",
  },
  trainer_tower = {
    cap = "trainerTower",
    label = "Trainer Tower",
    source = "pokefirered/src/trainer_tower.c",
    counterpart = "absent from pokeemerald/pokeruby (Emerald's src/battle_tower.c is a different mode)",
    core = "src.core.game3.trainer_tower",
    ui = "src.ui.game3.trainer_tower_records",
    extractor = "trainer_tower_extract",
    natives = "natives_tower",
  },
  seagallop = {
    cap = "seagallop",
    label = "Seagallop ferry",
    source = "pokefirered/src/seagallop.c",
    counterpart = "absent from pokeemerald/pokeruby",
    natives = "natives_seagallop",
    extractor = "seagallop_extract",
  },
  help_system = {
    cap = "helpSystem",
    label = "Help System",
    source = "pokefirered/src/help_system.c",
    counterpart = "absent from pokeemerald/pokeruby",
    ui = "src.ui.game3.help_system",
    extractor = "help_extract",
  },
  tm_case = {
    cap = "tmCase",
    label = "TM Case",
    source = "pokefirered/src/tm_case.c",
    counterpart = "absent from pokeemerald/pokeruby",
    ui = "src.ui.game3.tm_case",
    extractor = "tm_case_extract",
  },
  trainer_fan_club = {
    cap = "trainerFanClub",
    label = "Trainer Fan Club",
    source = "pokefirered/src/trainer_fan_club.c",
    counterpart = "absent from pokeemerald/pokeruby",
    core = "src.core.game3.trainer_fan_club",
    natives = "natives_fan_club",
  },
  berry_pouch = {
    cap = "berryPouch",
    label = "Berry Pouch",
    source = "pokefirered/src/berry_pouch.c",
    counterpart = "absent from pokeemerald/pokeruby (RSE keeps berries in the bag)",
    ui = "src.ui.game3.berry_pouch",
    extractor = "berry_pouch_extract",
  },
  -- RSE-only (source present in pokeemerald, 404 in pokefirered)
  contests = {
    cap = "contests",
    label = "Pokemon Contests",
    source = "pokeemerald/src/contest.c",
    counterpart = "absent from pokefirered",
  },
  secret_base = {
    cap = "secretBase",
    label = "Secret Bases",
    source = "pokeemerald/src/secret_base.c",
    counterpart = "absent from pokefirered",
  },
  match_call = {
    cap = "matchCall",
    label = "Match Call (Emerald)",
    source = "pokeemerald/src/match_call.c",
    counterpart = "absent from pokefirered and pokeruby (RS use the PokeNav)",
  },
  poke_nav = {
    cap = "pokeNav",
    label = "PokeNav",
    source = "pokeemerald/src/pokenav.c",
    counterpart = "absent from pokefirered",
  },
}

local warned = {}

local function log(msg)
  print("[game3/capabilities] " .. tostring(msg))
end

local function warnOnce(key, msg)
  if warned[key] then return end
  warned[key] = true
  log(msg)
end

--- The capability table for a session's game.
function Capabilities.of(session)
  return Profile.capabilitiesFor(session)
end

--- Raw flag lookup, strict about the name: an unknown flag is a typo in a gate
-- (it would silently disable a feature), so it warns once and reads false.
function Capabilities.has(session, cap)
  if not Capabilities.NAMES[cap] then
    warnOnce("cap:" .. tostring(cap), "unknown capability '" .. tostring(cap) .. "'")
    return false
  end
  return Capabilities.of(session)[cap] == true
end

--- Pure helper for tests/tools: is a feature enabled in this capabilities table?
function Capabilities.enabled(caps, featureId)
  local feature = Capabilities.FEATURES[featureId]
  if not feature or type(caps) ~= "table" then return false end
  return caps[feature.cap] == true
end

--- Session gate a call site asks by feature id.  Unknown feature ids warn once
-- and read false -- the same typo protection as has().
function Capabilities.gate(session, featureId)
  if not Capabilities.FEATURES[featureId] then
    warnOnce("feat:" .. tostring(featureId),
      "unknown feature '" .. tostring(featureId) .. "'")
    return false
  end
  return Capabilities.enabled(Capabilities.of(session), featureId)
end

--- Reverse index: natives module base name -> feature id.
local nativesIndex

--- The feature a natives_* module belongs to, or nil when it is shared.
function Capabilities.nativeFeature(moduleName)
  nativesIndex = nativesIndex or (function()
    local index = {}
    for id, feature in pairs(Capabilities.FEATURES) do
      if feature.natives then index[feature.natives] = id end
    end
    return index
  end)()
  if type(moduleName) ~= "string" then return nil end
  return nativesIndex[moduleName]
end

--- Gate for the natives registry: a module mapped to a feature follows that
-- feature's capability; an unmapped module is shared and always allowed.
function Capabilities.nativeAllowed(session, moduleName)
  local featureId = Capabilities.nativeFeature(moduleName)
  if not featureId then return true end
  return Capabilities.gate(session, featureId)
end

--- Validate a profile row's capability table.  Returns ok, problems (sorted).
function Capabilities.audit(caps)
  local problems = {}
  if type(caps) ~= "table" then
    problems[1] = "capabilities table is missing"
    return false, problems
  end
  for name, value in pairs(caps) do
    if not Capabilities.NAMES[name] then
      problems[#problems + 1] = "unknown capability '" .. tostring(name) .. "'"
    elseif type(value) ~= "boolean" then
      problems[#problems + 1] =
        "capability '" .. name .. "' is " .. type(value) .. ", not boolean"
    end
  end
  table.sort(problems)
  return #problems == 0, problems
end

--- Test/tool hook: forget the warn-once keys.
function Capabilities.reset()
  warned = {}
end

return Capabilities
