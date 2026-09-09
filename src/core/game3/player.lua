-- Game3 independent player avatar (walk / run with B / facing / ledge hop).
-- Owns cell + pixel motion; does not call World:step or Player:tryMove.
-- Collision via game3.collision (owned COLL_* grid from extract bake).

local Collision = require("src.core.game3.collision")

local Player = {}

local CELL = 16
local WALK_FRAMES = 16
local RUN_FRAMES = 8
local BIKE_FRAMES = 4
local TURN_FRAMES = 4
-- pret Jump2 / DoJumpSpriteMovement: JUMP_DISTANCE_FAR = 32 frames.
local JUMP_FRAMES = 32
-- pret sJumpY_High (event_object_movement.c). Jump2 indexes with sTimer >> 1.
local JUMP_Y_HIGH = {
  -4, -6, -8, -10, -11, -12, -12, -12,
  -11, -10, -9, -8, -6, -4, 0, 0,
}

local DELTA = {
  up = { 0, -1 },
  down = { 0, 1 },
  left = { -1, 0 },
  right = { 1, 0 },
}

Player.cellX = 0
Player.cellY = 0
Player.px = 0
Player.py = 0
Player.facing = "down"
Player.moving = false
Player.progress = 0
Player.stepFrames = WALK_FRAMES
Player.targetX = 0
Player.targetY = 0
Player.turnTimer = 0
Player.turnArmed = true
Player.stepFlip = false
Player.animClock = 0
Player.running = false
Player.jumping = false
Player.spriteXOffset = 0
Player.spriteYOffset = 0
Player.biking = false
Player.visible = true
Player._logged = false

function Player.setVisible(vis)
  Player.visible = (vis ~= false)
  local Runtime = package.loaded["src.core.game3.runtime"]
  local g = Runtime and (Runtime._game or (Runtime.getGame and Runtime.getGame()))
  local world = g and (g.overworld or g.world)
  if world and world.player then
    world.player.visible = Player.visible
    world.player.hidden = not Player.visible
  end
end

function Player.isVisible()
  return Player.visible ~= false
end

local function log(msg)

  print("[game3/player] " .. tostring(msg))
end

local function dirs_from_input(input)
  if not input then return nil end
  -- Prefer last-pressed feel: check wasPressed first, else held.
  local order = { "down", "up", "left", "right" }
  for _, d in ipairs(order) do
    if input.wasPressed and input:wasPressed(d) then return d end
  end
  for _, d in ipairs(order) do
    if input.isDown and input:isDown(d) then return d end
  end
  return nil
end

function Player.reset(x, y, facing)
  Player.cellX = tonumber(x) or 0
  Player.cellY = tonumber(y) or 0
  Player.px = Player.cellX * CELL
  Player.py = Player.cellY * CELL
  Player.facing = facing or "down"
  Player.moving = false
  Player.progress = 0
  Player.stepFrames = WALK_FRAMES
  Player.targetX = Player.cellX
  Player.targetY = Player.cellY
  Player.turnTimer = 0
  Player.turnArmed = true
  Player.stepFlip = false
  Player.animClock = 0
  Player.running = false
  Player.jumping = false
  Player.spriteXOffset = 0
  Player.spriteYOffset = 0
  Player.biking = false
  if not Player._logged then
    log(string.format("avatar ready @ %d,%d %s",
      Player.cellX, Player.cellY, Player.facing))
    Player._logged = true
  end
end

function Player.syncFromSession(session)
  if not session then return end
  Player.reset(session.x, session.y, session.facing)
end

function Player.syncFromHost(game)
  local world = game and (game.overworld or game.world)
  local p = world and world.player
  if not p then return end
  Player.reset(p.cellX or p.x, p.cellY or p.y, p.facing or "down")
end

--- Write avatar coords into save.position (ferry / host save). No host entity mirror.
function Player.syncSavePosition(game)
  local save = game and game.save
  if not (save and save.position) then return end
  save.position.x = Player.cellX
  save.position.y = Player.cellY
  save.position.facing = Player.facing
  local session = package.loaded["src.core.game3.runtime"]
  session = session and session.getSession and session.getSession()
  if session and session.map then
    save.position.map = session.map
  end
end

--- Optional: mirror onto host player for heal-machine anim / leftover host reads.
-- Prefer syncSavePosition; full mirror is not required for talk/field.
function Player.syncToHost(game)
  Player.syncSavePosition(game)
  local world = game and (game.overworld or game.world)
  local p = world and world.player
  if not p then return end
  p.cellX = Player.cellX
  p.cellY = Player.cellY
  p.px = Player.px
  p.py = Player.py
  p.facing = Player.facing
  p.moving = Player.moving
  p.stepFlip = Player.stepFlip
  p.animClock = Player.animClock
  p.turnTimer = Player.turnTimer
  if p.stepFrames ~= nil then p.stepFrames = Player.stepFrames end
  if p.progress ~= nil then p.progress = Player.progress end
  if p.targetX ~= nil then p.targetX = Player.targetX end
  if p.targetY ~= nil then p.targetY = Player.targetY end
  p.jumping = Player.jumping
  p.spriteYOffset = Player.spriteYOffset or 0
end

function Player.walkPhase()
  if Player.turnTimer > 0 then return 1 end
  if not Player.moving then return 0 end
  local frames = Player.stepFrames or WALK_FRAMES
  local p = Player.animClock % frames
  local mid = math.floor(frames / 2)
  return (p >= math.floor(frames / 4) and p < mid + math.floor(frames / 4)) and 1 or 0
end

function Player.drawFlip()
  return Player.stepFlip and true or false
end

--- pret DoJumpSpriteMovement y2 for JUMP_DISTANCE_FAR + JUMP_TYPE_HIGH.
function Player.jumpSpriteY()
  if not Player.jumping then return 0 end
  local progress = Player.progress or 0
  if progress < 1 then return 0 end
  -- After frame N's Step1, sTimer == N; y2 = sJumpY_High[sTimer >> 1].
  local idx = math.floor((progress - 1) / 2)
  if idx < 0 then return 0 end
  if idx >= #JUMP_Y_HIGH then return 0 end
  return JUMP_Y_HIGH[idx + 1]
end

local function beginStep(tx, ty, run, ledge)
  Player.moving = true
  Player.progress = 0
  Player.targetX = tx
  Player.targetY = ty
  Player.running = (not ledge) and run and true or false
  Player.jumping = ledge and true or false
  Player.spriteYOffset = 0
  if ledge then
    Player.stepFrames = JUMP_FRAMES
  elseif Player.biking then
    Player.stepFrames = BIKE_FRAMES
    Player.running = true
  else
    Player.stepFrames = run and RUN_FRAMES or WALK_FRAMES
  end
  Player.animClock = 0

  -- pret GroundEffect_StepOnTallGrass when entering a grass cell.
  local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
  if okFx and FieldEffects then
    if Collision.isGrass and Collision.isGrass(tx, ty) then
      FieldEffects.tallGrassAt(tx, ty, false)
    else
      FieldEffects.leaveTallGrass()
    end
  end
end

function Player.tryMove(dir, game, run)
  if Player.moving then return nil end
  if not DELTA[dir] then return nil end

  if Player.facing ~= dir then
    Player.facing = dir
    if Player.turnArmed then
      Player.turnArmed = false
      Player.turnTimer = TURN_FRAMES
      return "turned"
    end
  end
  if Player.turnTimer > 0 then return nil end

  local d = DELTA[dir]
  local tx = Player.cellX + d[1]
  local ty = Player.cellY + d[2]

  -- pret CheckForPlayerAvatarCollision → ShouldJumpLedge(dest): hop over the
  -- impassable ledge tile when facing matches; otherwise canEnter bumps.
  local lx, ly = Collision.ledgeLanding(game, Player.cellX, Player.cellY, dir)
  if lx then
    beginStep(lx, ly, false, true)
    pcall(function()
      local Audio = require("src.core.game3.audio")
      local SE = require("src.core.game3.se_ids")
      if Audio.playSe and SE.SE_LEDGE then Audio.playSe(SE.SE_LEDGE) end
    end)
    return "ledge"
  end

  if dir == "up" then
    local doorWarp = Collision.isDoorWarp and Collision.isDoorWarp(game, tx, ty)
    if doorWarp then
      local Warp = require("src.core.game3.warp")
      if not Warp.isBusy() then
        local Runtime = package.loaded["src.core.game3.runtime"]
        local mod = Runtime and Runtime._mod
        local g = game or (Runtime and Runtime._game)
        Warp.startDoorEntrance(mod, g, doorWarp.destMap, doorWarp.destX, doorWarp.destY, tx, ty)
        return "door"
      end
      return "door_busy"
    end
  end

  if dir == "down" then
    local exitWarp = Collision.isExitWarp and Collision.isExitWarp(game, Player.cellX, Player.cellY)
    if exitWarp then
      local Warp = require("src.core.game3.warp")
      if not Warp.isBusy() then
        local Runtime = package.loaded["src.core.game3.runtime"]
        local mod = Runtime and Runtime._mod
        local g = game or (Runtime and Runtime._game)
        Warp.startDoorExit(mod, g, exitWarp.destMap, exitWarp.destX, exitWarp.destY, Player.cellX, Player.cellY)
        return "exit_door"
      end
      return "door_busy"
    end
  end

  local escWarp = Collision.isEscalatorWarp and Collision.isEscalatorWarp(game, tx, ty, dir)
  if escWarp then
    local Warp = require("src.core.game3.warp")
    if not Warp.isBusy() then
      local Runtime = package.loaded["src.core.game3.runtime"]
      local mod = Runtime and Runtime._mod
      local g = game or (Runtime and Runtime._game)
      Warp.startEscalator(mod, g, escWarp.destMap, escWarp.destX, escWarp.destY, escWarp.escDir, dir, tx, ty)
      return "escalator"
    end
    return "escalator_busy"
  end

  local ok, why = Collision.canEnter(game, tx, ty, {
    fromX = Player.cellX,
    fromY = Player.cellY,
    dir = dir,
  })

  if not ok then
    -- Outdoor map connection (Pallet north → Route 1, etc.).
    if why == "bounds" and Collision.tryConnection
        and Collision.tryConnection(game, Player.cellX, Player.cellY, dir, run) then
      return "connection"
    end
    return "blocked", why
  end
  beginStep(tx, ty, run, false)
  return "step"
end

--- Forced step along dir with onDone callback (e.g. exiting door).
function Player.forceStep(dir, onDone)
  if Player.moving then return false end
  local d = DELTA[dir or Player.facing]
  if not d then return false end
  Player.facing = dir or Player.facing
  Player._onStepDone = onDone
  beginStep(Player.cellX + d[1], Player.cellY + d[2], false, false)
  return true
end

--- Forced script step (applymovement localId 0xFF) — skips collision.
function Player.scriptStep(dir)
  if Player.moving then return false end
  local d = DELTA[dir or Player.facing]
  if not d then return false end
  Player.facing = dir or Player.facing
  beginStep(Player.cellX + d[1], Player.cellY + d[2], false, false)
  return true
end

function Player.scriptFace(dir)
  if DELTA[dir] then Player.facing = dir end
end

local function finishStep(game)
  Player.cellX = Player.targetX
  Player.cellY = Player.targetY
  Player.px = Player.cellX * CELL
  Player.py = Player.cellY * CELL
  Player.moving = false
  Player.progress = 0
  Player.stepFlip = not Player.stepFlip
  Player.running = false
  Player.jumping = false
  Player.spriteYOffset = 0
  Player.syncSavePosition(game)

  local session = package.loaded["src.core.game3.runtime"]
  session = session and session.getSession and session.getSession()
  if session then
    session.x, session.y, session.facing = Player.cellX, Player.cellY, Player.facing
  end

  local onDoneCb = Player._onStepDone
  Player._onStepDone = nil
  if onDoneCb then
    onDoneCb()
    return
  end

  -- Land-on-warp via owned warp table (mapDef.warps).
  Collision.tryWarpAt(game, Player.cellX, Player.cellY, Player.facing)

  -- Coord events (Oak leave-block, triggers) after landing on the cell.
  local Field = package.loaded["src.core.game3.field"]
    or require("src.core.game3.field")
  if Field.tryCoordEvents then
    Field.tryCoordEvents(game, Player.cellX, Player.cellY)
  end

  -- Wild encounters on grass when step completes (pret StandardWildEncounter).
  local onGrass = Collision.isGrass and Collision.isGrass(Player.cellX, Player.cellY)
  local okE, Encounters = pcall(require, "src.core.game3.encounters")
  if onGrass and okE and Encounters and Encounters.onStep then
    local Battle = package.loaded["src.core.game3.battle"]
    local busy = (Battle and Battle.isActive and Battle.isActive()) or Field.locked
    local Space = package.loaded["src.core.game3.scripting.space"]
    if Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning() then
      busy = true
    end
    if not busy then
      local mapId = session and session.map
      if not mapId then
        local Map = package.loaded["src.core.game3.map"]
        mapId = Map and Map.current
      end
      local enterFromOther = not (Encounters._prevGrass)
      local enc = Encounters.onStep(mapId, "land", { enterFromOther = enterFromOther })
      if enc then
        local Runtime = package.loaded["src.core.game3.runtime"]
        local BattleBridge = require("src.core.game3.battle_bridge")
        local mod = Runtime and Runtime._mod
        local g = game or (Runtime and Runtime._game)
        local okB, errB = BattleBridge.startWild(mod, g, enc, {})
        if not okB then
          print("[game3/encounters] startWild failed: " .. tostring(errB))
        end
      end
    end
  end
  if okE and Encounters and Encounters.noteGrass then
    Encounters.noteGrass(onGrass)
  end
  if onGrass then
    local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
    if okFx and FieldEffects and FieldEffects.tallGrassAt then
      FieldEffects.tallGrassAt(Player.cellX, Player.cellY, true)
    end
  end
end

function Player.tick(game)
  if Player.turnTimer > 0 then
    Player.turnTimer = Player.turnTimer - 1
  end
  if not Player.moving then
    return false
  end
  Player.progress = Player.progress + 1
  Player.animClock = Player.animClock + 1
  local frames = Player.stepFrames or WALK_FRAMES
  local dx = Player.targetX - Player.cellX
  local dy = Player.targetY - Player.cellY
  -- pret Step1: 1px/frame along the move. Ledge Jump2 is 32px over 32 frames.
  local span = math.max(math.abs(dx), math.abs(dy), 1)
  local adv = math.floor(Player.progress * CELL * span / frames)
  Player.px = Player.cellX * CELL + (dx / span) * adv
  Player.py = Player.cellY * CELL + (dy / span) * adv
  if Player.jumping then
    Player.spriteYOffset = Player.jumpSpriteY()
  else
    Player.spriteYOffset = 0
  end
  if Player.progress >= frames then
    finishStep(game)
    return true
  end
  return false
end

--- pret field_player_avatar: B-dash only with FLAG_SYS_B_DASH (Running Shoes).
function Player.canDash()
  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = Space and Space.getStore and Space.getStore()
  if not store then
    -- Field not scripted yet — deny dash (shoes not granted).
    return false
  end
  local Flags = require("src.core.game3.scripting.flags")
  return Flags.getFlag(store, nil, Flags.IDS.SYS_B_DASH) == true
end

--- Poll D-pad + B-run when field is free.
function Player.update(game, input)
  Player.tick(game)
  if Player.moving then return end

  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.locked then return end
  local Warp = package.loaded["src.core.game3.warp"]
  if Warp and Warp.isBusy and Warp.isBusy() then return end
  local Runtime = package.loaded["src.core.game3.runtime"]
  if Runtime and Runtime.uiBusy and Runtime.uiBusy() then return end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning() then
    return
  end

  local dir = dirs_from_input(input)
  if not dir then
    Player.turnArmed = true
    return
  end
  local wantRun = input and input.isDown and input:isDown("b")
  local run = Player.biking or (wantRun and Player.canDash())
  Player.tryMove(dir, game, run)
end

return Player
