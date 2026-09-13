-- Fire Red boot UI: copyright → title → main menu → Oak speech → field.
-- Oak onboarding lives in oak_speech.lua (pret oak_speech.c task chain).

local Display = require("src.core.game3.display")
local Window = require("src.ui.game3.window")
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
  TITLE_CRY = "title_cry",
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

function Boot.setContinueInfo(state, info)
  state.continueInfo = info
end

function Boot.continueInfoFromSave(save)
  if type(save) ~= "table" then return nil end
  local Flags = require("src.core.game3.scripting.flags")
  local store = { flags = type(save.flags) == "table" and save.flags or {} }
  local pt = type(save.playTime) == "table" and save.playTime
    or type(save.playtime) == "table" and save.playtime or {}
  local dex = type(save.dex) == "table" and save.dex or {}
  local caught = dex.caught or dex.owned or {}
  local counted, n = {}, 0
  for sp, on in pairs(caught) do
    local id = tonumber(sp)
    if id and on and on ~= 0 and not counted[id] and (dex.national or id <= 151) then
      counted[id] = true
      n = n + 1
    end
  end
  local name = tostring(save.name or save.playerName or "")
  return {
    name = name:sub(1, 7),
    gender = tonumber(save.gender) or 0,
    hours = tonumber(pt.hours) or 0,
    minutes = tonumber(pt.minutes) or 0,
    hasDex = Flags.getFlag(store, nil, Flags.IDS.SYS_POKEDEX_GET) == true,
    dexCount = n,
    badges = Flags.countBadges(store),
  }
end

local function menuItems(state)
  if state.hasContinue then
    return { "CONTINUE", "NEW GAME" }
  end
  return { "NEW GAME" }
end

Boot.menuItems = menuItems

local function beginNewGame(state)
  NamingChrome.install()
  state.phase = Boot.PHASE.CONTROLS
  state.guide = IntroGuide.beginControls(state.assets)
  IntroGuide.start(state.guide)
  state.timer = 0
  Audio.playSong(323)
  return nil
end

local function beginMenuFade(state, color, from, to, after)
  state.fadeColor = color
  state.fadeT = from
  state.fadeTarget = to
  state.fadeThen = after
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
      state.phase = Boot.PHASE.TITLE_CRY
      state.cryFrames = 0
      state.white = 0
      state.whiteFading = false
      Audio.playCry(6, 0) -- pokefirered/src/title_screen.c:715
    elseif state.timer >= 2700 / 60 then -- pokefirered/src/title_screen.c:435
      leaveTitle(state)
      state.phase = Boot.PHASE.INTRO
      state.introMovie = IntroMovie.new(state.assets)
      state.timer = 0
    end
    return nil
  end

  if state.phase == Boot.PHASE.TITLE_CRY then
    TitleScreen.update(state, dt)
    if not state.whiteFading then
      if state.cryFrames < 90 then -- pokefirered/src/title_screen.c:722
        state.cryFrames = state.cryFrames + 1
      else
        state.whiteFading = true
        Audio.fadeOutBgm(4) -- pokefirered/src/title_screen.c:728
      end
    elseif state.white < 16 then
      state.white = math.min(16, state.white + 2) -- pokefirered/src/palette.c:162
    else
      leaveTitle(state)
      state.whiteFading = false
      state.timer = 0
      if not state.hasContinue then -- pokefirered/src/main_menu.c:317
        return beginNewGame(state)
      end
      state.phase = Boot.PHASE.MENU
      state.menuIndex = 1
      beginMenuFade(state, "white", 16, 0, nil) -- pokefirered/src/main_menu.c:398
    end
    return nil
  end

  if state.phase == Boot.PHASE.MENU then
    local t, target = state.fadeT or 0, state.fadeTarget or 0
    if t ~= target then
      if t < target then
        state.fadeT = math.min(target, t + 2)
      else
        state.fadeT = math.max(target, t - 2)
      end
      return nil
    end
    local pending = state.fadeThen
    if pending then
      state.fadeThen = nil
      if pending == "continue" then
        state.fadeT, state.fadeTarget = 0, 0
        return { action = "continue" }
      elseif pending == "new_game" then
        state.fadeT, state.fadeTarget = 0, 0
        return beginNewGame(state)
      elseif pending == "title" then
        state.fadeT, state.fadeTarget = 0, 0
        state.phase = Boot.PHASE.TITLE
        state.timer = 0
        enterTitle(state)
        Audio.playSong(278) -- pokefirered/src/title_screen.c:389
      end
      return nil
    end
    local items = menuItems(state)
    local pressed = function(k) return input and input.wasPressed and input:wasPressed(k) end
    if pressed("a") then -- pokefirered/src/main_menu.c:570
      Audio.playSe(5)
      local choice = items[state.menuIndex]
      beginMenuFade(state, "black", 0, 16, choice == "CONTINUE" and "continue" or "new_game")
    elseif pressed("b") then -- pokefirered/src/main_menu.c:577
      Audio.playSe(5)
      beginMenuFade(state, "black", 0, 16, "title")
    elseif up() and state.menuIndex > 1 then
      state.menuIndex = state.menuIndex - 1
    elseif down() and state.menuIndex < #items then
      state.menuIndex = state.menuIndex + 1
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

local MENU_BG = { 139 / 255, 148 / 255, 255 / 255 }
local MENU_TEXT = { 98 / 255, 98 / 255, 98 / 255, 1 }
local MENU_SHADOW = { 213 / 255, 213 / 255, 205 / 255, 1 }
local MENU_FILL = { 1, 1, 1, 1 }
local ACCENT_MALE = { 4 / 31, 16 / 31, 31 / 31, 1 }
local ACCENT_FEMALE = { 31 / 31, 3 / 31, 21 / 31, 1 }
local WIN0V = { { 0x02, 0x5E }, { 0x62, 0x7E } }

local function darkenOutside(W, H, x0, y0, x1, y1)
  love.graphics.setColor(0, 0, 0, 7 / 16) -- pokefirered/src/main_menu.c:231
  love.graphics.rectangle("fill", 0, 0, W, y0)
  love.graphics.rectangle("fill", 0, y1, W, H - y1)
  love.graphics.rectangle("fill", 0, y0, x0, y1 - y0)
  love.graphics.rectangle("fill", x1, y0, W - x1, y1 - y0)
end

local function drawMainMenu(state, W, H)
  love.graphics.clear(MENU_BG[1], MENU_BG[2], MENU_BG[3], 1) -- pokefirered/src/main_menu.c:199
  local info = state.continueInfo or {}
  local head = { fg = MENU_TEXT, shadow = MENU_SHADOW, bg = MENU_FILL }
  local stat = {
    fg = (info.gender == 1) and ACCENT_FEMALE or ACCENT_MALE, -- pokefirered/src/main_menu.c:342
    shadow = MENU_SHADOW,
    bg = MENU_FILL,
  }
  Window.stdFrame(Window.template(3, 1, 24, 10)) -- pokefirered/src/main_menu.c:84
  Window.stdFrame(Window.template(3, 13, 24, 2)) -- pokefirered/src/main_menu.c:93
  local x, y = 24, 8
  Window.printPx("CONTINUE", x + 2, y + 2, { colors = head })
  Window.printPx("PLAYER", x + 2, y + 18, { colors = stat }) -- pokefirered/src/main_menu.c:623
  Window.printPx(info.name or "", x + 62, y + 18, { colors = stat })
  Window.printPx("TIME", x + 2, y + 34, { colors = stat }) -- pokefirered/src/main_menu.c:636
  Window.printPx(string.format("%d:%02d", info.hours or 0, info.minutes or 0), x + 62, y + 34, { colors = stat })
  if info.hasDex then -- pokefirered/src/main_menu.c:648
    Window.printPx("POKéDEX", x + 2, y + 50, { colors = stat })
    Window.printPx(tostring(info.dexCount or 0), x + 62, y + 50, { colors = stat })
  end
  Window.printPx("BADGES", x + 2, y + 66, { colors = stat }) -- pokefirered/src/main_menu.c:672
  Window.printPx(tostring(info.badges or 0), x + 62, y + 66, { colors = stat })
  Window.printPx("NEW GAME", 24 + 2, 104 + 2, { colors = head })
  local rows = WIN0V[state.menuIndex] or WIN0V[1] -- pokefirered/src/main_menu.c:565
  darkenOutside(W, H, 18, rows[1], 222, rows[2])
  local t = state.fadeT or 0
  if t > 0 then
    if state.fadeColor == "white" then
      love.graphics.setColor(1, 1, 1, t / 16)
    else
      love.graphics.setColor(0, 0, 0, t / 16)
    end
    love.graphics.rectangle("fill", 0, 0, W, H)
  end
  love.graphics.setColor(1, 1, 1, 1)
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

  if state.phase == Boot.PHASE.TITLE_CRY then
    TitleScreen.draw(state)
    local white = state.white or 0
    if white > 0 then
      love.graphics.setColor(1, 1, 1, white / 16) -- pokefirered/src/title_screen.c:726
      love.graphics.rectangle("fill", 0, 0, W, H)
      love.graphics.setColor(1, 1, 1, 1)
    end
    return
  end

  if state.phase == Boot.PHASE.MENU then
    drawMainMenu(state, W, H)
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
