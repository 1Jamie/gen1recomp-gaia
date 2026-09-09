-- Controls guide + Pikachu intro (pret oak_speech.c front matter).
-- Full-screen windows on ROM-extracted guide BG — NOT oak_speech_bg / Message box.
-- Texts/layout: pret data/text/new_game_intro.inc + WindowTemplates.
-- Top bar is NOT a dark strip: pret TopBarWindow uses PIXEL_FILL(15) = same guide blue.

local Display = require("src.core.game3.display")
local Fade = require("src.ui.game3.fade")
local Audio = require("src.core.game3.audio")
local FrlgFont = require("src.ui.game3.frlg_font")
local Task = require("src.core.game3.task")
local Chrome = require("src.ui.game3.chrome")

local IntroGuide = {}

local T = Display.TILE

-- pret gControlsGuide_Text_* / gPikachuIntro_Text_* (explicit \\n only — no auto-wrap).
local CONTROLS_PAGES = {
  {
    bgKey = "controlsPage1",
    windows = {
      {
        left = 0, top = 7, width = 30, height = 4,
        ox = 2, oy = 0,
        text = "The various buttons will be explained in\nthe order of their importance.",
      },
    },
  },
  {
    bgKey = "controlsPage2",
    -- Button icons come from ROM tilemap overlay; text only in right windows.
    windows = {
      {
        left = 6, top = 3, width = 24, height = 6,
        ox = 6, oy = 0,
        text = "Moves the main character.\nAlso used to choose various data\nheadings.",
      },
      {
        left = 6, top = 10, width = 24, height = 4,
        ox = 6, oy = 0,
        text = "Used to confirm a choice, check\nthings, chat, and scroll text.",
      },
      {
        left = 6, top = 15, width = 24, height = 4,
        ox = 6, oy = 0,
        text = "Used to exit, cancel a choice,\nand cancel a mode.",
      },
    },
  },
  {
    bgKey = "controlsPage3",
    windows = {
      {
        left = 6, top = 3, width = 24, height = 4,
        ox = 6, oy = 0,
        text = "Press this button to open the\nMENU.",
      },
      {
        left = 6, top = 8, width = 24, height = 4,
        ox = 6, oy = 0,
        text = "Used to shift items and to use\na registered item.",
      },
      {
        left = 6, top = 13, width = 24, height = 6,
        ox = 6, oy = 0,
        text = "If you need help playing the\ngame, or on how to do things,\npress the L or R Button.",
      },
    },
  },
}

local PIKA_PAGES = {
  -- WIN_INTRO_TEXTBOX (1,4) 28×15; printer ox=3 oy=5, letterSpacing=1, lineSpacing=0
  "In the world which you are about to\nenter, you will embark on a grand\nadventure with you as the hero.\n\nSpeak to people and check things\nwherever you go, be it towns, roads,\nor caves. Gather information and\nhints from every source.",
  "New paths will open to you by helping\npeople in need, overcoming challenges,\nand solving mysteries.\n\nAt times, you will be challenged by\nothers and attacked by wild creatures.\nBe brave and keep pushing on.",
  "Through your adventure, we hope\nthat you will interact with all sorts\nof people and achieve personal growth.\nThat is our biggest objective.\n\nPress the A Button, and let your\nadventure begin!",
}

-- pret CreateSprite centers → top-left via centerToCornerVec
local PIKA = {
  bodyCX = 16, bodyCY = 17, bodyW = 32, bodyH = 32,
  earsCX = 16, earsCY = 9, earsW = 32, earsH = 16,
  eyesCX = 24, eyesCY = 13, eyesW = 16, eyesH = 8,
}

-- pret sPikachuIntro_Pikachu{Body,Ears,Eyes}_Anim (durations in 60fps frames).
-- Body FRAME tileOffsets 0/16 → sheet frames 0/1; ears 0/8 → 0/1; eyes 0/2 → 0/1.
local BODY_ANIM = { { 0, 30 }, { 1, 30 } }
local EARS_ANIM = {
  { 0, 60 }, { 0, 60 }, { 0, 60 }, { 0, 60 }, { 0, 60 }, { 0, 60 },
  { 1, 12 }, { 0, 12 }, { 1, 12 },
  { 0, 60 }, { 0, 60 }, { 0, 60 },
  { 1, 12 }, { 0, 12 }, { 1, 12 },
}
local EYES_ANIM = {
  { 0, 60 }, { 0, 60 }, { 0, 60 }, { 0, 60 }, { 0, 60 },
  { 1, 8 }, { 0, 8 }, { 1, 8 },
  { 0, 60 }, { 0, 60 }, { 0, 60 },
  { 1, 8 }, { 0, 8 }, { 1, 8 },
}

local function playSe()
  Audio.playSe(5)
end

local function newAnimState(script)
  return { script = script, cmd = 1, age = 0, frame = script[1][1] }
end

--- Advance one pret AnimCmd script; returns current sheet frame + cmd index (for y2 bob).
local function tickAnim(st, dt)
  if not st or not st.script then return 0, 0 end
  -- Convert real-time dt to 60fps frames (pret VBlank ticks).
  st.age = (st.age or 0) + (dt or 1 / 60) * 60
  local cmd = st.script[st.cmd]
  while cmd and st.age >= cmd[2] do
    st.age = st.age - cmd[2]
    st.cmd = st.cmd + 1
    if st.cmd > #st.script then st.cmd = 1 end
    cmd = st.script[st.cmd]
    st.frame = cmd[1]
  end
  return st.frame or 0, (st.cmd or 1) - 1
end

function IntroGuide.beginControls(assets)
  return {
    kind = "controls",
    page = 1,
    pages = CONTROLS_PAGES,
    assets = assets or {},
    done = false,
    blink = 0,
  }
end

function IntroGuide.beginPikachu(assets)
  Audio.playSong(324)
  return {
    kind = "pikachu",
    page = 1,
    pages = PIKA_PAGES,
    assets = assets or {},
    done = false,
    blink = 0,
    pikaBody = newAnimState(BODY_ANIM),
    pikaEars = newAnimState(EARS_ANIM),
    pikaEyes = newAnimState(EYES_ANIM),
  }
end

function IntroGuide.start(_state)
  -- Pages are drawn directly; nothing to open (no Message / typewriter).
end

local function advancePage(state)
  if state.page < #state.pages then
    state.page = state.page + 1
    playSe()
    return
  end
  playSe()
  state.done = true
end

local function backPage(state)
  if state.page > 1 then
    state.page = state.page - 1
    playSe()
  end
end

function IntroGuide.update(state, input, dt)
  if not state or state.done then return true end
  dt = dt or 1 / 60
  state.blink = (state.blink or 0) + dt
  Task.update(dt)
  Fade.tick(dt)

  if state.kind == "pikachu" then
    if not state.pikaBody then
      state.pikaBody = newAnimState(BODY_ANIM)
      state.pikaEars = newAnimState(EARS_ANIM)
      state.pikaEyes = newAnimState(EYES_ANIM)
    end
    local _, bodyCmd = tickAnim(state.pikaBody, dt)
    tickAnim(state.pikaEars, dt)
    tickAnim(state.pikaEyes, dt)
    -- SpriteCB_Pikachu: ears/eyes y2 = body's animCmdIndex (0 or 1)
    state.pikaBob = bodyCmd % 2
  end

  if input and input.wasPressed then
    if input:wasPressed("a") or input:wasPressed("start") then
      advancePage(state)
    elseif input:wasPressed("b") then
      backPage(state)
    end
  end
  return state.done
end

local function drawTopBar(state)
  -- pret TopBarWindowPrint*: white text on guide-blue fill (no navy strip).
  local white = FrlgFont.COLOR.WHITE
  if state.kind == "controls" then
    FrlgFont.draw("CONTROLS", 8, 2, { colors = white, maxWidth = 120, small = true })
    local hint = state.page > 1 and "A NEXT  B BACK" or "A NEXT"
    local tw = FrlgFont.measure(hint, { small = true })
    if tw < 1 then tw = FrlgFont.measure(hint) end
    FrlgFont.draw(hint, Display.W - 8 - tw, 2, { colors = white, maxWidth = 160, small = true })
  else
    local hint = state.page > 1 and "A NEXT  B BACK" or "A NEXT"
    local tw = FrlgFont.measure(hint, { small = true })
    if tw < 1 then tw = FrlgFont.measure(hint) end
    FrlgFont.draw(hint, Display.W - 8 - tw, 2, { colors = white, maxWidth = 160, small = true })
  end
end

local function drawControlsPage(state)
  local page = state.pages[state.page]
  if not page then return end
  local white = FrlgFont.COLOR.WHITE
  local pitch = FrlgFont.LINE_PITCH
  for _, win in ipairs(page.windows or {}) do
    local x = win.left * T + (win.ox or 0)
    local y = win.top * T + (win.oy or 0)
    local maxW = win.width * T - (win.ox or 0)
    FrlgFont.draw(win.text, x, y, {
      colors = white,
      maxWidth = maxW,
      linePitch = pitch,
    })
  end
end

local function drawPikachuSprite(state)
  local a = state.assets or {}
  local body = a.pikachuBody
  if not body then return end
  love.graphics.setColor(1, 1, 1, 1)

  local bodyFrame = (state.pikaBody and state.pikaBody.frame) or 0
  local earsFrame = (state.pikaEars and state.pikaEars.frame) or 0
  local eyesFrame = (state.pikaEyes and state.pikaEyes.frame) or 0
  local bob = state.pikaBob or 0

  local bw, bh = body:getDimensions()
  local q = love.graphics.newQuad and love.graphics.newQuad(0, bodyFrame * 32, 32, 32, bw, bh)
  local bx = PIKA.bodyCX - PIKA.bodyW / 2
  local by = PIKA.bodyCY - PIKA.bodyH / 2
  if q then
    love.graphics.draw(body, q, bx, by)
  else
    love.graphics.draw(body, bx, by)
  end

  local ears = a.pikachuEars
  if ears then
    local ew, eh = ears:getDimensions()
    local eq = love.graphics.newQuad and love.graphics.newQuad(0, earsFrame * 16, 32, 16, ew, eh)
    local ex = PIKA.earsCX - PIKA.earsW / 2
    local ey = PIKA.earsCY - PIKA.earsH / 2 + bob
    if eq then love.graphics.draw(ears, eq, ex, ey)
    else love.graphics.draw(ears, ex, ey) end
  end

  local eyes = a.pikachuEyes
  if eyes then
    local iw, ih = eyes:getDimensions()
    local eyq = love.graphics.newQuad and love.graphics.newQuad(0, eyesFrame * 8, 16, 8, iw, ih)
    local ex = PIKA.eyesCX - PIKA.eyesW / 2
    local ey = PIKA.eyesCY - PIKA.eyesH / 2 + bob
    if eyq then love.graphics.draw(eyes, eyq, ex, ey)
    else love.graphics.draw(eyes, ex, ey) end
  end
end

local function drawPikachuPage(state)
  drawPikachuSprite(state)
  local text = state.pages[state.page]
  if not text then return end
  local x = 1 * T + 3
  local y = 4 * T + 5
  local maxW = 28 * T - 3
  FrlgFont.draw(text, x, y, {
    colors = FrlgFont.COLOR.DARK_GRAY,
    maxWidth = maxW,
    linePitch = FrlgFont.GLYPH_HEIGHT, -- 14; pret lineSpacing 0
  })
end

local function drawPrompt(state)
  local t = state.blink or 0
  local frame = math.floor(t * 8) % 8
  local bounce = ({ 0, 1, 2, 1 })[1 + (math.floor(t * 8) % 4)] or 0
  local ax = Display.W - 16
  local ay = Display.H - 16 - bounce
  if Chrome.promptArrow then
    Chrome.promptArrow(ax, ay, frame)
  end
end

local function drawBg(state)
  local W, H = Display.W, Display.H
  local img = nil
  if state.kind == "controls" then
    local page = state.pages[state.page]
    local key = page and page.bgKey
    img = key and state.assets[key]
  else
    img = state.assets.pikachuBg or state.assets.pikachuIntroBg
  end
  if img then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, 0, 0)
  else
    -- Fallback: pret guide blue RGB(0,123,197)
    love.graphics.setColor(0 / 255, 123 / 255, 197 / 255, 1)
    love.graphics.rectangle("fill", 0, 0, W, H)
  end
end

function IntroGuide.draw(state)
  if not state then return end
  drawBg(state)
  -- No dark navy overlay — pret top bar is the same blue as the field.
  love.graphics.setColor(1, 1, 1, 1)
  drawTopBar(state)

  if state.kind == "controls" then
    drawControlsPage(state)
  else
    drawPikachuPage(state)
  end

  drawPrompt(state)
  Fade.draw()
end

return IntroGuide
