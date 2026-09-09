-- Trainer party lookup + ROM-derived class/name/pic info for battle intro.

local Trainers = {}

-- pret opponents.h / trainer_parties.h (Oak's Lab early rival parties until full party extract)
local SPECIES_BULBASAUR = 1
local SPECIES_CHARMANDER = 4
local SPECIES_SQUIRTLE = 7

local TRAINER_RIVAL_OAKS_LAB_SQUIRTLE = 326
local TRAINER_RIVAL_OAKS_LAB_BULBASAUR = 327
local TRAINER_RIVAL_OAKS_LAB_CHARMANDER = 328

local PARTIES = {
  [TRAINER_RIVAL_OAKS_LAB_SQUIRTLE] = {
    { species = SPECIES_SQUIRTLE, level = 5 },
  },
  [TRAINER_RIVAL_OAKS_LAB_BULBASAUR] = {
    { species = SPECIES_BULBASAUR, level = 5 },
  },
  [TRAINER_RIVAL_OAKS_LAB_CHARMANDER] = {
    { species = SPECIES_CHARMANDER, level = 5 },
  },
}

-- Fallbacks when trainers.lua cache is missing (Oak's Lab rivals).
local FALLBACK_INFO = {
  [TRAINER_RIVAL_OAKS_LAB_SQUIRTLE] = {
    class = 81, className = "RIVAL", pic = 106, name = "TERRY", partySize = 1, lastLevel = 5, aiFlags = 7,
  },
  [TRAINER_RIVAL_OAKS_LAB_BULBASAUR] = {
    class = 81, className = "RIVAL", pic = 106, name = "TERRY", partySize = 1, lastLevel = 5, aiFlags = 7,
  },
  [TRAINER_RIVAL_OAKS_LAB_CHARMANDER] = {
    class = 81, className = "RIVAL", pic = 106, name = "TERRY", partySize = 1, lastLevel = 5, aiFlags = 7,
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

--- Resolve a foe battler stub from trainer id (first party mon).
function Trainers.foeFromId(trainerId)
  trainerId = tonumber(trainerId)
  if not trainerId then return nil end
  local party = PARTIES[trainerId]
  local mon = party and party[1]
  if not mon then return nil end
  local foeParty = {}
  for _, m in ipairs(party) do
    foeParty[#foeParty + 1] = {
      species = m.species,
      level = m.level or 5,
      moves = m.moves,
      trainerId = trainerId,
    }
  end
  return {
    species = mon.species,
    level = mon.level or 5,
    moves = mon.moves,
    trainerId = trainerId,
    party = foeParty,
  }
end

--- ROM-derived trainer presentation info (class / name / pic / partySize).
-- opts.rivalName replaces placeholder "TERRY" for class RIVAL when provided.
function Trainers.info(trainerId, opts)
  opts = opts or {}
  trainerId = tonumber(trainerId)
  if not trainerId then return nil end

  local pack = load_pack()
  local row = pack and pack.trainers and pack.trainers[trainerId]
  local classNames = pack and pack.classNames
  local info
  if row then
    local class = tonumber(row.class) or 0
    info = {
      class = class,
      className = (classNames and classNames[class]) or "",
      pic = tonumber(row.pic) or 0,
      name = row.name or "",
      partySize = tonumber(row.partySize) or 1,
      lastLevel = tonumber(row.lastLevel) or 1,
      aiFlags = tonumber(row.aiFlags) or 0,
      items = row.items,
    }
  else
    local fb = FALLBACK_INFO[trainerId]
    if not fb then return nil end
    info = {
      class = fb.class,
      className = fb.className,
      pic = fb.pic,
      name = fb.name,
      partySize = fb.partySize,
      lastLevel = fb.lastLevel or 5,
      aiFlags = fb.aiFlags or 7,
      items = fb.items or { 0, 0, 0, 0 },
    }
  end

  if info.className == "RIVAL" and opts.rivalName and opts.rivalName ~= "" then
    info.name = opts.rivalName
  end
  return info
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
