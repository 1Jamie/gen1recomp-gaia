-- FireRed title screen (pokefirered/src/title_screen.c RUN scene) on Bg + Oam.
-- Layering (front→back): logo BG0 → mon BG1 → copyright BG2 → flames OBJ3 → border BG3 → backdrop.

local Display = require("src.core.game3.display")
local Bg = require("src.core.game3.bg")
local Oam = require("src.core.game3.oam")

local Title = {}

local BG_LOGO = 0
local BG_MON = 1
local BG_COPYRIGHT = 2
local BG_BORDER = 3

-- BackgroundPals[0] — backdrop (firered/background.pal)
local BACKDROP = { 255 / 255, 255 / 255, 139 / 255, 1 }

local FLAME_X = { 4, 16, 26, 32, 48, 200, 216, 224, 232, 60, 76, 92, 108, 128, 144 }

local function mulU32(a, b)
  local aL, aH = a % 65536, math.floor(a / 65536) % 65536
  local bL, bH = b % 65536, math.floor(b / 65536) % 65536
  return (aL * bL + ((aL * bH + aH * bL) % 65536) * 65536) % 4294967296
end

local function titleRand(state)
  -- TitleScreen_rand approx (ISO LCG)
  state._rng = mulU32(state._rng or 30840, 1103515245) + 24691
  state._rng = state._rng % 4294967296
  return math.floor(state._rng / 65536) % 65536
end

local function SpriteCB_Flame(sprite)
  sprite.data[1] = sprite.data[1] - sprite.data[2] -- posX -= speedX
  sprite.x = math.floor(sprite.data[1] / 16)
  if sprite.x < -8 then
    Oam.destroySprite(sprite._id)
    return
  end
  sprite.data[3] = sprite.data[3] + sprite.data[4] -- posY += speedY
  sprite.y = math.floor(sprite.data[3] / 16)
  if sprite.y < 16 or sprite.y > 200 then
    Oam.destroySprite(sprite._id)
    return
  end
  -- Anim: tile steps 0,4,...,36 → 10 frames; durations ~3 then 6s
  sprite.data[5] = (sprite.data[5] or 0) + 1
  local af = sprite.data[6] or 0
  local dur = (af == 0) and 3 or 6
  if sprite.data[5] >= dur then
    sprite.data[5] = 0
    af = af + 1
    if af >= 10 then
      Oam.destroySprite(sprite._id)
      return
    end
    sprite.data[6] = af
    if sprite._quads then
      sprite.quad = sprite._quads[af + 1]
    end
  end
end

local function createFlame(state, x, y, xspeed, yspeed, visible)
  local img = state.assets and state.assets.titleFlames
  if not img or not state.flameQuads then return end
  local id, spr = Oam.createSprite({
    dims = Oam.SQUARE_16,
    priority = 3, -- behind BG0–2, above border BG3
    image = img,
    quad = state.flameQuads[1],
    callback = SpriteCB_Flame,
  }, x, y, 0)
  if not spr then return end
  spr._quads = state.flameQuads
  spr.data[1] = x * 16
  spr.data[2] = xspeed
  spr.data[3] = y * 16
  spr.data[4] = yspeed
  spr.data[5] = 0
  spr.data[6] = 0
  spr.invisible = not visible
end

function Title.buildQuads(state)
  if not (love and love.graphics and love.graphics.newQuad) then return end
  -- 10× 16×16 in 16×160 sheet (or 16×80 fallback → 5 frames)
  local img = state.assets and state.assets.titleFlames
  local sh = 160
  if img and img.getHeight then
    local ok, h = pcall(function() return img:getHeight() end)
    if ok and h then sh = h end
  end
  local n = math.floor(sh / 16)
  state.flameQuads = {}
  for i = 0, n - 1 do
    state.flameQuads[i + 1] = love.graphics.newQuad(0, i * 16, 16, 16, 16, sh)
  end
end

function Title.enter(state)
  Oam.destroyAll()
  Bg.reset()
  Title.buildQuads(state)

  local A = state.assets or {}
  Bg.initFromTemplates({
    { bg = BG_LOGO, priority = 0, visible = true },
    { bg = BG_MON, priority = 1, visible = true },
    { bg = BG_COPYRIGHT, priority = 2, visible = true },
    { bg = BG_BORDER, priority = 3, visible = true },
  })

  -- Border (back), then mon, copyright, logo (front)
  if state.titleBorder then
    Bg.setImage(BG_BORDER, state.titleBorder, nil)
    Bg.show(BG_BORDER)
  end
  if state.titleMon then
    Bg.setImage(BG_MON, state.titleMon, nil)
    Bg.show(BG_MON)
  end
  -- Copyright without press-start; press-start blinks separately at same pri via overlay
  if state.copyrightLayer then
    Bg.setImage(BG_COPYRIGHT, state.copyrightLayer, nil)
    Bg.show(BG_COPYRIGHT)
  end
  if state.titleLogo then
    Bg.setImage(BG_LOGO, state.titleLogo, nil)
    Bg.show(BG_LOGO)
  end

  -- Press Start: pret is on BG2 (behind logo/mon). Approximate with OAM pri 2.
  if state.pressStart then
    local id, spr = Oam.createSprite({
      dims = Oam.SQUARE_64,
      priority = 2,
      image = state.pressStart,
    }, 120, 80, 0)
    if spr then
      spr.centerToCornerVecX = -120
      spr.centerToCornerVecY = -80
      state._pressStartId = id
    end
  end

  state._titleActive = true
  state._rng = 30840
  state._flameState = 0
  state._flameTimer = 0
  state._flameDelay = 0
  state._flameOffsetX = 0
  state.flames = nil -- legacy list unused
end

function Title.leave(state)
  state._titleActive = false
  state._pressStartId = nil
  Oam.destroyAll()
  Bg.reset()
end

function Title.update(state, dt)
  if not state._titleActive then return end
  state._titleAccum = (state._titleAccum or 0) + dt
  local frameDt = 1 / 60
  while state._titleAccum >= frameDt do
    state._titleAccum = state._titleAccum - frameDt
    Title._tickFlames(state)
    Oam.animateSprites()
  end
  -- Blink Press Start (~60/30 frame periods ≈ 0.55s duty)
  if state._pressStartId then
    local on = (state.blink % 1.0) < 0.55
    Oam.setInvisible(state._pressStartId, not on)
  end
end

function Title._tickFlames(state)
  -- Task_FlameSpawner
  if state._flameState == 0 then
    state._rng = 30840
    state._flameState = 1
    return
  end
  state._flameTimer = (state._flameTimer or 0) + 1
  if state._flameTimer < (state._flameDelay or 0) then
    return
  end
  state._flameTimer = 0
  state._flameDelay = 18

  titleRand(state)
  local xspeed = (titleRand(state) % 4) - 2
  local yspeed = (titleRand(state) % 8) - 16
  local y = (titleRand(state) % 3) + 116
  local x = titleRand(state) % Display.W
  local show = (titleRand(state) % 16) >= 8
  createFlame(state, x, y, xspeed, yspeed, show)

  local ox = state._flameOffsetX or 0
  for i = 1, 15 do
    createFlame(state, ox + FLAME_X[i], y, xspeed, yspeed, true)
    xspeed = (titleRand(state) % 4) - 2
    yspeed = (titleRand(state) % 8) - 16
  end
  ox = ox + 1
  if ox > 3 then ox = 0 end
  state._flameOffsetX = ox
end

function Title.draw(_state)
  Display.composeHardware({
    clear = BACKDROP,
    animate = false,
    build = true,
  })
end

return Title
