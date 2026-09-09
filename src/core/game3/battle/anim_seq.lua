-- Host hit sequencer: pret battle-script loop analogue
-- (anim → wait VM → tween HP → wait tween) per hit for multi-hit / drain.

local Anim = require("src.core.game3.battle.anim")

local AnimSeq = {}

AnimSeq._steps = nil
AnimSeq._i = 1
AnimSeq._waiting = false
AnimSeq._waitingMsg = false
AnimSeq._pushMsg = nil
AnimSeq._hitSe = nil
AnimSeq._pendingEff = nil -- { effectiveness, pan } until anim ends

local function play_effectiveness_se(eff, pan)
  local Audio = require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")
  eff = tonumber(eff) or 1
  local id = SE.SE_EFFECTIVE
  if eff == 0 then
    id = nil
  elseif eff >= 2 then
    id = SE.SE_SUPER_EFFECTIVE
  elseif eff > 0 and eff < 1 then
    id = SE.SE_NOT_EFFECTIVE
  end
  if id then
    Audio.playSe(id, { pan = pan or 63 })
  end
end

local function flush_pending_eff()
  local p = AnimSeq._pendingEff
  AnimSeq._pendingEff = nil
  if p and p.effectiveness ~= nil then
    play_effectiveness_se(p.effectiveness, p.pan)
  end
end

function AnimSeq.reset()
  AnimSeq._steps = nil
  AnimSeq._i = 1
  AnimSeq._waiting = false
  AnimSeq._waitingMsg = false
  AnimSeq._pushMsg = nil
  AnimSeq._hitSe = nil
  AnimSeq._pendingEff = nil
  Anim.setSeqBusy(false)
end

function AnimSeq.busy()
  return AnimSeq._steps ~= nil
end

local function side_of(battler)
  return battler and battler.side or "enemy"
end

local function finish_seq()
  AnimSeq._steps = nil
  AnimSeq._i = 1
  AnimSeq._waiting = false
  AnimSeq._waitingMsg = false
  Anim.setSeqBusy(false)
end

local function advance()
  AnimSeq._waiting = false
  AnimSeq._i = AnimSeq._i + 1
end

--- Build and start a presentation sequence from Engine.resolveMove result table.
-- result fields (set by engine):
--   msgs, moveId, user, target, hits[{from,to,maxHp,side}], missed, statusOnly, faints[]
function AnimSeq.begin(result, pushMsg)
  AnimSeq.reset()
  if not result then
    return
  end
  local steps = {}
  local function add(kind, data)
    steps[#steps + 1] = { kind = kind, data = data }
  end

  -- Opening "used MOVE!" is first msg; push separately then anim
  local msgs = result.msgs or {}
  local usedLine = msgs[1]
  local restStart = 1
  if usedLine and tostring(usedLine):find("used") then
    add("msg", { text = usedLine })
    restStart = 2
  end

  if result.missed then
    add("anim", { moveId = result.moveId, user = result.user, target = result.target, miss = true })
  elseif result.hits and #result.hits > 0 then
    for hi, hit in ipairs(result.hits) do
      -- pret BattleScript_HitFromCritCalc: attackanimation → waitanimation →
      -- effectivenesssound → hitanimation. Thud plays after the move anim finishes
      -- so move SE (same MusicPlayer as SE_EFFECTIVE for Tackle) can be heard.
      add("anim", {
        moveId = result.moveId,
        user = result.user,
        target = result.target,
        effectiveness = (hi == 1) and result.effectiveness or nil,
      })
      add("hp", hit)
    end
  elseif not result.statusOnly then
    -- Damaging with no hit list (shouldn't happen) — still play anim
    add("anim", { moveId = result.moveId, user = result.user, target = result.target })
  else
    add("anim", { moveId = result.moveId, user = result.user, target = result.target })
  end

  -- Heal on user (Absorb)
  if result.heals then
    for _, h in ipairs(result.heals) do
      add("hp", h)
    end
  end

  local faintI = 1
  local faints = result.faints or {}
  for i = restStart, #msgs do
    local text = msgs[i]
    add("msg", { text = text })
    if type(text) == "string" and text:find("fainted") then
      local side = faints[faintI] and faints[faintI].side
      if not side then
        if faintI == 1 then
          side = side_of(result.target)
        else
          side = side_of(result.user)
        end
      end
      faintI = faintI + 1
      -- pret: waitmessage on faint line, then FaintAnimation (SE + sink).
      add("faint", { side = side })
    end
  end

  if #steps == 0 then
    finish_seq()
    return
  end

  AnimSeq._steps = steps
  AnimSeq._i = 1
  AnimSeq._waiting = false
  AnimSeq._pushMsg = pushMsg
  Anim.setSeqBusy(true)
end

local function run_step(step)
  if not step then
    finish_seq()
    return
  end
  local kind = step.kind
  local d = step.data or {}

  if kind == "msg" then
    if AnimSeq._pushMsg and d.text then
      AnimSeq._pushMsg(d.text)
    end
    -- Hold until dismissed so faint sink starts after "X fainted!" (pret waitmessage).
    AnimSeq._waiting = true
    AnimSeq._waitingMsg = true
    return
  end

  if kind == "anim" then
    AnimSeq._waiting = true
    local user = d.user
    local isReversed = user and user.side == "enemy"
    AnimSeq._pendingEff = nil
    if d.effectiveness ~= nil then
      local pan = 63
      if d.target and d.target.side == "player" then pan = -64 end
      AnimSeq._pendingEff = { effectiveness = d.effectiveness, pan = pan }
    end
    Anim.launchMove(d.moveId, {
      miss = d.miss,
      isReversed = isReversed,
      attackerSide = user and user.side or "player",
      targetSide = d.target and d.target.side or "enemy",
      onEnd = function()
        -- pret: waitanimation then Cmd_effectivenesssound.
        flush_pending_eff()
        advance()
      end,
    })
    -- If launch instant-completed (headless), onEnd already ran
    if not Anim.busy() and AnimSeq._waiting then
      if not Anim.vm() or Anim.vm():idle() then
        if AnimSeq._waiting then
          flush_pending_eff()
          advance()
        end
      end
    end
    return
  end

  if kind == "hp" then
    AnimSeq._waiting = true
    Anim.tweenHp(d.side, d.from, d.to, d.maxHp, {
      onComplete = function()
        advance()
      end,
    })
    if not Anim.busy() and AnimSeq._waiting then
      advance()
    end
    return
  end

  if kind == "hitse" then
    -- Legacy step; normal path plays on anim end.
    play_effectiveness_se(d.effectiveness, d.pan or 63)
    advance()
    return
  end

  if kind == "faint" or kind == "faintse" then
    AnimSeq._waiting = true
    Anim.faintMon(d.side or "enemy", {
      onComplete = function()
        advance()
      end,
    })
    if not Anim.busy() and AnimSeq._waiting then
      advance()
    end
    return
  end

  advance()
end

--- No-op: effectiveness SE is tied to anim onEnd (was mid-anim and cut move SE).
function AnimSeq.tickHitSe()
end

function AnimSeq.update()
  if not AnimSeq._steps then return true end

  if AnimSeq._waitingMsg then
    local Ui = require("src.core.game3.battle.ui")
    local pending = false
    if Ui.dialogPending then
      pending = Ui.dialogPending()
    elseif not Ui._headless then
      pending = (Ui._showing == true)
        or (Ui._queue and #Ui._queue > 0)
    end
    if pending then
      return false
    end
    AnimSeq._waitingMsg = false
    AnimSeq._waiting = false
    advance()
  end

  if AnimSeq._waiting then
    -- Orphan wait: VM/tween finished but onEnd never fired
    if not Anim.busy() then
      flush_pending_eff()
      advance()
    else
      return false
    end
  end
  local step = AnimSeq._steps[AnimSeq._i]
  if not step then
    finish_seq()
    return true
  end
  run_step(step)
  return false
end

return AnimSeq
