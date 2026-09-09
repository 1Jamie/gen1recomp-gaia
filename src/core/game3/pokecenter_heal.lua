-- pret FLDEFF_POKECENTER_HEAL (field_effect.c FldEff_PokecenterHeal).
-- 1:1 screen OAM: CreateSprite coords are sprite CENTER; Love draws top-left
-- so we apply the same centerToCornerVec as pret sprite.c.

local PokecenterHeal = {}

PokecenterHeal.FLDEFF = 25 -- FLDEFF_POKECENTER_HEAL

-- pret FldEff_PokecenterHeal — absolute screen coords (coordOffsetEnabled = FALSE).
local BALL_CENTER_X, BALL_CENTER_Y = 93, 36
local MONITOR_CENTER_X, MONITOR_CENTER_Y = 128, 24

-- pret sCenterToCornerVecTable: 8x8 square → (-4,-4); 32x16 h-rect size2 → (-16,-8).
local BALL_CORNER = { -4, -4 }
local MONITOR_CORNER = { -16, -8 }

-- pret sPokeballCoordOffsets: L→R, top→bottom on the 2×3 LED tray.
local BALL_OFFSETS = {
  { 0, 0 }, { 6, 0 },
  { 0, 4 }, { 6, 4 },
  { 0, 8 }, { 6, 8 },
}

local GLOW = { 1.0, 0.75, 0.5, 0.0 }

local STATE = {
  PLACE = 0,
  WAIT_SE = 1,
  FLASH_A = 2,
  FLASH_B = 3,
  WAIT_AFTER = 4,
  DUMMY = 5,
  WAIT_SOUND = 6,
  IDLE = 7,
}

PokecenterHeal._fx = nil
PokecenterHeal._ballImg = nil
PokecenterHeal._ballQuad = nil
PokecenterHeal._monImg = nil
PokecenterHeal._monQuads = nil
PokecenterHeal._cache = nil
PokecenterHeal._logged = false

local function log(msg)
  if PokecenterHeal._logged then return end
  PokecenterHeal._logged = true
  print("[game3/pokecenter_heal] " .. tostring(msg))
end

--- Force palette-0 / RGB-black → alpha 0 (GBA OBJ color 0 is always clear).
local function load_sprite_png(path, w, h)
  if not (love and love.image and love.graphics) then return nil end
  local ok, data = pcall(love.image.newImageData, path)
  if not ok or not data then return nil end
  local dw, dh = data:getDimensions()
  if dw < w or dh < h then return nil end
  -- Punch through black / near-black so mis-exported indexed PNGs still clear.
  data:mapPixel(function(_x, _y, r, g, b, a)
    if a < 1 / 255 then return 0, 0, 0, 0 end
    if r < 1 / 255 and g < 1 / 255 and b < 1 / 255 then return 0, 0, 0, 0 end
    return r, g, b, a
  end)
  local img = love.graphics.newImage(data)
  if img.setFilter then img:setFilter("nearest", "nearest") end
  return img
end

local function try_paths(names, w, h)
  for i = 1, #names do
    local img = load_sprite_png(names[i], w, h)
    if img then return img end
  end
  return nil
end

function PokecenterHeal.install(cache)
  PokecenterHeal._cache = cache
  PokecenterHeal._ballImg = nil
  PokecenterHeal._monImg = nil
  PokecenterHeal._logged = false
end

function PokecenterHeal.invalidate()
  PokecenterHeal._ballImg = nil
  PokecenterHeal._monImg = nil
  PokecenterHeal._ballQuad = nil
  PokecenterHeal._monQuads = nil
end

local function ensure_gfx()
  if PokecenterHeal._ballImg and PokecenterHeal._monImg then return true end
  local root = "data/generated/gba/field_effects"
  local ball = try_paths({
    "src/import/gba/chrome/field_effects/pokeball_glow.png",
    root .. "/pokeball_glow.png",
  }, 8, 8)
  local mon = try_paths({
    "src/import/gba/chrome/field_effects/pokemoncenter_monitor.png",
    root .. "/pokemoncenter_monitor.png",
  }, 32, 16)
  if not (ball and mon) then
    log("heal gfx missing — vendor pokeball_glow / pokemoncenter_monitor PNGs")
    return false
  end
  PokecenterHeal._ballImg = ball
  PokecenterHeal._ballQuad = love.graphics.newQuad(0, 0, 8, 8, ball:getDimensions())
  PokecenterHeal._monImg = mon
  local quads = {}
  local iw, ih = mon:getDimensions()
  for i = 0, 3 do
    quads[i] = love.graphics.newQuad(0, i * 16, 32, 16, iw, ih)
  end
  PokecenterHeal._monQuads = quads
  log("pokecenter heal gfx ready (centerToCorner screen OAM)")
  return true
end

local function party_count()
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  local Party = package.loaded["src.core.game3.party"]
    or require("src.core.game3.party")
  if session and session.party and Party.size then
    return math.max(1, math.min(6, Party.size(session.party)))
  end
  if session and type(session.party) == "table" then
    return math.max(1, math.min(6, #session.party))
  end
  return 1
end

local function play_se_ball()
  pcall(function()
    local Audio = require("src.core.game3.audio")
    local SE = require("src.core.game3.se_ids")
    if Audio.playSe and SE.SE_BALL then Audio.playSe(SE.SE_BALL) end
  end)
end

local function play_heal_fanfare()
  pcall(function()
    local Audio = require("src.core.game3.audio")
    local id = (Audio.role and Audio.role("heal")) or 256
    if Audio.playFanfare then Audio.playFanfare(id) end
  end)
end

local function fanfare_done()
  local ok, Audio = pcall(require, "src.core.game3.audio")
  if not (ok and Audio) then return true end
  if Audio.isFanfareFinished then return Audio.isFanfareFinished() end
  if Audio._fanfareActive ~= nil then return not Audio._fanfareActive end
  return true
end

local function finish_waiters(fx)
  local waiters = fx and fx.waiters
  if not waiters then return end
  fx.waiters = {}
  for i = 1, #waiters do
    local cb = waiters[i]
    if cb then pcall(cb) end
  end
end

local function destroy_fx()
  local fx = PokecenterHeal._fx
  PokecenterHeal._fx = nil
  if fx then finish_waiters(fx) end
end

--- Screen top-left for ball slot i (0-based), matching pret OAM after centerToCorner.
local function ball_screen_tl(slot)
  local off = BALL_OFFSETS[slot + 1] or BALL_OFFSETS[1]
  return BALL_CENTER_X + off[1] + BALL_CORNER[1],
    BALL_CENTER_Y + off[2] + BALL_CORNER[2]
end

local function monitor_screen_tl()
  return MONITOR_CENTER_X + MONITOR_CORNER[1],
    MONITOR_CENTER_Y + MONITOR_CORNER[2]
end

function PokecenterHeal.start()
  -- Always reload art so a prior opaque load cannot stick across hot reload.
  PokecenterHeal.invalidate()
  ensure_gfx()
  if PokecenterHeal._fx then
    destroy_fx()
  end
  local n = party_count()
  local mx, my = monitor_screen_tl()
  PokecenterHeal._fx = {
    state = STATE.PLACE,
    timer = 0,
    counter = 0,
    numFlashed = 0,
    remaining = n,
    placed = 0,
    monitorX = mx,
    monitorY = my,
    balls = {}, -- screen top-left pixels
    monitorVisible = false,
    monitorFrame = 0,
    monitorAnim = nil,
    glowPhase = 0,
    waiters = {},
  }
  return true
end

function PokecenterHeal.isActive()
  return PokecenterHeal._fx ~= nil
end

function PokecenterHeal.wait(done)
  local fx = PokecenterHeal._fx
  if not fx then
    if done then done() end
    return
  end
  if fx.state >= STATE.IDLE then
    if done then done() end
    return
  end
  fx.waiters[#fx.waiters + 1] = done
end

local function start_monitor_anim(fx)
  fx.monitorVisible = true
  fx.monitorAnim = {
    seq = { 1, 2, 3, 2, 1, 0 },
    durs = { 5, 5, 7, 5, 5, 5 },
    i = 1,
    timer = 0,
    loopsLeft = 3,
  }
  fx.monitorFrame = 1
end

local function step_monitor(fx)
  local a = fx.monitorAnim
  if not a then return end
  a.timer = a.timer + 1
  local dur = a.durs[a.i] or 5
  if a.timer < dur then return end
  a.timer = 0
  a.i = a.i + 1
  if a.i > #a.seq then
    if a.loopsLeft > 0 then
      a.loopsLeft = a.loopsLeft - 1
      a.i = 1
    else
      fx.monitorFrame = 0
      fx.monitorAnim = nil
      fx.monitorVisible = false
      return
    end
  end
  fx.monitorFrame = a.seq[a.i] or 0
end

local function place_ball(fx)
  local i = fx.placed
  local sx, sy = ball_screen_tl(i)
  fx.balls[#fx.balls + 1] = { x = sx, y = sy }
  fx.placed = i + 1
  fx.remaining = fx.remaining - 1
  play_se_ball()
end

function PokecenterHeal.step()
  local fx = PokecenterHeal._fx
  if not fx then return end

  if fx.monitorAnim then step_monitor(fx) end

  local st = fx.state
  if st == STATE.PLACE then
    if fx.timer == 0 then
      place_ball(fx)
      fx.timer = 25
      if fx.remaining <= 0 then
        fx.timer = 32
        fx.state = STATE.WAIT_SE
      end
    else
      fx.timer = fx.timer - 1
      if fx.timer == 0 and fx.remaining > 0 then
        place_ball(fx)
        fx.timer = 25
        if fx.remaining <= 0 then
          fx.timer = 32
          fx.state = STATE.WAIT_SE
        end
      end
    end
  elseif st == STATE.WAIT_SE then
    fx.timer = fx.timer - 1
    if fx.timer <= 0 then
      start_monitor_anim(fx)
      play_heal_fanfare()
      fx.state = STATE.FLASH_A
      fx.timer = 8
      fx.counter = 0
      fx.numFlashed = 0
    end
  elseif st == STATE.FLASH_A then
    fx.timer = fx.timer - 1
    if fx.timer <= 0 then
      fx.timer = 8
      fx.counter = (fx.counter + 1) % 4
      if fx.counter == 0 then
        fx.numFlashed = fx.numFlashed + 1
      end
    end
    fx.glowPhase = fx.counter
    if fx.numFlashed >= 3 then
      fx.state = STATE.FLASH_B
      fx.timer = 8
      fx.counter = 0
    end
  elseif st == STATE.FLASH_B then
    fx.timer = fx.timer - 1
    if fx.timer <= 0 then
      fx.timer = 8
      fx.counter = (fx.counter + 1) % 4
      if fx.counter == 3 then
        fx.state = STATE.WAIT_AFTER
        fx.timer = 30
      end
    end
    fx.glowPhase = fx.counter
  elseif st == STATE.WAIT_AFTER then
    fx.timer = fx.timer - 1
    if fx.timer <= 0 then
      fx.state = STATE.DUMMY
    end
  elseif st == STATE.DUMMY then
    fx.state = STATE.WAIT_SOUND
  elseif st == STATE.WAIT_SOUND then
    if fanfare_done() then
      fx.state = STATE.IDLE
      destroy_fx()
    end
  end
end

--- Draw in absolute screen space (pret OAM; ignore camera).
function PokecenterHeal.draw(_camX, _camY)
  local fx = PokecenterHeal._fx
  if not fx then return end
  if not ensure_gfx() then
    love.graphics.setColor(1, 0.2, 0.2, 1)
    for _, b in ipairs(fx.balls) do
      love.graphics.rectangle("fill", b.x, b.y, 8, 8)
    end
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  local phase = fx.glowPhase or 0
  local g = GLOW[(phase % 4) + 1] or 1
  if fx.state < STATE.FLASH_A then g = 1 end

  love.graphics.setColor(1, g, g, 1)
  for _, b in ipairs(fx.balls) do
    love.graphics.draw(
      PokecenterHeal._ballImg, PokecenterHeal._ballQuad, b.x, b.y)
  end

  if fx.monitorVisible and PokecenterHeal._monQuads then
    local q = PokecenterHeal._monQuads[fx.monitorFrame or 0]
    if q then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(
        PokecenterHeal._monImg, q, fx.monitorX or 0, fx.monitorY or 0)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

-- Exported for tests: pret OAM top-left after centerToCorner.
PokecenterHeal._ballScreenTl = ball_screen_tl
PokecenterHeal._monitorScreenTl = monitor_screen_tl

return PokecenterHeal
