local Rng = require("src.core.game3.rng")

local AmbientCry = {}

AmbientCry.INIT, AmbientCry.FIRST, AmbientCry.RESET, AmbientCry.WAIT, AmbientCry.IDLE = 0, 1, 2, 3, 4

AmbientCry.species = 0
AmbientCry.isWaterMon = false
AmbientCry.state = AmbientCry.INIT
AmbientCry.delay = 0

local function profile() return require("src.core.game3.profile") end

local function encounter_helpers()
  local Encounters = require("src.core.game3.encounters")
  Encounters.ensureLoaded()
  return Encounters._h
end

local function slot_species(H, area, weights)
  local entry = H.pick_slot(area.slots, weights)
  return entry and (tonumber(entry.species or entry[1]) or 0) or 0
end

-- pokeemerald/src/wild_encounter.c:836
local function local_water_mon(mapId)
  local H = encounter_helpers()
  local water = H.area_for(mapId, "water")
  if not water then return 0 end
  return slot_species(H, water, H.WATER_WEIGHTS)
end

-- pokeemerald/src/wild_encounter.c:800
function AmbientCry.localWildMon(mapId)
  local H = encounter_helpers()
  local land = H.area_for(mapId, "land")
  local water = H.area_for(mapId, "water")
  if not land and not water then return 0, false end
  if land and not water then return slot_species(H, land, H.LAND_WEIGHTS), false end
  if water and not land then return slot_species(H, water, H.WATER_WEIGHTS), true end
  if Rng.Random() % 100 < 80 then return slot_species(H, land, H.LAND_WEIGHTS), false end
  return slot_species(H, water, H.WATER_WEIGHTS), true
end

local function mirage_island_present(session)
  return require("src.core.game3.scripting.natives_field_rse").isMirageIslandPresent(session) == true
end

-- pokeemerald/src/overworld.c:1317
function AmbientCry.choose(session, mapId)
  mapId = mapId or (session and session.map)
  if profile().family(session) == "rse" and tostring(mapId):match("_ROUTE130$")
      and not mirage_island_present(session) then
    AmbientCry.isWaterMon = true
    AmbientCry.species = local_water_mon(mapId)
  else
    AmbientCry.species, AmbientCry.isWaterMon = AmbientCry.localWildMon(mapId)
  end
  return AmbientCry.species
end

-- pokeemerald/src/field_tasks.c:214
function AmbientCry.resetTask()
  AmbientCry.state = AmbientCry.INIT
  AmbientCry.delay = 0
end

local function is_egg(mon) return mon.isEgg == true or mon.egg == true end

-- pokeemerald/src/overworld.c:1287
local function swarm_divisor(session)
  if profile().forSession(session).id ~= "emerald" then return 1 end
  local party = type(session) == "table" and session.party or {}
  local lead = party[1]
  if type(lead) ~= "table" then return 1 end
  local Constants = require("src.core.game3.constants")
  local swarm = Constants.active(session):require("abilities", "ABILITY_SWARM")
  local ability = tonumber(lead.abilityId or lead.ability)
    or tonumber(require("src.core.game3.pokemon").abilityId(lead.species or lead.speciesId, lead.personality))
  if ability ~= swarm then return 1 end
  for i = 1, 6 do
    local mon = party[i]
    if type(mon) ~= "table" or (tonumber(mon.species or mon.speciesId) or 0) == 0 then break end
    if not is_egg(mon) then return 2 end
  end
  return 1
end

local function dest_behavior()
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local x, y = Player.cellX, Player.cellY
  -- pokeemerald/src/field_player_avatar.c:1141
  if Player.moving then x, y = Player.targetX, Player.targetY end
  return Collision.behavior(x, y), Collision
end

-- pokeemerald/src/overworld.c:1245
function AmbientCry.play(session)
  if AmbientCry.isWaterMon then
    local beh, Collision = dest_behavior()
    if not Collision.isSurfable(beh) then return false end
  end
  local pan = (Rng.Random() % 88) + 212
  if pan >= 128 then pan = pan - 256 end
  local volume = (Rng.Random() % 30) + 50
  if profile().family(session) ~= "rse" then
    local Map = require("src.core.game3.map")
    -- pokefirered/src/overworld.c:1144
    if Map.disableMusicChange == Map.MUSIC_DISABLE_STOP then
      require("src.core.game3.audio").playSong(0)
      return false
    end
    if Map.disableMusicChange == Map.MUSIC_DISABLE_KEEP then return false end
  end
  require("src.core.game3.audio").playCry(AmbientCry.species,
    { mode = 0, pan = pan, volume = volume, noDuck = true })
  return true, pan, volume
end

-- pokeemerald/src/overworld.c:1269
function AmbientCry.update(session)
  local s = AmbientCry.state
  if s == AmbientCry.INIT then
    AmbientCry.state = (AmbientCry.species == 0) and AmbientCry.IDLE or AmbientCry.FIRST
  elseif s == AmbientCry.FIRST then
    AmbientCry.delay = (Rng.Random() % 2400) + 1200
    AmbientCry.state = AmbientCry.WAIT
  elseif s == AmbientCry.RESET then
    local divBy = swarm_divisor(session)
    AmbientCry.delay = math.floor(((Rng.Random() % 1200) + 1200) / divBy)
    AmbientCry.state = AmbientCry.WAIT
  elseif s == AmbientCry.WAIT then
    AmbientCry.delay = (AmbientCry.delay - 1) % 0x10000
    if AmbientCry.delay == 0 then
      AmbientCry.play(session)
      AmbientCry.state = AmbientCry.RESET
    end
  end
end

-- pokeemerald/src/field_tasks.c:168
function AmbientCry.tick(field, space, session)
  if field.locked or field.isLocked() then return false end
  if space and space.vm and space.vm:isRunning() then return false end
  AmbientCry.update(session)
  return true
end

return AmbientCry
