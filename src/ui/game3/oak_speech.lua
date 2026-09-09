-- FireRed Oak speech — Gen1/2-style step runner over shared primitives.
-- Logic reference: pret oak_speech.c. Assets/text: ROM extract only.

local MapIds = require("src.core.game3.map_ids")
local Audio = require("src.core.game3.audio")
local Task = require("src.core.game3.task")
local Message = require("src.ui.game3.message")
local Choice = require("src.ui.game3.choice")
local Fade = require("src.ui.game3.fade")
local Naming = require("src.ui.game3.naming")
local OakScene = require("src.ui.game3.oak_scene")

local OakSpeech = {}

local FALLBACK_TEXT = {
  welcome = "Hello, there!\nGlad to meet you!\fWelcome to the world of POKéMON!\fMy name is OAK.\fPeople affectionately refer to me\nas the POKéMON PROFESSOR.",
  this_world = "This world…",
  inhabited = "…is inhabited far and wide by\ncreatures called POKéMON.",
  study = "For some people, POKéMON are pets.\nOthers use them for battling.\fAs for myself…\fI study POKéMON as a profession.",
  tell_me = "But first, tell me a little about\nyourself.",
  ask_gender = "Now tell me. Are you a boy?\nOr are you a girl?",
  your_name = "Let's begin with your name.\nWhat is it?",
  confirm_player = "Right…\nSo your name is {PLAYER}.",
  rival_intro = "This is my grandson.\fHe's been your rival since you both\nwere babies.\f…Erm, what was his name now?",
  rival_name_ask = "Your rival's name, what was it now?",
  confirm_rival = "…Er, was it {RIVAL}?",
  remember_rival = "That's right! I remember now!\nHis name is {RIVAL}!",
  lets_go = "{PLAYER}!\fYour very own POKéMON legend is\nabout to unfold!\fA world of dreams and adventures\nwith POKéMON awaits! Let's go!",
}

local FALLBACK_MALE = { "RED", "FIRE", "ASH", "KENE", "GEKI", "JAK", "JANNE", "JONN", "KAMON", "KARL", "TAYLOR", "OSCAR", "HIRO", "MAX", "JON", "RALPH", "KAY", "TOSH", "ROAK" }
local FALLBACK_FEMALE = { "RED", "FIRE", "OMI", "JODI", "AMANDA", "HILLARY", "MAKEY", "MICHI", "PAULA", "JUNE", "CASSIE", "REY", "SEDA", "KIKO", "MINA", "NORIE", "SAI", "MOMO", "SUZI" }
local FALLBACK_RIVAL = { "GREEN", "GARY", "KAZ", "TORU" }

local function loadBundle()
  if not (love and love.filesystem and love.filesystem.load) then return nil end
  local paths = {
    "data/generated/gba/intro/oak_speech.lua",
    "data/generated/intro.lua",
  }
  for _, p in ipairs(paths) do
    local ok, chunk = pcall(love.filesystem.load, p)
    if ok and type(chunk) == "function" then
      local ok2, t = pcall(chunk)
      if ok2 and type(t) == "table" and t.welcome then return t end
      if ok2 and type(t) == "table" and t.oakSpeech then
        local ok3, chunk2 = pcall(love.filesystem.load, t.oakSpeech)
        if ok3 and type(chunk2) == "function" then
          local ok4, t2 = pcall(chunk2)
          if ok4 and type(t2) == "table" then return t2 end
        end
      end
    end
  end
  return nil
end

local function expand(text, state)
  text = tostring(text or "")
  text = text:gsub("{PLAYER}", state.playerName or "???")
  text = text:gsub("{RIVAL}", state.rivalName or "???")
  return text
end

local function txt(state, key)
  local b = state.bundle or {}
  return expand(b[key] or FALLBACK_TEXT[key] or key, state)
end

local function playSe()
  Audio.playSe(5)
end

local function randomName(list)
  if not list or #list < 1 then return "RED" end
  local r = (love and love.math and love.math.random) or math.random
  return list[r(#list)]
end

local function maleNames(state)
  return (state.bundle and state.bundle.maleNames) or FALLBACK_MALE
end

local function femaleNames(state)
  return (state.bundle and state.bundle.femaleNames) or FALLBACK_FEMALE
end

local function rivalNames(state)
  return (state.bundle and state.bundle.rivalNames) or FALLBACK_RIVAL
end

local function advance(state)
  state.stepIndex = state.stepIndex + 1
  state.waiting = nil
  OakSpeech._runStep(state)
end

local function say(state, key, nextFn)
  state.waiting = "message"
  Message.show(txt(state, key), {
    done = function()
      state.waiting = nil
      if nextFn then nextFn() else advance(state) end
    end,
  })
end

--- Open naming under a held fade-to-black, then fade in so the screen is visible.
-- On confirm: fade to black, then run `done` (caller fades back into Oak).
local function openNaming(state, template, done)
  local seed
  if template == "PLAYER" then
    local pool = state.gender == 1 and femaleNames(state) or maleNames(state)
    seed = randomName(pool)
    state.playerName = seed
  else
    seed = randomName(rivalNames(state))
    state.rivalName = seed
  end
  state.waiting = "naming"
  -- pret NamingScreen_CreatePlayerIcon: field OW (Red/Leaf), not Oak portrait.
  Naming.open({
    title = template == "RIVAL" and "RIVAL's NAME?" or "YOUR NAME?",
    maxLen = 7,
    seed = seed,
    template = template,
    gender = state.gender or 0,
    onDone = function(name)
      if name and name ~= "" then
        if template == "PLAYER" then state.playerName = name
        else state.rivalName = name end
      end
      -- Naming already closed; wipe to black before restoring Oak under the overlay.
      state.waiting = "fade"
      Fade.begin(Fade.MODE.TO_BLACK, 1, function()
        if done then done() else
          Fade.begin(Fade.MODE.FROM_BLACK, 1, function()
            state.waiting = nil
            advance(state)
          end)
        end
      end)
    end,
  })
  -- TO_BLACK leaves Fade.t=16 while inactive; without FROM_BLACK naming stays covered.
  Fade.begin(Fade.MODE.FROM_BLACK, 1, function()
    state.waiting = "naming"
  end)
end

-- Step table (ids stable for hooks)
local STEPS = {
  { id = "init", kind = "fn" },
  { id = "welcome", kind = "say", text = "welcome", portrait = "oak" },
  { id = "this_world", kind = "say", text = "this_world", portrait = "oak" },
  { id = "release_nidoran", kind = "fn" },
  { id = "inhabited", kind = "fn" },
  { id = "study", kind = "say", text = "study", portrait = "oak" },
  { id = "return_nidoran", kind = "fn" },
  { id = "tell_me", kind = "say", text = "tell_me", portrait = "oak" },
  { id = "fade_oak", kind = "fn" },
  { id = "ask_gender", kind = "say", text = "ask_gender", portrait = "none" },
  { id = "gender_menu", kind = "fn" },
  { id = "load_player", kind = "fn" },
  { id = "your_name", kind = "say", text = "your_name", portrait = "player" },
  { id = "name_player", kind = "fn" },
  { id = "confirm_player", kind = "say", text = "confirm_player", portrait = "player" },
  { id = "yesno_player", kind = "fn" },
  { id = "fade_to_rival", kind = "fn" },
  { id = "rival_intro", kind = "say", text = "rival_intro", portrait = "rival" },
  { id = "rival_presets", kind = "fn" },
  { id = "confirm_rival", kind = "say", text = "confirm_rival", portrait = "rival" },
  { id = "yesno_rival", kind = "fn" },
  { id = "remember_rival", kind = "say", text = "remember_rival", portrait = "oak" },
  { id = "lets_go", kind = "say", text = "lets_go", portrait = "player" },
  { id = "shrink_exit", kind = "fn" },
  { id = "done", kind = "fn" },
}

function OakSpeech._runStep(state)
  local step = STEPS[state.stepIndex]
  if not step then
    state.phase = "done"
    return
  end
  state.stepId = step.id
  local scene = state.scene

  if step.portrait then
    OakScene.setPortrait(scene, step.portrait)
  end

  if step.kind == "say" then
    say(state, step.text)
    return
  end

  if step.id == "init" then
    state.waiting = "task"
    Audio.playSong(292)
    Task.waitFrames(80, function()
      state.waiting = nil
      advance(state)
    end)
    return
  end

  if step.id == "release_nidoran" then
    state.waiting = "task"
    scene.nidoranVisible = true
    scene.nidoranX, scene.nidoranY = 100, 66
    scene.nidoranScale = 0.4
    scene.ballVisible = true
    scene.ballX, scene.ballY, scene.ballFrame = 100, 66, 0
    Task.tween(32, function(u)
      local trig = u * 128
      local s = math.sin(trig * math.pi / 180)
      scene.nidoranX = 100 + (96 - 100) * u
      scene.nidoranY = 66 + (96 - 66) * u - s * 8
      scene.nidoranScale = 0.4 + 0.6 * u
      scene.ballFrame = u > 0.5 and 1 or 0
    end, function()
      scene.ballVisible = false
      scene.nidoranX, scene.nidoranY, scene.nidoranScale = 96, 96, 1
      state.waiting = nil
      advance(state)
    end)
    return
  end

  if step.id == "inhabited" then
    state.waiting = "task"
    state._inhabitedMsgDone = false
    Task.spawn(function(t)
      if t.frames == 32 then
        Audio.playCry(29)
        state.waiting = "message"
        Message.show(txt(state, "inhabited"), {
          done = function()
            state._inhabitedMsgDone = true
            state.waiting = "task"
          end,
        })
      end
      return t.frames >= 96 and state._inhabitedMsgDone == true
    end, {
      onDone = function()
        state.waiting = nil
        advance(state)
      end,
    })
    return
  end

  if step.id == "return_nidoran" then
    state.waiting = "task"
    scene.ballVisible = true
    scene.ballX, scene.ballY, scene.ballFrame = 100, 66, 1
    local rise = 0
    Task.spawn(function(t)
      if t.frames <= 32 then
        scene.nidoranScale = 1 - t.frames / 40
      end
      if t.frames > 32 and t.frames <= 56 then
        rise = rise + 1
        scene.nidoranY = 96 - rise
      end
      if t.frames == 48 then
        scene.nidoranVisible = false
        scene.ballVisible = false
      end
      return t.frames >= 64
    end, {
      onDone = function()
        state.waiting = nil
        advance(state)
      end,
    })
    return
  end

  if step.id == "fade_oak" then
    state.waiting = "fade"
    Fade.begin(Fade.MODE.TO_BLACK, 2, function()
      OakScene.setPortrait(scene, "none")
      scene.scrollX = 0
      Fade.begin(Fade.MODE.FROM_BLACK, 2, function()
        state.waiting = nil
        advance(state)
      end)
    end)
    return
  end

  if step.id == "gender_menu" then
    state.waiting = "choice"
    Choice.multi({ "BOY", "GIRL" }, 0, function(idx)
      state.waiting = nil
      state.gender = (idx == 1) and 1 or 0
      OakScene.setGender(scene, state.gender)
      playSe()
      advance(state)
    end, { left = 18, top = 9 })
    return
  end

  if step.id == "load_player" then
    state.waiting = "fade"
    OakScene.setPortrait(scene, "player")
    Fade.begin(Fade.MODE.FROM_BLACK, 2, function()
      state.waiting = nil
      advance(state)
    end)
    return
  end

  if step.id == "name_player" then
    state.waiting = "fade"
    Fade.begin(Fade.MODE.TO_BLACK, 1, function()
      openNaming(state, "PLAYER", function()
        scene.scrollX = 60
        OakScene.setPortrait(scene, "player")
        Fade.begin(Fade.MODE.FROM_BLACK, 1, function()
          state.waiting = nil
          advance(state)
        end)
      end)
    end)
    return
  end

  if step.id == "yesno_player" then
    state.waiting = "choice"
    Choice.yesNo(function(yes)
      state.waiting = nil
      playSe()
      if yes then
        advance(state)
      else
        for i, s in ipairs(STEPS) do
          if s.id == "name_player" then
            state.stepIndex = i
            OakSpeech._runStep(state)
            return
          end
        end
      end
    end, { left = 2, top = 2 })
    return
  end

  if step.id == "fade_to_rival" then
    state.waiting = "fade"
    Fade.begin(Fade.MODE.TO_BLACK, 2, function()
      OakScene.setPortrait(scene, "rival")
      scene.scrollX = 0
      Fade.begin(Fade.MODE.FROM_BLACK, 2, function()
        state.waiting = nil
        advance(state)
      end)
    end)
    return
  end

  if step.id == "rival_presets" then
    state.waiting = "task"
    Task.tween(30, function(u)
      scene.scrollX = u * 60
    end, function()
      state.waiting = "choice"
      local names = rivalNames(state)
      local opts = { "NEW NAME", names[1], names[2], names[3], names[4] }
      Choice.multi(opts, 0, function(idx)
        playSe()
        state.waiting = nil
        if idx == 0 then
          state.waiting = "fade"
          Fade.begin(Fade.MODE.TO_BLACK, 1, function()
            openNaming(state, "RIVAL", function()
              scene.scrollX = 60
              OakScene.setPortrait(scene, "rival")
              Fade.begin(Fade.MODE.FROM_BLACK, 1, function()
                state.waiting = nil
                advance(state)
              end)
            end)
          end)
        elseif idx >= 1 and idx <= 4 then
          state.rivalName = names[idx]
          advance(state)
        else
          -- B cancel → treat as re-ask
          Message.show(txt(state, "rival_name_ask"), {
            speed = 0,
            done = function()
              state.stepIndex = state.stepIndex -- re-run presets
              for i, s in ipairs(STEPS) do
                if s.id == "rival_presets" then
                  state.stepIndex = i
                  OakSpeech._runStep(state)
                  return
                end
              end
            end,
          })
        end
      end, { left = 2, top = 2 })
    end)
    return
  end

  if step.id == "yesno_rival" then
    state.waiting = "choice"
    Choice.yesNo(function(yes)
      playSe()
      state.waiting = nil
      if yes then
        advance(state)
      else
        Message.show(txt(state, "rival_name_ask"), {
          speed = 0,
          done = function()
            for i, s in ipairs(STEPS) do
              if s.id == "rival_presets" then
                state.stepIndex = i
                OakSpeech._runStep(state)
                return
              end
            end
          end,
        })
      end
    end, { left = 2, top = 2 })
    return
  end

  if step.id == "shrink_exit" then
    -- pret Task_OakSpeech_SetUpExitAnimation / ShrinkPlayerPic / FadePlayerPicToBlack
    state.waiting = "task"
    Audio.fadeOutBgm(4)
    local scene = state.scene
    OakScene.setPortrait(scene, "player")
    OakScene.setGender(scene, state.gender or 0)
    scene.portraitScale = 1
    scene.portraitWhite = 0
    scene.platformVisible = true
    scene.fade = 0
    local scaleQ88 = 256 -- pret tScaleDelta
    local whiteT = 0
    local fadeOutTimer = nil
    Task.spawn(function(t)
      local f = t.frames or 0
      -- White flash on portrait while shrinking (approx BlendPalette).
      if f >= 8 and whiteT < 14 then
        whiteT = whiteT + 0.35
        scene.portraitWhite = math.min(1, whiteT / 14)
      end
      -- Shrink every 20 frames by 32/256 until scaleQ88 <= 96.
      if fadeOutTimer == nil and f > 0 and f % 20 == 0 then
        scaleQ88 = scaleQ88 - 32
        scene.portraitScale = math.max(0.01, scaleQ88 / 256)
        if f == 40 then Audio.playSe(39) end -- SE_WARP_IN
        if scaleQ88 <= 96 then
          scene.portraitScale = 96 / 256
          fadeOutTimer = 36
        end
      end
      -- Platform fades with the room (pret palette fade on objects).
      if f >= 16 then
        scene.platformVisible = false
      end
      if fadeOutTimer ~= nil then
        fadeOutTimer = fadeOutTimer - 1
        if fadeOutTimer <= 0 then
          scene.fade = math.min(1, (scene.fade or 0) + 0.06)
        end
        return scene.fade >= 1
      end
      return false
    end, {
      onDone = function()
        scene.fade = 1
        state.waiting = nil
        advance(state)
      end,
    })
    return
  end

  if step.id == "done" then
    state.phase = "done"
    return
  end

  advance(state)
end

function OakSpeech.new(assets)
  local bundle = loadBundle()
  local state = {
    phase = "run",
    stepIndex = 1,
    stepId = nil,
    waiting = nil,
    bundle = bundle,
    gender = 0,
    playerName = "RED",
    rivalName = "GREEN",
    scene = OakScene.new(assets),
    timer = 0,
  }
  Audio.playSong(292)
  OakSpeech._runStep(state)
  return state
end

function OakSpeech.update(state, input, dt)
  if not state then return nil end
  if state.phase == "done" then
    return {
      action = "new_game",
      gender = state.gender or 0,
      name = state.playerName or "RED",
      rivalName = state.rivalName or "GREEN",
      start = MapIds.NEW_GAME_START,
    }
  end

  state.timer = (state.timer or 0) + (dt or 1 / 60)
  Task.update(dt)
  Fade.tick(dt)

  if Naming.isOpen() then
    Naming.update(input, dt)
    return nil
  end

  if state.waiting == "choice" and Choice.active then
    if input and input.wasPressed then
      if input:wasPressed("up") then Choice.move(-1); playSe()
      elseif input:wasPressed("down") then Choice.move(1); playSe()
      elseif input:wasPressed("a") or input:wasPressed("start") then Choice.confirm()
      elseif input:wasPressed("b") then Choice.cancel()
      end
    end
    return nil
  end

  if state.waiting == "message" and Message.isOpen() then
    Message.tick()
    if input and input.wasPressed then
      local held = input.isDown and (input:isDown("a") or input:isDown("b"))
      Message.setSpeedUp(held)
      if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
        Message.advance()
      end
    end
    return nil
  end

  -- Keep typewriter moving even during inhabited overlap
  if Message.isOpen() and state.waiting ~= "naming" then
    Message.tick()
    if input and input.wasPressed then
      local held = input.isDown and (input:isDown("a") or input:isDown("b"))
      Message.setSpeedUp(held)
      if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
        Message.advance()
      end
    end
  end

  return nil
end

function OakSpeech.draw(state)
  if not state then return end
  OakScene.draw(state.scene)
  -- Message / Choice / Naming / Fade drawn via Gfx.drawUi when boot routes through it;
  -- also draw here so boot path without Gfx still works.
  if Message.isOpen() then Message.draw() end
  if Choice.active then Choice.draw() end
  if Naming.isOpen() then Naming.draw() end
  Fade.draw()
end

return OakSpeech
