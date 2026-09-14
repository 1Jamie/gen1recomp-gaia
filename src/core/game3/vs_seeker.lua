-- VS Seeker Overworld Radar & Battery Engine (pret vs_seeker.c).
-- Features:
-- 1. Battery charge management: 100 steps on any locomotion mode (Walk, Run, Bike, Surf).
-- 2. Hard indoor/cave validation rejection: Preserves 100 charge.
-- 3. Outdoor radar ping: Emits signal, drains battery to 0 (even on "no response").
-- 4. Trainer detection (8-tile radius) with animated '!!' alert emoticons and rematch party progression.

local VsSeeker = {}

local function se(id)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    if Audio and Audio.playSe then Audio.playSe(id) end
  end)
end

function VsSeeker.getBattery(session)
  if not session then return 0 end
  return tonumber(session.vsSeekerCharge or (session.vars and session.vars[0x4044])) or 0
end

function VsSeeker.setBattery(session, charge)
  if not session then return end
  charge = math.min(100, math.max(0, math.floor(tonumber(charge) or 0)))
  session.vsSeekerCharge = charge
  if session.vars then session.vars[0x4044] = charge end
end

local function is_valid_map(mapId)
  mapId = tostring(mapId or ""):upper()
  -- Caves, gyms, buildings, and indoor rooms reject VS Seeker
  if mapId:find("_HOUSE") or mapId:find("_POKECENTER") or mapId:find("_MART")
      or mapId:find("_GYM") or mapId:find("_CAVE") or mapId:find("_TUNNEL")
      or mapId:find("MT_MOON") or mapId:find("VIRIDIAN_FOREST")
      or mapId:find("ROCK_TUNNEL") or mapId:find("SEAFOAM")
      or mapId:find("VICTORY_ROAD") or mapId:find("POKEMON_MANSION")
      or mapId:find("POKEMON_TOWER") or mapId:find("POWER_PLANT")
      or mapId:find("SAFARI_ZONE") or mapId:find("_1F") or mapId:find("_2F") or mapId:find("_3F")
      or mapId:find("_B1F") or mapId:find("_B2F") then
    return false
  end
  return true
end

--- Use the VS Seeker in the overworld.
function VsSeeker.use(session, game, onDone)
  local Hud = require("src.ui.game3.hud")
  local currentMap = (session and session.map) or ""

  -- 1. Location check
  if not is_valid_map(currentMap) then
    Hud.showDialogue("This can't be used here.", { onDone = onDone })
    return false
  end

  -- 2. Battery check
  local battery = VsSeeker.getBattery(session)
  if battery < 100 then
    local needed = 100 - battery
    local msg = string.format("The battery has run down!\nNo. of steps to charge: %d", needed)
    Hud.showDialogue(msg, { onDone = onDone })
    return false
  end

  -- 3. Battery drain on valid search signal
  VsSeeker.setBattery(session, 0)
  se(43) -- SE_PIN

  -- 4. Scan nearby NPC trainers in 8-tile radius
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  local px, py = Player.cellX, Player.cellY
  local rematchTrainers = {}

  for _, obj in ipairs(Objects.all and Objects.all() or {}) do
    local def = obj.def or {}
    local isTrainer = def.trainerType ~= nil and def.trainerType > 0
    if isTrainer then
      local dx = math.abs((obj.x or 0) - px)
      local dy = math.abs((obj.y or 0) - py)
      if dx <= 8 and dy <= 8 then
        rematchTrainers[#rematchTrainers + 1] = obj
      end
    end
  end

  if #rematchTrainers > 0 then
    -- Trigger rematch alert emoticons
    pcall(function()
      local Audio = require("src.core.game3.audio")
      if Audio and Audio.playSong then Audio.playSong(299, { loop = false }) end -- MUS_VS_SEEKER_SEARCH
    end)

    local FieldEffects = require("src.core.game3.field_effects")
    for _, tr in ipairs(rematchTrainers) do
      if FieldEffects and FieldEffects.spawnEmoticon then
        FieldEffects.spawnEmoticon(tr, 1) -- Double Exclamation / Alert
      end
      tr._rematchReady = true
    end

    if onDone then onDone(true, #rematchTrainers) end
    return true
  else
    Hud.showDialogue("There is no response...", { onDone = onDone })
    return false
  end
end

return VsSeeker
