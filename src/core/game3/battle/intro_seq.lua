-- Battle intro presentation (pret BeginBattleIntro + DoPokeballSendOutAnimation).
-- Separate from AnimSeq (hit loop); same contract as ExpSeq.

local Anim = require("src.core.game3.battle.anim")
local State = require("src.core.game3.battle.state")
local Audio = require("src.core.game3.audio")
local SE = require("src.core.game3.se_ids")

local IntroSeq = {}

IntroSeq._steps = nil
IntroSeq._i = 1
IntroSeq._waiting = false
IntroSeq._pushMsg = nil
IntroSeq._headless = false
IntroSeq._opts = nil

function IntroSeq.reset()
  IntroSeq._steps = nil
  IntroSeq._i = 1
  IntroSeq._waiting = false
  IntroSeq._waitingMsg = false
  IntroSeq._waitingFade = false
  IntroSeq._waitingCry = false
  IntroSeq._pendingSlideIn = nil
  IntroSeq._pushMsg = nil
  IntroSeq._opts = nil
end

function IntroSeq.busy()
  return IntroSeq._steps ~= nil
end

local function finish()
  IntroSeq._steps = nil
  IntroSeq._i = 1
  IntroSeq._waiting = false
  IntroSeq._waitingMsg = false
  IntroSeq._waitingFade = false
  IntroSeq._waitingCry = false
  IntroSeq._pendingSlideIn = nil
end

local function advance()
  IntroSeq._waiting = false
  IntroSeq._i = IntroSeq._i + 1
end

local function stage()
  return Anim.stage()
end

local function ball_status(mon)
  if not mon then return "empty" end
  local hp = tonumber(mon.hp) or 0
  if hp <= 0 then return "faint" end
  local status = mon.status
  if status and status ~= 0 and status ~= "" then return "status" end
  return "ok"
end

local function player_party_balls(party)
  local balls = {}
  local count = #(party or {})
  for i = 1, 6 do
    if i <= count and party[i] then
      balls[i] = ball_status(party[i])
    else
      balls[i] = "empty"
    end
  end
  return balls
end

local function enemy_party_balls(foeParty, partySize)
  local balls = {}
  local count = math.max(1, math.min(6, tonumber(partySize) or (foeParty and #foeParty) or 1))
  local s = 6
  for i = 1, 6 do
    if i <= count then
      local mon = foeParty and foeParty[i]
      balls[s] = mon and ball_status(mon) or "ok"
    else
      balls[s] = "empty"
    end
    s = s - 1
  end
  return balls
end

local function build_wild(st, opts)
  local steps = {}
  local function add(kind, data)
    steps[#steps + 1] = { kind = kind, data = data or {} }
  end
  local ename = State.displayName(st.enemy)
  local pname = State.displayName(st.player)
  add("fade", { mode = "FROM_BLACK", speed = 1 })
  -- pret: player back sprite slides in with the BG intro even in wild battles
  -- (BattleIntroDrawTrainersOrMonsSprites → EmitDrawTrainerPic for PLAYER_LEFT).
  add("bgslide", {
    frames = 24,
    unlockAt = 8,
    slidePlayer = true,
    slideEnemyMon = true,
    playerFrom = 240,
    playerTo = 0,
    enemyMonFrom = -240,
    enemyMonTo = 0,
    slideFrames = 120,
    darken = 10 / 16,
    gender = opts.playerGender or 0,
  })
  add("cry", { side = "enemy" })  add("undarken", { side = "enemy", frames = 10 })
  add("healthbox", { side = "enemy", frames = 23, from = -115 })
  add("msg", { text = "Wild " .. ename .. " appeared!" })
  add("msg", { text = "Go! " .. pname .. "!" })
  add("player_throw", {})
  add("healthbox", { side = "player", frames = 23, from = 115 })
  add("wait", { frames = 3 })
  return steps
end

local function build_trainer(st, opts)
  local steps = {}
  local function add(kind, data)
    steps[#steps + 1] = { kind = kind, data = data or {} }
  end
  local Trainers = require("src.core.game3.scripting.trainers")
  local strings = Trainers.introStrings(
    opts.trainerId or st.trainerId,
    State.displayName(st.enemy),
    { rivalName = opts.rivalName })
  local info = strings.info or {}
  local pname = State.displayName(st.player)
  local enemyBalls = enemy_party_balls(st.foeParty, info.partySize or (st.foeParty and #st.foeParty) or 1)
  local playerBalls = player_party_balls(st.playerParty or (st.player and { st.player.mon }))

  add("fade", { mode = "FROM_BLACK", speed = 1 })
  -- pret: DrawTrainerPic for both sides during BG slide; sprites wait off-screen
  -- until gIntroSlideFlags clears, then SpriteCB_TrainerSlideIn (~120f at 2px/frame).
  add("bgslide", {
    frames = 24,
    unlockAt = 8,
    slidePlayer = true,
    slideEnemy = true,
    playerFrom = 240,
    playerTo = 0,
    enemyFrom = -240,
    enemyTo = 0,
    slideFrames = 120,
    picId = opts.trainerPicId or info.pic,
    gender = opts.playerGender or 0,
  })
  add("partybar", {
    enemyBalls = enemyBalls,
    playerBalls = playerBalls,
    frames = 20,
  })
  add("msg", { text = strings.wants })
  add("msg", { text = strings.sentOut })
  add("opponent_sendout", { toX = 280, frames = 35 })
  add("cry", { side = "enemy" })
  add("healthbox", { side = "enemy", frames = 23, from = -115 })
  add("msg", { text = "Go! " .. pname .. "!" })
  add("player_throw", {})
  add("healthbox", { side = "player", frames = 23, from = 115 })
  add("wait", { frames = 3 })
  return steps
end

--- Begin intro. Returns false when headless (caller pushes strings).
function IntroSeq.begin(st, opts)
  opts = opts or {}
  IntroSeq.reset()
  IntroSeq._opts = opts
  IntroSeq._pushMsg = opts.pushMsg
  IntroSeq._headless = opts.headless and true or false
  if IntroSeq._headless or not st then
    return false
  end

  local s = stage()
  s.slide = 0
  s.slideDone = false
  s.trainer.player.visible = false
  s.trainer.enemy.visible = false
  s.ball.visible = false
  s.healthbox.player.visible = false
  s.healthbox.enemy.visible = false
  s.partyBar.player.visible = false
  s.partyBar.enemy.visible = false
  Anim.present("player").visible = false
  Anim.present("enemy").visible = false
  Anim.present("player").ox = 0
  Anim.present("enemy").ox = 0
  Anim.present("player").darken = 0
  Anim.present("enemy").darken = 0
  Anim.present("player").scale = 1
  Anim.present("enemy").scale = 1

  -- Park terrain and sliding sprites off-screen immediately so the first
  -- rendered frame (and fade-in) starts with them in initial slide positions.
  s.bgSlide = { enemyOx = -240, playerOx = 240 }
  s.trainer.player.visible = true
  s.trainer.player.gender = opts.playerGender or 0
  s.trainer.player.ox = 240
  s.trainer.player.frame = 0

  if st.wild then
    local p = Anim.present("enemy")
    p.visible = true
    p.ox = -240
    p.darken = 10 / 16
    IntroSeq._steps = build_wild(st, opts)
  else
    s.trainer.enemy.visible = true
    s.trainer.enemy.picId = opts.trainerPicId or st.trainerPicId
    s.trainer.enemy.ox = -240
    IntroSeq._steps = build_trainer(st, opts)
  end
  IntroSeq._i = 1
  return true
end

local function wait_busy()
  IntroSeq._waiting = true
end

local function run_step(step)
  local kind = step.kind
  local d = step.data or {}
  local s = stage()

  if kind == "fade" then
    local okF, Fade = pcall(require, "src.ui.game3.fade")
    if okF and Fade and Fade.begin then
      local mode = Fade.MODE and Fade.MODE[d.mode or "FROM_BLACK"] or 0
      IntroSeq._waiting = true
      IntroSeq._waitingFade = true
      Fade.begin(mode, d.speed or 1, function()
        IntroSeq._waitingFade = false
        IntroSeq._waiting = false
        advance()
      end)
    else
      advance()
    end
    return
  end

  if kind == "bgslide" then
    local frames = d.frames or 24
    local unlockAt = d.unlockAt or 8
    local slideFrames = d.slideFrames or 120
    local needSpriteSlide = d.slidePlayer or d.slideEnemy or d.slideEnemyMon
    s.bgSlide = s.bgSlide or { enemyOx = 0, playerOx = 0 }
    -- pret DrawTrainersOrMonsSprites: park sprites off-screen immediately;
    -- SpriteCB_TrainerSlideIn starts once gIntroSlideFlags clears (unlockAt).
    if d.slidePlayer then
      s.trainer.player.visible = true
      s.trainer.player.gender = d.gender or 0
      s.trainer.player.ox = d.playerFrom or 240
      s.trainer.player.frame = 0
      s.bgSlide.playerOx = d.playerFrom or 240
    end
    if d.slideEnemy then
      s.trainer.enemy.visible = true
      s.trainer.enemy.picId = d.picId
      s.trainer.enemy.ox = d.enemyFrom or -240
      s.bgSlide.enemyOx = d.enemyFrom or -240
    end
    if d.slideEnemyMon then
      local p = Anim.present("enemy")
      p.visible = true
      p.ox = d.enemyMonFrom or d.from or -240
      p.darken = d.darken or (10 / 16)
      s.bgSlide.enemyOx = d.enemyMonFrom or d.from or -240
    end
    wait_busy()
    local spritesStarted = false
    local spritesDone = not needSpriteSlide
    local bgDone = false
    local function try_advance()
      if bgDone and spritesDone then
        s.bgSlide.enemyOx = 0
        s.bgSlide.playerOx = 0
        advance()
      end
    end
    local function start_sprite_slide()
      if spritesStarted or not needSpriteSlide then return end
      spritesStarted = true
      local pFrom = d.playerFrom or 240
      local pTo = d.playerTo or 0
      local eFrom = d.enemyFrom or -240
      local eTo = d.enemyTo or 0
      local mFrom = d.enemyMonFrom or d.from or -240
      local mTo = d.enemyMonTo or d.to or 0
      Anim.tweenStage(slideFrames, function(u)
        if d.slidePlayer then
          s.trainer.player.ox = pFrom + (pTo - pFrom) * u
          s.bgSlide.playerOx = pFrom + (pTo - pFrom) * u
        end
        if d.slideEnemy then
          s.trainer.enemy.ox = eFrom + (eTo - eFrom) * u
          s.bgSlide.enemyOx = eFrom + (eTo - eFrom) * u
        end
        if d.slideEnemyMon then
          local p = Anim.present("enemy")
          p.ox = mFrom + (mTo - mFrom) * u
          s.bgSlide.enemyOx = mFrom + (mTo - mFrom) * u
        end
      end, function()
        if d.slidePlayer then
          s.trainer.player.ox = pTo
          s.bgSlide.playerOx = pTo
        end
        if d.slideEnemy then
          s.trainer.enemy.ox = eTo
          s.bgSlide.enemyOx = eTo
        end
        if d.slideEnemyMon then
          Anim.present("enemy").ox = mTo
          s.bgSlide.enemyOx = mTo
        end
        spritesDone = true
        try_advance()
      end)
    end
    Anim.tweenStage(frames, function(u)
      s.slide = u
      if u * frames >= unlockAt then
        s.slideDone = true
        start_sprite_slide()
      end
    end, function()
      s.slide = 1
      s.slideDone = true
      start_sprite_slide()
      bgDone = true
      try_advance()
    end)
    return
  end

  if kind == "slidein" then
    if d.who == "enemy_mon" then
      local p = Anim.present("enemy")
      p.visible = true
      p.ox = d.from or -240
      p.darken = d.darken or (10 / 16)
      wait_busy()
      local function start_move()
        Anim.tweenStage(d.frames or 120, function(u)
          p.ox = (d.from or -240) + ((d.to or 0) - (d.from or -240)) * u
        end, function()
          p.ox = d.to or 0
          advance()
        end)
      end
      if s.slideDone then
        start_move()
      else
        -- Wait until intro slide releases sprites.
        IntroSeq._pendingSlideIn = start_move
        wait_busy()
      end
      return
    end
    if d.who == "both_trainers" then
      s.trainer.enemy.visible = true
      s.trainer.enemy.picId = d.picId
      s.trainer.enemy.ox = d.enemyFrom or -240
      s.trainer.player.visible = true
      s.trainer.player.gender = d.gender or 0
      s.trainer.player.ox = d.playerFrom or 240
      s.trainer.player.frame = 0
      wait_busy()
      local function start_move()
        Anim.tweenStage(d.frames or 120, function(u)
          s.trainer.enemy.ox = (d.enemyFrom or -240)
            + ((d.enemyTo or 0) - (d.enemyFrom or -240)) * u
          s.trainer.player.ox = (d.playerFrom or 240)
            + ((d.playerTo or 0) - (d.playerFrom or 240)) * u
        end, function()
          s.trainer.enemy.ox = d.enemyTo or 0
          s.trainer.player.ox = d.playerTo or 0
          advance()
        end)
      end
      if s.slideDone then
        start_move()
      else
        IntroSeq._pendingSlideIn = start_move
        wait_busy()
      end
      return
    end
  end

  if kind == "undarken" then
    local p = Anim.present(d.side or "enemy")
    local from = p.darken or 0
    wait_busy()
    Anim.tweenStage(d.frames or 10, function(u)
      p.darken = from * (1 - u)
    end, function()
      p.darken = 0
      advance()
    end)
    return
  end

  if kind == "partybar" then
    s.partyBar.enemy.visible = true
    s.partyBar.enemy.ox = -100
    s.partyBar.enemy.balls = d.enemyBalls or { "ok" }
    s.partyBar.player.visible = true
    s.partyBar.player.ox = 100
    s.partyBar.player.balls = d.playerBalls or { "ok" }
    wait_busy()
    Anim.tweenStage(d.frames or 20, function(u)
      s.partyBar.enemy.ox = -100 + 100 * u
      s.partyBar.player.ox = 100 - 100 * u
    end, function()
      s.partyBar.enemy.ox = 0
      s.partyBar.player.ox = 0
      advance()
    end)
    return
  end

  if kind == "msg" then
    if IntroSeq._pushMsg and d.text then
      IntroSeq._pushMsg(d.text)
    end
    -- pret waits for PrintString / controller exec before send-out / slide-out.
    -- Do not advance past this step until Ui has shown + dismissed the line.
    IntroSeq._waiting = true
    IntroSeq._waitingMsg = true
    return
  end

  if kind == "trainerexit" then
    local side = d.side or "enemy"
    local tr = s.trainer[side]
    local from = tr.ox or 0
    local to = (side == "enemy") and (d.toX or 280) - 176 or (d.toX or -40) - 80
    -- Store as ox delta from resting center: resting ox=0 at center.
    -- Enemy exit: center 176 → 280 ⇒ ox 0 → 104
    if side == "enemy" then
      to = (d.toX or 280) - 176
    else
      to = (d.toX or -40) - 80
    end
    s.partyBar[side].visible = false
    wait_busy()
    Anim.tweenStage(d.frames or 35, function(u)
      tr.ox = from + (to - from) * u
    end, function()
      tr.ox = to
      tr.visible = false
      advance()
    end)
    return
  end

  if kind == "opponent_sendout" then
    local cx, cy = Anim.ENEMY_MON.x, Anim.ENEMY_MON.y
    local tr = s.trainer.enemy
    local exitFrom = tr.ox or 0
    local exitTo = (d.toX or 280) - 176
    s.partyBar.enemy.visible = false
    s.ball.visible = true
    s.ball.frame = 0
    s.ball.rot = 0
    s.ball.side = "enemy"
    s.ball.x = cx
    s.ball.y = cy + 24
    wait_busy()
    -- pret OpponentHandleIntroTrainerBallThrow: starts linear slide-out (35 frames)
    -- AND StartSendOutAnim (16f delay + 12f emergence).
    local totalFrames = d.frames or 35
    local openedSe = false
    Anim.tweenStage(totalFrames, function(u, t)
      local f = t.frames
      -- Opponent trainer slides offscreen (35 frames)
      tr.ox = exitFrom + (exitTo - exitFrom) * math.min(1, f / totalFrames)
      if f >= totalFrames then
        tr.visible = false
      end
      -- Ball opens after 16 frames delay (SpriteCB_OpponentMonSendOut)
      if f == 16 then
        s.ball.frame = 1
        if not openedSe then
          openedSe = true
          pcall(function() Audio.playSe(SE.SE_BALL_OPEN, { pan = 63 }) end)
        end
        local p = Anim.present("enemy")
        p.visible = true
        p.ox = 0
        p.oy = 16
        p.scale = 0.16
        p.darken = 0
      end
      -- Emergence over 12 frames (frames 16..28) matching pret BATTLER_AFFINE_EMERGE
      if f > 16 and f <= 28 then
        local eu = (f - 16) / 12
        local p = Anim.present("enemy")
        p.oy = 16 * (1 - eu)
        p.scale = 0.16 + 0.84 * eu
        s.ball.frame = (eu < 0.5) and 1 or 2
      end
      if f > 28 then
        local p = Anim.present("enemy")
        p.oy = 0
        p.scale = 1
        s.ball.visible = false
      end
    end, function()
      tr.visible = false
      tr.ox = exitTo
      s.ball.visible = false
      local p = Anim.present("enemy")
      p.oy = 0
      p.scale = 1
      advance()
    end)
    return
  end

  if kind == "player_throw" then
    local tr = s.trainer.player
    if not tr.visible then
      tr.visible = true
      tr.ox = 0
      tr.frame = 0
      tr.gender = (IntroSeq._opts and IntroSeq._opts.playerGender) or 0
    end
    s.partyBar.player.visible = false
    -- pret sAnimCmd_Red_1: 1(20) 2(6) 3(6) 4(24) 0(1) = 57f; exit linear ox 0→-120 over 50f.
    local pose = { { 1, 20 }, { 2, 6 }, { 3, 6 }, { 4, 24 }, { 0, 1 } }
    local poseFrame, poseLeft, poseI = 0, 0, 0
    local exitTo = -120
    local pcx, pcy = Anim.PLAYER_MON.x, Anim.PLAYER_MON.y
    local threwSe, openedSe = false, false
    wait_busy()
    Anim.tweenStage(57, function(u, t)
      local f = t.frames
      if poseLeft <= 0 then
        poseI = poseI + 1
        local entry = pose[poseI]
        if entry then
          poseFrame = entry[1]
          poseLeft = entry[2]
        end
      end
      poseLeft = poseLeft - 1
      tr.frame = poseFrame
      if f <= 50 then
        tr.ox = exitTo * (f / 50)
      else
        tr.visible = false
        tr.ox = exitTo
      end
      -- pret Task_StartSendOutAnim (31f delay) + Task_DoPokeballSendOutAnim (1f delay) -> spawn at frame 32
      if f == 32 then
        s.ball.visible = true
        s.ball.frame = 0
        s.ball.rot = 0
        s.ball.side = "player"
        s.ball.x = 48
        s.ball.y = 70
        s.ball._sx, s.ball._sy = 48, 70
        s.ball._tx, s.ball._ty = pcx, pcy + 24
        if not threwSe then
          threwSe = true
          pcall(function() Audio.playSe(SE.SE_BALL_THROW, { pan = -64 }) end)
        end
      end
      -- pret SpriteCB_PlayerMonSendOut_1 / 2: 25 frames arc flight with affine rotation
      if f > 32 and f <= 57 and s.ball.visible then
        local bu = (f - 32) / 25
        local sx, sy = s.ball._sx, s.ball._sy
        local tx, ty = s.ball._tx, s.ball._ty
        s.ball.x = sx + (tx - sx) * bu
        s.ball.y = sy + (ty - sy) * bu + (-30 * 4 * bu * (1 - bu))
        -- pret sAffineAnim_BallRotate_4: 25 units per frame (approx 0.613 rad/frame)
        s.ball.rot = (f - 32) * ((25 / 256) * math.pi * 2)
      end
    end, function()
      tr.visible = false
      tr.ox = exitTo
      s.ball.frame = 1
      s.ball.rot = 0
      if not openedSe then
        openedSe = true
        pcall(function() Audio.playSe(SE.SE_BALL_OPEN, { pan = -64 }) end)
      end
      local Battle = package.loaded["src.core.game3.battle"]
      local st = Battle and Battle._st
      local species = st and st.player and (st.player.species or (st.player.mon and (st.player.mon.species or st.player.mon.speciesId)))
      if species then
        pcall(function() Audio.playCry(species) end)
      end
      local p = Anim.present("player")
      p.visible = true
      p.ox = 0
      p.oy = 16
      p.scale = 0.16
      -- pret BATTLER_AFFINE_EMERGE: 12 frames scaling 40/256 to 256/256
      Anim.tweenStage(12, function(uu)
        p.oy = 16 * (1 - uu)
        p.scale = 0.16 + 0.84 * uu
        s.ball.frame = (uu < 0.5) and 1 or 2
      end, function()
        p.oy = 0
        p.scale = 1
        s.ball.visible = false
        s.ball.rot = 0
        advance()
      end)
    end)
    return
  end

  if kind == "cry" then
    local side = d.side or "enemy"
    local Battle = package.loaded["src.core.game3.battle"]
    local st = Battle and Battle._st
    local battler = st and st[side]
    local species = battler and (battler.species
      or (battler.mon and (battler.mon.species or battler.mon.speciesId)))
    if species then
      Audio.playCry(species)
    end
    IntroSeq._waiting = true
    IntroSeq._waitingCry = true
    return
  end

  if kind == "healthbox" then
    local side = d.side or "enemy"
    local hb = s.healthbox[side]
    local from = d.from or ((side == "player") and 115 or -115)
    hb.visible = true
    hb.ox = from
    wait_busy()
    Anim.tweenStage(d.frames or 23, function(u)
      hb.ox = from * (1 - u)
    end, function()
      hb.ox = 0
      advance()
    end)
    return
  end

  if kind == "wait" then
    wait_busy()
    Anim.tweenStage(d.frames or 1, function() end, function()
      advance()
    end)
    return
  end

  advance()
end

function IntroSeq.update()
  if not IntroSeq._steps then return true end

  if IntroSeq._pendingSlideIn and Anim.introSlideDone() then
    local fn = IntroSeq._pendingSlideIn
    IntroSeq._pendingSlideIn = nil
    fn()
  end

  if IntroSeq._waitingCry then
    if (not Audio.isCryFinished) or Audio.isCryFinished() then
      IntroSeq._waitingCry = false
      IntroSeq._waiting = false
      advance()
    else
      return false
    end
  end

  -- Hold on intro dialog until the battle UI queue is drained (wants / sent out).
  if IntroSeq._waitingMsg then
    local Ui = require("src.core.game3.battle.ui")
    local pending = false
    if Ui.dialogPending then
      pending = Ui.dialogPending()
    elseif not Ui._headless then
      local Message = package.loaded["src.ui.game3.message"]
      pending = (Ui._showing == true)
        or (Ui._queue and #Ui._queue > 0)
        or (Message and Message.isOpen and Message.isOpen())
    end
    if pending then
      return false
    end
    IntroSeq._waitingMsg = false
    IntroSeq._waiting = false
    advance()
  end

  if IntroSeq._waiting then
    if Anim.busy() or IntroSeq._waitingFade or IntroSeq._pendingSlideIn then
      return false
    end
    IntroSeq._waiting = false
  end

  while IntroSeq._steps and IntroSeq._i <= #IntroSeq._steps do
    run_step(IntroSeq._steps[IntroSeq._i])
    if IntroSeq._waiting or IntroSeq._waitingFade or IntroSeq._waitingCry
        or IntroSeq._waitingMsg or IntroSeq._pendingSlideIn then
      return false
    end
  end

  finish()
  return true
end

return IntroSeq
