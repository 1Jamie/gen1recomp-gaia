local Rng = require("src.core.game3.rng")

local Roamer = {}

local function cfg_of(session)
  local ok, BattleProfile = pcall(require, "src.core.game3.battle.profile")
  if not ok then return nil end
  local okP, p = pcall(BattleProfile.get, session)
  return okP and p and p.roamer or nil
end
Roamer.config = cfg_of

local IV_KEYS = { "hp", "atk", "def", "spe", "spa", "spd" }
local IV_LONG = { hp = "hp", atk = "attack", def = "defense", spe = "speed", spa = "spAtk", spd = "spDef" }
local STATUS1 = {
  { "PSN", "STATUS1_POISON" }, { "BRN", "STATUS1_BURN" }, { "FRZ", "STATUS1_FREEZE" },
  { "PAR", "STATUS1_PARALYSIS" }, { "TOX", "STATUS1_TOXIC_POISON" },
}

local function battle_const(session, name)
  local Constants = require("src.core.game3.constants")
  return Constants.active(session):require("battle", name)
end

-- pokefirered/include/global.h:417
function Roamer.statusWord(session, status, sleep)
  if type(status) == "number" then return status % 256 end
  if status == "SLP" then
    local mask = battle_const(session, "STATUS1_SLEEP")
    local n = math.floor(tonumber(sleep) or 0)
    if n < 1 then n = 1 elseif n > mask then n = mask end
    return n
  end
  for _, e in ipairs(STATUS1) do
    if status == e[1] then return battle_const(session, e[2]) end
  end
  return 0
end

function Roamer.battleStatus(session, word)
  word = (tonumber(word) or 0) % 256
  local sleep = word % (battle_const(session, "STATUS1_SLEEP") + 1)
  if sleep ~= 0 then return "SLP", sleep end
  for _, e in ipairs(STATUS1) do
    local bit = battle_const(session, e[2])
    if math.floor(word / bit) % 2 == 1 then return e[1], nil end
  end
  return nil, nil
end

local function iv_table(src)
  local out = {}
  for i, k in ipairs(IV_KEYS) do
    if type(src) == "number" then
      out[k] = math.floor(src / 2 ^ ((i - 1) * 5)) % 32
    else
      local v = type(src) == "table" and (src[k] or src[IV_LONG[k]]) or 0
      out[k] = (tonumber(v) or 0) % 32
    end
  end
  return out
end

function Roamer.normalize(session)
  local r = session and session.roamer
  if type(r) ~= "table" then return nil end
  r.personality = (tonumber(r.personality or r.pid) or 0) % 0x100000000
  r.ivs = iv_table(r.ivs)
  local status = r.status
  if status == nil or status == 0 then status = r.statusNum end
  r.status = Roamer.statusWord(session, status, r.sleep)
  r.pid, r.statusNum, r.sleep, r.maxHp, r.moves, r.pp = nil, nil, nil, nil, nil, nil
  return r
end

function Roamer.instanceIvs(ivs, truncated)
  local out = iv_table(ivs)
  if not truncated then return out end
  -- pokefirered/src/pokemon.c:3660
  return iv_table(out.hp + (out.atk % 8) * 32)
end

-- pokefirered/src/roamer.c:206
function Roamer.instance(session)
  local r = Roamer.normalize(session)
  if not r then return nil end
  local cfg = cfg_of(session)
  local status, sleep = Roamer.battleStatus(session, r.status)
  return {
    species = r.species, speciesId = r.species, level = r.level, roamer = true,
    personality = r.personality, ivs = Roamer.instanceIvs(r.ivs, cfg and cfg.truncateIvs),
    hp = r.hp, status = status, sleep = sleep, item = 0,
  }
end

-- pokefirered/src/roamer.c:240
local function update_hp_status(session, mon, battler)
  local r = session.roamer
  if mon then r.hp = math.max(0, tonumber(mon.hp) or r.hp or 0) end
  local status, sleep
  if battler then
    status, sleep = battler.status, battler.sleepTurns or (battler.mon and battler.mon.sleep)
  elseif mon then
    status, sleep = mon.status, mon.sleepTurns or mon.sleep
  else
    return
  end
  r.status = Roamer.statusWord(session, status, sleep)
end

-- pokefirered/src/roamer.c:103
local function create_initial(species, level)
  -- pokefirered/src/pokemon.c:1778
  local personality = Rng.Random32()
  -- pokefirered/src/pokemon.c:1836
  local iv1 = Rng.Random()
  local iv2 = Rng.Random()
  local ivs = iv_table(iv1 % 0x8000 + (iv2 % 0x8000) * 0x8000)
  local stats = require("src.core.game3.pokemon").calcStats(species, level, ivs, {}, personality)
  return {
    active = true,
    species = species,
    level = level,
    status = 0,
    ivs = ivs,
    personality = personality,
    hp = stats.maxHp,
  }
end

Roamer._locations = setmetatable({}, { __mode = "k" })

function Roamer.locationSets(cfg)
  local hit = Roamer._locations[cfg]
  if hit then return hit end
  local src = require("src.core.game3.dataset").cache():read(cfg.locations)
  if type(src) ~= "string" then error(tostring(cfg.locations) .. " is missing from the cache") end
  local data = assert(load(src, "@" .. cfg.locations, "t", {}))()
  if type(data) ~= "table" or type(data.sets) ~= "table" or #data.sets == 0 then
    error(tostring(cfg.locations) .. " has no roamer location sets")
  end
  Roamer._locations[cfg] = data.sets
  return data.sets
end

local function roamer_state(session)
  local r = session and session.roamer
  if type(r) ~= "table" then return nil end
  r.history = r.history or { false, false, false }
  return r
end

-- pokeemerald/src/roamer.c:84
function Roamer.initRse(session, createLatios)
  local cfg = cfg_of(session)
  if not (session and cfg) then return false end
  local C = require("src.core.game3.constants").of(require("src.core.game3.constants").versionOf(session))
  -- pokeruby/include/constants/species.h:1282
  local species = C:require("species", cfg.fixedSpecies or cfg.species[createLatios and 1 or 0])
  session.roamer = create_initial(species, cfg.level)
  session.roamer.history = { false, false, false }
  -- pokeemerald/src/roamer.c:104
  local sets = Roamer.locationSets(cfg)
  session.roamer.map = sets[(Rng.Random() % #sets) + 1][1]
  return true
end

-- pokeemerald/src/roamer.c:115
function Roamer.updateHistory(session, mapId)
  local r = roamer_state(session)
  if not r then return end
  r.history[3] = r.history[2]
  r.history[2] = r.history[1]
  r.history[1] = mapId or false
end

-- pokeemerald/src/roamer.c:127
function Roamer.moveToOtherSet(session)
  local r = roamer_state(session)
  if not (r and r.active) then return end
  local sets = Roamer.locationSets(cfg_of(session))
  while true do
    local mapId = sets[(Rng.Random() % #sets) + 1][1]
    if r.map ~= mapId then
      r.map = mapId
      return
    end
  end
end

-- pokefirered/src/overworld.c:345
function Roamer.onContinue(session, mapId)
  local r = roamer_state(session)
  if not (r and cfg_of(session)) then return end
  -- pokeemerald/src/roamer.c:18
  r.history, r.map = { false, false, false }, false
  Roamer.updateHistory(session, mapId)
  Roamer.moveToOtherSet(session)
end

-- pokeemerald/src/roamer.c:149
function Roamer.moveWithinSet(session)
  local cfg = cfg_of(session)
  if (Rng.Random() % cfg.moveOdds) == 0 then
    return Roamer.moveToOtherSet(session)
  end
  local r = roamer_state(session)
  if not (r and r.active) then return end
  for _, set in ipairs(Roamer.locationSets(cfg)) do
    if r.map == set[1] then
      while true do
        local mapId = set[(Rng.Random() % (#set - 1)) + 2]
        if r.history[3] ~= mapId and mapId then
          r.map = mapId
          return
        end
      end
    end
  end
end

-- pokeemerald/src/roamer.c:216
local function try_encounter(session, cfg, mapId)
  local r = session.roamer
  if not (r.active and r.map == mapId) then return nil end
  if (Rng.Random() % cfg.encounterOdds) ~= 0 then return nil end
  -- pokeemerald/src/roamer.c:194
  return Roamer.instance(session)
end

Roamer.SPECIES_RAIKOU = 243
Roamer.SPECIES_ENTEI = 244
Roamer.SPECIES_SUICUNE = 245

-- pokefirered/src/roamer.c:82
function Roamer.speciesForStarter(starter)
  starter = tonumber(starter) or 0
  if starter == 1 then
    return Roamer.SPECIES_RAIKOU
  elseif starter == 2 then
    return Roamer.SPECIES_SUICUNE
  else
    return Roamer.SPECIES_ENTEI
  end
end

-- pokefirered/src/roamer.c:99
function Roamer.init(session, starterChoice)
  local cfg = cfg_of(session)
  if not (session and cfg) then return false end
  session.roamer = create_initial(Roamer.speciesForStarter(starterChoice), cfg.level)
  session.roamer.history = { false, false, false }
  -- pokefirered/src/roamer.c:117
  local sets = Roamer.locationSets(cfg)
  session.roamer.map = sets[(Rng.Random() % #sets) + 1][1]
  return true
end

function Roamer.move(session, reason, mapId)
  if not cfg_of(session) then return end
  -- pokefirered/src/overworld.c:778
  Roamer.updateHistory(session, mapId)
  if reason == "map_transition" or reason == "connection" then return Roamer.moveWithinSet(session) end
  -- pokefirered/src/overworld.c:809
  return Roamer.moveToOtherSet(session)
end

-- pokefirered/src/roamer.c:228
function Roamer.tryEncounter(session, mapId)
  local cfg = cfg_of(session)
  if not (session and type(session.roamer) == "table" and cfg) then return nil end
  return try_encounter(session, cfg, mapId)
end

function Roamer.onBattleEnd(session, foeState, battleResult, _endReason, battler)
  if not (session and session.roamer and session.roamer.active) then return end
  local roamer = Roamer.normalize(session)
  -- pokefirered/src/battle_main.c:3929
  update_hp_status(session, foeState, battler)
  Roamer.moveToOtherSet(session)
  -- pokefirered/src/battle_main.c:3933
  local code = require("src.core.game3.scripting.natives").outcome_to_code(battleResult)
  if code % 2 == 1 then roamer.active = false end
end

return Roamer
