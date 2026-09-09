-- In-battle Poké Ball catch presentation sequencer (pret SpriteCB_BallThrow state machine).
-- Paces:
--   1. "PLAYER used the BALL!"
--   2. Ball throw arc from player side towards foe Pokémon (SE_BALL_THROW)
--   3. Ball opens (SE_BALL_OPEN) & foe Pokémon shrinks into red energy into ball
--   4. Ball closes, falls to ground, and bounces twice (SE_BALL_BOUNCE_1, SE_BALL_BOUNCE_2)
--   5. Wobble / shake loop 0..4 times with SE_BALL sound effect
--   6. Capture success (SE_BALL_CLICK, Pokédex + PC storage, victory fanfare) OR
--      Breakout (SE_BALL_OPEN, foe Pokémon restored, breakout message)

local Anim = require("src.core.game3.battle.anim")
local State = require("src.core.game3.battle.state")
local Audio = require("src.core.game3.audio")
local SE = require("src.core.game3.se_ids")
local ItemsData = require("src.core.game3.items_data")
local Pokemon = require("src.core.game3.pokemon")
local Catching = require("src.core.game3.battle.catching")

local CatchSeq = {}

CatchSeq._steps = nil
CatchSeq._i = 1
CatchSeq._waiting = false
CatchSeq._waitingMsg = false
CatchSeq._pushMsg = nil
CatchSeq._headless = false
CatchSeq._result = nil -- "catch" | "fail_catch"
CatchSeq._st = nil
CatchSeq._session = nil
CatchSeq._ballId = nil
CatchSeq._caught = false
CatchSeq._shakes = 0

function CatchSeq.reset()
  CatchSeq._steps = nil
  CatchSeq._i = 1
  CatchSeq._waiting = false
  CatchSeq._waitingMsg = false
  CatchSeq._pushMsg = nil
  CatchSeq._headless = false
  CatchSeq._result = nil
  CatchSeq._st = nil
  CatchSeq._session = nil
  CatchSeq._ballId = nil
  CatchSeq._caught = false
  CatchSeq._shakes = 0
  CatchSeq._catchResult = nil
end

function CatchSeq.busy()
  return CatchSeq._steps ~= nil
end

function CatchSeq.result()
  return CatchSeq._result
end

function CatchSeq.catchResult()
  return CatchSeq._catchResult
end

local function finish()
  CatchSeq._steps = nil
  CatchSeq._i = 1
  CatchSeq._waiting = false
  CatchSeq._waitingMsg = false
end

local function advance()
  CatchSeq._waiting = false
  CatchSeq._i = CatchSeq._i + 1
end

local function wait_busy()
  CatchSeq._waiting = true
end

--- Begin a catch animation sequence.
-- opts: { pushMsg, headless, session }
function CatchSeq.begin(st, itemId, caught, shakes, opts)
  opts = opts or {}
  CatchSeq.reset()
  CatchSeq._st = st
  CatchSeq._ballId = itemId
  CatchSeq._caught = caught and true or false
  CatchSeq._shakes = math.max(0, math.min(4, tonumber(shakes) or 0))
  CatchSeq._pushMsg = opts.pushMsg
  CatchSeq._headless = opts.headless and true or false
  CatchSeq._session = opts.session
  CatchSeq._result = caught and "catch" or "fail_catch"

  local session = opts.session
  if not session then
    local okR, Runtime = pcall(require, "src.core.game3.runtime")
    if okR and Runtime and Runtime.getSession then
      session = Runtime.getSession()
      CatchSeq._session = session
    end
  end

  local playerName = (session and (session.name or session.playerName)) or "RED"
  local ballName = ItemsData.displayName(itemId) or "POKé BALL"
  local ename = (st and st.enemy and st.enemy.mon and (st.enemy.mon.nickname or st.enemy.mon.name))
    or Pokemon.name(st and st.enemy and st.enemy.species) or "POKéMON"

  if CatchSeq._headless then
    if CatchSeq._pushMsg then
      CatchSeq._pushMsg(playerName .. " used\nthe " .. ballName .. "!")
    end
    if caught then
      local res = Catching.storeCaught(session, st and st.enemy, itemId)
      if CatchSeq._pushMsg then
        CatchSeq._pushMsg("Gotcha!\n" .. ename .. " was caught!")
        if res and res.firstTimeCaught then
          CatchSeq._pushMsg(ename .. "'s data was\nadded to the POKéDEX.")
        end
        if res and res.location == "pc" then
          CatchSeq._pushMsg(ename .. " was transferred\nto the PC.")
        end
      end
    else
      if CatchSeq._pushMsg then
        if CatchSeq._shakes == 0 then
          CatchSeq._pushMsg("Oh no! The POKéMON broke free!")
        elseif CatchSeq._shakes == 1 then
          CatchSeq._pushMsg("Aww! It appeared to be caught!")
        elseif CatchSeq._shakes == 2 then
          CatchSeq._pushMsg("Aargh! Almost had it!")
        else
          CatchSeq._pushMsg("Shoot! It was so close too!")
        end
      end
    end
    finish()
    return true
  end

  local steps = {}
  local function add(kind, data)
    steps[#steps + 1] = { kind = kind, data = data or {} }
  end

  -- Step 1: "PLAYER used the BALL!"
  add("msg", { text = playerName .. " used\nthe " .. ballName .. "!" })

  -- Step 2: Ball throw arc (72 frames for smooth, deliberate GBA flight arc)
  add("throw", {
    fromX = 36,
    fromY = 85,
    toX = 176,
    toY = 28,
    frames = 72,
  })

  -- Step 3: Ball open & absorb foe into ball
  add("absorb", {
    delayFrames = 14,
    shrinkFrames = 36,
  })

  -- Step 4: Ball drop & bounces
  add("drop_and_bounce", {
    groundY = 56,
  })

  -- Step 5: Wobble / shakes (max 3 in pret: 1, 2, or 3 shakes before breakout or capture confirmation)
  local wobbleCount = caught and 3 or math.min(3, math.max(0, CatchSeq._shakes))
  if wobbleCount > 0 then
    for s = 1, wobbleCount do
      add("wobble", { shakeIndex = s })
    end
  end

  -- Step 6: Outcome
  if caught then
    add("capture_success", {
      ballId = itemId,
      ename = ename,
    })
  else
    add("breakout", {
      shakes = math.min(3, CatchSeq._shakes),
      ename = ename,
    })
  end

  CatchSeq._steps = steps
  CatchSeq._i = 1
  CatchSeq._waiting = false
  return true
end

local function run_step(step)
  if not step then
    finish()
    return
  end

  local s = Anim.stage()
  local kind = step.kind
  local d = step.data or {}

  if kind == "msg" then
    if CatchSeq._pushMsg and d.text then
      CatchSeq._pushMsg(d.text)
    end
    CatchSeq._waiting = true
    CatchSeq._waitingMsg = true
    return
  end

  if kind == "throw" then
    s.ball.visible = true
    s.ball.frame = 0
    s.ball.side = "player"
    s.ball.rot = 0
    s.ball.ox = 0
    s.ball.oy = 0
    s.ball.darken = 0
    s.ball.flash = 0
    s.ball.x = d.fromX or 48
    s.ball.y = d.fromY or 70

    pcall(function()
      Audio.playSe(SE.SE_BALL_THROW, { pan = -64 })
    end)

    wait_busy()
    -- Deliberate, smooth GBA throw arc flight (72 frames)
    Anim.tweenStage(d.frames or 72, function(u)
      local sx, sy = d.fromX or 36, d.fromY or 85
      local tx, ty = d.toX or 176, d.toY or 28
      s.ball.x = sx + (tx - sx) * u
      -- Parabolic arc: height boost -45px at apex
      s.ball.y = sy + (ty - sy) * u - (45 * 4 * u * (1 - u))
      -- Smooth ball rotation during flight (3 full spins)
      s.ball.rot = u * math.pi * 6
    end, function()
      s.ball.x = d.toX or 176
      s.ball.y = d.toY or 28
      s.ball.rot = 0
      advance()
    end)
    return
  end

  if kind == "absorb" then
    s.ball.frame = 1
    pcall(function()
      Audio.playSe(SE.SE_BALL_OPEN, { pan = 63 })
    end)

    local p = Anim.present("enemy")
    if p then
      p.flash = 12
      p.darken = 0.6
    end
    if s.healthbox and s.healthbox.enemy then
      s.healthbox.enemy.visible = false
    end

    wait_busy()
    -- Apex delay (14f) + Mon shrink into ball (36f)
    Anim.tweenStage(d.delayFrames or 14, function() end, function()
      Anim.tweenStage(d.shrinkFrames or 36, function(u)
        if p then
          p.scale = math.max(0, 1 - u)
          p.oy = -14 * u
          p.darken = 0.6 + 0.4 * u
        end
        s.ball.frame = (u < 0.6) and 1 or 2
      end, function()
        if p then
          p.visible = false
          p.scale = 1
          p.oy = 0
          p.darken = 0
          p.flash = 0
        end
        s.ball.frame = 0
        advance()
      end)
    end)
    return
  end

  if kind == "drop_and_bounce" then
    local groundY = d.groundY or 56
    local startY = s.ball.y or 28
    wait_busy()

    -- 1. Drop to ground (14 frames)
    Anim.tweenStage(14, function(u)
      s.ball.y = startY + (groundY - startY) * (u * u)
    end, function()
      s.ball.y = groundY
      pcall(function() Audio.playSe(SE.SE_BALL_BOUNCE_1, { pan = 63 }) end)

      -- 2. Bounce 1 (hop up 12px, 14 frames)
      Anim.tweenStage(14, function(u)
        s.ball.y = groundY - (12 * 4 * u * (1 - u))
      end, function()
        s.ball.y = groundY
        pcall(function() Audio.playSe(SE.SE_BALL_BOUNCE_2, { pan = 63 }) end)

        -- 3. Bounce 2 (hop up 6px, 10 frames)
        Anim.tweenStage(10, function(u)
          s.ball.y = groundY - (6 * 4 * u * (1 - u))
        end, function()
          s.ball.y = groundY
          pcall(function() Audio.playSe(SE.SE_BALL_BOUNCE_3 or SE.SE_BALL_BOUNCE_2, { pan = 63 }) end)

          -- 4. Bounce 3 (hop up 2px, 8 frames)
          Anim.tweenStage(8, function(u)
            s.ball.y = groundY - (2 * 4 * u * (1 - u))
          end, function()
            s.ball.y = groundY
            -- Pre-shake suspense pause: 45 frames of stillness on ground
            Anim.tweenStage(45, function() end, function()
              advance()
            end)
          end)
        end)
      end)
    end)
    return
  end

  if kind == "wobble" then
    wait_busy()
    pcall(function() Audio.playSe(SE.SE_BALL, { pan = 63 }) end)

    -- Slow, heavy weighted wobble: 56 frames total
    -- 0..18f: tilt smoothly to left (-0.42 rad / -24 deg, -4px)
    -- 18..44f: rock across center all the way to right (+0.42 rad / +24 deg, +4px)
    -- 44..56f: settle upright back to center (0 rad, 0px)
    Anim.tweenStage(56, function(u)
      if u < (18 / 56) then
        local tu = u / (18 / 56)
        s.ball.rot = -0.42 * math.sin(tu * math.pi * 0.5)
        s.ball.ox = -4 * tu
      elseif u < (44 / 56) then
        local tu = (u - (18 / 56)) / (26 / 56)
        s.ball.rot = -0.42 + 0.84 * tu
        s.ball.ox = -4 + 8 * tu
      else
        local tu = (u - (44 / 56)) / (12 / 56)
        s.ball.rot = 0.42 * (1 - tu)
        s.ball.ox = 4 * (1 - tu)
      end
    end, function()
      s.ball.rot = 0
      s.ball.ox = 0
      -- Motionless suspense pause between shakes: 45 frames
      Anim.tweenStage(45, function() end, function()
        advance()
      end)
    end)
    return
  end

  if kind == "capture_success" then
    wait_busy()
    -- 48 frames suspense pause after 3rd wobble before capture click confirmation
    Anim.tweenStage(48, function() end, function()
      pcall(function() Audio.playSe(SE.SE_BALL_CLICK, { pan = 63 }) end)
      s.ball.darken = 0.55
      s.ball.flash = 6

      -- Spawn pret 1:1 capture stars (sCaptureStar from battle_anim_special.c)
      s.ball.stars = {
        { ox = 0, oy = -4, dx = 12, dy = 1, amplitude = -6, rot = 0 },
        { ox = 0, oy = -4, dx = 18, dy = -3, amplitude = -8, rot = 0.3 },
        { ox = 0, oy = -4, dx = -14, dy = 0, amplitude = -7, rot = -0.3 },
      }

      local res = Catching.storeCaught(CatchSeq._session, CatchSeq._st and CatchSeq._st.enemy, d.ballId)
      CatchSeq._catchResult = res
      local ename = d.ename or "POKéMON"

      -- Victory BGM
      pcall(function()
        local song = Audio.role("victoryWild") or 311
        Audio.playSong(song)
      end)

      if CatchSeq._pushMsg then
        CatchSeq._pushMsg("Gotcha!\n" .. ename .. " was caught!")
        if res and res.firstTimeCaught then
          CatchSeq._pushMsg(ename .. "'s data was\nadded to the POKéDEX.")
        end
        if res and res.location == "pc" then
          CatchSeq._pushMsg(ename .. " was transferred\nto the PC.")
        end
      end

      -- Animate stars hopping out in clear arcs around the ball over 36 frames
      Anim.tweenStage(36, function(u, t)
        if s.ball.stars then
          for _, st in ipairs(s.ball.stars) do
            st.ox = st.dx * u
            st.oy = -4 + st.dy * u + (st.amplitude * 4 * u * (1 - u))
            st.rot = (st.rot or 0) + 0.08
            st.alpha = u < 0.75 and 1.0 or ((1.0 - u) / 0.25)
            st.visible = true
          end
        end
      end, function()
        s.ball.stars = nil
        -- 50 frames of held captured stillness on the darkened clicked ball
        Anim.tweenStage(50, function(u)
          s.ball.darken = 0.55 * (1 - u * 0.3)
        end, function()
          s.ball.darken = 0.38
          advance()
        end)
      end)
    end)
    return
  end

  if kind == "breakout" then
    wait_busy()
    -- 40 frames suspense pause before pop-out breakout
    Anim.tweenStage(40, function() end, function()
      s.ball.frame = 1
      pcall(function() Audio.playSe(SE.SE_BALL_OPEN, { pan = 63 }) end)

      local p = Anim.present("enemy")
      if p then
        p.visible = true
        p.scale = 0.2
        p.oy = 12
        p.darken = 0
      end
      if s.healthbox and s.healthbox.enemy then
        s.healthbox.enemy.visible = true
      end

      -- 24 frames scale-up restoration
      Anim.tweenStage(24, function(u)
        if p then
          p.scale = 0.2 + 0.8 * u
          p.oy = 12 * (1 - u)
        end
        s.ball.frame = (u < 0.5) and 1 or 2
      end, function()
        if p then
          p.scale = 1
          p.oy = 0
        end
        s.ball.visible = false

        if CatchSeq._pushMsg then
          if d.shakes == 0 then
            CatchSeq._pushMsg("Oh no! The POKéMON broke free!")
          elseif d.shakes == 1 then
            CatchSeq._pushMsg("Aww! It appeared to be caught!")
          elseif d.shakes == 2 then
            CatchSeq._pushMsg("Aargh! Almost had it!")
          else
            CatchSeq._pushMsg("Shoot! It was so close too!")
          end
        end

        -- 20 frames settle pause before dialogue proceeds
        Anim.tweenStage(20, function() end, function()
          advance()
        end)
      end)
    end)
    return
  end

  advance()
end

function CatchSeq.update()
  if not CatchSeq._steps then return true end

  if CatchSeq._waitingMsg then
    local Ui = require("src.core.game3.battle.ui")
    local pending = false
    if Ui.dialogPending then
      pending = Ui.dialogPending()
    elseif not Ui._headless then
      pending = (Ui._showing == true) or (Ui._queue and #Ui._queue > 0)
    end
    if pending then
      return false
    end
    CatchSeq._waitingMsg = false
    CatchSeq._waiting = false
    advance()
  end

  if CatchSeq._waiting then
    if not Anim.busy() then
      advance()
    else
      return false
    end
  end

  local step = CatchSeq._steps[CatchSeq._i]
  if not step then
    finish()
    return true
  end
  run_step(step)
  return false
end

return CatchSeq
