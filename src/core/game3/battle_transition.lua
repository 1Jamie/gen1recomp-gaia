-- Gen 3 (FireRed) battle transition orchestrator & visual effects.
-- Replicates pret battle_transition.c and battle_setup.c.

local Display = require("src.core.game3.display")
local Audio = require("src.core.game3.audio")

local BattleTransition = {}

local ID = {
  BLUR = 0,
  SWIRL = 1,
  SHUFFLE = 2,
  BIG_POKEBALL = 3,
  POKEBALLS_TRAIL = 4,
  CLOCKWISE_WIPE = 5,
  RIPPLE = 6,
  WAVE = 7,
  SLICE = 8,
  WHITE_BARS_FADE = 9,
  GRID_SQUARES = 10,
  ANGLED_WIPES = 11,
  LORELEI = 12,
  BRUNO = 13,
  AGATHA = 14,
  LANCE = 15,
  BLUE = 16,
  SPIRAL = 17,
}
BattleTransition.ID = ID

local TERRAIN = {
  NORMAL = 0,
  CAVE = 1,
  FLASH = 2,
  WATER = 3,
}
BattleTransition.TERRAIN = TERRAIN

local TABLE_WILD = {
  [TERRAIN.NORMAL] = { ID.SLICE, ID.WHITE_BARS_FADE },
  [TERRAIN.CAVE]   = { ID.CLOCKWISE_WIPE, ID.GRID_SQUARES },
  [TERRAIN.FLASH]  = { ID.BLUR, ID.GRID_SQUARES },
  [TERRAIN.WATER]  = { ID.WAVE, ID.RIPPLE },
}

local TABLE_TRAINER = {
  [TERRAIN.NORMAL] = { ID.POKEBALLS_TRAIL, ID.ANGLED_WIPES },
  [TERRAIN.CAVE]   = { ID.SHUFFLE, ID.BIG_POKEBALL },
  [TERRAIN.FLASH]  = { ID.BLUR, ID.GRID_SQUARES },
  [TERRAIN.WATER]  = { ID.SWIRL, ID.RIPPLE },
}

local MUGSHOT_BY_ID = {
  [ID.LORELEI] = "lorelei",
  [ID.BRUNO]   = "bruno",
  [ID.AGATHA]  = "agatha",
  [ID.LANCE]   = "lance",
  [ID.BLUE]    = "blue",
}

BattleTransition._active = false
BattleTransition._phase = "idle" -- "intro" | "main" | "done"
BattleTransition._transitionId = ID.SLICE
BattleTransition._opts = {}
BattleTransition._doneCb = nil
BattleTransition._frame = 0
BattleTransition._introTimer = 0
BattleTransition._introCycle = 0
BattleTransition._introBlend = 0
BattleTransition._mainFrame = 0
BattleTransition._snapshot = nil

local function getChrome()
  local ok, Chrome = pcall(require, "src.ui.game3.battle_transition_chrome")
  if ok and Chrome then return Chrome end
  return nil
end

local function getTrainerPic()
  local ok, TP = pcall(require, "src.core.game3.trainer_pic")
  if ok and TP then return TP end
  return nil
end

--------------------------------------------------------------------------------
-- Transition Selection (battle_setup.c parity)
--------------------------------------------------------------------------------

function BattleTransition.getTerrainByMap(opts)
  opts = opts or {}
  if opts.flash or opts.flashLevel and opts.flashLevel > 0 then
    return TERRAIN.FLASH
  end
  if opts.surfing or opts.isWater or opts.mapKind == "water" or opts.mapType == 4 or opts.mapType == 5 then
    return TERRAIN.WATER
  end
  if opts.isCave or opts.mapKind == "cave" or opts.mapKind == "dungeon" or opts.mapType == 3 then
    return TERRAIN.CAVE
  end
  return TERRAIN.NORMAL
end

function BattleTransition.pickWild(opts)
  opts = opts or {}
  local terrain = opts.terrain or BattleTransition.getTerrainByMap(opts)
  local tableEntry = TABLE_WILD[terrain] or TABLE_WILD[TERRAIN.NORMAL]
  local playerLv = tonumber(opts.playerLevel) or 5
  local enemyLv = tonumber(opts.enemyLevel) or 3
  if enemyLv < playerLv then
    return tableEntry[1]
  else
    return tableEntry[2]
  end
end

function BattleTransition.pickTrainer(opts)
  opts = opts or {}
  local tid = tonumber(opts.trainerId) or 0
  local tClass = opts.trainerClass

  -- E4 / Champion / Rival check
  if tClass == "ELITE_FOUR" or tClass == 57 then
    if tid == 412 or tid == 413 or opts.isLorelei then return ID.LORELEI end
    if tid == 414 or tid == 415 or opts.isBruno then return ID.BRUNO end
    if tid == 416 or tid == 417 or opts.isAgatha then return ID.AGATHA end
    if tid == 418 or tid == 419 or opts.isLance then return ID.LANCE end
    return ID.BLUE
  end
  if tClass == "CHAMPION" or tClass == "RIVAL" or tClass == 58 or opts.isRival or opts.isChampion then
    return ID.BLUE
  end
  if opts.isLorelei then return ID.LORELEI end
  if opts.isBruno then return ID.BRUNO end
  if opts.isAgatha then return ID.AGATHA end
  if opts.isLance then return ID.LANCE end
  if opts.isBlue then return ID.BLUE end

  local terrain = opts.terrain or BattleTransition.getTerrainByMap(opts)
  local tableEntry = TABLE_TRAINER[terrain] or TABLE_TRAINER[TERRAIN.NORMAL]
  local playerLv = tonumber(opts.playerLevel) or 5
  local enemyLv = tonumber(opts.enemyLevel) or 3
  if enemyLv < playerLv then
    return tableEntry[1]
  else
    return tableEntry[2]
  end
end

function BattleTransition.pick(opts)
  opts = opts or {}
  if opts.transitionId then return opts.transitionId end
  if opts.wild then
    return BattleTransition.pickWild(opts)
  else
    return BattleTransition.pickTrainer(opts)
  end
end

--------------------------------------------------------------------------------
-- Orchestrator Lifecycle
--------------------------------------------------------------------------------

function BattleTransition.start(transitionId, opts, doneCb)
  opts = opts or {}
  BattleTransition._active = true
  BattleTransition._transitionId = transitionId or ID.SLICE
  BattleTransition._opts = opts
  BattleTransition._doneCb = doneCb
  BattleTransition._frame = 0
  BattleTransition._mainFrame = 0
  BattleTransition._introCycle = 0
  BattleTransition._introBlend = 0
  BattleTransition._introTimer = 0

  if opts.skipIntro then
    BattleTransition._phase = "main"
  else
    BattleTransition._phase = "intro"
  end

  -- Snapshot the current field frame if love.graphics is available
  if love and love.graphics and Display.ensureCanvas and not opts.headless then
    local canvas = Display.ensureCanvas("main")
    if canvas and love.graphics.newImage and canvas.newImageData then
      pcall(function()
        local imgData = canvas:newImageData()
        if imgData then
          local snap = love.graphics.newImage(imgData)
          if snap and snap.setFilter then snap:setFilter("nearest", "nearest") end
          BattleTransition._snapshot = snap
        end
      end)
    end
  end

  -- Sound effects
  if MUGSHOT_BY_ID[BattleTransition._transitionId] then
    pcall(function() Audio.playSe("SE_MUGSHOT") end)
  end

  if opts.headless then
    BattleTransition.finish()
    return true
  end
  return true
end

function BattleTransition.isActive()
  return BattleTransition._active
end

function BattleTransition.finish()
  BattleTransition._active = false
  BattleTransition._phase = "done"
  BattleTransition._snapshot = nil
  local cb = BattleTransition._doneCb
  BattleTransition._doneCb = nil
  if cb then cb() end
end

function BattleTransition.abort()
  BattleTransition._active = false
  BattleTransition._phase = "idle"
  BattleTransition._snapshot = nil
  BattleTransition._doneCb = nil
end

function BattleTransition.tick(dt)
  if not BattleTransition._active then return false end
  BattleTransition._frame = BattleTransition._frame + 1

  if BattleTransition._phase == "intro" then
    -- 2 gray flash pulses: 8 frames fade to gray (+2/frame), 8 frames fade back (-2/frame).
    -- Total per pulse = 16 frames; 2 pulses = 32 frames.
    local step = 2
    if BattleTransition._introCycle % 2 == 0 then
      BattleTransition._introBlend = math.min(16, BattleTransition._introBlend + step)
      if BattleTransition._introBlend >= 16 then
        BattleTransition._introCycle = BattleTransition._introCycle + 1
      end
    else
      BattleTransition._introBlend = math.max(0, BattleTransition._introBlend - step)
      if BattleTransition._introBlend <= 0 then
        BattleTransition._introCycle = BattleTransition._introCycle + 1
        if BattleTransition._introCycle >= 4 then
          BattleTransition._phase = "main"
          BattleTransition._mainFrame = 0
        end
      end
    end
    return true
  end

  if BattleTransition._phase == "main" then
    BattleTransition._mainFrame = BattleTransition._mainFrame + 1
    local tid = BattleTransition._transitionId
    local maxFrames = 36
    if tid == ID.BLUR or tid == ID.SWIRL or tid == ID.RIPPLE or tid == ID.WAVE then
      maxFrames = 40
    elseif tid == ID.GRID_SQUARES or tid == ID.SPIRAL then
      maxFrames = 42
    elseif tid == ID.BIG_POKEBALL or tid == ID.POKEBALLS_TRAIL then
      maxFrames = 44
    elseif MUGSHOT_BY_ID[tid] then
      maxFrames = 56
    end

    if BattleTransition._mainFrame >= maxFrames then
      BattleTransition.finish()
      return true
    end
    return true
  end

  return false
end

--------------------------------------------------------------------------------
-- Rendering Handlers & Primitives
--------------------------------------------------------------------------------

local function drawIntroFlash()
  local blend = (BattleTransition._introBlend or 0) / 16
  if blend > 0 then
    -- Gray tone RGB (11/31 ~ 0.35)
    love.graphics.setColor(0.35, 0.35, 0.35, blend * 0.85)
    love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

local function drawSlice(t)
  -- Alternating horizontal strips slide left and right
  local numSlices = 16
  local sliceH = Display.H / numSlices
  local offset = t * Display.W * 1.2
  for i = 0, numSlices - 1 do
    local dir = (i % 2 == 0) and -1 or 1
    local ox = dir * offset
    love.graphics.setColor(0, 0, 0, 1)
    if dir < 0 then
      love.graphics.rectangle("fill", Display.W + ox, i * sliceH, Display.W, sliceH + 1)
    else
      love.graphics.rectangle("fill", -Display.W + ox, i * sliceH, Display.W, sliceH + 1)
    end
  end
end

local function drawWhiteBarsFade(t)
  -- 4 horizontal white bars expand vertically, then fade to black
  local bars = 4
  local segH = Display.H / bars
  local barH = math.min(segH, segH * t * 1.8)
  love.graphics.setColor(1, 1, 1, 1)
  for i = 0, bars - 1 do
    local cy = (i + 0.5) * segH
    love.graphics.rectangle("fill", 0, cy - barH * 0.5, Display.W, barH)
  end
  if t > 0.5 then
    local blackA = (t - 0.5) / 0.5
    love.graphics.setColor(0, 0, 0, blackA)
    love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
  end
end

local function drawClockwiseWipe(t)
  -- Sector sweep from center (12 o'clock clockwise)
  local angle = t * math.pi * 2
  local cx, cy = Display.W * 0.5, Display.H * 0.5
  local r = 180
  local steps = 40
  local curAngle = math.min(angle, math.pi * 2)
  local numSteps = math.floor(curAngle / (math.pi * 2) * steps)
  if numSteps > 0 then
    love.graphics.setColor(0, 0, 0, 1)
    for i = 0, numSteps do
      local a1 = -math.pi * 0.5 + (i / steps) * math.pi * 2
      local a2 = -math.pi * 0.5 + ((i + 1) / steps) * math.pi * 2
      if a1 < -math.pi * 0.5 + curAngle then
        a2 = math.min(a2, -math.pi * 0.5 + curAngle)
        local x1 = cx + math.cos(a1) * r
        local y1 = cy + math.sin(a1) * r
        local x2 = cx + math.cos(a2) * r
        local y2 = cy + math.sin(a2) * r
        love.graphics.polygon("fill", cx, cy, x1, y1, x2, y2)
      end
    end
  end
end

local function drawAngledWipes(t)
  -- Diagonal corner wipes closing inwards
  local w, h = Display.W, Display.H
  local d = t * math.max(w, h) * 1.5
  love.graphics.setColor(0, 0, 0, 1)
  -- Top-left and bottom-right triangles
  love.graphics.polygon("fill", 0, 0, d, 0, 0, d)
  love.graphics.polygon("fill", w, h, w - d, h, w, h - d)
  -- Top-right and bottom-left triangles
  love.graphics.polygon("fill", w, 0, w - d, 0, w, d)
  love.graphics.polygon("fill", 0, h, d, h, 0, h - d)
  if t > 0.8 then
    local a = (t - 0.8) / 0.2
    love.graphics.setColor(0, 0, 0, a)
    love.graphics.rectangle("fill", 0, 0, w, h)
  end
end

local function drawGridSquares(t)
  local Chrome = getChrome()
  local img, quads = Chrome and Chrome.gridSquare()
  local cols, rows = 30, 20
  for row = 0, rows - 1 do
    for col = 0, cols - 1 do
      local dist = (col + row) / (cols + rows)
      local localT = math.max(0, math.min(1, (t - dist * 0.4) / 0.6))
      if localT > 0 then
        local frame = math.floor(localT * 14) + 1
        if frame > 15 then frame = 15 end
        if img and quads and quads[frame] then
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(img, quads[frame], col * 8, row * 8)
        else
          local sz = localT * 8
          love.graphics.setColor(0, 0, 0, 1)
          love.graphics.rectangle("fill", col * 8 + (8 - sz) * 0.5, row * 8 + (8 - sz) * 0.5, sz, sz)
        end
      end
    end
  end
end

local function drawPokeballsTrail(t)
  local Chrome = getChrome()
  local ball = Chrome and Chrome.slidingPokeball()
  local w, h = Display.W, Display.H
  local numLanes = 4
  local laneH = h / numLanes

  for lane = 0, numLanes - 1 do
    local dir = (lane % 2 == 0) and 1 or -1
    local ballX = (dir > 0)
      and (-32 + t * (w + 64))
      or (w + 32 - t * (w + 64))
    local ballY = lane * laneH + (laneH - 32) * 0.5

    -- Black trail behind ball
    love.graphics.setColor(0, 0, 0, 1)
    if dir > 0 then
      local trailW = math.max(0, ballX + 16)
      love.graphics.rectangle("fill", 0, lane * laneH, trailW, laneH)
    else
      local trailX = math.min(w, ballX + 16)
      love.graphics.rectangle("fill", trailX, lane * laneH, w - trailX, laneH)
    end

    if ball then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(ball, ballX, ballY)
    end
  end
end

local function drawBigPokeball(t)
  local Chrome = getChrome()
  local bigBall = Chrome and Chrome.bigPokeball()
  local cx, cy = Display.W * 0.5, Display.H * 0.5

  if t < 0.6 then
    -- Pokéball scales into center
    local scale = t / 0.6
    if bigBall then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(bigBall, cx, cy, 0, scale, scale, 120, 80)
    else
      local r = scale * 60
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.circle("fill", cx, cy, r)
    end
  else
    -- Black mask fills screen
    local blackT = (t - 0.6) / 0.4
    if bigBall then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(bigBall, cx, cy, 0, 1, 1, 120, 80)
    end
    love.graphics.setColor(0, 0, 0, blackT)
    love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
  end
end

local function drawSpiral(t)
  -- Inward rectangle spiral
  local w, h = Display.W, Display.H
  local maxThick = math.max(w, h) * 0.5 * t * 1.2
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", 0, 0, w, maxThick)
  love.graphics.rectangle("fill", 0, h - maxThick, w, maxThick)
  love.graphics.rectangle("fill", 0, 0, maxThick, h)
  love.graphics.rectangle("fill", w - maxThick, 0, maxThick, h)
end

local function drawMugshot(t, mugKey)
  local Chrome = getChrome()
  local TP = getTrainerPic()
  local opts = BattleTransition._opts or {}
  local gender = opts.playerGender or 0
  local gKey = (gender == 1 or gender == "female") and "female" or "male"

  local vsbar = Chrome and Chrome.vsbar(mugKey, gKey)
  local banner = Chrome and Chrome.banner(mugKey)

  -- 1. VS Banners slide horizontally in opposite directions
  local bannerT = math.min(1, t * 2.2)
  local topX = (1 - bannerT) * -Display.W
  local bottomX = (1 - bannerT) * Display.W

  if vsbar then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(vsbar, topX, 0)
    love.graphics.draw(vsbar, bottomX, 80)
  elseif banner then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(banner, topX, 20, 0, 2, 6)
    love.graphics.draw(banner, bottomX, 80, 0, 2, 6)
  else
    love.graphics.setColor(0.1, 0.2, 0.4, 1)
    love.graphics.rectangle("fill", topX, 0, Display.W, 80)
    love.graphics.setColor(0.3, 0.1, 0.1, 1)
    love.graphics.rectangle("fill", bottomX, 80, Display.W, 80)
  end

  -- 2. Opponent and Player front pics slide in
  local oppPicId = 106 -- default / Blue
  if mugKey == "lorelei" then oppPicId = 98
  elseif mugKey == "bruno" then oppPicId = 99
  elseif mugKey == "agatha" then oppPicId = 100
  elseif mugKey == "lance" then oppPicId = 101
  elseif mugKey == "blue" then oppPicId = 106
  end

  local oppImg = TP and TP.front and TP.front(oppPicId)
  local playerPicId = (gKey == "female") and 88 or 87
  local playerImg = TP and TP.front and TP.front(playerPicId)

  local slideT = math.max(0, math.min(1, (t - 0.2) / 0.5))
  local oppX = -64 + slideT * (Display.W * 0.35 + 64)
  local playerX = Display.W - slideT * (Display.W * 0.35 + 64)

  if oppImg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(oppImg, oppX, 8)
  end
  if playerImg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(playerImg, playerX, 88)
  end

  -- 3. Central white burst spreads out vertically
  if t > 0.65 then
    local burstT = (t - 0.65) / 0.35
    local halfH = burstT * 80
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 80 - halfH, Display.W, halfH * 2)
  end

  if t > 0.88 then
    local fadeA = (t - 0.88) / 0.12
    love.graphics.setColor(0, 0, 0, fadeA)
    love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
  end
end

local function drawWaveRipple(t, isWave)
  -- Horizontal wavy scanlines displacement + fade to black
  local freq = isWave and 0.15 or 0.35
  local amp = t * 24
  local fadeA = math.min(1, t * 1.5)
  love.graphics.setColor(0, 0, 0, fadeA)
  love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
end

local function drawBlur(t)
  -- Mosaic step simulation + fade to black
  local fadeA = math.min(1, t * 1.4)
  love.graphics.setColor(0, 0, 0, fadeA)
  love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
end

local function drawShuffle(t)
  -- Sliced block shuffle
  local blocks = 8
  local bw = Display.W / blocks
  local off = t * Display.H * 1.2
  love.graphics.setColor(0, 0, 0, 1)
  for col = 0, blocks - 1 do
    local dir = (col % 2 == 0) and -1 or 1
    if dir < 0 then
      love.graphics.rectangle("fill", col * bw, Display.H - off, bw + 1, Display.H)
    else
      love.graphics.rectangle("fill", col * bw, -Display.H + off, bw + 1, Display.H)
    end
  end
end

--------------------------------------------------------------------------------
-- Main Draw Entrypoint
--------------------------------------------------------------------------------

function BattleTransition.draw()
  if not BattleTransition._active then return end
  if not (love and love.graphics) then return end

  love.graphics.setColor(1, 1, 1, 1)

  if BattleTransition._phase == "intro" then
    drawIntroFlash()
    return
  end

  local tid = BattleTransition._transitionId
  local maxFrames = 36
  if tid == ID.BLUR or tid == ID.SWIRL or tid == ID.RIPPLE or tid == ID.WAVE then
    maxFrames = 40
  elseif tid == ID.GRID_SQUARES or tid == ID.SPIRAL then
    maxFrames = 42
  elseif tid == ID.BIG_POKEBALL or tid == ID.POKEBALLS_TRAIL then
    maxFrames = 44
  elseif MUGSHOT_BY_ID[tid] then
    maxFrames = 56
  end

  local t = math.min(1, BattleTransition._mainFrame / maxFrames)

  if tid == ID.SLICE then
    drawSlice(t)
  elseif tid == ID.WHITE_BARS_FADE then
    drawWhiteBarsFade(t)
  elseif tid == ID.CLOCKWISE_WIPE then
    drawClockwiseWipe(t)
  elseif tid == ID.ANGLED_WIPES then
    drawAngledWipes(t)
  elseif tid == ID.GRID_SQUARES then
    drawGridSquares(t)
  elseif tid == ID.POKEBALLS_TRAIL then
    drawPokeballsTrail(t)
  elseif tid == ID.BIG_POKEBALL then
    drawBigPokeball(t)
  elseif tid == ID.SPIRAL then
    drawSpiral(t)
  elseif tid == ID.WAVE then
    drawWaveRipple(t, true)
  elseif tid == ID.RIPPLE or tid == ID.SWIRL then
    drawWaveRipple(t, false)
  elseif tid == ID.BLUR then
    drawBlur(t)
  elseif tid == ID.SHUFFLE then
    drawShuffle(t)
  elseif MUGSHOT_BY_ID[tid] then
    drawMugshot(t, MUGSHOT_BY_ID[tid])
  else
    drawSlice(t)
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return BattleTransition
