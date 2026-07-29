-- Yellow's overworld companion Pikachu (pokeyellow engine/pikachu/
-- pikachu_follow.asm ShouldPikachuSpawn / SpawnPikachu_, plus the
-- talk-to-it mood beat of engine/pikachu/pikachu_emotions.asm
-- TalkToPikachu).  The follower is an NPC-shaped entity that lives in
-- ow.npcs (so the standard update/draw walk cycle runs) but never in
-- ow.entities -- like the original it does not block the player: walk
-- onto its cell and it simply trails to the cell you vacated.
--
-- Happiness rides in save.pikachuHappiness (wPikachuHappiness, seeded 90
-- by init_player_data.asm) and mood in save.pikachuMood (wPikachuMood,
-- neutral 128).  modifyHappiness below is the full ModifyPikachuHappiness
-- port (engine/events/pikachu_happiness.asm): the HappinessChangeTable
-- delta picked by the current happiness hundred-band, then the
-- PikachuMoods byte nudging the mood; onStep is poison.asm's
-- UpdatePikachuHappinessAndMood (256-step coin-flip WALKING bump, mood
-- converging by 1 per step toward 128).

local GameVersion = require("src.core.GameVersion")

local PikachuFollower = {}

local INDEX = 99 -- synthetic object index, clear of any map's real objects

local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

-- wPikachuHappiness boot value (engine/movie/oak_speech/
-- init_player_data.asm: happiness = 90)
local function happiness(save)
  if save.pikachuHappiness == nil then save.pikachuHappiness = 90 end
  return save.pikachuHappiness
end

function PikachuFollower.bumpHappiness(save, delta)
  save.pikachuHappiness =
    math.max(0, math.min(255, happiness(save) + delta))
end

-- HappinessChangeTable (engine/events/pikachu_happiness.asm): delta by
-- happiness band (<100 / <200 / rest), plus the PikachuMoods target byte
-- ($80 leaves the mood alone).  Keys mirror the PIKAHAPPY_* constants.
local HAPPINESS_CHANGES = {
  LEVELUP         = {   5,   3,   2, mood = 0x8a },
  USEDITEM        = {   5,   3,   2, mood = 0x83 },
  USEDXITEM       = {   1,   1,   0, mood = 0x80 },
  GYMLEADER       = {   3,   2,   1, mood = 0x80 },
  USEDTMHM        = {   1,   1,   0, mood = 0x94 },
  WALKING         = {   2,   1,   1, mood = 0x80 },
  DEPOSITED       = {  -3,  -3,  -5, mood = 0x62 },
  FAINTED         = {  -1,  -1,  -1, mood = 0x6c },
  PSNFNT          = {  -5,  -5, -10, mood = 0x62 },
  CARELESSTRAINER = {  -5,  -5, -10, mood = 0x6c },
  TRADE           = { -10, -10, -20, mood = 0x00 },
}

-- the companion mon: a healthy (or any) party PIKACHU stands in for the
-- original's OT-checked starter, same approximation as shouldSpawn
function PikachuFollower.starterInParty(save, needHealthy)
  for _, mon in ipairs(save.party or {}) do
    if mon.species == "PIKACHU"
       and (not needHealthy or (mon.hp or 0) > 0) then
      return mon
    end
  end
  return nil
end

-- ModifyPikachuHappiness.  mon is the party mon the event applied to for
-- the per-mon reasons (IsThisPartyMonStarterPikachu); GYMLEADER and
-- WALKING instead require any healthy starter in the party
-- (IsStarterPikachuAliveInOurParty).
function PikachuFollower.modifyHappiness(save, reason, mon)
  if not GameVersion.isYellow() then return end
  local row = HAPPINESS_CHANGES[reason]
  if not row then return end
  if reason == "GYMLEADER" or reason == "WALKING" then
    if not PikachuFollower.starterInParty(save, true) then return end
  elseif not (mon and mon.species == "PIKACHU") then
    return
  end
  local h = happiness(save)
  local band = h < 100 and 1 or h < 200 and 2 or 3
  save.pikachuHappiness = math.max(0, math.min(255, h + row[band]))
  -- PikachuMoods: bytes above $80 only ever raise the mood (and defer to
  -- a pending scripted emotion modifier), bytes below only lower it
  local b = row.mood
  if b ~= 0x80 then
    local mood = save.pikachuMood or 128
    if b > 0x80 then
      if mood < b and not save.pikachuEmotionModifier then
        save.pikachuMood = b
      end
    elseif mood > b then
      save.pikachuMood = b
    end
  end
end

-- UpdatePikachuHappinessAndMood (engine/events/poison.asm): every 256th
-- step a coin flip on the WALKING bump; every step the mood converges by
-- 1 toward the neutral 128.
function PikachuFollower.onStep(save)
  if not GameVersion.isYellow() then return end
  save.pikachuWalkSteps = ((save.pikachuWalkSteps or 0) + 1) % 256
  local rand = love and love.math and love.math.random or math.random
  if save.pikachuWalkSteps == 0 and rand(0, 1) == 1 then
    PikachuFollower.modifyHappiness(save, "WALKING")
  end
  local mood = save.pikachuMood or 128
  if mood < 128 then
    save.pikachuMood = mood + 1
  elseif mood > 128 then
    save.pikachuMood = mood - 1
  end
end

-- ShouldPikachuSpawn, approximated: Yellow, the lab gift happened, and a
-- healthy Pikachu is in the party (the original checks the starter's OT
-- identity; a traded second Pikachu standing in is accepted here).
-- Surfing and biking hide the follower (BIT_PIKACHU_SPAWN flags).
local function shouldSpawn(game, ow)
  if not GameVersion.isYellow() then return false end
  local save = game.save
  if not (save.flags and save.flags.EVENT_GOT_STARTER) then return false end
  if save.onBike or (ow.player and ow.player.surfing) then return false end
  if not (game.data.sprites and game.data.sprites.SPRITE_PIKACHU) then
    return false
  end
  for _, mon in ipairs(save.party or {}) do
    if mon.species == "PIKACHU" and (mon.hp or 0) > 0 then return true end
  end
  return false
end

local function makeFollower(game, ow, x, y, facing)
  local NPC = require("src.world.NPC")
  local npc = NPC.new(game.data, ow.map.id, {
    index = INDEX, name = "PIKACHU_FOLLOWER", sprite = "SPRITE_PIKACHU",
    movement = "STAY", range = "NONE", x = x, y = y,
  })
  npc.pikachuFollower = true
  npc.passable = true -- never blocks a step (Collision.occupied)
  npc.facing = facing or "down"
  return npc
end

local function findFollower(ow)
  for i, npc in ipairs(ow.npcs or {}) do
    if npc.pikachuFollower then return npc, i end
  end
  return nil
end

local function remove(ow)
  local npc, i = findFollower(ow)
  if not npc then return end
  table.remove(ow.npcs, i)
  for j, e in ipairs(ow.entities or {}) do
    if e == npc then table.remove(ow.entities, j) break end
  end
end

-- spawn cell: directly behind the player's facing when that cell is
-- walkable, else the player's own cell (it trails out on the next step)
local function spawnCell(ow)
  local p = ow.player
  local dx = p.facing == "left" and 1 or p.facing == "right" and -1 or 0
  local dy = p.facing == "up" and 1 or p.facing == "down" and -1 or 0
  local bx, by = p.cellX + dx, p.cellY + dy
  if ow.map:inBounds(bx, by) and ow.map:isWalkableCell(bx, by) then
    return bx, by
  end
  return p.cellX, p.cellY
end

function PikachuFollower.onMapEntered(game, ow)
  remove(ow)
  if not shouldSpawn(game, ow) then return end
  local x, y = spawnCell(ow)
  local npc = makeFollower(game, ow, x, y, ow.player.facing)
  table.insert(ow.npcs, npc)
  -- entities is the draw list; passable keeps it out of collision
  table.insert(ow.entities, npc)
  ow.pikachuTrail = { x = ow.player.cellX, y = ow.player.cellY }
end

-- one follow step per frame: chase the cell the player last vacated
-- (pikachu_follow.asm keeps it one walk step behind)
function PikachuFollower.update(game, ow)
  local npc = findFollower(ow)
  if not npc then
    if shouldSpawn(game, ow) then PikachuFollower.onMapEntered(game, ow) end
    return
  end
  if not shouldSpawn(game, ow) then
    remove(ow)
    return
  end
  local p = ow.player
  local trail = ow.pikachuTrail
  if not trail then
    trail = { x = p.cellX, y = p.cellY }
    ow.pikachuTrail = trail
  end
  -- the player left the trailing cell: it becomes Pikachu's next goal
  if p.cellX ~= trail.x or p.cellY ~= trail.y then
    npc.goalX, npc.goalY = trail.x, trail.y
    trail.x, trail.y = p.cellX, p.cellY
  end
  if npc.moving or not npc.goalX then return end
  local gx, gy = npc.goalX, npc.goalY
  if npc.cellX == gx and npc.cellY == gy then
    npc.goalX, npc.goalY = nil, nil
    return
  end
  -- fell more than a screen behind (forced movement, warp math): snap
  local far = math.abs(npc.cellX - gx) + math.abs(npc.cellY - gy)
  if far > 6 then
    npc.cellX, npc.cellY = gx, gy
    npc.px, npc.py = gx * 16, gy * 16
    npc.goalX, npc.goalY = nil, nil
    return
  end
  local dir
  if npc.cellX < gx then dir = "right"
  elseif npc.cellX > gx then dir = "left"
  elseif npc.cellY < gy then dir = "down"
  else dir = "up" end
  npc.facing = dir
  npc.targetX = npc.cellX + (dir == "right" and 1 or dir == "left" and -1 or 0)
  npc.targetY = npc.cellY + (dir == "down" and 1 or dir == "up" and -1 or 0)
  npc.moving = true
  npc.progress = 0
end

-- ---------------------------------------------------------------------
-- TalkToPikachu (engine/pikachu/pikachu_emotions.asm + data/pikachu/
-- pikachu_emotions.asm): pick a scripted emotion, then play its bubble
-- and voiced PCM clip.  The face-pic animation half of each emotion
-- (pikaemotion_pikapic) has no port; the bubble + clip carry the beat.
-- ---------------------------------------------------------------------

-- PikachuEmotionTable, reduced to each entry's bubble + pikaemotion_pcm
-- clip (bubble names are the *_BUBBLE constants; nil cry = silent).
-- turnAway is pikaemotion_9 (face away from the player, emotion 30).
local EMOTIONS = {
  [1] = {},
  [2] = { bubble = "SMILE_BUBBLE", cry = 35 },
  [3] = { cry = 40 },
  [4] = { cry = 29 },
  [5] = { cry = 31 },
  [6] = { bubble = "SKULL_BUBBLE" },
  [7] = { cry = 1 },
  [8] = { cry = 39 },
  [9] = { bubble = "SKULL_BUBBLE", cry = 6 },
  [10] = { bubble = "HEART_BUBBLE", cry = 5 },
  [11] = { bubble = "ZZZ_BUBBLE", cry = 37 },
  [12] = {},
  [13] = {},
  [14] = { bubble = "BOLT_BUBBLE", cry = 10 },
  [15] = { cry = 34 },
  [16] = { cry = 33 },
  [17] = { cry = 13 },
  [18] = {},
  [19] = { bubble = "HEART_BUBBLE", cry = 33 },
  [20] = { bubble = "HEART_BUBBLE", cry = 5 },
  [21] = { bubble = "FISH_BUBBLE" },
  [22] = { cry = 4 },
  [23] = { cry = 19 },
  [24] = { bubble = "EXCLAMATION_BUBBLE" },
  [25] = { bubble = "BOLT_BUBBLE", cry = 35 },
  [26] = { bubble = "ZZZ_BUBBLE", cry = 37 },
  [27] = { cry = 9 },
  [28] = { cry = 15 },
  [29] = { cry = 5 },
  [30] = { bubble = "HEART_BUBBLE", cry = 5, turnAway = true },
  [31] = { cry = 19 },
  [32] = { cry = 26 },
}

-- GetPikaPicAnimationScriptIndex (engine/pikachu/pikachu_pic_animation
-- .asm): mood picks the column (PikachuMoodLookupTable), happiness the
-- row (PikaPicAnimationScriptPointerLookupTable); the cell is the
-- emotion index.
local MOOD_THRESHOLDS = { 40, 127, 128, 210, 255 }
local MOOD_MATRIX = {
  { limit = 50,  14, 14, 6,  13, 13 },
  { limit = 100, 9,  9,  5,  12, 12 },
  { limit = 130, 3,  3,  1,  8,  8 },
  { limit = 160, 3,  3,  4,  15, 15 },
  { limit = 200, 17, 17, 7,  2,  2 },
  { limit = 250, 17, 17, 16, 10, 10 },
  { limit = 255, 17, 17, 19, 20, 20 },
}

-- wPikachuEmotionModifier values 1-5 (MapSpecificPikachuExpression
-- .Emotions): scripted one-shots -- 21 is the fishing-rod reaction
local MODIFIER_EMOTIONS = { 18, 21, 23, 24, 25 }

local function moodEmotion(save)
  local mood = save.pikachuMood or 128
  local column = 5
  for i, threshold in ipairs(MOOD_THRESHOLDS) do
    if mood <= threshold then column = i break end
  end
  local h = happiness(save)
  local row = MOOD_MATRIX[#MOOD_MATRIX]
  for _, r in ipairs(MOOD_MATRIX) do
    if h <= r.limit then row = r break end
  end
  return row[column]
end

-- MapSpecificPikachuExpression + TalkToPikachu's selection order
local function selectEmotion(game, ow, save)
  local mapId = ow.map.id
  -- Fan Club / Pewter Center map beats (the Bill's-house event variant
  -- is owned by that map's script)
  if mapId == "POKEMON_FAN_CLUB" then return 30 end
  if mapId == "PEWTER_POKECENTER" then return 26 end
  local starter = PikachuFollower.starterInParty(save)
  if starter then
    if starter.status == "SLP" then return 11 end
    if starter.status then return 28 end
  end
  if mapId:find("POKEMON_TOWER_", 1, true) == 1 then return 22 end
  local modifier = save.pikachuEmotionModifier
  if modifier and MODIFIER_EMOTIONS[modifier] then
    save.pikachuEmotionModifier = nil
    return MODIFIER_EMOTIONS[modifier]
  end
  return moodEmotion(save)
end

local function bubbleIndex(game, name)
  local sheet = game.data.field and game.data.field.emotionBubbles
  for i, b in ipairs(sheet and sheet.bubbles or {}) do
    if b.name == name then return i end
  end
  return nil
end

function PikachuFollower.talk(game, ow, npc, done)
  npc:facePlayer(ow.player)
  ow.player.facing = OPPOSITE[npc.facing] or ow.player.facing
  local save = game.save
  local emotion = selectEmotion(game, ow, save)
  local e = EMOTIONS[emotion] or EMOTIONS[1]
  if e.turnAway then
    npc.facing = ow.player.facing -- pikaemotion_9: back to the player
  end
  local Sound = require("src.core.Sound")
  if e.cry then
    if not Sound.playPikaCry(game.data, e.cry) then
      Sound.playCry(game.data, "PIKACHU")
    end
  end
  -- caches built before the Yellow bubble sheet only carry the three
  -- shared bubbles; a missing crop degrades to a silent hold
  local bi = e.bubble and bubbleIndex(game, e.bubble)
  ow.emote = {
    npc = npc, frames = 50, bubble = bi or false,
    onDone = done,
  }
end

-- npc the player is facing, when it is the follower (interact hook)
function PikachuFollower.at(ow, cx, cy)
  local npc = findFollower(ow)
  if npc and not npc.moving and npc.cellX == cx and npc.cellY == cy then
    return npc
  end
  return nil
end

return PikachuFollower
