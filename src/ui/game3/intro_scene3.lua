-- Scene 3 fight (pokefirered IntroCB_Scene3_*). Driven by shared Bg + Oam.

local Display = require("src.core.game3.display")
local Audio = require("src.core.game3.audio")
local Bg = require("src.core.game3.bg")
local Oam = require("src.core.game3.oam")

local S3 = {}

local BG_GENGAR = 0
local BG_BACKGROUND = 1

local NIDORINO = { NORMAL = 1, CRY = 2, CROUCH = 3, HOP = 4, ATTACK = 5 }

local function sine(idx)
  idx = idx % 256
  return math.floor(math.sin(idx * math.pi / 128) * 256 + 0.5)
end

local function setNidoAnim(movie, frame)
  local spr = movie._s3NidoId and Oam.get(movie._s3NidoId)
  if spr and movie.nidorinoQuads then
    spr.quad = movie.nidorinoQuads[frame] or movie.nidorinoQuads[1]
  end
end

local function applyGengarFrame(movie, frame, xSub, ySub, xBaseQ88)
  -- Scene3_ApplyGengarAnim: Y = (frame<<15)+0x1F000; X = xBase; then SUB xSub<<8, ySub<<8
  Bg.changeBgY(BG_GENGAR, (frame * 0x8000) + 0x1F000, Bg.COORD_SET)
  Bg.changeBgX(BG_GENGAR, xBaseQ88 or movie._gengarBaseXQ88 or 0xEF00, Bg.COORD_SET)
  if xSub and xSub ~= 0 then
    Bg.changeBgX(BG_GENGAR, xSub * 256, Bg.COORD_SUB)
  end
  if ySub and ySub ~= 0 then
    Bg.changeBgY(BG_GENGAR, ySub * 256, Bg.COORD_SUB)
  end
end

------------------------------------------------------------------------
-- Sprite callbacks
------------------------------------------------------------------------

local function SpriteCB_Grass(sprite)
  local st = sprite.data[1]
  if st == 0 then
    sprite.data[2] = sprite.x * 32
    sprite.data[3] = 160
    sprite.data[1] = 1
    st = 1
  end
  if st == 1 then
    sprite.data[2] = sprite.data[2] - sprite.data[3]
    sprite.x = math.floor(sprite.data[2] / 32)
    if sprite.x <= 52 then
      local m = sprite._movie
      if m then m._bgScrollSlow = true end
      sprite.data[1] = 2
    end
  elseif st == 2 then
    sprite.data[2] = sprite.data[2] - 32
    sprite.x = math.floor(sprite.data[2] / 32)
    if sprite.x <= -32 then
      Oam.destroySprite(sprite._id)
    end
  end
end

local function SpriteCB_NidorinoEnter(sprite)
  sprite.data[5] = (sprite.data[5] or 0) + 1
  if sprite.data[5] >= 40 and sprite.data[2] > 1 then
    sprite.data[2] = sprite.data[2] - 1
  end
  sprite.data[1] = sprite.data[1] + sprite.data[2]
  sprite.x = math.floor(sprite.data[1] / 16)
  if sprite.x >= sprite.data[4] then
    sprite.x = sprite.data[4]
    sprite.callback = nil
  end
end

local function SpriteCB_GengarSwipe(sprite)
  sprite.invisible = not sprite.invisible
  sprite.data[1] = (sprite.data[1] or 0) + 1
  local dur = sprite.data[2] or 8
  if sprite.data[1] >= dur then
    local af = (sprite.data[3] or 0) + 1
    if af >= 2 then
      Oam.destroySprite(sprite._id)
      return
    end
    sprite.data[3] = af
    sprite.data[1] = 0
    sprite.data[2] = 4 -- second anim frame duration
    if sprite._quads then
      sprite.quad = sprite._quads[af + 1]
    end
  end
end

local function SpriteCB_RecoilDust(sprite)
  if (sprite.data[1] or 0) == 0 then
    sprite.data[2] = sprite.x * 16
    sprite.data[3] = sprite.y * 16
    sprite.data[1] = 1
  end
  sprite.data[2] = sprite.data[2] - sprite.data[4]
  sprite.data[3] = sprite.data[3] + sprite.data[5]
  sprite.x = math.floor(sprite.data[2] / 16)
  sprite.y = math.floor(sprite.data[3] / 16)
  sprite.data[8] = (sprite.data[8] or 0) + 1
  if sprite.data[8] > 1 then
    sprite.data[8] = 0
    sprite.invisible = not sprite.invisible
  end
  -- 4 frames × ~10 ticks
  sprite.data[6] = (sprite.data[6] or 0) + 1
  if sprite.data[6] >= 10 then
    sprite.data[6] = 0
    local af = (sprite.data[7] or 0) + 1
    if af >= 4 then
      Oam.destroySprite(sprite._id)
      return
    end
    sprite.data[7] = af
    if sprite._quads then
      sprite.quad = sprite._quads[af + 1]
    end
  end
end

local function createSwipeSprites(movie)
  local A = movie.assets
  if not A.introScene3Swipe or not movie.swipeQuads then return end
  -- Top: 32×64 at (132,78), frames 0 then 1
  local id1, s1 = Oam.createSprite({
    dims = Oam.VRECT_32x64,
    priority = 1,
    image = A.introScene3Swipe,
    quad = movie.swipeQuads.top[1],
    callback = SpriteCB_GengarSwipe,
  }, 132, 78, 6)
  if s1 then
    s1._quads = movie.swipeQuads.top
    s1.data[2] = 8 -- first frame duration
  end
  -- Bottom: reshaped to 32×16 at (132,118)
  local id2, s2 = Oam.createSprite({
    dims = Oam.HRECT_32x16,
    priority = 1,
    image = A.introScene3Swipe,
    quad = movie.swipeQuads.bottom[1],
    callback = SpriteCB_GengarSwipe,
  }, 132, 118, 6)
  if s2 then
    s2._quads = movie.swipeQuads.bottom
    s2.data[2] = 8
  end
  movie._swipeIds = { id1, id2 }
end

local function createRecoilDust(movie, x, y, seed)
  local A = movie.assets
  if not A.introScene3RecoilDust or not movie.dustQuads then return seed end
  local RAND_MULT = 1103515245
  for i = 0, 1 do
    local id, spr = Oam.createSprite({
      dims = Oam.SQUARE_16,
      priority = 1,
      image = A.introScene3RecoilDust,
      quad = movie.dustQuads[1],
      callback = SpriteCB_RecoilDust,
    }, x - 22, y + 24, 10)
    if spr then
      spr._quads = movie.dustQuads
      spr.data[4] = (seed % 13) + 8
      spr.data[5] = seed % 3
      spr.data[8] = i -- invisible timer phase
      spr.invisible = (i == 1)
    end
    seed = (seed * RAND_MULT) % 4294967296
  end
  return seed
end

------------------------------------------------------------------------
-- Nidorino fight anims (ported callbacks)
------------------------------------------------------------------------

local function nidoRunning(movie)
  local spr = movie._s3NidoId and Oam.get(movie._s3NidoId)
  return spr and spr.callback ~= nil
end

local function startNidorinoCry(movie)
  local spr = Oam.get(movie._s3NidoId)
  if not spr then return end
  setNidoAnim(movie, NIDORINO.CROUCH)
  spr.y2 = 3
  spr.data[1] = 0
  spr.data[2] = 0
  spr.data[3] = 0
  spr.callback = function(sprite)
    local st = sprite.data[1]
    if st == 0 then
      sprite.data[2] = sprite.data[2] + 1
      if sprite.data[2] > 8 then
        setNidoAnim(movie, NIDORINO.CRY)
        sprite.y2 = 0
        sprite.data[1] = 1
      end
    elseif st == 1 then
      Audio.playCry(33) -- NIDORINO
      sprite.data[2] = 0
      sprite.data[1] = 2
    elseif st == 2 then
      sprite.data[3] = sprite.data[3] + 1
      if sprite.data[3] > 1 then
        sprite.data[3] = 0
        sprite.y2 = (sprite.y2 == 0) and 1 or 0
      end
      sprite.data[2] = sprite.data[2] + 1
      if sprite.data[2] > 48 then
        setNidoAnim(movie, NIDORINO.NORMAL)
        sprite.y2 = 0
        sprite.callback = nil
      end
    end
  end
end

local function startNidorinoHop(movie, time, targetX, heightShift)
  local spr = Oam.get(movie._s3NidoId)
  if not spr then return end
  spr.data[1] = 0
  spr.data[2] = time
  spr.data[3] = spr.x2 * 16
  spr.data[4] = math.floor((targetX * 16) / time)
  spr.data[5] = 0
  spr.data[6] = math.floor(0x800 / time)
  spr.data[7] = 0
  spr.data[8] = heightShift
  setNidoAnim(movie, NIDORINO.CROUCH)
  spr.callback = function(sprite)
    local st = sprite.data[1]
    if st == 0 then
      sprite.data[7] = sprite.data[7] + 1
      if sprite.data[7] > 4 then
        setNidoAnim(movie, NIDORINO.HOP)
        sprite.data[7] = 0
        sprite.data[1] = 1
      end
    elseif st == 1 then
      sprite.data[2] = sprite.data[2] - 1
      if sprite.data[2] ~= 0 then
        sprite.data[3] = sprite.data[3] + sprite.data[4]
        sprite.data[5] = sprite.data[5] + sprite.data[6]
        sprite.x2 = math.floor(sprite.data[3] / 16)
        local s = sine(math.floor(sprite.data[5] / 16))
        sprite.y2 = -math.floor(s / (2 ^ sprite.data[8]))
      else
        sprite.x2 = math.floor(sprite.data[3] / 16) % 65536
        if sprite.x2 > 32767 then sprite.x2 = sprite.x2 - 65536 end
        sprite.y2 = 0
        setNidoAnim(movie, NIDORINO.CROUCH)
        if sprite.data[8] == 5 then
          sprite.callback = nil
        else
          sprite.data[7] = 0
          sprite.data[1] = 2
        end
      end
    elseif st == 2 then
      sprite.data[7] = sprite.data[7] + 1
      if sprite.data[7] > 4 then
        setNidoAnim(movie, NIDORINO.NORMAL)
        sprite.callback = nil
      end
    end
  end
end

local function startNidorinoRecoil(movie)
  local spr = Oam.get(movie._s3NidoId)
  if not spr then return end
  movie._nidoJumpMult = 3
  movie._nidoJumpDiv = 5
  setNidoAnim(movie, NIDORINO.CROUCH)
  spr.data[1] = 0
  spr.data[2] = 0
  spr.data[3] = 0
  spr.data[4] = 0
  spr.data[5] = 0
  spr.data[6] = 0
  spr.data[7] = 0x4757
  spr.data[8] = 40
  spr.callback = function(sprite)
    local st = sprite.data[1]
    if st == 0 then
      sprite.data[2] = sprite.data[2] + 1
      if sprite.data[2] > 4 then
        setNidoAnim(movie, NIDORINO.HOP)
        sprite.data[1] = 1
      end
    elseif st == 1 then
      sprite.data[3] = sprite.data[3] + sprite.data[8]
      sprite.data[4] = sprite.data[4] + 8
      sprite.x2 = math.floor(sprite.data[3] / 16)
      sprite.y2 = -math.floor((sine(sprite.data[4]) * movie._nidoJumpMult) / (2 ^ movie._nidoJumpDiv))
      sprite.data[6] = sprite.data[6] + 1
      if sprite.data[6] > 0 then
        sprite.data[6] = 0
        if sprite.data[8] > 0 then sprite.data[8] = sprite.data[8] - 1 end
      end
      sprite.data[5] = sprite.data[5] + 1
      if sprite.data[5] > 15 then
        setNidoAnim(movie, NIDORINO.CROUCH)
        sprite.data[2] = 0
        sprite.data[8] = 28
        sprite.data[1] = 2
      end
    elseif st == 2 then
      sprite.data[3] = sprite.data[3] + sprite.data[8]
      sprite.x2 = math.floor(sprite.data[3] / 16)
      sprite.data[2] = sprite.data[2] + 1
      if sprite.data[2] > 6 then
        sprite.data[7] = createRecoilDust(movie, sprite.x + sprite.x2, sprite.y + sprite.y2, sprite.data[7])
      end
      if sprite.data[2] > 12 then
        setNidoAnim(movie, NIDORINO.NORMAL)
        sprite.data[2] = 0
        sprite.data[1] = 3
      end
    elseif st == 3 then
      sprite.data[2] = sprite.data[2] + 1
      if sprite.data[2] > 16 then
        startNidorinoHop(movie, 16, -sprite.x2, 4)
      end
    end
  end
end

local function startNidorinoAttack(movie)
  local spr = Oam.get(movie._s3NidoId)
  if not spr then return end
  spr.x = spr.x + spr.x2
  spr.x2 = 0
  movie._nidoJumpMult = 3
  movie._nidoJumpDiv = 4
  spr.data[1] = 0
  spr.data[2] = 0
  spr.data[3] = 0
  spr.data[8] = 36
  setNidoAnim(movie, NIDORINO.CROUCH)
  spr.callback = function(sprite)
    local st = sprite.data[1]
    if st == 0 then
      sprite.data[2] = sprite.data[2] + 1
      if sprite.data[2] % 2 == 1 then
        sprite.data[3] = sprite.data[3] + 1
        if sprite.data[3] % 2 == 1 then
          sprite.x2 = sprite.x2 + 1
        else
          sprite.x2 = sprite.x2 - 1
        end
      end
      if sprite.data[2] > 17 then
        sprite.data[2] = 0
        sprite.data[1] = 1
      end
    elseif st == 1 then
      sprite.data[2] = sprite.data[2] + 1
      if sprite.data[2] >= 40 then
        setNidoAnim(movie, NIDORINO.ATTACK)
        sprite.data[2] = 0
        sprite.data[1] = 2
      end
    elseif st == 2 then
      sprite.data[2] = sprite.data[2] + sprite.data[8]
      sprite.x2 = -math.floor(sprite.data[2] / 16)
      sprite.y2 = -math.floor((sine(math.floor(sprite.data[2] / 16)) * movie._nidoJumpMult) / (2 ^ movie._nidoJumpDiv))
      if sprite.data[8] > 12 then sprite.data[8] = sprite.data[8] - 1 end
      if math.floor(sprite.data[2] / 16) > 63 then
        sprite.callback = nil
      end
    end
  end
end

------------------------------------------------------------------------
-- Gengar attack task
------------------------------------------------------------------------

local function tickGengarAttack(movie)
  local t = movie._gengarAtk
  if not t then return end
  local st = t.state
  if st == 0 then
    t.frame = 2
    t.timer = 0
    t.multY = 6
    t.multX = 32
    t.state = 1
  elseif st == 1 then
    t.sinIdx = t.sinIdx - 2
    t.timer = t.timer + 1
    if t.timer > 15 then t.timer = 0; t.state = 2 end
  elseif st == 2 then
    t.timer = t.timer + 1
    if t.timer == 14 then movie._gengarAttackLanded = true end
    if t.timer > 15 then t.timer = 0; t.state = 3 end
  elseif st == 3 then
    t.sinIdx = t.sinIdx + 8
    t.timer = t.timer + 1
    if t.timer == 4 then
      createSwipeSprites(movie)
      t.multY = 32
      t.multX = 48
      t.frame = 3
    end
    if t.timer > 7 then t.timer = 0; t.state = 4 end
  elseif st == 4 then
    t.sinIdx = t.sinIdx - 8
    t.timer = t.timer + 1
    if t.timer > 3 then
      t.frame = 0
      t.sinIdx = 64
      t.timer = 0
      t.state = 5
    end
  elseif st == 5 then
    movie._gengarAtk = nil
    return
  end
  local xSub = -math.floor((sine(t.sinIdx + 64) * t.multX) / 256)
  local ySub = t.multY - math.floor((sine(t.sinIdx) * t.multY) / 256)
  applyGengarFrame(movie, t.frame, xSub, ySub, t.baseXQ88)
end

local function tickGengarBounce(movie)
  if movie._gengarBouncePaused then return end
  movie._gengarBounceTimer = (movie._gengarBounceTimer or 0) + 1
  if movie._gengarBounceTimer >= 30 then
    movie._gengarBounceTimer = 0
    movie._gengarBounceState = 1 - (movie._gengarBounceState or 0)
    local frame = movie._gengarBounceState
    Bg.changeBgY(BG_GENGAR, (frame * 0x8000) + 0x1F000, Bg.COORD_SET)
  end
end

local function tickGengarEnter(movie)
  local t = movie._gengarEnter
  if not t then return true end
  if t.state == 0 then
    t.speed = 0x400
    t.state = 1
  end
  t.moves = (t.moves or 0) + 1
  if t.moves >= 40 and t.speed > 16 then
    t.speed = t.speed - 16
  end
  Bg.changeBgX(BG_GENGAR, t.speed, Bg.COORD_ADD)
  local L = Bg.get(BG_GENGAR)
  local scrollQ = (L and L.scrollX or 0) * 256
  if scrollQ >= 0xEF00 then
    Bg.changeBgX(BG_GENGAR, 0xEF00, Bg.COORD_SET)
    movie._gengarBaseXQ88 = 0xEF00
    movie._gengarEnter = nil
    return true
  end
  return false
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

function S3.buildQuads(movie)
  if not (love and love.graphics and love.graphics.newQuad) then return end
  movie.nidorinoQuads = {}
  for i = 0, 4 do
    movie.nidorinoQuads[i + 1] = love.graphics.newQuad(0, i * 64, 64, 64, 64, 320)
  end
  -- Swipe sheet 32×160: top 32×64 ×2, bottom 32×16 ×2
  movie.swipeQuads = {
    top = {
      love.graphics.newQuad(0, 0, 32, 64, 32, 160),
      love.graphics.newQuad(0, 64, 32, 64, 32, 160),
    },
    bottom = {
      love.graphics.newQuad(0, 128, 32, 16, 32, 160),
      love.graphics.newQuad(0, 144, 32, 16, 32, 160),
    },
  }
  movie.dustQuads = {}
  for i = 0, 3 do
    movie.dustQuads[i + 1] = love.graphics.newQuad(0, i * 16, 16, 16, 16, 64)
  end
  movie.scene3GrassQuad = love.graphics.newQuad(0, 0, 64, 32, 64, 64)
  -- Full 256×512 sheet; scroll selects frame (don't crop to one quad)
  movie.scene3GengarQuad = nil
end

function S3.setup(movie)
  local A = movie.assets
  Bg.initFromTemplates({
    { bg = BG_GENGAR, priority = 0, visible = false },
    { bg = BG_BACKGROUND, priority = 1, visible = true },
  })
  if A.introScene3Bg then
    Bg.setImage(BG_BACKGROUND, A.introScene3Bg, nil)
    Bg.setWrap(BG_BACKGROUND, 240, nil)
    Bg.show(BG_BACKGROUND)
  end
  if A.introScene3GengarAnim then
    Bg.setImage(BG_GENGAR, A.introScene3GengarAnim, nil)
    Bg.setWrap(BG_GENGAR, 256, 512)
    Bg.changeBgX(BG_GENGAR, 0x00001800, Bg.COORD_SET)
    Bg.changeBgY(BG_GENGAR, 0x0001F000, Bg.COORD_SET)
  end

  movie._s3Phase = "entrance"
  movie._s3State = 0
  movie._s3Timer = 0
  movie._bgScrollSlow = false
  movie._gengarBouncePaused = false
  movie._gengarBounceState = 0
  movie._gengarBounceTimer = 0
  movie._gengarEnter = { state = 0, moves = 0, speed = 0x400 }
  movie._gengarAtk = nil
  movie._gengarAttackLanded = false
  movie._gengarBaseXQ88 = 0x1800
  -- Full letterbox from frame 1 (skip pret WIN0 half-width wipe — scene reads as one piece).
  movie._winHalf = false
  movie._grassSpawned = false
  movie._s3NidoId = nil
  movie._s3Done = false

  -- Nidorino starts off-screen for entrance
  if A.introScene3Nidorino and movie.nidorinoQuads then
    local id, spr = Oam.createSprite({
      dims = Oam.SQUARE_64,
      priority = 1,
      image = A.introScene3Nidorino,
      quad = movie.nidorinoQuads[1],
      callback = SpriteCB_NidorinoEnter,
    }, 0, 100, 9)
    movie._s3NidoId = id
    if spr then
      spr._movie = movie
      -- StartNidorinoEntrance(0, 180, 52)
      spr.data[1] = 0 * 16
      spr.data[2] = math.floor((180 - 0) * 16 / 52)
      spr.data[4] = 180
      spr.data[5] = 0
      spr.y = 100
    end
  end
end

function S3.scissor(movie)
  -- Letterbox only (pret WIN0V 32 .. HEIGHT-32). Full width from the start.
  return { x = 0, y = 32, w = Display.W, h = Display.H - 64 }
end

function S3.update(movie, dt)
  -- Frame-accurate 60Hz
  movie._s3Accum = (movie._s3Accum or 0) + dt
  local frameDt = 1 / 60
  local didFrame = false
  while movie._s3Accum >= frameDt do
    movie._s3Accum = movie._s3Accum - frameDt
    didFrame = true
    S3._tick(movie)
    Oam.animateSprites()
  end
  return movie._s3Done
end

function S3._tick(movie)
  local A = movie.assets
  -- BG scroll
  if movie._bgScrollSlow then
    Bg.changeBgX(BG_BACKGROUND, 0x020, Bg.COORD_SUB)
  else
    Bg.changeBgX(BG_BACKGROUND, 0x400, Bg.COORD_SUB)
  end

  if movie._s3Phase == "entrance" then
    local st = movie._s3State
    if st == 0 then
      -- Show gengar once tiles "ready"
      Bg.show(BG_GENGAR)
      movie._s3State = 1
      movie._s3Timer = 0
    elseif st == 1 then
      movie._s3Timer = movie._s3Timer + 1
      local gengarDone = tickGengarEnter(movie)
      tickGengarBounce(movie)
      if movie._s3Timer == 16 and not movie._grassSpawned and A.introScene3Grass then
        movie._grassSpawned = true
        local id, spr = Oam.createSprite({
          dims = Oam.HRECT_64x32,
          priority = 0,
          image = A.introScene3Grass,
          quad = movie.scene3GrassQuad,
          callback = SpriteCB_Grass,
        }, 296, 112, 7)
        if spr then spr._movie = movie end
        movie._s3GrassId = id
      end
      if gengarDone and not nidoRunning(movie) then
        movie._s3Phase = "fight"
        movie._s3State = 0
        movie._s3Timer = 0
      end
    end
    return
  end

  -- Fight state machine (IntroCB_Scene3_Fight)
  local st = movie._s3State
  movie._s3Timer = movie._s3Timer + 1

  if movie._gengarAtk then
    tickGengarAttack(movie)
  else
    tickGengarBounce(movie)
  end

  if st == 0 then
    movie._s3Timer = 0
    movie._s3State = 1
  elseif st == 1 then
    if movie._s3Timer > 30 then
      startNidorinoCry(movie)
      movie._s3State = 2
    end
  elseif st == 2 then
    if not nidoRunning(movie) then
      movie._s3Timer = 0
      movie._s3State = 3
    end
  elseif st == 3 then
    if movie._s3Timer > 30 then
      movie._gengarBouncePaused = true
      movie._gengarAttackLanded = false
      movie._gengarAtk = {
        state = 0,
        timer = 0,
        sinIdx = 64,
        baseXQ88 = movie._gengarBaseXQ88 or 0xEF00,
        frame = 0,
        multX = 32,
        multY = 6,
      }
      movie._s3Timer = 0
      movie._s3State = 4
    end
  elseif st == 4 then
    if movie._gengarAttackLanded then
      startNidorinoRecoil(movie)
      movie._s3State = 5
    end
  elseif st == 5 then
    if not nidoRunning(movie) then
      movie._gengarBouncePaused = false
      movie._s3Timer = 0
      movie._s3State = 6
    end
  elseif st == 6 then
    if movie._s3Timer > 16 then
      startNidorinoHop(movie, 8, 12, 5)
      movie._s3State = 7
    end
  elseif st == 7 then
    if not nidoRunning(movie) then
      startNidorinoHop(movie, 8, 12, 5)
      movie._s3State = 8
    end
  elseif st == 8 then
    if not nidoRunning(movie) then
      movie._s3Timer = 0
      movie._s3State = 9
    end
  elseif st == 9 then
    if movie._s3Timer > 20 then
      startNidorinoAttack(movie)
      movie._s3Timer = 0
      movie._s3State = 10
    end
  elseif st == 10 then
    -- Wait for attack leap to finish, then fade out to title
    if not nidoRunning(movie) then
      movie._s3Timer = 0
      movie._s3State = 11
    end
  elseif st == 11 then
    -- Approximate pret white/black fade lead-in
    if movie._s3Timer > 48 then
      movie._s3Done = true
    end
  end
end

return S3
