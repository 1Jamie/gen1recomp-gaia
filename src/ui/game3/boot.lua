-- Fire Red boot UI: copyright → title → main menu → Oak speech → field.
-- Oak onboarding lives in oak_speech.lua (pret oak_speech.c task chain).

local Display = require("src.core.game3.display")
local FrlgFont = require("src.ui.game3.frlg_font")
local Audio = require("src.core.game3.audio")
local OakSpeech = require("src.ui.game3.oak_speech")
local IntroGuide = require("src.ui.game3.intro_guide")
local NamingChrome = require("src.ui.game3.naming_chrome")
local IntroMovie = require("src.ui.game3.intro_movie")
local TitleScreen = require("src.ui.game3.title_screen")

local Boot = {}

Boot.PHASE = {
  INTRO = "intro",
  COPYRIGHT = "copyright",
  TITLE = "title",
  MENU = "menu",
  CONTROLS = "controls",
  PIKACHU = "pikachu",
  OAK = "oak",
}

local INTRO_FALLBACK = "data/generated/gba/intro"

local function loadIntroIndex()
  if not (love and love.filesystem) then return nil end
  local ok, chunk = pcall(love.filesystem.load, "data/generated/intro.lua")
  if not ok or type(chunk) ~= "function" then return nil end
  local ok2, t = pcall(chunk)
  if ok2 and type(t) == "table" and not t.stub then return t end
  return nil
end

local function loadImage(rel)
  if not rel or not (love and love.filesystem and love.filesystem.getInfo(rel)) then
    return nil
  end
  local ok, img = pcall(love.graphics.newImage, rel)
  if ok then
    if img.setFilter then img:setFilter("nearest", "nearest") end
    return img
  end
  return nil
end

function Boot.new()
  local index = loadIntroIndex()
  local base = INTRO_FALLBACK
  local function path(key, file)
    if index and index[key] then return index[key] end
    return base .. "/" .. file
  end

  local platform = loadImage(path("platform", "platform.png"))
  local platformQuad = nil
  if platform and love and love.graphics and love.graphics.newQuad then
    local pw, ph = platform:getDimensions()
    if pw >= 32 and ph >= 32 then
      platformQuad = love.graphics.newQuad(0, 0, 32, 32, pw, ph)
    end
  end

  local titleFlamesImg = loadImage(path("titleFlames", "title_flames.png"))

  local assets = {
    oakSprite = loadImage(path("oakPic", "oak.png")),
    boySprite = loadImage(path("playerPic", "boy.png")),
    girlSprite = loadImage(path("playerPicFemale", "girl.png")),
    rivalSprite = loadImage(path("rivalPic", "rival.png")),
    platform = platform,
    platformQuad = platformQuad,
    oakSpeechBg = loadImage(path("oakSpeechBg", "oak_speech_bg.png")),
    controlsPage1 = loadImage(path("controlsPage1", "controls_page1.png")),
    controlsPage2 = loadImage(path("controlsPage2", "controls_page2.png")),
    controlsPage3 = loadImage(path("controlsPage3", "controls_page3.png")),
    pikachuBg = loadImage(path("pikachuIntroBg", "pikachu_intro_bg.png")),
    pikachuBody = loadImage(path("pikachuBody", "pikachu_body.png")),
    pikachuEars = loadImage(path("pikachuEars", "pikachu_ears.png")),
    pikachuEyes = loadImage(path("pikachuEyes", "pikachu_eyes.png")),
    nidoranFront = loadImage(path("nidoranFront", "nidoran_f.png")),
    ballPoke = loadImage(path("ballPoke", "ball_poke.png")),
    -- Intro Movie Assets
    introCopyright = loadImage(path("introCopyright", "intro_copyright.png")),
    introGfBg = loadImage(path("introGfBg", "intro_gf_bg.png")),
    introGfText = loadImage(path("introGfText", "intro_gf_text.png")),
    introGfLogo = loadImage(path("introGfLogo", "intro_gf_logo.png")),
    introStar = loadImage(path("introStar", "intro_star.png")),
    introSparklesSmall = loadImage(path("introSparklesSmall", "intro_sparkles_small.png")),
    introSparklesBig = loadImage(path("introSparklesBig", "intro_sparkles_big.png")),
    introPresents = loadImage(path("introPresents", "intro_presents.png")),
    introScene1Grass = loadImage(path("introScene1Grass", "intro_scene1_grass.png")),
    introScene1Bg = loadImage(path("introScene1Bg", "intro_scene1_bg.png")),
    introScene2Bg = loadImage(path("introScene2Bg", "intro_scene2_bg.png")),
    introScene2Plants = loadImage(path("introScene2Plants", "intro_scene2_plants.png")),
    introScene2GengarClose = loadImage(path("introScene2GengarClose", "intro_scene2_gengar_close.png")),
    introScene2NidorinoClose = loadImage(path("introScene2NidorinoClose", "intro_scene2_nidorino_close.png")),
    introScene2Gengar = loadImage(path("introScene2Gengar", "intro_scene2_gengar.png")),
    introScene2Nidorino = loadImage(path("introScene2Nidorino", "intro_scene2_nidorino.png")),
    introScene3Bg = loadImage(path("introScene3Bg", "intro_scene3_bg.png")),
    introScene3GengarAnim = loadImage(path("introScene3GengarAnim", "intro_scene3_gengar_anim.png")),
    introScene3Grass = loadImage(path("introScene3Grass", "intro_scene3_grass.png")),
    introScene3GengarStatic = loadImage(path("introScene3GengarStatic", "intro_scene3_gengar_static.png")),
    introScene3Nidorino = loadImage(path("introScene3Nidorino", "intro_scene3_nidorino.png")),
    introScene3Swipe = loadImage(path("introScene3Swipe", "intro_scene3_swipe.png")),
    introScene3RecoilDust = loadImage(path("introScene3RecoilDust", "intro_scene3_recoil_dust.png")),
    titleFlames = titleFlamesImg,
    titleSlash = loadImage(path("titleSlash", "title_slash.png")),
    titleBorder = loadImage(path("titleBorder", "title_border_bg.png")),
  }

  local introMovie = IntroMovie.new(assets)

  local state = {
    phase = Boot.PHASE.INTRO,
    timer = 0,
    blink = 0,
    menuIndex = 1,
    hasContinue = false,
    introIndex = index,
    assets = assets,
    introMovie = introMovie,
    oak = nil,
    titleScreen = loadImage(path("titleScreen", "title_screen.png")),
    titleLogo = loadImage(path("titleLogo", "title_logo.png")),
    titleMon = loadImage(path("boxArtMon", "box_art_mon.png")),
    titleBorder = assets.titleBorder,
    pressStart = loadImage(path("pressStart", "press_start.png")),
    copyrightLayer = loadImage(path("copyrightPressStart", "copyright_press_start.png")),
  }
  return state
end

function Boot.setHasContinue(state, yes)
  state.hasContinue = yes and true or false
  state.menuIndex = 1
end

local function menuItems(state)
  if state.hasContinue then
    return { "CONTINUE", "NEW GAME", "OPTION" }
  end
  return { "NEW GAME", "OPTION" }
end

local function enterTitle(state)
  TitleScreen.enter(state)
end

local function leaveTitle(state)
  if state._titleActive then
    TitleScreen.leave(state)
  end
end

function Boot.update(state, input, dt)
  dt = dt or (1 / 60)
  state.timer = (state.timer or 0) + dt
  state.blink = (state.blink or 0) + dt

  local function a()
    return input and input.wasPressed and (input:wasPressed("a") or input:wasPressed("start"))
  end
  local function up()
    return input and input.wasPressed and input:wasPressed("up")
  end
  local function down()
    return input and input.wasPressed and input:wasPressed("down")
  end

  if state.phase == Boot.PHASE.INTRO then
    if state.introMovie then
      local done = state.introMovie:update(input, dt)
      if done then
        if state.introMovie.destroy then state.introMovie:destroy() end
        state.phase = Boot.PHASE.TITLE
        state.timer = 0
        enterTitle(state)
        Audio.playSong(278) -- MUS_TITLE
      end
    else
      state.phase = Boot.PHASE.TITLE
      state.timer = 0
      enterTitle(state)
      Audio.playSong(278)
    end
    return nil
  end

  if state.phase == Boot.PHASE.COPYRIGHT then
    state.phase = Boot.PHASE.TITLE
    state.timer = 0
    enterTitle(state)
    Audio.playSong(278)
    return nil
  end

  if state.phase == Boot.PHASE.TITLE then
    TitleScreen.update(state, dt)
    if a() then
      leaveTitle(state)
      state.phase = Boot.PHASE.MENU
      state.timer = 0
      Audio.playSe(5)
    end
    -- Idle timeout: cycle back to intro after 30s
    if state.timer > 30.0 then
      leaveTitle(state)
      state.phase = Boot.PHASE.INTRO
      state.introMovie = IntroMovie.new(state.assets)
      state.timer = 0
    end
    return nil
  end

  if state.phase == Boot.PHASE.MENU then
    local items = menuItems(state)
    if up() then
      state.menuIndex = state.menuIndex - 1
      if state.menuIndex < 1 then state.menuIndex = #items end
      Audio.playSe(5)
    elseif down() then
      state.menuIndex = state.menuIndex + 1
      if state.menuIndex > #items then state.menuIndex = 1 end
      Audio.playSe(5)
    elseif a() then
      local choice = items[state.menuIndex]
      Audio.playSe(5)
      if choice == "CONTINUE" then
        return { action = "continue" }
      elseif choice == "NEW GAME" then
        NamingChrome.install()
        state.phase = Boot.PHASE.CONTROLS
        state.guide = IntroGuide.beginControls(state.assets)
        IntroGuide.start(state.guide)
        state.timer = 0
        Audio.playSong(323)
      elseif choice == "OPTION" then
        print("[game3/boot] OPTION selected (stub)")
      end
    end
    return nil
  end

  if state.phase == Boot.PHASE.CONTROLS and state.guide then
    if IntroGuide.update(state.guide, input, dt) then
      state.phase = Boot.PHASE.PIKACHU
      state.guide = IntroGuide.beginPikachu(state.assets)
      IntroGuide.start(state.guide)
      state.timer = 0
    end
    return nil
  end

  if state.phase == Boot.PHASE.PIKACHU and state.guide then
    if IntroGuide.update(state.guide, input, dt) then
      Audio.playSong(325)
      state.phase = Boot.PHASE.OAK
      state.oak = OakSpeech.new(state.assets)
      state.guide = nil
      state.timer = 0
    end
    return nil
  end

  if state.phase == Boot.PHASE.OAK and state.oak then
    return OakSpeech.update(state.oak, input, dt)
  end

  return nil
end

local function drawText(str, x, y, kind)
  kind = kind or "NORMAL"
  local colors = FrlgFont.COLOR and FrlgFont.COLOR[kind] or nil
  if FrlgFont.draw then
    FrlgFont.draw(str, x, y, { colors = colors, maxWidth = 220 })
  else
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(str, x, y)
  end
end

function Boot.draw(state)
  local W, H = Display.W, Display.H
  love.graphics.clear(0, 0, 0, 1)

  if state.phase == Boot.PHASE.INTRO and state.introMovie then
    state.introMovie:draw()
    return
  end

  if state.phase == Boot.PHASE.TITLE then
    TitleScreen.draw(state)
    return
  end

  if state.phase == Boot.PHASE.MENU then
    -- Static title underlay (no particles) + dim
    if state.titleBorder then
      love.graphics.setColor(255 / 255, 255 / 255, 139 / 255, 1)
      love.graphics.rectangle("fill", 0, 0, W, H)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(state.titleBorder, 0, 0)
      if state.titleMon then love.graphics.draw(state.titleMon, 0, 0) end
      if state.copyrightLayer then love.graphics.draw(state.copyrightLayer, 0, 0) end
      if state.titleLogo then love.graphics.draw(state.titleLogo, 0, 0) end
    elseif state.titleScreen then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(state.titleScreen, 0, 0)
    else
      love.graphics.setColor(0.1, 0.2, 0.4, 1)
      love.graphics.rectangle("fill", 0, 0, W, H)
    end
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 0, W, H)
    local items = menuItems(state)
    local boxX, boxY = 56, 48
    love.graphics.setColor(0.95, 0.95, 0.95, 1)
    love.graphics.rectangle("fill", boxX, boxY, 128, 16 + #items * 18)
    love.graphics.setColor(0.2, 0.35, 0.7, 1)
    love.graphics.rectangle("line", boxX, boxY, 128, 16 + #items * 18)
    for i, label in ipairs(items) do
      local y = boxY + 8 + (i - 1) * 18
      love.graphics.setColor(0.1, 0.1, 0.15, 1)
      if i == state.menuIndex then
        drawText(">", boxX + 8, y)
      end
      drawText(label, boxX + 24, y)
    end
    return
  end

  if state.phase == Boot.PHASE.CONTROLS or state.phase == Boot.PHASE.PIKACHU then
    IntroGuide.draw(state.guide)
    return
  end

  if state.phase == Boot.PHASE.OAK and state.oak then
    OakSpeech.draw(state.oak)
  end
end

return Boot
