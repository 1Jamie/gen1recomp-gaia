-- Public runtime checkpoint implementation. Loader exposes bound forwarding
-- methods; mods never receive controller or state-stack internals from here.

local SaveSerializer = require("src.core.SaveSerializer")
local SaveData = require("src.core.SaveData")
local Version = require("src.core.Version")

local Checkpoint = {}

Checkpoint.FORMAT = 1

local function refusal(kind, reason, message)
  return {
    canCapture = false,
    canRestore = false,
    kind = kind or "unknown",
    reason = reason,
    message = message,
  }
end

local function running(runner)
  return runner and runner.isRunning and runner:isRunning()
end

local function nonempty(value)
  return type(value) == "table" and next(value) ~= nil
end

function Checkpoint.inspect(game)
  local save = game and game.save
  if type(save) ~= "table" or type(save.version) ~= "string" then
    return refusal("unknown", "not_in_playthrough",
      "A checkpoint requires an identified active playthrough.")
  end

  local ow = game.overworld
  if type(ow) ~= "table" or type(ow.map) ~= "table"
      or type(ow.map.id) ~= "string" or type(ow.player) ~= "table" then
    return refusal("unknown", "not_overworld",
      "Only a settled overworld can be checkpointed.")
  end
  local top = game.stack and game.stack.top and game.stack:top()
  if top ~= ow then
    return refusal("overworld", "screen_busy",
      "Close the active menu or screen before creating a checkpoint.")
  end
  local identity = save.meta and save.meta.playthroughId
  if type(identity) ~= "string" or identity == "" then
    identity = SaveData.ensurePlaythroughId(save)
  end
  if type(identity) ~= "string" or identity == "" then
    return refusal("overworld", "not_in_playthrough",
      "The active playthrough could not be identified.")
  end
  if ow.transitioning then
    return refusal("overworld", "transition_busy",
      "Wait for the map transition to finish.")
  end
  if running(ow.runner) or nonempty(ow.parallelRunners)
      or nonempty(ow.pendingScripts) or nonempty(ow.parallelQueue)
      or nonempty(ow.scriptMoves) then
    return refusal("overworld", "script_busy",
      "Wait for the active or queued script to finish.")
  end

  local animationFields = {
    "engaging", "emote", "teleportOut", "dustAnim", "cutAnim", "fishPose",
    "pikaHop", "healAnim", "flyAnim", "flyArrive",
  }
  for _, field in ipairs(animationFields) do
    if ow[field] then
      return refusal("overworld", "animation_busy",
        "Wait for the overworld animation to finish.")
    end
  end
  if ow.player.moving or ow.player.targetX ~= nil or ow.player.targetY ~= nil then
    return refusal("overworld", "movement_busy",
      "Wait for movement to settle on a tile.")
  end
  return { canCapture = true, canRestore = true, kind = "overworld" }
end

local function dataCopy(value)
  local ok, encoded = pcall(SaveSerializer.encode, value)
  if not ok then return nil, tostring(encoded) end
  local decoded, err = SaveSerializer.decode(encoded)
  if not decoded then return nil, err end
  return decoded
end

function Checkpoint.capture(game)
  local capability = Checkpoint.inspect(game)
  if not capability.canCapture then
    return nil, capability.reason, capability.message
  end

  local progress = {}
  for key, value in pairs(game.save) do
    if key ~= "options" then progress[key] = value end
  end
  progress = dataCopy(progress)
  if not progress then
    return nil, "capture_failed", "Progress contains non-serializable runtime data."
  end

  local ok, err = pcall(game.overworld.captureSave, game.overworld, progress)
  if not ok then
    return nil, "capture_failed", "Could not synchronize overworld progress: "
      .. tostring(err)
  end
  progress, err = dataCopy(progress)
  if not progress then
    return nil, "capture_failed", "Synchronized progress is not data-only: "
      .. tostring(err)
  end

  local player = game.overworld.player
  return {
    format = Checkpoint.FORMAT,
    kind = "overworld",
    identity = {
      engineVersion = Version.engine,
      gameVersion = game.save.version,
      playthroughId = game.save.meta.playthroughId,
    },
    save = progress,
    runtime = { overworld = {
      map = game.overworld.map.id,
      x = player.cellX,
      y = player.cellY,
      facing = player.facing,
      surfing = player.surfing and true or false,
    } },
  }
end

local FACINGS = { up = true, down = true, left = true, right = true }

local function validate(game, checkpoint)
  if type(checkpoint) ~= "table" then
    return nil, "invalid_checkpoint", "Checkpoint root must be a table."
  end
  if checkpoint.format ~= Checkpoint.FORMAT then
    return nil, "unsupported_format", "This checkpoint format is not supported."
  end
  if checkpoint.kind ~= "overworld" then
    return nil, "unsupported_runtime_kind", "Only overworld checkpoints are supported."
  end

  local copy, copyErr = dataCopy(checkpoint)
  if not copy then
    return nil, "invalid_checkpoint", "Checkpoint is not data-only: "
      .. tostring(copyErr)
  end
  local identity = copy.identity
  local current = game and game.save
  local currentId = current and current.meta and current.meta.playthroughId
  if type(identity) ~= "table" or type(identity.engineVersion) ~= "string"
      or type(identity.gameVersion) ~= "string"
      or type(identity.playthroughId) ~= "string" then
    return nil, "invalid_checkpoint", "Checkpoint identity is missing or corrupt."
  end
  if identity.gameVersion ~= current.version then
    return nil, "wrong_game", "Checkpoint belongs to another game version."
  end
  if identity.playthroughId ~= currentId then
    return nil, "wrong_playthrough", "Checkpoint belongs to another playthrough."
  end

  local save = copy.save
  local runtime = copy.runtime and copy.runtime.overworld
  if type(save) ~= "table" or type(save.player) ~= "table"
      or type(runtime) ~= "table" then
    return nil, "invalid_checkpoint", "Checkpoint progress or runtime data is missing."
  end
  if save.version ~= identity.gameVersion
      or not save.meta or save.meta.playthroughId ~= identity.playthroughId then
    return nil, "invalid_checkpoint", "Checkpoint progress identity is inconsistent."
  end
  if type(runtime.map) ~= "string" or type(runtime.x) ~= "number"
      or type(runtime.y) ~= "number" or runtime.x % 1 ~= 0 or runtime.y % 1 ~= 0
      or not FACINGS[runtime.facing] or type(runtime.surfing) ~= "boolean" then
    return nil, "invalid_checkpoint", "Overworld position is missing or corrupt."
  end
  if save.player.map ~= runtime.map or save.player.x ~= runtime.x
      or save.player.y ~= runtime.y or save.player.facing ~= runtime.facing
      or (save.player.surfing and true or false) ~= runtime.surfing then
    return nil, "invalid_checkpoint", "Progress and runtime position disagree."
  end

  local map = game.data and game.data.maps and game.data.maps[runtime.map]
  if type(map) ~= "table" then
    return nil, "invalid_map", "Checkpoint references a map that is unavailable."
  end
  local width, height = tonumber(map.width), tonumber(map.height)
  if not width or not height or runtime.x < 0 or runtime.y < 0
      or runtime.x >= width * 2 or runtime.y >= height * 2 then
    return nil, "invalid_position", "Checkpoint position is outside the map."
  end

  -- A checkpoint is a strict restoration record, not an ordinary CONTINUE
  -- migration. Reuse the canonical save validator on the detached copy, but
  -- reject any quarantine, remap, reclaim, clamp, or content repair it would
  -- perform instead of silently changing the state the caller selected.
  local beforeContent = SaveSerializer.encode(copy.save)
  local validOk, report = pcall(SaveData.validate, copy.save, game.data)
  local afterOk, afterContent = pcall(SaveSerializer.encode, copy.save)
  if not validOk or not afterOk or not SaveData.emptyReport(report)
      or afterContent ~= beforeContent then
    return nil, "invalid_content",
      "Checkpoint references unavailable or invalid game content."
  end
  return copy
end

local function apply(game, checkpoint, options)
  local save, err = dataCopy(checkpoint.save)
  if not save then error("checkpoint progress decode failed: " .. tostring(err), 0) end
  local runtime = checkpoint.runtime.overworld
  save.options = options
  save.player.map = runtime.map
  save.player.x = runtime.x
  save.player.y = runtime.y
  save.player.facing = runtime.facing
  save.player.surfing = runtime.surfing
  if type(game.restoreCheckpointSave) ~= "function" then
    error("game has no checkpoint reconstruction path", 0)
  end
  game:restoreCheckpointSave(save)
end

local function equalData(a, b)
  local okA, encodedA = pcall(SaveSerializer.encode, a)
  local okB, encodedB = pcall(SaveSerializer.encode, b)
  return okA and okB and encodedA == encodedB
end

function Checkpoint.restore(game, checkpoint)
  local capability = Checkpoint.inspect(game)
  if not capability.canRestore then
    return false, capability.reason, capability.message
  end
  local validated, code, message = validate(game, checkpoint)
  if not validated then return false, code, message end

  local rollback, captureCode, captureMessage = Checkpoint.capture(game)
  if not rollback then return false, captureCode, captureMessage end
  local options = game.save.options

  local ok, err = pcall(apply, game, validated, options)
  if ok then
    local restored, verifyCode = Checkpoint.capture(game)
    if restored and equalData(restored, validated) then return true end
    err = "restored state did not match checkpoint: " .. tostring(verifyCode)
  end

  local rolledBack, rollbackErr = pcall(apply, game, rollback, options)
  if not rolledBack then
    return false, "rollback_failed",
      "Checkpoint restore and rollback both failed: " .. tostring(rollbackErr)
  end
  return false, "restore_failed", "Checkpoint restoration failed: " .. tostring(err)
end

return Checkpoint
