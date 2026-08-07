-- Semantic, data-only capture for settled single-player battle checkpoints.
-- Reconstruction lives here too; public mods only see the opaque checkpoint
-- facade in Loader.

local BattleCheckpoint = {}

local BATTLER_FIELDS = {
  "shownHP", "shownStatus", "stages", "curStats", "curTypes", "curMoves",
  "sleepTurns", "confusedTurns", "disabledSlot", "disabledTurns",
  "toxicCounter", "substituteHP", "bideDamage", "bideTurns", "boundTurns",
  "charging", "chargeReady", "invulnerable", "mustRecharge", "thrashMove",
  "thrashTurns", "thrashAnnounced", "rageMove", "focusEnergy", "leechSeeded",
  "lightScreen", "reflect", "mist", "xAccuracy", "lastMove", "flinched",
  "skipMove", "hazeStatReset", "drainFloor", "drainHold", "trappingTurns",
  "trapMove", "trapDamage", "fainted",
}

local BATTLE_FIELDS = {
  "oppClass", "partyIndex", "enemyIndex", "turnCount", "menuIndex",
  "moveIndex", "moveSwapIndex", "aiUses", "runAttempts", "payDay",
  "sideToxic", "isGymLeader", "musicKind", "lastBall", "lockedBall",
  "lowHealthAlarmDisabled", "lowHealthAlarmOn", "victoryMusicPlayed",
  "endBattleText",
}

local function partyIndex(party, mon)
  for index, candidate in ipairs(party or {}) do
    if candidate == mon then return index end
  end
end

local function indexSet(set, party)
  local out = {}
  for mon, present in pairs(set or {}) do
    if present then
      local index = partyIndex(party, mon)
      if index then out[#out + 1] = index end
    end
  end
  table.sort(out)
  return out
end

local function captureBattler(battler, index, copy)
  local out = { index = index }
  for _, field in ipairs(BATTLER_FIELDS) do
    if battler[field] ~= nil then out[field] = battler[field] end
  end
  return copy(out)
end

local function captureExtensions(battle, copy)
  local sides = {}
  for i = 1, 2 do
    local side = battle.sides and battle.sides[i] or {}
    local encoded, err = copy({
      index = i,
      screens = side.screens or {},
      hazards = side.hazards or {},
      tokens = side.tokens or {},
    })
    if not encoded then return nil, err end
    sides[i] = encoded
  end
  local field, err = copy({
    weather = battle.field and battle.field.weather or nil,
    tokens = battle.field and battle.field.tokens or {},
  })
  if not field then return nil, err end
  return sides, field
end

function BattleCheckpoint.capture(game, battle, progress, copy)
  local getState = love and love.math and love.math.getRandomState
  local setState = love and love.math and love.math.setRandomState
  if type(getState) ~= "function" or type(setState) ~= "function" then
    return nil, "rng_state_unavailable",
      "This runtime cannot preserve deterministic battle randomness."
  end
  local ok, rngState = pcall(getState)
  if not ok or type(rngState) ~= "string" or rngState == "" then
    return nil, "rng_state_unavailable",
      "The gameplay random-number state could not be captured."
  end

  local origin, originErr = copy(battle.checkpointOrigin)
  if not origin then
    return nil, "battle_origin_unsupported",
      "The battle completion path is not data-only: " .. tostring(originErr)
  end
  local sides, fieldOrErr = captureExtensions(battle, copy)
  if not sides then
    return nil, "battle_extension_unsafe",
      "Battle extension state is not data-only: " .. tostring(fieldOrErr)
  end
  local field = fieldOrErr

  local liveParty = game.save.party
  local playerIndex = partyIndex(liveParty, battle.player.mon)
  if not playerIndex then
    return nil, "battle_state_invalid",
      "The active player battler is not in the current party."
  end

  local model = {
    kind = battle.kind,
    origin = origin,
    player = captureBattler(battle.player, playerIndex, copy),
    participants = indexSet(battle.participants, liveParty),
    leveledUp = indexSet(battle.leveledUp, liveParty),
    sides = sides,
    field = field,
  }
  if battle.kind == "trainer" then
    model.enemyParty = copy(battle.enemyParty)
    model.enemy = captureBattler(battle.enemy, battle.enemyIndex, copy)
  else
    model.enemyMon = copy(battle.enemy.mon)
    model.enemy = captureBattler(battle.enemy, 1, copy)
  end
  for _, fieldName in ipairs(BATTLE_FIELDS) do
    if battle[fieldName] ~= nil then model[fieldName] = battle[fieldName] end
  end

  model = copy(model)
  if not model then
    return nil, "battle_state_invalid",
      "Battle state contains non-serializable runtime data."
  end
  local player = progress.player
  return {
    overworld = {
      map = player.map, x = player.x, y = player.y,
      facing = player.facing, surfing = player.surfing and true or false,
    },
    battle = model,
  }, { love = rngState }
end

return BattleCheckpoint
