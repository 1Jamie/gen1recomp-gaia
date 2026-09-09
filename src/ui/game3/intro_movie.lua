-- Game3 Intro — pokefirered/src/intro.c on shared Bg + Oam hardware.
-- Phases/timing stay here; compositing is Display.composeHardware (BG×OBJ priority).

local Display = require("src.core.game3.display")
local Audio = require("src.core.game3.audio")
local Bg = require("src.core.game3.bg")
local Oam = require("src.core.game3.oam")
local IntroScene3 = require("src.ui.game3.intro_scene3")

local IntroMovie = {}
IntroMovie.__index = IntroMovie

IntroMovie.PHASE = {
  COPYRIGHT = "copyright",
  GF_OPEN = "gf_open",
  GF_STAR = "gf_star",
  GF_REVEAL = "gf_reveal",
  GF_HOLD = "gf_hold",
  SCENE1 = "scene1",
  SCENE2_WIDE = "scene2_wide",
  SCENE2_CLOSE = "scene2_close", -- both close-ups + orange bg (pret Scene2_Task_PanMons)
  SCENE3_FIGHT = "scene3_fight",
  FADE_OUT = "fade_out",
  DONE = "done",
}

-- pret BG ids (re-inited per scene)
local BG_GF_TEXT_LOGO = 2
local BG_GF_BACKGROUND = 3
local BG_SCENE1_GRASS = 0
local BG_SCENE1_BACKGROUND = 1
local BG_SCENE2_PLANTS = 0
local BG_SCENE2_NIDORINO = 1
local BG_SCENE2_GENGAR = 2
local BG_SCENE2_BACKGROUND = 3

local SCENE1_FRAME_PX = 128
local SCENE1_VIEW_W, SCENE1_VIEW_H = 256, 128
local SCENE1_DRAW_Y = 16

local U32 = 4294967296
local RAND_MULT = 1103515245
local function mulU32(a, b)
  local aL, aH = a % 65536, math.floor(a / 65536) % 65536
  local bL, bH = b % 65536, math.floor(b / 65536) % 65536
  return (aL * bL + ((aL * bH + aH * bL) % 65536) * 65536) % U32
end
local function isoRandomize1(seed)
  return (mulU32(seed, RAND_MULT) + 24691) % U32
end
local function sineTableY2(sinIdx)
  local idx = (math.floor(sinIdx / 16) + 64) % 256
  local q88 = math.floor(math.sin(idx * math.pi / 128) * 256 + 0.5)
  return math.floor(q88 / 32)
end

local STAR_SPEED_X, STAR_SPEED_Y = 96, 16
local SPARKLE_SPAWN_RATE = 8
local SPARKLE_FLICKER_AT = 90
local SPARKLE_DESTROY_AT = 120
local SPARKLE_XMOD_MASK = 0x07
local STAR_RNG_SEED0 = 354128453

local TEXT_SPARKLE_COORDS = {
  { 72, 80 }, { 136, 74 }, { 168, 80 }, { 120, 80 }, { 104, 86 },
  { 88, 74 }, { 184, 74 }, { 56, 86 }, { 152, 86 },
}

-- Module ctx for sprite callbacks (AnimateSprites has no IntroMovie self).
local CTX = {
  movie = nil,
  sparkleYMod = 0,
  smallQuads = nil,
  bigQuads = nil,
  smallImg = nil,
  bigImg = nil,
}

local function destroyId(id)
  if id ~= nil then Oam.destroySprite(id) end
end

local function clearHardware(movie)
  Oam.destroyAll()
  Bg.reset()
  if movie then
    movie._starId = nil
    movie._logoId = nil
    movie._s2GengarId = nil
    movie._s2NidoId = nil
    movie._s3NidoId = nil
    movie._s3GrassIds = nil
    movie._swipeIds = nil
    movie._dustId = nil
  end
  CTX.sparkleYMod = 0
end

------------------------------------------------------------------------
-- Sprite callbacks (pret SpriteCB_*)
------------------------------------------------------------------------

local function SpriteCB_SparklesSmall_Star(sprite)
  -- data: 1 baseX, 2 baseY, 3 speedX, 4 speedY, 5 fallSpeed, 6 fallDist, 7 timer, 8 animTimer
  sprite.data[1] = sprite.data[1] + sprite.data[3]
  sprite.data[2] = sprite.data[2] + sprite.data[4]
  sprite.data[5] = sprite.data[5] + 1
  sprite.data[6] = sprite.data[6] + sprite.data[5]
  sprite.data[7] = sprite.data[7] + 1
  sprite.x = math.floor(sprite.data[1] / 32) % 65536
  sprite.y = math.floor(sprite.data[2] / 32)
  sprite.y2 = 0
  if sprite.data[7] > SPARKLE_FLICKER_AT then
    sprite.invisible = not sprite.invisible
    if sprite.data[7] > SPARKLE_DESTROY_AT then
      Oam.destroySprite(sprite._id)
      return
    end
  end
  local yy = sprite.y + sprite.y2
  if yy < 0 or yy > Display.H then
    Oam.destroySprite(sprite._id)
    return
  end
  sprite.data[8] = (sprite.data[8] or 0) + 1
  if sprite.data[8] >= 4 then
    sprite.data[8] = 0
    local frame = ((sprite._animFrame or 0) + 1) % 4
    sprite._animFrame = frame
    if CTX.smallQuads then
      sprite.quad = CTX.smallQuads[frame + 1]
    end
  end
end

local function createStarSparkleOam(x, y, random)
  local xMod = (random % (SPARKLE_XMOD_MASK + 1)) + 2
  local yMod = CTX.sparkleYMod
  CTX.sparkleYMod = CTX.sparkleYMod + 1
  if CTX.sparkleYMod > 3 then CTX.sparkleYMod = -3 end
  x = x + xMod
  y = y + yMod
  if x <= 0 or x >= Display.W or not CTX.smallImg then return end
  local id, spr = Oam.createSprite({
    dims = Oam.SQUARE_8,
    priority = 2,
    image = CTX.smallImg,
    quad = CTX.smallQuads and CTX.smallQuads[1],
    callback = SpriteCB_SparklesSmall_Star,
  }, x, y, 1)
  if not spr then return end
  spr._id = id
  spr._animFrame = 0
  spr.data[1] = x * 32
  spr.data[2] = y * 32
  spr.data[3] = 1 * xMod
  spr.data[4] = 1 * yMod
  spr.data[5] = 0
  spr.data[6] = 0
  spr.data[7] = 0
  spr.data[8] = 0
end

local function SpriteCB_Star(sprite)
  -- data: 1 baseX, 2 baseY, 3 speedX, 4 speedY, 5 sinIdx, 6 sparkleTimer, 7 rngSeed
  sprite.data[1] = sprite.data[1] - sprite.data[3]
  sprite.data[2] = sprite.data[2] + sprite.data[4]
  sprite.data[5] = sprite.data[5] + 48
  sprite.x = math.floor(sprite.data[1] / 16)
  sprite.y = math.floor(sprite.data[2] / 16)
  sprite.y2 = sineTableY2(sprite.data[5])
  sprite.data[6] = sprite.data[6] + 1
  if sprite.data[6] % SPARKLE_SPAWN_RATE ~= 0 then
    sprite.data[7] = isoRandomize1(sprite.data[7])
    local random = math.floor(sprite.data[7] / 65536) % 65536
    createStarSparkleOam(sprite.x, sprite.y + sprite.y2, random)
  end
  if sprite.x < -8 then
    Oam.destroySprite(sprite._id)
    local m = CTX.movie
    if m then
      m._starId = nil
      m.starActive = false
    end
  end
end

local function SpriteCB_SparklesSmall_Name(sprite)
  -- data: 1 state, 2 baseY, 3 animTimer, 4 loops, 5 destroyTimer, 6 frameTimer, 7 animFrame
  if sprite.data[3] > 0 then
    sprite.data[3] = sprite.data[3] - 1
    sprite.data[2] = sprite.data[2] + 1
    sprite.y = math.floor(sprite.data[2] / 16)
    if sprite.y > 86 then
      sprite.y = 74
      sprite.data[2] = 74 * 16
    end
    sprite.data[6] = (sprite.data[6] or 0) + 1
    if sprite.data[6] >= 4 then
      sprite.data[6] = 0
      local af = sprite.data[7] or 0
      if af < 3 then
        sprite.data[7] = af + 1
      else
        if sprite.data[1] == 0 then
          sprite.x = sprite.x + 26
          if sprite.x > 188 then
            sprite.x = (188 * 2) - sprite.x
            sprite.data[1] = 1
          end
        else
          sprite.x = sprite.x - 26
          if sprite.x < 52 then
            sprite.x = (52 * 2) - sprite.x
            sprite.data[1] = 0
          end
        end
        sprite.data[7] = 0
        sprite.data[4] = (sprite.data[4] or 0) + 1
      end
      if CTX.smallQuads then
        sprite.quad = CTX.smallQuads[(sprite.data[7] or 0) + 1]
      end
    end
  else
    sprite.data[5] = (sprite.data[5] or 0) + 1
    sprite.data[2] = sprite.data[2] + 4
    sprite.y = math.floor(sprite.data[2] / 16)
    if sprite.data[5] > 50 then
      Oam.destroySprite(sprite._id)
    end
  end
end

local function SpriteCB_SparklesBig(sprite)
  sprite.data[1] = (sprite.data[1] or 0) + 1
  if sprite.data[1] >= 8 then
    sprite.data[1] = 0
    local af = (sprite.data[2] or 0) + 1
    sprite.data[2] = af
    if af >= 4 then
      Oam.destroySprite(sprite._id)
      return
    end
    if CTX.bigQuads then
      sprite.quad = CTX.bigQuads[af + 1]
    end
  end
end

local function spawnNameSparkleSmall(x, y)
  if not CTX.smallImg then return end
  local id, spr = Oam.createSprite({
    dims = Oam.SQUARE_8,
    priority = 2,
    image = CTX.smallImg,
    quad = CTX.smallQuads and CTX.smallQuads[1],
    callback = SpriteCB_SparklesSmall_Name,
  }, x, y, 2)
  if not spr then return end
  spr._id = id
  spr.data[1] = 0
  spr.data[2] = y * 16
  spr.data[3] = 120
  spr.data[4] = 0
  spr.data[5] = 0
  spr.data[6] = 0
  spr.data[7] = 0
end

local function spawnNameSparkleBig(x, y)
  if not CTX.bigImg then return end
  local id, spr = Oam.createSprite({
    dims = Oam.SQUARE_32,
    priority = 2,
    image = CTX.bigImg,
    quad = CTX.bigQuads and CTX.bigQuads[1],
    callback = SpriteCB_SparklesBig,
  }, x, y, 3)
  if not spr then return end
  spr._id = id
  spr.data[1] = 0
  spr.data[2] = 0
end

------------------------------------------------------------------------
-- Scene hardware setup
------------------------------------------------------------------------

local function setupCopyright(movie)
  clearHardware(movie)
  local A = movie.assets
  Bg.initFromTemplates({
    { bg = 0, priority = 0, visible = true },
  })
  if A.introCopyright then
    Bg.setImage(0, A.introCopyright, nil)
    Bg.show(0)
  end
end

local function setupGf(movie)
  clearHardware(movie)
  local A = movie.assets
  Bg.initFromTemplates({
    { bg = BG_GF_BACKGROUND, priority = 3, visible = true },
    { bg = BG_GF_TEXT_LOGO, priority = 2, visible = false },
  })
  if A.introGfBg then
    Bg.setImage(BG_GF_BACKGROUND, A.introGfBg, nil)
    Bg.show(BG_GF_BACKGROUND)
  end
  CTX.movie = movie
  CTX.smallImg = A.introSparklesSmall
  CTX.bigImg = A.introSparklesBig
  CTX.smallQuads = movie.sparklesSmallQuads
  CTX.bigQuads = movie.sparklesBigQuads
end

local function createStarSprite(movie)
  local A = movie.assets
  if not A.introStar then return end
  destroyId(movie._starId)
  local id, spr = Oam.createSprite({
    dims = Oam.SQUARE_16,
    priority = 2,
    image = A.introStar,
    callback = SpriteCB_Star,
  }, 248, 55, 0)
  if not spr then return end
  spr._id = id
  spr.data[1] = 248 * 16
  spr.data[2] = 55 * 16
  spr.data[3] = STAR_SPEED_X
  spr.data[4] = STAR_SPEED_Y
  spr.data[5] = 0
  spr.data[6] = 0
  spr.data[7] = STAR_RNG_SEED0
  movie._starId = id
  movie.starActive = true
  CTX.sparkleYMod = 0
end

local function setupScene1(movie)
  clearHardware(movie)
  local A = movie.assets
  Bg.initFromTemplates({
    { bg = BG_SCENE1_GRASS, priority = 0, visible = true },
    { bg = BG_SCENE1_BACKGROUND, priority = 0, visible = true },
  })
  -- Same pri: lower BG index in front → grass (0) over bg (1)
  if A.introScene1Bg and movie.scene1BgQuads then
    Bg.setImage(BG_SCENE1_BACKGROUND, A.introScene1Bg, movie.scene1BgQuads[1])
    Bg.setOffset(BG_SCENE1_BACKGROUND, 0, SCENE1_DRAW_Y)
    Bg.show(BG_SCENE1_BACKGROUND)
  end
  if A.introScene1Grass and movie.scene1GrassQuads then
    Bg.setImage(BG_SCENE1_GRASS, A.introScene1Grass, movie.scene1GrassQuads[1])
    Bg.setOffset(BG_SCENE1_GRASS, 0, SCENE1_DRAW_Y)
    Bg.show(BG_SCENE1_GRASS)
  end
end

local function setupScene2Wide(movie)
  clearHardware(movie)
  local A = movie.assets
  -- pret sBgTemplates_Scene2
  Bg.initFromTemplates({
    { bg = BG_SCENE2_PLANTS, priority = 0, visible = true },
    { bg = BG_SCENE2_NIDORINO, priority = 1, visible = false },
    { bg = BG_SCENE2_GENGAR, priority = 2, visible = false },
    { bg = BG_SCENE2_BACKGROUND, priority = 3, visible = true },
  })
  if A.introScene2Bg and movie.scene2BgWideQuad then
    Bg.setImage(BG_SCENE2_BACKGROUND, A.introScene2Bg, movie.scene2BgWideQuad)
    Bg.setWrap(BG_SCENE2_BACKGROUND, 256, nil)
    Bg.show(BG_SCENE2_BACKGROUND)
  end
  if A.introScene2Plants then
    Bg.setImage(BG_SCENE2_PLANTS, A.introScene2Plants, nil)
    Bg.setWrap(BG_SCENE2_PLANTS, 240, nil)
    Bg.show(BG_SCENE2_PLANTS)
  end
  -- sOam_Scene2_Mons priority 1 — behind plants (BG pri 0)
  if A.introScene2Gengar then
    local id = select(1, Oam.createSprite({
      dims = Oam.SQUARE_64,
      priority = 1,
      image = A.introScene2Gengar,
    }, 72, 80, 12))
    movie._s2GengarId = id
  end
  if A.introScene2Nidorino then
    local id = select(1, Oam.createSprite({
      dims = Oam.SQUARE_64,
      priority = 1,
      image = A.introScene2Nidorino,
    }, 168, 80, 11))
    movie._s2NidoId = id
  end
end

local function setupScene2Close(movie)
  clearHardware(movie)
  local A = movie.assets
  -- pret case 4: hide plants, show both close BGs + lower-half forest bg
  Bg.initFromTemplates({
    { bg = BG_SCENE2_PLANTS, priority = 0, visible = false },
    { bg = BG_SCENE2_NIDORINO, priority = 1, visible = true },
    { bg = BG_SCENE2_GENGAR, priority = 2, visible = true },
    { bg = BG_SCENE2_BACKGROUND, priority = 3, visible = true },
  })
  if A.introScene2Bg and movie.scene2BgCloseQuad then
    -- ChangeBgY(BACKGROUND, 0x10000) → lower half of 512 sheet
    Bg.setImage(BG_SCENE2_BACKGROUND, A.introScene2Bg, movie.scene2BgCloseQuad)
    Bg.show(BG_SCENE2_BACKGROUND)
  end
  -- Initial scrolls from IntroCB_Scene2 case 1 (applied before show in pret)
  if A.introScene2GengarClose then
    Bg.setImage(BG_SCENE2_GENGAR, A.introScene2GengarClose, nil)
    Bg.setWrap(BG_SCENE2_GENGAR, 256, 256)
    Bg.changeBgY(BG_SCENE2_GENGAR, 0x0001CE00, Bg.COORD_SET)
    Bg.show(BG_SCENE2_GENGAR)
  end
  if A.introScene2NidorinoClose then
    Bg.setImage(BG_SCENE2_NIDORINO, A.introScene2NidorinoClose, nil)
    Bg.setWrap(BG_SCENE2_NIDORINO, 256, 256)
    Bg.changeBgY(BG_SCENE2_NIDORINO, 0x00002800, Bg.COORD_SET)
    Bg.show(BG_SCENE2_NIDORINO)
  end
  movie.scene2CloseFrames = 0
end

local function setupScene3(movie)
  clearHardware(movie)
  IntroScene3.buildQuads(movie)
  IntroScene3.setup(movie)
end

------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------

function IntroMovie.new(assets)
  assets = assets or {}
  local self = setmetatable({
    assets = assets,
    phase = IntroMovie.PHASE.COPYRIGHT,
    timer = 0,
    state = 0,
    fadeAlpha = 0,
    fadeDir = 0,
    fadeSpeed = 2.0,
    nextPhase = nil,
    gfWindowHalfH = 0,
    starActive = false,
    gfFrameAccum = 0,
    nameSparkleIdx = 0,
    nameSparkleLoops = 0,
    nameSparkleTimer = 0,
    nameBigSparkleIdx = 0,
    nameBigSparkleCount = 0,
    nameBigSparkleTimer = 0,
    nameBigActive = false,
    logoAlpha = 0,
    textAlpha = 0,
    presentsAlpha = 0,
    scene1GrassFrame = 0,
    scene1BgFrame = 0,
    scene1GrassTimer = 0,
    scene1BgTimer = 0,
    scene1Exiting = false,
    scene1GrassScrollY = 0,
    scene2X = 0,
    scene2CloseFrames = 0,
    isDone = false,
    _hwPhase = nil,
  }, IntroMovie)

  if love and love.graphics and love.graphics.newQuad then
    self.sparklesBigQuads = {}
    for i = 0, 3 do
      self.sparklesBigQuads[i + 1] = love.graphics.newQuad(0, i * 32, 32, 32, 32, 128)
    end
    self.sparklesSmallQuads = {
      love.graphics.newQuad(0, 0, 8, 8, 16, 16),
      love.graphics.newQuad(8, 0, 8, 8, 16, 16),
      love.graphics.newQuad(0, 8, 8, 8, 16, 16),
      love.graphics.newQuad(8, 8, 8, 8, 16, 16),
    }
    self.scene1GrassQuads = {}
    self.scene1BgQuads = {}
    for i = 0, 2 do
      local y = i * SCENE1_FRAME_PX
      self.scene1GrassQuads[i + 1] = love.graphics.newQuad(0, y, SCENE1_VIEW_W, SCENE1_VIEW_H, SCENE1_VIEW_W, 512)
      self.scene1BgQuads[i + 1] = love.graphics.newQuad(0, y, SCENE1_VIEW_W, SCENE1_VIEW_H, SCENE1_VIEW_W, 512)
    end
    self.scene2BgWideQuad = love.graphics.newQuad(0, 0, 256, 160, 256, 512)
    self.scene2BgCloseQuad = love.graphics.newQuad(0, 256, 256, 160, 256, 512)
    IntroScene3.buildQuads(self)
  end

  CTX.movie = self
  setupCopyright(self)
  self._hwPhase = IntroMovie.PHASE.COPYRIGHT
  return self
end

function IntroMovie:skip()
  if self.phase ~= IntroMovie.PHASE.DONE and self.phase ~= IntroMovie.PHASE.FADE_OUT then
    self.phase = IntroMovie.PHASE.FADE_OUT
    self.nextPhase = IntroMovie.PHASE.DONE
    self.fadeDir = 1
    self.fadeSpeed = 5.0
  end
end

local function ensureHardware(self)
  local P = IntroMovie.PHASE
  local ph = self.phase
  if ph == self._hwPhase then return end
  -- Group GF phases on same BG setup
  local gf = (ph == P.GF_OPEN or ph == P.GF_STAR or ph == P.GF_REVEAL or ph == P.GF_HOLD)
  local prevGf = (self._hwPhase == P.GF_OPEN or self._hwPhase == P.GF_STAR
    or self._hwPhase == P.GF_REVEAL or self._hwPhase == P.GF_HOLD)
  if gf and prevGf then
    self._hwPhase = ph
    return
  end
  if ph == P.COPYRIGHT then
    setupCopyright(self)
  elseif gf then
    setupGf(self)
  elseif ph == P.SCENE1 then
    setupScene1(self)
  elseif ph == P.SCENE2_WIDE then
    setupScene2Wide(self)
  elseif ph == P.SCENE2_CLOSE then
    setupScene2Close(self)
  elseif ph == P.SCENE3_FIGHT then
    setupScene3(self)
  elseif ph == P.DONE or ph == P.FADE_OUT then
    clearHardware(self)
  end
  self._hwPhase = ph
end

local function tick60(self, fn)
  self.gfFrameAccum = (self.gfFrameAccum or 0) + (self._dt or 1 / 60)
  local frameDt = 1 / 60
  while self.gfFrameAccum >= frameDt do
    self.gfFrameAccum = self.gfFrameAccum - frameDt
    fn()
    Oam.animateSprites()
  end
end

function IntroMovie:update(input, dt)
  dt = dt or (1 / 60)
  self._dt = dt
  self.timer = self.timer + dt

  if input and input.wasPressed and (input:wasPressed("a") or input:wasPressed("start") or input:wasPressed("select")) then
    self:skip()
  end

  if self.fadeDir ~= 0 then
    self.fadeAlpha = self.fadeAlpha + self.fadeDir * self.fadeSpeed * dt
    if self.fadeDir > 0 and self.fadeAlpha >= 1.0 then
      self.fadeAlpha = 1.0
      self.fadeDir = 0
      if self.nextPhase then
        self.phase = self.nextPhase
        self.timer = 0
        self.state = 0
        self.nextPhase = nil
        if self.phase == IntroMovie.PHASE.DONE then
          clearHardware(self)
          self.isDone = true
          return true
        end
      end
    elseif self.fadeDir < 0 and self.fadeAlpha <= 0 then
      self.fadeAlpha = 0
      self.fadeDir = 0
    end
  end

  ensureHardware(self)
  local P = IntroMovie.PHASE

  if self.phase == P.COPYRIGHT then
    if self.timer > 2.4 and self.fadeDir == 0 then
      self.fadeDir = 1
      self.nextPhase = P.GF_OPEN
      self.fadeSpeed = 3.0
    end

  elseif self.phase == P.GF_OPEN then
    if self.state == 0 then
      self.fadeAlpha = 0
      self.fadeDir = 0
      self.gfWindowHalfH = 0
      -- pret: music starts in IntroCB_GF_Star (PlaySE(MUS_GAME_FREAK)), not on open.
      self.state = 1
    elseif self.state == 1 then
      self.gfWindowHalfH = math.min(48, self.gfWindowHalfH + 480 * dt)
      if self.gfWindowHalfH >= 48 then
        self.phase = P.GF_STAR
        self.timer = 0
        self.state = 0
        self.gfFrameAccum = 0
        self.nameSparkleIdx = 0
        self.nameSparkleLoops = 0
        self.nameSparkleTimer = 0
        self.nameBigActive = false
        createStarSprite(self)
        Audio.playSong(321) -- MUS_GAME_FREAK (twinkles live in this BGM)
      end
    end

  elseif self.phase == P.GF_STAR then
    tick60(self, function()
      if self.state >= 1 then
        self.nameSparkleTimer = self.nameSparkleTimer + 1
        if self.nameSparkleTimer > 6 and self.nameSparkleLoops <= 1 then
          self.nameSparkleTimer = 0
          local c = TEXT_SPARKLE_COORDS[self.nameSparkleIdx + 1]
          if c then spawnNameSparkleSmall(c[1], c[2]) end
          self.nameSparkleIdx = self.nameSparkleIdx + 1
          if self.nameSparkleIdx >= #TEXT_SPARKLE_COORDS then
            self.nameSparkleLoops = self.nameSparkleLoops + 1
            if self.nameSparkleLoops <= 1 then self.nameSparkleIdx = 0 end
          end
        end
      end
    end)
    if self.timer >= 0.5 and self.state == 0 then
      self.state = 1
      self.nameSparkleTimer = 0
      self.nameSparkleIdx = 0
      self.nameSparkleLoops = 0
    end
    if self.timer >= 2.0 and self.state == 1 then
      self.nameBigActive = true
      self.nameBigSparkleIdx = 0
      self.nameBigSparkleCount = 0
      self.nameBigSparkleTimer = 0
      self.phase = P.GF_REVEAL
      self.timer = 0
      self.state = 0
    end

  elseif self.phase == P.GF_REVEAL then
    self.textAlpha = math.min(1.0, self.textAlpha + 2.0 * dt)
    if self.timer > 0.9 then
      self.logoAlpha = math.min(1.0, self.logoAlpha + 3.0 * dt)
    end
    if self.timer > 1.4 then
      self.presentsAlpha = math.min(1.0, self.presentsAlpha + 3.0 * dt)
    end
    tick60(self, function()
      if self.nameBigActive then
        if self.nameBigSparkleTimer == 0 then
          local c = TEXT_SPARKLE_COORDS[self.nameBigSparkleIdx + 1]
          if c then spawnNameSparkleBig(c[1], c[2]) end
          self.nameBigSparkleIdx = self.nameBigSparkleIdx + 4
          if self.nameBigSparkleIdx >= #TEXT_SPARKLE_COORDS then
            self.nameBigSparkleIdx = self.nameBigSparkleIdx - #TEXT_SPARKLE_COORDS
          end
          self.nameBigSparkleCount = self.nameBigSparkleCount + 1
          if self.nameBigSparkleCount >= #TEXT_SPARKLE_COORDS then
            self.nameBigActive = false
          end
        end
        self.nameBigSparkleTimer = self.nameBigSparkleTimer + 1
        if self.nameBigSparkleTimer > 9 then self.nameBigSparkleTimer = 0 end
      end
    end)
    if self.timer > 2.8 then
      self.phase = P.GF_HOLD
      self.timer = 0
    end

  elseif self.phase == P.GF_HOLD then
    tick60(self, function() end)
    if self.timer > 0.5 and self.fadeDir == 0 then
      self.fadeDir = 1
      self.nextPhase = P.SCENE1
      self.fadeSpeed = 3.0
    end

  elseif self.phase == P.SCENE1 then
    if self.state == 0 then
      Audio.playSong(277)
      self.fadeAlpha = 0
      self.fadeDir = 0
      self.scene1GrassFrame = 0
      self.scene1BgFrame = 0
      self.scene1GrassTimer = 0
      self.scene1BgTimer = 0
      self.scene1Exiting = false
      self.scene1GrassScrollY = 0
      self.state = 1
    end
    self.scene1GrassTimer = self.scene1GrassTimer + dt
    if self.scene1GrassTimer > 6 / 60 then
      self.scene1GrassTimer = 0
      self.scene1GrassFrame = (self.scene1GrassFrame + 1) % 3
      Bg.setQuad(BG_SCENE1_GRASS, self.scene1GrassQuads[self.scene1GrassFrame + 1])
    end
    if self.timer >= 20 / 60 and not self.scene1Exiting then
      self.scene1Exiting = true
    end
    if self.scene1Exiting then
      self.scene1BgTimer = self.scene1BgTimer + dt
      if self.scene1BgTimer > 4 / 60 then
        self.scene1BgTimer = 0
        if self.scene1BgFrame < 2 then
          self.scene1BgFrame = self.scene1BgFrame + 1
          Bg.setQuad(BG_SCENE1_BACKGROUND, self.scene1BgQuads[self.scene1BgFrame + 1])
        end
      end
      self.scene1GrassScrollY = self.scene1GrassScrollY + 1.125 * 60 * dt
      Bg.setOffset(BG_SCENE1_GRASS, 0, SCENE1_DRAW_Y - self.scene1GrassScrollY)
    end
    if self.timer >= 30 / 60 then
      self.phase = P.SCENE2_WIDE
      self.timer = 0
      self.state = 0
      self.scene2X = 0
    end

  elseif self.phase == P.SCENE2_WIDE then
    -- pret: ChangeBgX(BG, 0x0E0, SUB), ChangeBgX(PLANTS, 0x110, ADD) per frame
    local frames = dt * 60
    Bg.changeBgX(BG_SCENE2_BACKGROUND, 0x0E0 * frames, Bg.COORD_SUB)
    Bg.changeBgX(BG_SCENE2_PLANTS, 0x110 * frames, Bg.COORD_ADD)
    self.scene2X = self.scene2X - 35 * dt
    -- pret case 4: after 60 frames → close-ups
    if self.timer > 1.0 then
      self.phase = P.SCENE2_CLOSE
      self.timer = 0
      self.state = 0
      self.scene2CloseFrames = 0
    end

  elseif self.phase == P.SCENE2_CLOSE then
    -- Scene2_Task_PanMons: both BGs visible; Gengar up, Nidorino down
    self.gfFrameAccum = (self.gfFrameAccum or 0) + dt
    local frameDt = 1 / 60
    while self.gfFrameAccum >= frameDt do
      self.gfFrameAccum = self.gfFrameAccum - frameDt
      Bg.changeBgY(BG_SCENE2_GENGAR, 0x020, Bg.COORD_ADD)
      Bg.changeBgY(BG_SCENE2_NIDORINO, 0x024, Bg.COORD_SUB)
      self.scene2CloseFrames = (self.scene2CloseFrames or 0) + 1
    end
    -- pret case 6: 60 frames then Scene3
    if (self.scene2CloseFrames or 0) >= 60 or self.timer > 1.05 then
      self.phase = P.SCENE3_FIGHT
      self.timer = 0
      self.state = 0
    end

  elseif self.phase == P.SCENE3_FIGHT then
    if IntroScene3.update(self, dt) then
      if self.fadeDir == 0 then
        self.fadeDir = 1
        self.nextPhase = P.DONE
        self.fadeSpeed = 3.5
      end
    end
  end

  return self.isDone
end

function IntroMovie:draw()
  local P = IntroMovie.PHASE
  local A = self.assets
  local W, H = Display.W, Display.H

  ensureHardware(self)

  local scissor = nil
  if self.phase == P.GF_OPEN or self.phase == P.GF_STAR
      or self.phase == P.GF_REVEAL or self.phase == P.GF_HOLD then
    local midY = H / 2
    local topY = midY - self.gfWindowHalfH
    local boxH = math.max(0, self.gfWindowHalfH * 2)
    scissor = { x = 0, y = topY, w = W, h = boxH }
  elseif self.phase == P.SCENE3_FIGHT then
    scissor = IntroScene3.scissor(self)
  end

  Display.composeHardware({
    clear = { 0, 0, 0, 1 },
    animate = false, -- already ticked in update @60Hz
    build = true,
    scissor = scissor,
    overlay = function()
      -- GF name/logo/presents: pret BG blend approximated with alpha blit
      if self.phase == P.GF_REVEAL or self.phase == P.GF_HOLD
          or (self.phase == P.GF_STAR and self.textAlpha > 0) then
        if scissor then
          love.graphics.setScissor(scissor.x, scissor.y, scissor.w, scissor.h)
        end
        if self.logoAlpha > 0 and A.introGfLogo then
          love.graphics.setColor(1, 1, 1, self.logoAlpha)
          love.graphics.draw(A.introGfLogo, 104, 38)
        end
        if self.textAlpha > 0 and A.introGfText then
          love.graphics.setColor(1, 1, 1, self.textAlpha)
          love.graphics.draw(A.introGfText, 48, 72)
        end
        if self.presentsAlpha > 0 and A.introPresents then
          love.graphics.setColor(1, 1, 1, self.presentsAlpha)
          love.graphics.draw(A.introPresents, 88, 108)
        end
        love.graphics.setColor(1, 1, 1, 1)
        if scissor then love.graphics.setScissor() end
      end
      if self.fadeAlpha > 0 then
        love.graphics.setColor(0, 0, 0, self.fadeAlpha)
        love.graphics.rectangle("fill", 0, 0, W, H)
        love.graphics.setColor(1, 1, 1, 1)
      end
    end,
  })
end

function IntroMovie:destroy()
  clearHardware(self)
end

return IntroMovie
