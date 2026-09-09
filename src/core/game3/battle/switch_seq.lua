-- Mid-battle switch, withdraw, and send-out presentation sequencer.
-- Handles dynamic withdraw strings, sprite tweens, cry audio, shiny checks, and hazard triggers.

local Anim = require("src.core.game3.battle.anim")
local State = require("src.core.game3.battle.state")
local Audio = require("src.core.game3.audio")
local SE = require("src.core.game3.se_ids")
local SummaryData = require("src.core.game3.summary_data")

local SwitchSeq = {}

SwitchSeq._steps = nil
SwitchSeq._i = 1
SwitchSeq._waiting = false
SwitchSeq._waitingMsg = false
SwitchSeq._waitingCry = false
SwitchSeq._pushMsg = nil
SwitchSeq._onDone = nil
SwitchSeq._headless = false
SwitchSeq._st = nil

function SwitchSeq.reset()
  SwitchSeq._steps = nil
  SwitchSeq._i = 1
  SwitchSeq._waiting = false
  SwitchSeq._waitingMsg = false
  SwitchSeq._waitingCry = false
  SwitchSeq._pushMsg = nil
  SwitchSeq._onDone = nil
  SwitchSeq._st = nil
end

function SwitchSeq.busy()
  return SwitchSeq._steps ~= nil
end

local function finish()
  local cb = SwitchSeq._onDone
  SwitchSeq._steps = nil
  SwitchSeq._i = 1
  SwitchSeq._waiting = false
  SwitchSeq._waitingMsg = false
  SwitchSeq._waitingCry = false
  SwitchSeq._onDone = nil
  if cb then cb() end
end

local function advance()
  SwitchSeq._waiting = false
  SwitchSeq._i = SwitchSeq._i + 1
end

local function stage()
  return Anim.stage()
end

local function withdraw_text(battler)
  local name = battler and State.displayName(battler) or "POKéMON"
  local hp = tonumber(battler and battler.mon and battler.mon.hp) or 0
  local maxHp = tonumber(battler and battler.mon and (battler.mon.maxHp or battler.mon.maxhp)) or 1
  if maxHp < 1 then maxHp = 1 end
  local ratio = hp / maxHp
  if ratio > 0.5 then
    return string.format("%s, that's enough!\nCome back!", name)
  elseif ratio > 0.2 then
    return string.format("%s, good job!\nCome back!", name)
  else
    return string.format("%s, you did it!\nCome back!", name)
  end
end

function SwitchSeq.beginPlayerSwitch(st, newSlot, opts)
  opts = opts or {}
  SwitchSeq.reset()
  SwitchSeq._st = st
  SwitchSeq._headless = opts.headless and true or false
  SwitchSeq._pushMsg = opts.pushMsg
  SwitchSeq._onDone = opts.onDone

  local oldBattler = st.player
  local withdrawMsg = withdraw_text(oldBattler)

  if SwitchSeq._headless then
    if SwitchSeq._pushMsg then SwitchSeq._pushMsg(withdrawMsg) end
    State.trackParticipant(st, st.enemy, oldBattler and oldBattler.partyIndex or 1)
    State.syncBattlerToParty(st.player, st.playerParty)
    State.wipeVolatilesAndStages(st.player, { batonPass = opts.batonPass })
    st.player = State.makeBattler(st.playerParty[newSlot], "player", { partyIndex = newSlot })
    State.trackParticipant(st, st.enemy, newSlot)
    Anim.syncDisplayFromState(st)
    local newName = State.displayName(st.player)
    if SwitchSeq._pushMsg then SwitchSeq._pushMsg("Go! " .. newName .. "!") end
    finish()
    return false
  end

  local steps = {
    { kind = "msg", data = { text = withdrawMsg } },
    { kind = "withdraw", data = { side = "player" } },
    { kind = "swap_data", data = { side = "player", newSlot = newSlot, batonPass = opts.batonPass } },
    { kind = "sendout_player", data = { slot = newSlot } },
    { kind = "shiny_check", data = { side = "player" } },
    { kind = "cry", data = { side = "player" } },
    { kind = "msg_sendout", data = { side = "player" } },
    { kind = "healthbox", data = { side = "player" } },
    { kind = "hazard_check", data = { side = "player" } },
  }

  SwitchSeq._steps = steps
  SwitchSeq._i = 1
  return true
end

function SwitchSeq.beginSendOut(st, side, newSlot, opts)
  opts = opts or {}
  side = side or "player"
  SwitchSeq.reset()
  SwitchSeq._st = st
  SwitchSeq._headless = opts.headless and true or false
  SwitchSeq._pushMsg = opts.pushMsg
  SwitchSeq._onDone = opts.onDone

  if SwitchSeq._headless then
    if side == "player" then
      st.player = State.makeBattler(st.playerParty[newSlot], "player", { partyIndex = newSlot })
      State.trackParticipant(st, st.enemy, newSlot)
      Anim.syncDisplayFromState(st)
      if SwitchSeq._pushMsg then
        SwitchSeq._pushMsg("Go! " .. State.displayName(st.player) .. "!")
      end
    else
      st.enemy = State.makeBattler(st.foeParty[newSlot], "enemy", { partyIndex = newSlot })
      Anim.syncDisplayFromState(st)
      if SwitchSeq._pushMsg then
        local tname = (st.trainerClassName and st.trainerClassName ~= "")
          and (st.trainerClassName .. " " .. (st.trainerName or ""))
          or (st.trainerName or "TRAINER")
        SwitchSeq._pushMsg(tname .. " sent\nout " .. State.displayName(st.enemy) .. "!")
      end
    end
    finish()
    return false
  end

  local steps = {}
  if side == "player" then
    steps = {
      { kind = "swap_data", data = { side = "player", newSlot = newSlot } },
      { kind = "sendout_player", data = { slot = newSlot } },
      { kind = "shiny_check", data = { side = "player" } },
      { kind = "cry", data = { side = "player" } },
      { kind = "msg_sendout", data = { side = "player" } },
      { kind = "healthbox", data = { side = "player" } },
      { kind = "hazard_check", data = { side = "player" } },
    }
  else
    steps = {
      { kind = "swap_data", data = { side = "enemy", newSlot = newSlot } },
      { kind = "msg_sendout", data = { side = "enemy" } },
      { kind = "sendout_enemy", data = { slot = newSlot } },
      { kind = "shiny_check", data = { side = "enemy" } },
      { kind = "cry", data = { side = "enemy" } },
      { kind = "healthbox", data = { side = "enemy" } },
      { kind = "hazard_check", data = { side = "enemy" } },
    }
  end

  SwitchSeq._steps = steps
  SwitchSeq._i = 1
  return true
end

local function wait_busy()
  SwitchSeq._waiting = true
end

local function run_step(step)
  if not step then return end
  local kind = step.kind
  local d = step.data or {}
  local s = stage()
  local st = SwitchSeq._st

  if kind == "msg" then
    if SwitchSeq._pushMsg and d.text then
      SwitchSeq._pushMsg(d.text)
    end
    SwitchSeq._waiting = true
    SwitchSeq._waitingMsg = true
    return
  end

  if kind == "msg_sendout" then
    local side = d.side or "player"
    local text = ""
    if side == "player" then
      text = "Go! " .. State.displayName(st and st.player) .. "!"
    else
      local tname = (st and st.trainerClassName and st.trainerClassName ~= "")
        and (st.trainerClassName .. " " .. (st.trainerName or ""))
        or (st and st.trainerName or "TRAINER")
      text = tname .. " sent\nout " .. State.displayName(st and st.enemy) .. "!"
    end
    if SwitchSeq._pushMsg then
      SwitchSeq._pushMsg(text)
    end
    SwitchSeq._waiting = true
    SwitchSeq._waitingMsg = true
    return
  end

  if kind == "withdraw" then
    local side = d.side or "player"
    local p = Anim.present(side)
    local hb = s.healthbox[side]
    if hb then hb.visible = false end
    pcall(function() Audio.playSe(SE.SE_BALL_OPEN) end)
    wait_busy()
    Anim.tweenStage(12, function(u)
      if p then
        p.scale = math.max(0.01, 1 - u)
      end
    end, function()
      if p then
        p.visible = false
        p.scale = 1
      end
      advance()
    end)
    return
  end

  if kind == "swap_data" then
    local side = d.side or "player"
    local newSlot = d.newSlot or 1
    if side == "player" then
      if st and st.player then
        State.trackParticipant(st, st.enemy, st.player.partyIndex or 1)
        State.syncBattlerToParty(st.player, st.playerParty)
        State.wipeVolatilesAndStages(st.player, { batonPass = d.batonPass })
      end
      st.player = State.makeBattler(st.playerParty[newSlot], "player", { partyIndex = newSlot })
      State.trackParticipant(st, st.enemy, newSlot)
    else
      if st and st.enemy then
        State.syncBattlerToParty(st.enemy, st.foeParty)
        State.wipeVolatilesAndStages(st.enemy)
      end
      st.enemy = State.makeBattler(st.foeParty[newSlot], "enemy", { partyIndex = newSlot })
    end
    Anim.syncDisplayFromState(st)
    advance()
    return
  end

  if kind == "sendout_player" then
    local pcx, pcy = Anim.PLAYER_MON.x, Anim.PLAYER_MON.y
    s.ball.visible = true
    s.ball.frame = 0
    s.ball.side = "player"
    s.ball.x = 48
    s.ball.y = 70
    pcall(function() Audio.playSe(SE.SE_BALL_THROW, { pan = -64 }) end)
    wait_busy()
    Anim.tweenStage(20, function(u)
      local sx, sy = 48, 70
      local tx, ty = pcx, pcy + 24
      s.ball.x = sx + (tx - sx) * u
      s.ball.y = sy + (ty - sy) * u + (-24 * 4 * u * (1 - u))
    end, function()
      s.ball.frame = 1
      pcall(function() Audio.playSe(SE.SE_BALL_OPEN, { pan = -64 }) end)
      local p = Anim.present("player")
      p.visible = true
      p.ox = 0
      p.oy = 16
      p.scale = 0.2
      p.darken = 0
      Anim.tweenStage(12, function(u)
        p.oy = 16 * (1 - u)
        p.scale = 0.2 + 0.8 * u
        s.ball.frame = (u < 0.5) and 1 or 2
      end, function()
        p.oy = 0
        p.scale = 1
        s.ball.visible = false
        advance()
      end)
    end)
    return
  end

  if kind == "sendout_enemy" then
    local cx, cy = Anim.ENEMY_MON.x, Anim.ENEMY_MON.y
    s.ball.visible = true
    s.ball.frame = 0
    s.ball.side = "enemy"
    s.ball.x = cx
    s.ball.y = cy + 24
    wait_busy()
    Anim.tweenStage(12, function() end, function()
      s.ball.frame = 1
      pcall(function() Audio.playSe(SE.SE_BALL_OPEN, { pan = 63 }) end)
      local p = Anim.present("enemy")
      p.visible = true
      p.ox = 0
      p.oy = 16
      p.scale = 0.2
      p.darken = 0
      Anim.tweenStage(12, function(u)
        p.oy = 16 * (1 - u)
        p.scale = 0.2 + 0.8 * u
        s.ball.frame = (u < 0.5) and 1 or 2
      end, function()
        p.oy = 0
        p.scale = 1
        s.ball.visible = false
        advance()
      end)
    end)
    return
  end

  if kind == "shiny_check" then
    local side = d.side or "player"
    local b = st and st[side]
    local mon = b and b.mon
    local isShiny = mon and SummaryData.isShiny(mon)
    if isShiny then
      pcall(function() Audio.playSe(SE.SE_SHINY) end)
      wait_busy()
      Anim.tweenStage(24, function() end, function()
        advance()
      end)
      return
    end
    advance()
    return
  end

  if kind == "cry" then
    local side = d.side or "player"
    local b = st and st[side]
    local sp = b and (b.species or (b.mon and (b.mon.species or b.mon.speciesId)))
    if sp then
      local pan = (side == "player") and -64 or 63
      Audio.playCry(sp, { pan = pan })
    end
    SwitchSeq._waiting = true
    SwitchSeq._waitingCry = true
    return
  end

  if kind == "healthbox" then
    local side = d.side or "player"
    local hb = s.healthbox[side]
    local from = (side == "player") and 115 or -115
    hb.visible = true
    hb.ox = from
    wait_busy()
    Anim.tweenStage(20, function(u)
      hb.ox = from * (1 - u)
    end, function()
      hb.ox = 0
      advance()
    end)
    return
  end

  if kind == "hazard_check" then
    local side = d.side or "player"
    local sideState = (side == "player") and st.playerSide or st.enemySide
    local hazards = sideState and sideState.hazards or {}
    local spikesLayers = tonumber(hazards.spikes or hazards.SPIKES) or 0
    local b = st and st[side]
    if spikesLayers > 0 and b and b.mon then
      local isFlying = (b.type1 == 2 or b.type2 == 2 or b.type1 == "FLYING" or b.type2 == "FLYING")
      local hasLevitate = (b.ability == "LEVITATE" or b.ability == 26)
      if not isFlying and not hasLevitate then
        local maxHp = tonumber(b.mon.maxHp) or 1
        local fraction = (spikesLayers == 1) and 8 or (spikesLayers == 2 and 6 or 4)
        local dmg = math.max(1, math.floor(maxHp / fraction))
        State.applyHpLoss(b, dmg)
        local msg = State.displayName(b) .. " is hurt\nby the SPIKES!"
        if SwitchSeq._pushMsg then SwitchSeq._pushMsg(msg) end
        local p = Anim.present(side)
        if p then
          Anim.tweenHp(side, p.displayHp or maxHp, b.mon.hp, maxHp)
        end
      end
    end
    advance()
    return
  end

  advance()
end

function SwitchSeq.update()
  if not SwitchSeq._steps then return true end

  if SwitchSeq._waitingCry then
    if Audio.isCryPlaying and Audio.isCryPlaying() then
      return false
    end
    SwitchSeq._waitingCry = false
    SwitchSeq._waiting = false
    advance()
  end

  if SwitchSeq._waitingMsg then
    local Ui = package.loaded["src.core.game3.battle.ui"]
    local pending = Ui and (Ui.isShowing and Ui.isShowing() or (Ui.busy and Ui.busy()))
    if pending then
      return false
    end
    SwitchSeq._waitingMsg = false
    SwitchSeq._waiting = false
    advance()
  end

  if SwitchSeq._waiting then
    if Anim.busy() then
      return false
    end
    SwitchSeq._waiting = false
  end

  while SwitchSeq._steps and SwitchSeq._i <= #SwitchSeq._steps do
    run_step(SwitchSeq._steps[SwitchSeq._i])
    if SwitchSeq._waiting or SwitchSeq._waitingCry or SwitchSeq._waitingMsg then
      return false
    end
  end

  finish()
  return true
end

return SwitchSeq
