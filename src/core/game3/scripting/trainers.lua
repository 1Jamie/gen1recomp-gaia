-- Trainer party lookup + ROM-derived class/name/pic/party/dialog info for battles and overworld.

local Trainers = {}

-- Fallbacks when trainers.lua cache is missing (Oak's Lab rivals).
local SPECIES_BULBASAUR = 1
local SPECIES_CHARMANDER = 4
local SPECIES_SQUIRTLE = 7

local TRAINER_RIVAL_OAKS_LAB_SQUIRTLE = 326
local TRAINER_RIVAL_OAKS_LAB_BULBASAUR = 327
local TRAINER_RIVAL_OAKS_LAB_CHARMANDER = 328

local FALLBACK_TRAINERS = {
  [TRAINER_RIVAL_OAKS_LAB_SQUIRTLE] = {
    class = 81, className = "RIVAL", pic = 106, name = "TERRY", gender = 0, doubleBattle = false,
    partySize = 1, lastLevel = 5, aiFlags = 7, items = { 0, 0, 0, 0 },
    party = { { species = SPECIES_SQUIRTLE, level = 5, rawIv = 0, iv = 0, ivs = { hp=0, atk=0, def=0, spa=0, spd=0, spe=0 }, evs = { hp=0, atk=0, def=0, spa=0, spd=0, spe=0 } } },
    dialogs = { defeat = "WHAT?\nUnbelievable!\n\nI picked the wrong POKéMON!", victory = "RIVAL: Yeah!\nAm I great or what?" },
  },
  [TRAINER_RIVAL_OAKS_LAB_BULBASAUR] = {
    class = 81, className = "RIVAL", pic = 106, name = "TERRY", gender = 0, doubleBattle = false,
    partySize = 1, lastLevel = 5, aiFlags = 7, items = { 0, 0, 0, 0 },
    party = { { species = SPECIES_BULBASAUR, level = 5, rawIv = 0, iv = 0, ivs = { hp=0, atk=0, def=0, spa=0, spd=0, spe=0 }, evs = { hp=0, atk=0, def=0, spa=0, spd=0, spe=0 } } },
    dialogs = { defeat = "WHAT?\nUnbelievable!\n\nI picked the wrong POKéMON!", victory = "RIVAL: Yeah!\nAm I great or what?" },
  },
  [TRAINER_RIVAL_OAKS_LAB_CHARMANDER] = {
    class = 81, className = "RIVAL", pic = 106, name = "TERRY", gender = 0, doubleBattle = false,
    partySize = 1, lastLevel = 5, aiFlags = 7, items = { 0, 0, 0, 0 },
    party = { { species = SPECIES_CHARMANDER, level = 5, rawIv = 0, iv = 0, ivs = { hp=0, atk=0, def=0, spa=0, spd=0, spe=0 }, evs = { hp=0, atk=0, def=0, spa=0, spd=0, spe=0 } } },
    dialogs = { defeat = "WHAT?\nUnbelievable!\n\nI picked the wrong POKéMON!", victory = "RIVAL: Yeah!\nAm I great or what?" },
  },
}

Trainers._pack = nil

local function load_pack()
  if Trainers._pack then return Trainers._pack end
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  local cache = okD and Dataset and Dataset.cache and Dataset.cache()
  local src
  if cache and cache.read then
    src = cache:read("data/generated/gba/trainers.lua")
  end
  if not src then
    local ok, CacheFs = pcall(require, "src.import.CacheFs")
    if ok and CacheFs and CacheFs.readActive then
      src = CacheFs.readActive("data/generated/gba/trainers.lua")
    end
  end
  if type(src) == "string" and #src > 0 then
    local chunk = load(src, "@trainers.lua", "t", {})
    if chunk then
      local ok, pack = pcall(chunk)
      if ok and type(pack) == "table" then
        Trainers._pack = pack
        return pack
      end
    end
  end
  Trainers._pack = false
  return nil
end

local function decompose_ai_flags(flags)
  flags = tonumber(flags) or 0
  return {
    checkBadMove = (flags % 2 == 1),
    checkViability = (math.floor(flags / 2) % 2 == 1),
    tryToFaint = (math.floor(flags / 4) % 2 == 1),
    setupFirstTurn = (math.floor(flags / 8) % 2 == 1),
    risky = (math.floor(flags / 16) % 2 == 1),
    preferStrongestMove = (math.floor(flags / 32) % 2 == 1),
    preferBatonPass = (math.floor(flags / 64) % 2 == 1),
    doubleBattle = (math.floor(flags / 128) % 2 == 1),
    hpAware = (math.floor(flags / 256) % 2 == 1),
    roaming = (math.floor(flags / 0x20000000) % 2 == 1),
    safari = (math.floor(flags / 0x40000000) % 2 == 1),
    firstBattle = (flags >= 0x80000000),
  }
end

--- Get full trainer definition record by trainerId.
function Trainers.get(trainerId)
  trainerId = tonumber(trainerId)
  if not trainerId then return nil end

  local pack = load_pack()
  local row = pack and pack.trainers and pack.trainers[trainerId]
  if row then
    local classNames = pack and pack.classNames
    local class = tonumber(row.class) or 0
    return {
      id = trainerId,
      class = class,
      className = row.className or (classNames and classNames[class]) or "",
      pic = tonumber(row.pic) or 0,
      name = row.name or "",
      gender = tonumber(row.gender) or 0,
      encounterMusic = tonumber(row.encounterMusic) or 0,
      doubleBattle = row.doubleBattle and true or false,
      partySize = tonumber(row.partySize) or (row.party and #row.party) or 0,
      partyFlags = tonumber(row.partyFlags) or 0,
      lastLevel = tonumber(row.lastLevel) or 1,
      aiFlags = tonumber(row.aiFlags) or 0,
      ai = decompose_ai_flags(row.aiFlags),
      items = row.items or { 0, 0, 0, 0 },
      party = row.party or {},
      dialogs = row.dialogs or {},
      scriptKey = row.scriptKey,
      introTextKey = row.introTextKey,
      defeatTextKey = row.defeatTextKey,
    }
  end

  local fb = FALLBACK_TRAINERS[trainerId]
  if fb then
    return {
      id = trainerId,
      class = fb.class,
      className = fb.className,
      pic = fb.pic,
      name = fb.name,
      gender = fb.gender or 0,
      encounterMusic = fb.encounterMusic or 0,
      doubleBattle = fb.doubleBattle,
      partySize = fb.partySize,
      lastLevel = fb.lastLevel,
      aiFlags = fb.aiFlags,
      ai = decompose_ai_flags(fb.aiFlags),
      items = fb.items,
      party = fb.party,
      dialogs = fb.dialogs,
    }
  end

  return nil
end

--- Resolve a foe battler struct + full party for battle runtime.
-- Guarantees:
-- 1. Uniform Flat IV scaling: actualIv = (rawIv * 31) / 255 across all 6 stats
-- 2. Explicit Zero EVs across all stats (no residual player data)
-- 3. Correct custom moves and held items
function Trainers.foeFromId(trainerId)
  trainerId = tonumber(trainerId)
  if not trainerId then return nil end

  local t = Trainers.get(trainerId)
  if not t or not t.party or #t.party == 0 then
    return nil
  end

  local foeParty = {}
  for _, m in ipairs(t.party) do
    local rawIv = tonumber(m.rawIv) or tonumber(m.iv) or 0
    local iv = tonumber(m.iv) or math.floor((rawIv * 31) / 255)
    local mon = {
      species = tonumber(m.species) or 1,
      level = tonumber(m.level) or 5,
      rawIv = rawIv,
      iv = iv,
      ivs = { hp = iv, atk = iv, def = iv, spa = iv, spd = iv, spe = iv },
      -- Trainer EVs are strictly zero
      evs = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
      heldItem = tonumber(m.heldItem) or nil,
      moves = m.moves,
      trainerId = trainerId,
    }
    foeParty[#foeParty + 1] = mon
  end

  local lead = foeParty[1]
  return {
    species = lead.species,
    level = lead.level,
    rawIv = lead.rawIv,
    iv = lead.iv,
    ivs = lead.ivs,
    evs = lead.evs,
    heldItem = lead.heldItem,
    moves = lead.moves,
    trainerId = trainerId,
    aiFlags = t.aiFlags,
    ai = t.ai,
    items = t.items,
    party = foeParty,
    trainerName = t.name,
    trainerClass = t.class,
    trainerClassName = t.className,
    trainerPic = t.pic,
    gender = t.gender,
    encounterMusic = t.encounterMusic,
    doubleBattle = t.doubleBattle,
  }
end

--- ROM-derived trainer presentation info (class / name / pic / partySize / dialogs).
-- opts.rivalName replaces placeholder "TERRY" for class RIVAL when provided.
function Trainers.info(trainerId, opts)
  opts = opts or {}
  trainerId = tonumber(trainerId)
  if not trainerId then return nil end

  local t = Trainers.get(trainerId)
  if not t then return nil end

  local info = {
    class = t.class,
    className = t.className,
    name = t.name,
    pic = t.pic,
    gender = t.gender,
    encounterMusic = t.encounterMusic,
    doubleBattle = t.doubleBattle,
    partySize = t.partySize or #t.party,
    lastLevel = t.lastLevel,
    aiFlags = t.aiFlags,
    ai = t.ai,
    items = t.items,
    party = t.party,
    dialogs = t.dialogs,
  }

  if info.className == "RIVAL" and opts.rivalName and opts.rivalName ~= "" then
    info.name = opts.rivalName
  end
  return info
end

--- Get dialog texts table: { intro, defeat, victory, notEnough }
function Trainers.dialogs(trainerId)
  local t = Trainers.get(trainerId)
  return t and t.dialogs or {}
end

--- FRLG intro string pieces for a trainer battle.
function Trainers.introStrings(trainerId, monName, opts)
  local info = Trainers.info(trainerId, opts) or {
    className = "POKéMON TRAINER",
    name = "",
  }
  local class = info.className or "POKéMON TRAINER"
  local name = info.name or ""
  local who = class
  if name ~= "" then
    who = class .. " " .. name
  end
  monName = monName or "POKéMON"
  return {
    wants = who .. "\nwould like to battle!",
    sentOut = who .. " sent\nout " .. monName .. "!",
    info = info,
  }
end

return Trainers
