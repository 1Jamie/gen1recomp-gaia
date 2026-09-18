local Anim = require("src.core.game3.battle.anim")
local AnimCtx = require("src.core.game3.battle.anim_ctx")

local AnimSeq = {}

AnimSeq._steps = nil
AnimSeq._i = 1
AnimSeq._waiting = false
AnimSeq._waitingMsg = false
AnimSeq._waitFrames = 0
AnimSeq._waitSwitch = false
AnimSeq._pushMsg = nil
AnimSeq._pendingEff = nil
AnimSeq._scene = true
AnimSeq._ended = nil
AnimSeq._subLowered = {}

local MOVE_TRANSFORM = 144
local MOVE_SUBSTITUTE = 164
local PAUSE_SHORT = 32
local EFFECT_SEMI_INVULNERABLE = 155

-- pokefirered/src/battle_script_commands.c:3856
local ALWAYS_GENERAL = { STATS_CHANGE = true, SNATCH_MOVE = true, SUBSTITUTE_FADE = true, SILPH_SCOPED = true }
local WEATHER_GENERAL = { RAIN_CONTINUES = true, SUN_CONTINUES = true, SANDSTORM_CONTINUES = true, HAIL_CONTINUES = true }
-- pokefirered/src/battle_gfx_sfx_util.c:250
local SUB_EXEMPT_GENERAL = {
  SUBSTITUTE_FADE = true, RAIN_CONTINUES = true, SUN_CONTINUES = true,
  SANDSTORM_CONTINUES = true, HAIL_CONTINUES = true, SNATCH_MOVE = true,
}
-- pokefirered/data/battle_scripts_1.s:3913
local TARGET_ACTIVE_GENERAL = { ITEM_STEAL = true, ITEM_KNOCKOFF = true, SNATCH_MOVE = true }

local function battler_id(side)
  return (side == "enemy") and 1 or 0
end

local function other(side)
  return (side == "player") and "enemy" or "player"
end

local function battle_state()
  local Battle = package.loaded["src.core.game3.battle"]
  return Battle and Battle._st
end

local function battler_of(side)
  local st = battle_state()
  return st and st[side]
end

local function species_of(side)
  local b = Anim.shownBattler(side, battler_of(side))
  if type(b) ~= "table" then return nil end
  local p = Anim._present[side]
  if b.expTransform and p and not p.pendingTransform then
    return p.transformSpecies or b.expTransform.species
  end
  return b.species or (b.mon and (b.mon.species or b.mon.speciesId))
end

local function scene_on()
  local okO, Options = pcall(require, "src.core.game3.options")
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  if okO and session and Options.battleScene then
    return Options.battleScene(session) ~= false
  end
  return true
end

local function effectiveness_se(eff)
  local SE = require("src.core.game3.se_ids")
  eff = tonumber(eff) or 1
  if eff == 0 then return nil end
  if eff >= 2 then return SE.SE_SUPER_EFFECTIVE end
  if eff > 0 and eff < 1 then return SE.SE_NOT_EFFECTIVE end
  return SE.SE_EFFECTIVE
end

-- pokefirered/src/battle_script_commands.c:1883
local function play_effectiveness_se(eff, side)
  local id = effectiveness_se(eff)
  if not id then return end
  local pan = (side == "player") and -64 or 63
  pcall(function()
    require("src.core.game3.audio").playSe(id, { pan = pan })
  end)
end

local function flush_pending_eff()
  local p = AnimSeq._pendingEff
  AnimSeq._pendingEff = nil
  if p and p.effectiveness ~= nil then
    play_effectiveness_se(p.effectiveness, p.side)
  end
end

local function stand_in(side, slot)
  local st = battle_state()
  local party = st and ((side == "player") and st.playerParty or st.foeParty)
  local mon = party and slot and party[slot]
  if not mon then return nil end
  local State = require("src.core.game3.battle.state")
  local ok, b = pcall(State.makeBattler, mon, side, { partyIndex = slot })
  return ok and b or nil
end

function AnimSeq.reset()
  AnimSeq._steps = nil
  AnimSeq._i = 1
  AnimSeq._waiting = false
  AnimSeq._waitingMsg = false
  AnimSeq._waitFrames = 0
  AnimSeq._waitSwitch = false
  AnimSeq._pushMsg = nil
  AnimSeq._pendingEff = nil
  AnimSeq._ended = nil
  AnimSeq._subLowered = {}
  Anim.setSeqBusy(false)
end

function AnimSeq.busy()
  return AnimSeq._steps ~= nil
end

function AnimSeq.ended()
  return AnimSeq._ended
end

local function reconcile_sprites()
  local st = battle_state()
  if not st or Anim._headless then return end
  for _, side in ipairs({ "player", "enemy" }) do
    local p = Anim._present[side]
    if p then
      p.shown = nil
      p.blinkHidden = false
      p.pendingTransform = nil
      p.invisible = nil
      p.battlerInvisible = nil
    end
    local b = st[side]
    local alive = b and b.mon and (tonumber(b.mon.hp) or 0) > 0
    if p and alive and not st.over then
      if b.semiInvulnerable and AnimSeq._scene then
        p.visible = false
      elseif p.visible == false and not b.semiInvulnerable and not p.switchedOut then
        p.visible = true
        p.alpha = 1
      end
      local subbed = (b.substituteHP or 0) > 0
      if subbed ~= (p.substitute == true) and not AnimSeq._subLowered[side] then
        Anim.setSubstitute(side, subbed)
      end
    end
  end
end

local function finish_seq()
  if AnimSeq._steps then reconcile_sprites() end
  AnimSeq._steps = nil
  AnimSeq._i = 1
  AnimSeq._waiting = false
  AnimSeq._waitingMsg = false
  AnimSeq._waitFrames = 0
  AnimSeq._waitSwitch = false
  Anim.setSeqBusy(false)
end

local function advance()
  AnimSeq._waiting = false
  AnimSeq._i = AnimSeq._i + 1
end

local function is_miss_text(text)
  text = tostring(text or "")
  return text:find("attack missed") or text:find("avoided the attack")
    or text:find("protected itself") or text:find("doesn't affect")
    or text:find("is unaffected") or text:find("was protected by")
end

function AnimSeq.buildSteps(events, meta)
  meta = meta or {}
  local steps = {}
  local function add(kind, data)
    steps[#steps + 1] = { kind = kind, data = data or {} }
  end
  local lastMove = nil
  local lastMsg = nil
  local deferredIn = nil
  local prevKind = nil
  local n = #events
  for i = 1, n do
    local ev = events[i]
    local k = ev.kind
    if k == "msg" then
      if is_miss_text(ev.text) and not lastMove and prevKind == "msg" then
        -- pokefirered/data/battle_scripts_1.s:279
        add("pause", { frames = PAUSE_SHORT })
      end
      if lastMove and tostring(ev.text or ""):find("SUBSTITUTE took damage") then
        -- pokefirered/src/battle_script_commands.c:5300
        add("hitfx", { side = lastMove.target or other(lastMove.attacker or "player"),
          effectiveness = meta.effectiveness or 1 })
      end
      add("msg", { text = ev.text, wait = ev.wait })
      lastMsg = ev.text
      if deferredIn then
        add("switch_in", deferredIn)
        deferredIn = nil
      end
    elseif k == "move" then
      lastMove = ev
      add("move", {
        moveId = ev.moveId, attacker = ev.attacker, target = ev.target,
        turn = ev.turn or 0, calledBy = meta.calledBy, damage = ev.damage, power = ev.power,
      })
    elseif k == "anim" then
      local d = { anim = ev.anim, name = ev.name, attacker = ev.attacker, target = ev.target, arg = ev.arg }
      if ev.anim == "special" and (ev.name == "SUBSTITUTE_TO_MON" or ev.name == "MON_TO_SUBSTITUTE") then
        if ev.name == "SUBSTITUTE_TO_MON" then
          for j = i + 1, n do
            if events[j].kind == "move" then d.moveId = events[j].moveId break end
          end
        else
          d.moveId = lastMove and lastMove.moveId
        end
      end
      add("anim", d)
    elseif k == "hit" then
      local eff = 1
      if prevKind == "move" or (lastMove and prevKind ~= "hit" and prevKind ~= "hp") then
        eff = meta.effectiveness or 1
      end
      add("hitfx", { side = ev.side, effectiveness = eff })
      add("hp", { side = ev.side, from = ev.from, to = ev.to, maxHp = ev.maxHp })
    elseif k == "hp" then
      if prevKind == "msg" and tostring(lastMsg or ""):find("hurt itself in its") then
        -- pokefirered/data/battle_scripts_1.s:3741
        add("hitfx", { side = ev.side, effectiveness = 1 })
      end
      add("hp", { side = ev.side, from = ev.from, to = ev.to, maxHp = ev.maxHp })
    elseif k == "faint" then
      -- pokefirered/data/battle_scripts_1.s:2810
      add("faint_cry", { side = ev.side })
      add("pause", { frames = 64 })
      add("faint", { side = ev.side })
    elseif k == "switch_out" then
      add("switch_out", { side = ev.side, reason = ev.reason })
    elseif k == "switch" then
      add("switch_out", { side = ev.side, reason = ev.reason, slot = ev.from })
      local hp = nil
      for j = i + 1, n do
        local e2 = events[j]
        if (e2.kind == "hp" or e2.kind == "hit") and e2.side == ev.side then hp = e2.from break end
        if e2.kind == "switch" and e2.side == ev.side then break end
      end
      local d = { side = ev.side, slot = ev.to, hp = hp, reason = ev.reason }
      if ev.reason == "baton_pass" and events[i + 1] and events[i + 1].kind == "msg" then
        -- pokefirered/data/battle_scripts_1.s:1690
        deferredIn = d
      else
        add("switch_in", d)
      end
    elseif k == "end" then
      add("end", { result = ev.result, reason = ev.reason })
    end
    prevKind = k
  end
  if deferredIn then add("switch_in", deferredIn) end
  return steps
end

local function legacy_steps(result)
  local steps = {}
  local function add(kind, data)
    steps[#steps + 1] = { kind = kind, data = data }
  end
  local msgs = result.msgs or {}
  local usedLine = msgs[1]
  local restStart = 1
  if usedLine and tostring(usedLine):find("used") then
    add("msg", { text = usedLine })
    restStart = 2
  end
  local us = result.user and result.user.side or "player"
  local ts = result.target and result.target.side or other(us)
  if result.hits and #result.hits > 0 then
    for hi, hit in ipairs(result.hits) do
      add("move", { moveId = result.moveId, attacker = us, target = ts, turn = 0 })
      add("hitfx", { side = hit.side, effectiveness = (hi == 1) and result.effectiveness or nil })
      add("hp", hit)
    end
  elseif not result.missed then
    add("move", { moveId = result.moveId, attacker = us, target = ts, turn = 0 })
  end
  for _, h in ipairs(result.heals or {}) do add("hp", h) end
  local faintI = 1
  local faints = result.faints or {}
  for i = restStart, #msgs do
    local text = msgs[i]
    if type(text) == "string" and text:find("fainted") then
      local side = faints[faintI] and faints[faintI].side
      if not side then side = (faintI == 1) and ts or us end
      faintI = faintI + 1
      add("faint", { side = side })
      add("msg", { text = text })
    else
      add("msg", { text = text })
    end
  end
  return steps
end

local function start(steps, pushMsg)
  if #steps == 0 then
    finish_seq()
    return
  end
  local held = {}
  for _, step in ipairs(steps) do
    if step.kind == "move" and tonumber(step.data.moveId) == MOVE_TRANSFORM then
      local p = Anim.present(step.data.attacker or "player")
      if p then p.pendingTransform = true end
    elseif step.kind == "switch_out" and step.data.slot and not held[step.data.side] then
      held[step.data.side] = true
      Anim.setShown(step.data.side, stand_in(step.data.side, step.data.slot))
    end
  end
  AnimSeq._steps = steps
  AnimSeq._i = 1
  AnimSeq._waiting = false
  AnimSeq._pushMsg = pushMsg
  Anim.setSeqBusy(true)
end

function AnimSeq.begin(result, pushMsg)
  AnimSeq.reset()
  if not result then return end
  AnimSeq._scene = scene_on()
  local steps
  if type(result.events) == "table" then
    steps = AnimSeq.buildSteps(result.events, result)
  else
    steps = legacy_steps(result)
  end
  start(steps, pushMsg)
end

function AnimSeq.beginEvents(events, pushMsg, meta)
  AnimSeq.reset()
  AnimSeq._scene = scene_on()
  start(AnimSeq.buildSteps(events or {}, meta), pushMsg)
end

local function wait_anim()
  AnimSeq._waiting = true
end

local function launch_done()
  if AnimSeq._waiting and not Anim.busy() then
    advance()
  end
end

local function pause(frames)
  AnimSeq._waitFrames = frames or PAUSE_SHORT
end

local function ctx_for(attacker, target, opts)
  opts = opts or {}
  opts.lowered = AnimSeq._subLowered
  return AnimCtx.build(attacker, target, opts)
end

local function move_ctx(d)
  local attacker = d.attacker or "player"
  local ctx = ctx_for(attacker, d.target or other(attacker), { moveId = d.moveId, moveDmg = d.damage })
  if tonumber(d.power) then ctx.movePower = tonumber(d.power) end
  local okM, Moves = pcall(require, "src.core.game3.battle.moves")
  local mv = okM and Moves.get and Moves.get(d.moveId)
  return ctx, mv
end

local function after_move(d, mv)
  local side = d.attacker or "player"
  local p = Anim.present(side)
  if not p then return end
  if tonumber(d.moveId) == MOVE_TRANSFORM then p.pendingTransform = nil end
  if not AnimSeq._scene then return end
  if tonumber(d.moveId) == MOVE_SUBSTITUTE then
    local b = battler_of(side)
    if b and (b.substituteHP or 0) > 0 and not p.substitute then
      Anim.setSubstitute(side, true)
      p.visible = true
      p.ox, p.oy = 0, 0
    end
  end
  if mv and tonumber(mv.effect) == EFFECT_SEMI_INVULNERABLE then
    -- pokefirered/src/battle_controller_player.c:2370
    if (tonumber(d.turn) or 0) == 0 then
      p.visible = false
    else
      p.visible = true
    end
  end
end

local function run_move(d)
  if not AnimSeq._scene and tonumber(d.moveId) ~= MOVE_TRANSFORM and tonumber(d.moveId) ~= MOVE_SUBSTITUTE then
    -- pokefirered/src/battle_script_commands.c:1667
    pause(PAUSE_SHORT)
    advance()
    return
  end
  local ctx, mv = move_ctx(d)
  wait_anim()
  local attacker = d.attacker or "player"
  local target = d.target or other(attacker)
  Anim.launchMove(d.moveId, {
    attackerSide = attacker,
    targetSide = target,
    isReversed = attacker == "enemy",
    attackerSpecies = species_of(attacker),
    targetSpecies = species_of(target),
    moveTurn = d.turn or 0,
    ctx = ctx,
    onEnd = function()
      after_move(d, mv)
      if AnimSeq._waiting then advance() end
    end,
  })
  launch_done()
end

local function general_arg(d)
  if d.name == "LEECH_SEED_DRAIN" then
    -- pokefirered/src/battle_util.c:798
    local seeder = d.target or other(d.attacker or "player")
    return battler_id(seeder) + battler_id(d.attacker or "player") * 256
  end
  return tonumber(d.arg) or 0
end

local function run_general(d)
  local name = d.name
  local active = (TARGET_ACTIVE_GENERAL[name] and d.target) or d.attacker or "player"
  local p = Anim.present(active)
  local castform = name == "CASTFORM_CHANGE"
  if castform then
    local b = battler_of(active)
    local arg = tonumber(d.arg) or 0
    if p then p.castformMon = b and b.mon end
    -- pokefirered/src/battle_gfx_sfx_util.c:212
    if arg >= 128 then
      if p then p.castformForm = arg % 128 end
      advance()
      return
    end
  end
  if not ALWAYS_GENERAL[name] and not castform then
    if not AnimSeq._scene then
      -- pokefirered/src/battle_script_commands.c:3865
      pause(PAUSE_SHORT)
      advance()
      return
    end
    local ab = battler_of(active)
    if not WEATHER_GENERAL[name] and ab and ab.semiInvulnerable then
      advance()
      return
    end
  end
  if p and p.substitute and not SUB_EXEMPT_GENERAL[name] and not castform then
    advance()
    return
  end
  if name == "SUBSTITUTE_FADE" and p and p.substitute and p.visible == false then
    Anim.setSubstitute(active, false)
    advance()
    return
  end
  wait_anim()
  Anim.launchGeneral(name, {
    attackerSide = active,
    targetSide = active,
    isReversed = active == "enemy",
    attackerSpecies = species_of(active),
    targetSpecies = species_of(active),
    animArg = general_arg(d),
    ctx = ctx_for(active, active, { animArg = general_arg(d) }),
    onEnd = function()
      if castform and p then
        p.castformForm = (tonumber(d.arg) or 0) % 128
      elseif name == "SILPH_SCOPED" and p then
        p.ghostUnveiled = true
      end
      if name == "SUBSTITUTE_FADE" then
        Anim.setSubstitute(active, false)
        local pp = Anim.present(active)
        if pp then
          pp.alpha = 1
          pp.visible = true
        end
      end
      if AnimSeq._waiting then advance() end
    end,
  })
  launch_done()
end

-- pokefirered/src/battle_script_commands.c:5494
local function run_status(d)
  local side = d.attacker or d.target or "player"
  local b = battler_of(side)
  if not AnimSeq._scene or (b and (b.semiInvulnerable or (b.substituteHP or 0) > 0)) then
    advance()
    return
  end
  wait_anim()
  Anim.launchStatus(d.name, {
    force = true,
    attackerSide = side,
    targetSide = side,
    isReversed = side == "enemy",
    attackerSpecies = species_of(side),
    targetSpecies = species_of(side),
    ctx = ctx_for(side, side),
    onEnd = function()
      if AnimSeq._waiting then advance() end
    end,
  })
  launch_done()
end

local function run_special(d)
  local side = d.attacker or "player"
  local p = Anim.present(side)
  if d.name == "SUBSTITUTE_TO_MON" or d.name == "MON_TO_SUBSTITUTE" then
    local mid = tonumber(d.moveId)
    if not AnimSeq._scene and mid ~= MOVE_TRANSFORM and mid ~= MOVE_SUBSTITUTE then
      advance()
      return
    end
    -- pokefirered/src/battle_controller_player.c:2338
    if d.name == "SUBSTITUTE_TO_MON" then
      if not (p and p.substitute) then advance() return end
      AnimSeq._subLowered[side] = true
    else
      if not AnimSeq._subLowered[side] then advance() return end
      AnimSeq._subLowered[side] = nil
      local b = battler_of(side)
      if b and (b.substituteHP or 0) <= 0 then advance() return end
    end
  end
  wait_anim()
  Anim.launchSpecial(d.name, {
    attackerSide = side,
    targetSide = side,
    isReversed = side == "enemy",
    attackerSpecies = species_of(side),
    targetSpecies = species_of(side),
    ctx = ctx_for(side, side),
    onEnd = function()
      if d.name == "SUBSTITUTE_TO_MON" then
        Anim.setSubstitute(side, false)
      elseif d.name == "MON_TO_SUBSTITUTE" then
        Anim.setSubstitute(side, true)
      end
      local pp = Anim.present(side)
      if pp then pp.ox = 0 end
      if AnimSeq._waiting then advance() end
    end,
  })
  launch_done()
end

-- pokefirered/src/battle_controller_player.c:2144
local function run_switch_out(d)
  local side = d.side or "enemy"
  local p = Anim.present(side)
  local function hide()
    local pp = Anim.present(side)
    if pp then
      pp.visible = false
      pp.switchedOut = true
      pp.scale = 1
      pp.sx, pp.sy = 1, 1
    end
    local s = Anim.stage()
    if s and s.healthbox and s.healthbox[side] then s.healthbox[side].visible = false end
    if AnimSeq._waiting then advance() end
  end
  if d.slot then Anim.setShown(side, stand_in(side, d.slot)) end
  if not p or p.visible == false then
    AnimSeq._waiting = true
    hide()
    return
  end
  local function out()
    Anim.launchSpecial((side == "player") and "SWITCH_OUT_PLAYER_MON" or "SWITCH_OUT_OPPONENT_MON", {
      attackerSide = side,
      targetSide = side,
      isReversed = side == "enemy",
      attackerSpecies = species_of(side),
      targetSpecies = species_of(side),
      ctx = ctx_for(side, side),
      onEnd = hide,
    })
  end
  wait_anim()
  if p.substitute then
    Anim.launchSpecial("SUBSTITUTE_TO_MON", {
      attackerSide = side, targetSide = side, isReversed = side == "enemy",
      ctx = ctx_for(side, side),
      onEnd = function()
        Anim.setSubstitute(side, false)
        p.ox = 0
        out()
      end,
    })
  else
    out()
  end
  launch_done()
end

local function run_switch_in(d)
  local side = d.side or "enemy"
  local st = battle_state()
  local p = Anim.present(side)
  Anim.setShown(side, nil)
  if p then
    p.switchedOut = nil
    -- pokefirered/src/battle_gfx_sfx_util.c:997
    p.castformForm, p.castformMon = nil, nil
    Anim.setSubstitute(side, false)
    local b = st and st[side]
    if b and b.mon then
      p.displayHp = tonumber(d.hp) or tonumber(b.mon.hp) or 0
      p.displayMaxHp = tonumber(b.mon.maxHp) or 1
      p.displayLevel = tonumber(b.mon.level) or 1
    end
  end
  local SwitchSeq = require("src.core.game3.battle.switch_seq")
  AnimSeq._waitSwitch = true
  local started = SwitchSeq.beginEventSwitchIn(st, side, {
    headless = Anim._headless,
    pushMsg = AnimSeq._pushMsg,
    onDone = function()
      AnimSeq._waitSwitch = false
    end,
  })
  if not started then AnimSeq._waitSwitch = false end
  advance()
end

local function run_step(step)
  if not step then
    finish_seq()
    return
  end
  local kind = step.kind
  local d = step.data or {}

  if kind == "msg" then
    if AnimSeq._pushMsg and d.text then AnimSeq._pushMsg(d.text, d.wait) end
    AnimSeq._waiting = true
    AnimSeq._waitingMsg = true
    return
  end
  if kind == "faint_cry" then
    local side = d.side or "enemy"
    local sp = species_of(side)
    if sp and not Anim._headless then
      -- pokefirered/src/battle_controller_player.c:2696
      pcall(function()
        require("src.core.game3.audio").playCry(sp, 5, (side == "player") and -25 or 25)
      end)
    end
    advance()
    return
  end
  if kind == "pause" then
    if not Anim._headless then pause(d.frames) end
    advance()
    return
  end
  if kind == "move" then return run_move(d) end
  if kind == "anim" then
    if d.anim == "general" then return run_general(d) end
    if d.anim == "status" then return run_status(d) end
    if d.anim == "special" then return run_special(d) end
    advance()
    return
  end
  if kind == "hitfx" then
    -- pokefirered/src/battle_controller_player.c:2658
    if d.effectiveness ~= nil then play_effectiveness_se(d.effectiveness, d.side) end
    wait_anim()
    Anim.blinkMon(d.side, { onComplete = function() if AnimSeq._waiting then advance() end end })
    launch_done()
    return
  end
  if kind == "hp" then
    wait_anim()
    Anim.tweenHp(d.side, d.from, d.to, d.maxHp, {
      onComplete = function() if AnimSeq._waiting then advance() end end,
    })
    launch_done()
    return
  end
  if kind == "faint" then
    local p = Anim.present(d.side or "enemy")
    if p then
      Anim.setSubstitute(d.side or "enemy", false)
      p.blinkHidden = false
    end
    wait_anim()
    Anim.faintMon(d.side or "enemy", {
      onComplete = function() if AnimSeq._waiting then advance() end end,
    })
    launch_done()
    return
  end
  if kind == "switch_out" then return run_switch_out(d) end
  if kind == "switch_in" then return run_switch_in(d) end
  if kind == "end" then
    AnimSeq._ended = { result = d.result, reason = d.reason }
    advance()
    return
  end
  advance()
end

function AnimSeq.tickHitSe()
end

function AnimSeq.update()
  if not AnimSeq._steps then return true end
  local guard = 0
  while guard < 256 do
    guard = guard + 1
    if AnimSeq._waitingMsg then
      local Ui = require("src.core.game3.battle.ui")
      local pending = false
      if Ui.dialogPending then
        pending = Ui.dialogPending()
      elseif not Ui._headless then
        pending = (Ui._showing == true) or (Ui._queue and #Ui._queue > 0)
      end
      if pending then return false end
      AnimSeq._waitingMsg = false
      AnimSeq._waiting = false
      advance()
    end
    if AnimSeq._waitSwitch then
      local SwitchSeq = require("src.core.game3.battle.switch_seq")
      if SwitchSeq.busy() then
        if not Anim.busy() then
          local Ui = require("src.core.game3.battle.ui")
          if Ui.pump() then SwitchSeq.update() end
        end
        return false
      end
      AnimSeq._waitSwitch = false
    end
    if (AnimSeq._waitFrames or 0) > 0 then
      AnimSeq._waitFrames = AnimSeq._waitFrames - 1
      return false
    end
    if AnimSeq._waiting then
      if Anim.busy() then return false end
      flush_pending_eff()
      advance()
    end
    local step = AnimSeq._steps and AnimSeq._steps[AnimSeq._i]
    if not step then
      finish_seq()
      return true
    end
    run_step(step)
    if AnimSeq._waiting or AnimSeq._waitingMsg or AnimSeq._waitSwitch or (AnimSeq._waitFrames or 0) > 0 then
      return false
    end
  end
  return false
end

return AnimSeq
