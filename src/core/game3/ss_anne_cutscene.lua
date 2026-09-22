-- S.S. Anne departure cutscene matching pret pokefirered (src/ss_anne.c).
-- Manages the ship's horn sound effects, wake trailing animation, smoke puffs,
-- leftward sailing motion, and script coordination.

local SSAnneCutscene = {}

-- Audio constants (pokefirered/include/constants/songs.h:249)
local SE_SS_ANNE_HORN = 249

-- Timing constants matching pokefirered/src/ss_anne.c
local INIT_FRAMES = 50       -- Task_SSAnneInit countdown
local SMOKE_INTERVAL = 70    -- Task_SSAnneRun smoke puff period
local SLIDE_SPEED_DIV = 5    -- 1 pixel movement every 5 frames (x = data[2] / 5)
local TRAVEL_DISTANCE = 216  -- pixels to travel until boat is fully off-screen
local FINISH_FRAMES = 40     -- Task_SSAnneFinish delay after exit horn

SSAnneCutscene._active = false
SSAnneCutscene._phase = "idle" -- "init" | "run" | "finish" | "done"
SSAnneCutscene._initTimer = 0
SSAnneCutscene._runTimer1 = 0  -- smoke timer
SSAnneCutscene._runTimer2 = 0  -- motion timer
SSAnneCutscene._finishTimer = 0
SSAnneCutscene._boatOffset = 0
SSAnneCutscene._wake = nil
SSAnneCutscene._smokes = {}
SSAnneCutscene._wakeImage = nil
SSAnneCutscene._wakeQuads = nil
SSAnneCutscene._smokeImage = nil
SSAnneCutscene._smokeQuads = nil

local function playSe(id)
  local okA, Audio = pcall(require, "src.core.game3.audio")
  if okA and Audio and Audio.playSe then
    pcall(Audio.playSe, id)
  end
end

local function makeTransparentImage(path)
  if not (love and love.image and love.image.newImageData and love.graphics and love.graphics.newImage) then
    return nil
  end
  local okData, imgData = pcall(love.image.newImageData, path)
  if not (okData and imgData) then return nil end

  local w, h = imgData:getWidth(), imgData:getHeight()
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, _ = imgData:getPixel(x, y)
      local r8 = math.floor(r * 255 + 0.5)
      local g8 = math.floor(g * 255 + 0.5)
      local b8 = math.floor(b * 255 + 0.5)
      -- Key out GBA background blue palette entry (57, 115, 180)
      if (r8 >= 45 and r8 <= 68) and (g8 >= 105 and g8 <= 130) and (b8 >= 165 and b8 <= 195) then
        imgData:setPixel(x, y, 0, 0, 0, 0)
      end
    end
  end
  local img = love.graphics.newImage(imgData)
  if img.setFilter then img:setFilter("nearest", "nearest") end
  return img
end

local function loadGfx()
  if not (love and love.graphics and love.graphics.newQuad) then
    return
  end
  if not SSAnneCutscene._wakeImage then
    local paths = {
      "pokefirered/graphics/ss_anne/wake_transparent.png",
      "pokefirered/graphics/ss_anne/wake.png",
      "graphics/ss_anne/wake.png",
    }
    for _, p in ipairs(paths) do
      local img = makeTransparentImage(p)
      if img then
        SSAnneCutscene._wakeImage = img
        -- 16x64 image with two 16x32 frames
        SSAnneCutscene._wakeQuads = {
          [0] = love.graphics.newQuad(0, 0, 16, 32, 16, 64),
          [1] = love.graphics.newQuad(0, 32, 16, 32, 16, 64),
        }
        break
      end
    end
  end
  if not SSAnneCutscene._smokeImage then
    local paths = {
      "pokefirered/graphics/ss_anne/smoke_transparent.png",
      "pokefirered/graphics/ss_anne/smoke.png",
      "graphics/ss_anne/smoke.png",
    }
    for _, p in ipairs(paths) do
      local img = makeTransparentImage(p)
      if img then
        SSAnneCutscene._smokeImage = img
        local sw, sh = 16, 72
        if img.getDimensions then
          local iw, ih = img:getDimensions()
          if iw and ih then sw, sh = iw, ih end
        elseif img.getHeight and img:getHeight() then
          sh = img:getHeight()
        end
        -- Four 16x16 frames
        SSAnneCutscene._smokeQuads = {
          [0] = love.graphics.newQuad(0, 0, 16, 16, sw, sh),
          [1] = love.graphics.newQuad(0, 16, 16, 16, sw, sh),
          [2] = love.graphics.newQuad(0, 32, 16, 16, sw, sh),
          [3] = love.graphics.newQuad(0, 48, 16, 16, sw, sh),
        }
        break
      end
    end
  end
end

function SSAnneCutscene.isActive()
  return SSAnneCutscene._active
end

function SSAnneCutscene.reset()
  SSAnneCutscene._active = false
  SSAnneCutscene._phase = "idle"
  SSAnneCutscene._initTimer = 0
  SSAnneCutscene._runTimer1 = 0
  SSAnneCutscene._runTimer2 = 0
  SSAnneCutscene._finishTimer = 0
  SSAnneCutscene._boatOffset = 0
  SSAnneCutscene._wake = nil
  SSAnneCutscene._smokes = {}
end

--- pokefirered/src/ss_anne.c:82 DoSSAnneDepartureCutscene
function SSAnneCutscene.start(ctx, adapters)
  SSAnneCutscene.reset()
  SSAnneCutscene._active = true
  SSAnneCutscene._phase = "init"
  SSAnneCutscene._initTimer = INIT_FRAMES

  -- Initial horn sound
  playSe(SE_SS_ANNE_HORN)

  loadGfx()

  return function()
    return SSAnneCutscene.step()
  end
end

--- Ticked each frame during waitstate. Returns true when cutscene is fully finished.
function SSAnneCutscene.step()
  if not SSAnneCutscene._active then return true end

  local Objects = package.loaded["src.core.game3.objects"]
  local eo = Objects and Objects.find and Objects.find(1)

  if SSAnneCutscene._phase == "init" then
    SSAnneCutscene._initTimer = SSAnneCutscene._initTimer - 1
    if SSAnneCutscene._initTimer <= 0 then
      -- Task_SSAnneInit finishes: creates wake sprite and switches to Task_SSAnneRun
      SSAnneCutscene._phase = "run"
      SSAnneCutscene._wake = {
        timer = 0,
        x2 = 0,
        frame = 0,
      }
    end
    return false
  end

  if SSAnneCutscene._phase == "run" then
    SSAnneCutscene._runTimer1 = SSAnneCutscene._runTimer1 + 1
    SSAnneCutscene._runTimer2 = SSAnneCutscene._runTimer2 + 1

    -- Smoke puff creation every 70 frames
    if SSAnneCutscene._runTimer1 == SMOKE_INTERVAL then
      SSAnneCutscene._runTimer1 = 0
      table.insert(SSAnneCutscene._smokes, {
        timer = 0,
        x2 = 0,
        frame = 0,
        animEnded = false,
        boatOffsetAtSpawn = SSAnneCutscene._boatOffset,
      })
    end

    -- Boat movement: x = data[2] / 5 (1 pixel every 5 frames)
    SSAnneCutscene._boatOffset = math.floor(SSAnneCutscene._runTimer2 / SLIDE_SPEED_DIV)
    if eo then
      eo.raiseX = -SSAnneCutscene._boatOffset
    end

    -- Update wake sprite
    if SSAnneCutscene._wake then
      local w = SSAnneCutscene._wake
      if math.floor(w.timer / 6) < 22 then
        w.timer = w.timer + 1
      end
      w.x2 = math.floor(w.timer / 6)
      -- 12 ticks per frame, looping between frame 0 and frame 1
      w.frame = (math.floor(w.timer / 12) % 2 == 0) and 0 or 1
    end

    -- Update smoke sprites
    local activeSmokes = {}
    for _, s in ipairs(SSAnneCutscene._smokes) do
      s.timer = s.timer + 1
      s.x2 = math.floor(s.timer / 4)
      if s.timer < 10 then
        s.frame = 0
      elseif s.timer < 30 then
        s.frame = 1
      elseif s.timer < 50 then
        s.frame = 2
      elseif s.timer < 80 then
        s.frame = 3
      else
        s.animEnded = true
      end
      if not s.animEnded then
        activeSmokes[#activeSmokes + 1] = s
      end
    end
    SSAnneCutscene._smokes = activeSmokes

    -- Exit check: when boat moves completely off-screen
    if SSAnneCutscene._boatOffset >= TRAVEL_DISTANCE then
      -- Final horn sound
      playSe(SE_SS_ANNE_HORN)
      SSAnneCutscene._phase = "finish"
      SSAnneCutscene._finishTimer = 0
    end
    return false
  end

  if SSAnneCutscene._phase == "finish" then
    SSAnneCutscene._finishTimer = SSAnneCutscene._finishTimer + 1
    if SSAnneCutscene._finishTimer >= FINISH_FRAMES then
      -- Task_SSAnneFinish complete: clean up and unblock script
      SSAnneCutscene._active = false
      SSAnneCutscene._phase = "done"
      if eo then
        eo.raiseX = 0
      end
      return true
    end
    return false
  end

  return true
end

--- Draw wake under boat actors (pret oam.priority = 2, subpriority = 0xFF).
function SSAnneCutscene.drawWake(camX, camY)
  if not SSAnneCutscene._active then return end
  if not (SSAnneCutscene._wake and SSAnneCutscene._wakeImage and SSAnneCutscene._wakeQuads) then return end

  local Objects = package.loaded["src.core.game3.objects"]
  local eo = Objects and Objects.find and Objects.find(1)
  if not eo then return end

  local curBoatPx = (eo.px or (eo.cellX * 16)) - SSAnneCutscene._boatOffset
  local boatPy = eo.py or (eo.cellY * 16)
  local boatLeft = curBoatPx - camX - 56
  local boatTop = boatPy - camY - 48

  local w = SSAnneCutscene._wake
  local q = SSAnneCutscene._wakeQuads[w.frame or 0]
  if q then
    local wx = boatLeft + 106 + (w.x2 or 0)
    local wy = boatTop + 24
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(SSAnneCutscene._wakeImage, q, wx, wy)
  end
end

--- Draw smoke puffs rising from smokestack in overlay space (pret oam.priority = 0).
function SSAnneCutscene.drawSmoke(camX, camY)
  if not SSAnneCutscene._active then return end
  if not (SSAnneCutscene._smokeImage and SSAnneCutscene._smokeQuads and #SSAnneCutscene._smokes > 0) then return end

  local Objects = package.loaded["src.core.game3.objects"]
  local eo = Objects and Objects.find and Objects.find(1)
  if not eo then return end

  local boatPy = eo.py or (eo.cellY * 16)
  local boatTop = boatPy - camY - 48

  for _, s in ipairs(SSAnneCutscene._smokes) do
    local q = SSAnneCutscene._smokeQuads[s.frame or 0]
    if q then
      local spawnBoatLeft = (eo.px or (eo.cellX * 16)) - s.boatOffsetAtSpawn - camX - 56
      local sx = spawnBoatLeft + 78 + (s.x2 or 0)
      local sy = boatTop + 2
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(SSAnneCutscene._smokeImage, q, sx, sy)
    end
  end
end

--- Draw wake and smoke overlay particles in world/screen space.
function SSAnneCutscene.draw(camX, camY)
  SSAnneCutscene.drawWake(camX, camY)
  SSAnneCutscene.drawSmoke(camX, camY)
end

return SSAnneCutscene
