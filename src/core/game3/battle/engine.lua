-- Owned turn resolver: moves, effects, residuals, commands.

local Damage = require("src.core.game3.battle.damage")
local Moves = require("src.core.game3.battle.moves")
local State = require("src.core.game3.battle.state")
local Effects = require("src.core.game3.battle.effects")
local Damaging = require("src.core.game3.battle.effects.damaging")
local EffectIds = require("src.core.game3.battle.effect_ids")
local Residuals = require("src.core.game3.battle.residuals")
local ResidualHandlers = require("src.core.game3.battle.residual_handlers")
local Commands = require("src.core.game3.battle.commands")
local Types = require("src.core.game3.battle.types")

local Engine = {}

ResidualHandlers.registerAll()

local function speed_of(battler, _st)
  local mon = battler and battler.mon
  local spe = tonumber(mon and (mon.speed or mon.spe)) or 50
  local stage = battler.stages and battler.stages.speed or 0
  spe = spe * Damage.stageMul(stage)
  return spe
end

local function clear_turn_flags(battler)
  if not battler then return end
  -- Protect lasts one turn; leftover flinch must not carry into the next plan.
  battler.expProtected = nil
  battler.expEnduring = nil
  battler.expMagicCoat = nil
  battler.expSnatch = nil
  battler.flinched = nil
  battler.damageTakenThisTurn = 0
end

local function dec_pp(battler, slot)
  if not slot then return end
  local mon = battler.mon
  if not mon then return end
  mon.pp = mon.pp or {}
  local pp = tonumber(mon.pp[slot]) or 0
  if pp > 0 then mon.pp[slot] = pp - 1 end
end

local function effectiveness_line(eff)
  if eff == 0 then return "It doesn't affect the foe..." end
  if eff >= 2 then return "It's super effective!" end
  if eff > 0 and eff < 1 then return "It's not very effective..." end
  return nil
end

local function roll(adapter, lo, hi)
  local ok, v = pcall(adapter:rng(), lo, hi)
  if ok and type(v) == "number" then return v end
  return math.random(lo, hi)
end

local function can_move(battler, adapter)
  if battler.flinched then
    adapter:say(adapter:displayName(battler) .. " flinched\nand couldn't move!")
    battler.flinched = nil
    return false
  end
  local st = adapter:status(battler)
  if st == "SLP" then
    battler.sleepTurns = tonumber(battler.sleepTurns)
    if not battler.sleepTurns then
      battler.sleepTurns = roll(adapter, 1, 3)
    end
    battler.sleepTurns = battler.sleepTurns - 1
    if battler.sleepTurns <= 0 then
      adapter:clearStatus(battler)
      battler.sleepTurns = nil
      adapter:say(adapter:displayName(battler) .. " woke up!")
      return true
    end
    adapter:say(adapter:displayName(battler) .. " is\nfast asleep!")
    return false
  end
  if st == "FRZ" then
    if roll(adapter, 1, 5) == 1 then
      adapter:clearStatus(battler)
      adapter:say(adapter:displayName(battler) .. " thawed out!")
      return true
    end
    adapter:say(adapter:displayName(battler) .. " is\nfrozen solid!")
    return false
  end
  if st == "PAR" then
    if roll(adapter, 1, 4) == 1 then
      adapter:say(adapter:displayName(battler) .. " is paralyzed!\nIt can't move!")
      return false
    end
  end
  if battler.confusionTurns and battler.confusionTurns > 0 then
    adapter:say(adapter:displayName(battler) .. " is confused!")
    battler.confusionTurns = battler.confusionTurns - 1
    if roll(adapter, 1, 2) == 1 then
      local dmg = math.max(1, math.floor(adapter:maxHp(battler) / 8))
      adapter:applyHpLoss(battler, dmg)
      adapter:say("It hurt itself in its\nconfusion!")
      return false
    end
    if battler.confusionTurns <= 0 then
      battler.confusionTurns = nil
      adapter:say(adapter:displayName(battler) .. " snapped\nout of confusion!")
    end
  end
  return true
end

local function hit_count(move, adapter)
  local hits = move.hits
  if type(hits) == "table" and hits[1] and hits[2] then
    return roll(adapter, hits[1], hits[2])
  end
  if tonumber(hits) then return tonumber(hits) end
  local eff = tonumber(move.effect)
  if eff == EffectIds.MULTI_HIT then return roll(adapter, 2, 5) end
  if eff == EffectIds.DOUBLE_HIT then return 2 end
  return 1
end

--- Resolve a move. Returns message list.
-- Also fills out._anim (presentation meta for AnimSeq): moveId, user, target,
-- hits[{side,from,to,maxHp}], heals[], missed, statusOnly, msgs.
function Engine.resolveMove(user, target, moveId, slot, adapter, st, out, opts)
  out = out or {}
  opts = opts or {}
  if type(user) == "string" and st and st[user] then user = st[user] end
  if type(target) == "string" and st and st[target] then target = st[target] end
  if user and user.side and st and st[user.side] then user = st[user.side] end
  if target and target.side and st and st[target.side] then target = st[target.side] end

  local prevSay = adapter._say
  local captured = {}
  -- Capture only: do not forward to UI here. AnimSeq / push_msgs own text order
  -- (used MOVE! → anim → effect lines). Forwarding would leak "ATTACK fell!" early.
  adapter._say = function(text)
    captured[#captured + 1] = text
  end

  local move = Moves.get(moveId)
  local uname = adapter:displayName(user)
  local tname = adapter:displayName(target)
  local anim = {
    moveId = moveId,
    user = user,
    target = target,
    hits = {},
    heals = {},
    faints = {},
    missed = false,
    statusOnly = false,
  }

  local function finalize()
    for _, m in ipairs(captured) do out[#out + 1] = m end
    anim.msgs = {}
    for i = 1, #out do anim.msgs[i] = out[i] end
    out._anim = anim
    adapter._say = prevSay
    return out
  end

  if user.expMustRecharge then
    user.expMustRecharge = nil
    out[#out + 1] = uname .. " must\nrecharge!"
    anim.statusOnly = true
    return finalize()
  end

  local effectByte = tonumber(move.effect)
  local isSleepTalk = (effectByte == EffectIds.SLEEP_TALK) and (adapter:status(user) == "SLP")

  if not isSleepTalk and not user.sleepTalkActive and not can_move(user, adapter) then
    user.twoTurnMove = nil
    user.twoTurnTarget = nil
    user.semiInvulnerable = nil
    return finalize()
  end

  -- Phase 5: Two-turn charging / semi-invulnerable execution
  if user.twoTurnMove == moveId then
    -- Turn 2: Unleash
    user.twoTurnMove = nil
    user.twoTurnTarget = nil
    user.semiInvulnerable = nil
    out[#out + 1] = uname .. " used\n" .. Moves.displayName(moveId) .. "!"
  elseif effectByte == EffectIds.SOLAR_BEAM then
    local weather = st.weather
    if weather ~= "sun" and weather ~= "sunny" then
      user.twoTurnMove = moveId
      user.twoTurnTarget = target
      out[#out + 1] = uname .. " took in\nsunlight!"
      dec_pp(user, slot)
      anim.statusOnly = true
      return finalize()
    else
      out[#out + 1] = uname .. " used\n" .. Moves.displayName(moveId) .. "!"
      dec_pp(user, slot)
    end
  elseif effectByte == EffectIds.RAZOR_WIND then
    user.twoTurnMove = moveId
    user.twoTurnTarget = target
    out[#out + 1] = uname .. " whipped\nup a whirlwind!"
    dec_pp(user, slot)
    anim.statusOnly = true
    return finalize()
  elseif effectByte == EffectIds.SKULL_BASH then
    user.twoTurnMove = moveId
    user.twoTurnTarget = target
    out[#out + 1] = uname .. " lowered\nits head!"
    dec_pp(user, slot)
    adapter:changeStages(user, { defense = 1 })
    anim.statusOnly = true
    return finalize()
  elseif effectByte == EffectIds.SKY_ATTACK then
    user.twoTurnMove = moveId
    user.twoTurnTarget = target
    out[#out + 1] = uname .. " became\ncloaked in light!"
    dec_pp(user, slot)
    anim.statusOnly = true
    return finalize()
  elseif effectByte == EffectIds.SEMI_INVULNERABLE then
    user.twoTurnMove = moveId
    user.twoTurnTarget = target
    user.semiInvulnerable = move.id or "SEMI_INVULNERABLE"
    local mName = Moves.displayName(moveId):upper()
    if mName:find("FLY") then
      out[#out + 1] = uname .. " flew\nup high!"
    elseif mName:find("DIG") then
      out[#out + 1] = uname .. " dug\na hole!"
    elseif mName:find("DIVE") then
      out[#out + 1] = uname .. " hid\nunderwater!"
    elseif mName:find("BOUNCE") then
      out[#out + 1] = uname .. " bounced\nup high!"
    else
      out[#out + 1] = uname .. " disappeared!"
    end
    dec_pp(user, slot)
    anim.statusOnly = true
    return finalize()
  elseif effectByte == EffectIds.FOCUS_PUNCH then
    if (user.damageTakenThisTurn or 0) > 0 then
      out[#out + 1] = uname .. " lost its\nfocus and couldn't move!"
      anim.statusOnly = true
      return finalize()
    end
  elseif effectByte == EffectIds.METRONOME then
    dec_pp(user, slot)
    local Pokemon = require("src.core.game3.pokemon")
    local randMove = roll(adapter, 1, 354)
    out[#out + 1] = uname .. " used\n" .. Moves.displayName(moveId) .. "!"
    -- Dispatch random move
    return Engine.resolveMove(user, target, randMove, nil, adapter, st, out)
  elseif effectByte == EffectIds.SLEEP_TALK then
    dec_pp(user, slot)
    out[#out + 1] = uname .. " used\n" .. Moves.displayName(moveId) .. "!"
    local uMon = user.mon or user
    local eligible = {}
    if uMon.moves then
      for i = 1, 4 do
        local m = uMon.moves[i]
        local mid = type(m) == "table" and (m.id or m.move) or m
        mid = tonumber(mid)
        if mid and mid > 0 and mid ~= moveId then
          eligible[#eligible + 1] = mid
        end
      end
    end
    if #eligible == 0 then
      out[#out + 1] = "But it failed!"
      anim.statusOnly = true
      return finalize()
    end
    local pickIdx = roll(adapter, 1, #eligible)
    local pickedMove = eligible[pickIdx]
    user.sleepTalkActive = true
    local res = Engine.resolveMove(user, target, pickedMove, nil, adapter, st, out)
    user.sleepTalkActive = nil
    return res
  elseif effectByte == EffectIds.MIRROR_MOVE then
    dec_pp(user, slot)
    out[#out + 1] = uname .. " used\n" .. Moves.displayName(moveId) .. "!"
    local lastEnemyMove = target.lastMoveId or target.lastMove
    if not lastEnemyMove then
      out[#out + 1] = "The MIRROR MOVE failed!"
      anim.statusOnly = true
      return finalize()
    end
    return Engine.resolveMove(user, target, lastEnemyMove, nil, adapter, st, out)
  else
    out[#out + 1] = uname .. " used\n" .. Moves.displayName(moveId) .. "!"
    dec_pp(user, slot)
  end
  -- Protect/Endure share consecutive-success streak; other moves reset it.
  if effectByte ~= EffectIds.PROTECT and effectByte ~= EffectIds.ENDURE then
    user.expProtectStreak = 0
  end
  user.lastMoveId = moveId
  user.lastMove = moveId

  if effectByte == EffectIds.OHKO then
    local eff = Types.effectiveness(move.type, target.type1, target.type2)
    if eff == 0 then
      out[#out + 1] = "It doesn't affect\n" .. tname .. "..."
      anim.missed = true
      return finalize()
    end

    local tMon = target.mon or target
    local ability = tMon.ability or tMon.abilityId or target.ability
    if ability == 5 or ability == "STURDY" or ability == "Sturdy" then
      out[#out + 1] = tname .. " was protected by\nSTURDY!"
      anim.missed = true
      return finalize()
    end

    local uMon = user.mon or user
    local uLvl = tonumber(uMon.level) or 1
    local tLvl = tonumber(tMon.level) or 1
    if uLvl < tLvl then
      out[#out + 1] = "It doesn't affect\n" .. tname .. "..."
      anim.missed = true
      return finalize()
    end

    local sureHit = target.expLockedOn
    target.expLockedOn = nil
    if not sureHit then
      local baseAcc = tonumber(move.accuracy) or 30
      local acc = baseAcc + (uLvl - tLvl)
      if roll(adapter, 1, 100) > acc then
        out[#out + 1] = uname .. "'s\nattack missed!"
        anim.missed = true
        return finalize()
      end
    end

    if target.expProtected and user ~= target then
      out[#out + 1] = tname .. " protected itself!"
      anim.missed = true
      return finalize()
    end

    local hpBefore = adapter:hp(target)
    local dmg = hpBefore
    if target.expEnduring then
      dmg = math.max(0, hpBefore - 1)
      out[#out + 1] = tname .. " endured the hit!"
    end

    if dmg > 0 then
      adapter:applyHpLoss(target, dmg)
      anim.hits[#anim.hits + 1] = {
        side = target.side or "enemy",
        from = hpBefore,
        to = adapter:hp(target),
        maxHp = adapter:maxHp(target),
      }
    end
    out[#out + 1] = "It's a one-hit KO!"

    if adapter:isFainted(target) then
      out[#out + 1] = tname .. " fainted!"
      anim.fainted = true
      anim.faints[#anim.faints + 1] = { side = target.side or "enemy" }
      adapter:emitFaint(target)
    end

    return finalize()
  end

  local skipAcc = move.id == "STRUGGLE"
    or effectByte == EffectIds.ALWAYS_HIT
    or effectByte == EffectIds.PROTECT
    or effectByte == EffectIds.ENDURE
    or target.expLockedOn
  if target.expLockedOn then
    target.expLockedOn = nil
  end
  if not skipAcc then
    if target.semiInvulnerable and user ~= target then
      out[#out + 1] = uname .. "'s\nattack missed!"
      anim.missed = true
      return finalize()
    end
    local acc = tonumber(move.accuracy) or 100
    if acc > 0 and roll(adapter, 1, 100) > acc then
      out[#out + 1] = uname .. "'s\nattack missed!"
      anim.missed = true
      if effectByte == EffectIds.RECOIL_IF_MISS then
        local crashDmg = math.max(1, math.floor(adapter:maxHp(user) / 2))
        local uBefore = adapter:hp(user)
        adapter:applyHpLoss(user, crashDmg)
        anim.heals[#anim.heals + 1] = {
          side = user.side or "player",
          from = uBefore,
          to = adapter:hp(user),
          maxHp = adapter:maxHp(user),
        }
        out[#out + 1] = uname .. " kept going\nand crashed!"
        if adapter:isFainted(user) then
          out[#out + 1] = uname .. " fainted!"
          anim.fainted = true
          anim.faints[#anim.faints + 1] = { side = user.side or "player" }
          adapter:emitFaint(user)
        end
      end
      return finalize()
    end
  end

  if target.expProtected and user ~= target then
    out[#out + 1] = tname .. " protected itself!"
    anim.missed = true
    if effectByte == EffectIds.RECOIL_IF_MISS then
      local crashDmg = math.max(1, math.floor(adapter:maxHp(user) / 2))
      local uBefore = adapter:hp(user)
      adapter:applyHpLoss(user, crashDmg)
      anim.heals[#anim.heals + 1] = {
        side = user.side or "player",
        from = uBefore,
        to = adapter:hp(user),
        maxHp = adapter:maxHp(user),
      }
      out[#out + 1] = uname .. " kept going\nand crashed!"
      if adapter:isFainted(user) then
        out[#out + 1] = uname .. " fainted!"
        anim.fainted = true
        anim.faints[#anim.faints + 1] = { side = user.side or "player" }
        adapter:emitFaint(user)
      end
    end
    return finalize()
  end

  if move.category == "status" or (tonumber(move.power) or 0) <= 0 then
    anim.statusOnly = true
    local handled = Effects.runForMove(adapter, user, target, moveId)
    if not handled then
      out[#out + 1] = "But nothing happened!"
    end
    return finalize()
  end

  if tonumber(move.effect) == EffectIds.BRICK_BREAK then
    Damaging.brickBreak(adapter, target)
  end

  local nHits = hit_count(move, adapter)
  local totalDmg = 0
  local hitsLanded = 0
  local highCrit = (tonumber(move.effect) == EffectIds.HIGH_CRITICAL) or nil
  local tSide = target.side or "enemy"
  local tMax = adapter:maxHp(target)
  for hit = 1, nHits do
    if adapter:isFainted(target) then break end
    local hpBefore = adapter:hp(target)
    local dmg, info = Damage.calc(user, target, moveId, {
      rng = adapter:rng(),
      weather = st.weather,
      highCrit = highCrit,
    })
    if info.failed then
      out[#out + 1] = "But it failed!"
      return finalize()
    end
    local defSide = adapter:ownSide(target)
    if info.physical and defSide and (defSide.expReflectTurns or 0) > 0 then
      dmg = math.floor(dmg * 0.5)
    elseif (not info.physical) and defSide and (defSide.expLightScreenTurns or 0) > 0 then
      dmg = math.floor(dmg * 0.5)
    end
    if dmg > 0 then
      if (target.substituteHP or 0) > 0 then
        local subHp = target.substituteHP
        if dmg >= subHp then
          target.substituteHP = 0
          out[#out + 1] = tname .. "'s\nSUBSTITUTE broke!"
        else
          target.substituteHP = subHp - dmg
          out[#out + 1] = "The SUBSTITUTE took\ndamage for " .. tname .. "!"
        end
      else
        if target.expEnduring and dmg >= hpBefore then
          dmg = math.max(0, hpBefore - 1)
          out[#out + 1] = tname .. " endured the hit!"
        end
        target.damageTakenThisTurn = (target.damageTakenThisTurn or 0) + dmg
        if info.physical then
          target.lastPhysicalDamageTaken = dmg
        else
          target.lastSpecialDamageTaken = dmg
        end
        adapter:applyHpLoss(target, dmg)
        anim.hits[#anim.hits + 1] = {
          side = tSide,
          from = hpBefore,
          to = adapter:hp(target),
          maxHp = tMax,
        }
      end
      totalDmg = totalDmg + dmg
      hitsLanded = hitsLanded + 1
    end
    if hit == 1 then
      anim.effectiveness = info.effectiveness or 1
      if info.magnitude then
        out[#out + 1] = string.format("MAGNITUDE %d!", info.magnitude)
      end
      if info.critical then out[#out + 1] = "A critical hit!" end
      if not info.fixed then
        local el = effectiveness_line(info.effectiveness or 1)
        if el then out[#out + 1] = el end
      end
    end
  end
  if nHits > 1 and hitsLanded > 0 then
    out[#out + 1] = string.format("Hit %d time(s)!", hitsLanded)
  end

  if tonumber(move.effect) == EffectIds.RAPID_SPIN and hitsLanded > 0 then
    local uSide = adapter:ownSide(user)
    if uSide and (uSide.spikes or 0) > 0 then
      uSide.spikes = 0
      out[#out + 1] = uname .. " blew away\nSPIKES!"
    end
    if user.leechSeed then
      user.leechSeed = nil
      out[#out + 1] = uname .. " shed\nLEECH SEED!"
    end
    if user.trapped then
      user.trapped = nil
      out[#out + 1] = uname .. " freed itself\nfrom being trapped!"
    end
  end

  if tonumber(move.effect) == EffectIds.EXPLOSION then
    local uBefore = adapter:hp(user)
    adapter:applyHpLoss(user, uBefore)
    anim.heals[#anim.heals + 1] = {
      side = user.side or "player",
      from = uBefore,
      to = 0,
      maxHp = adapter:maxHp(user),
    }
  end

  if tonumber(move.effect) == EffectIds.SMELLINGSALT and hitsLanded > 0 then
    if adapter:status(target) == "PAR" then
      adapter:clearStatus(target)
      out[#out + 1] = tname .. " was\ncured of paralysis!"
    end
  end

  if tonumber(move.effect) == EffectIds.PAY_DAY and hitsLanded > 0 then
    local uMon = user.mon or user
    local uLvl = tonumber(uMon.level) or 1
    st.payDayCoins = (st.payDayCoins or 0) + (uLvl * 5)
    out[#out + 1] = "Coins scattered\neverywhere!"
  end

  if tonumber(move.effect) == EffectIds.RECHARGE and hitsLanded > 0 then
    user.expMustRecharge = true
  end

  if move.id == "STRUGGLE" then
    local recoil = math.max(1, math.floor(adapter:maxHp(user) / 4))
    local uBefore = adapter:hp(user)
    adapter:applyHpLoss(user, recoil)
    anim.heals[#anim.heals + 1] = {
      side = user.side or "player",
      from = uBefore,
      to = adapter:hp(user),
      maxHp = adapter:maxHp(user),
    }
    out[#out + 1] = uname .. " is hit\nwith recoil!"
  else
    local uBefore = adapter:hp(user)
    Damaging.afterHit(adapter, user, target, move, totalDmg)
    local uAfter = adapter:hp(user)
    if uAfter > uBefore then
      -- Absorb / drain heal
      anim.heals[#anim.heals + 1] = {
        side = user.side or "player",
        from = uBefore,
        to = uAfter,
        maxHp = adapter:maxHp(user),
      }
    elseif uAfter < uBefore then
      anim.heals[#anim.heals + 1] = {
        side = user.side or "player",
        from = uBefore,
        to = uAfter,
        maxHp = adapter:maxHp(user),
      }
    end
  end

  if adapter:isFainted(target) then
    out[#out + 1] = tname .. " fainted!"
    anim.fainted = true
    anim.faints[#anim.faints + 1] = { side = target.side or "enemy" }
    adapter:emitFaint(target)
  end
  if adapter:isFainted(user) then
    out[#out + 1] = uname .. " fainted!"
    anim.fainted = true
    anim.faints[#anim.faints + 1] = { side = user.side or "player" }
    adapter:emitFaint(user)
  end

  return finalize()
end

function Engine.planTurnFromActions(st, adapter, playerAct, enemyAct)
  playerAct = playerAct or Commands.playerAction(st, 1, 1)
  enemyAct = enemyAct or Commands.enemyAction(st)

  clear_turn_flags(st.player)
  clear_turn_flags(st.enemy)

  local actions = {}
  if playerAct.kind == "run" or playerAct.kind == "bag" or playerAct.kind == "switch" then
    if enemyAct.kind == "move" then
      actions[#actions + 1] = {
        user = st.enemy, target = st.player,
        move = enemyAct.move, slot = enemyAct.slot,
      }
    end
    return actions, playerAct
  end

  local pMove, pSlot = playerAct.move, playerAct.slot
  local eMove, eSlot = enemyAct.move, enemyAct.slot
  local pPri = Moves.priority(pMove)
  local ePri = Moves.priority(eMove)
  local pSpe = speed_of(st.player, st)
  local eSpe = speed_of(st.enemy, st)
  local playerFirst
  if pPri ~= ePri then
    playerFirst = pPri > ePri
  else
    playerFirst = pSpe >= eSpe
  end
  if playerFirst then
    actions[#actions + 1] = { user = st.player, target = st.enemy, move = pMove, slot = pSlot }
    actions[#actions + 1] = { user = st.enemy, target = st.player, move = eMove, slot = eSlot }
  else
    actions[#actions + 1] = { user = st.enemy, target = st.player, move = eMove, slot = eSlot }
    actions[#actions + 1] = { user = st.player, target = st.enemy, move = pMove, slot = pSlot }
  end
  return actions, nil
end

function Engine.planTurn(st, adapter)
  return Engine.planTurnFromActions(st, adapter, nil, nil)
end

function Engine.collectResidualEvents(_st, adapter)
  return Residuals.collectEvents(adapter)
end

function Engine.runResiduals(adapter)
  local events = Residuals.collectEvents(adapter)
  local captured = {}
  for _, evt in ipairs(events or {}) do
    for _, m in ipairs(evt.msgs or {}) do
      captured[#captured + 1] = m
    end
  end
  return captured
end

function Engine.hasLivingMons(party)
  if not party then return false end
  for _, mon in ipairs(party) do
    if mon and (tonumber(mon.hp) or 0) > 0 then
      return true
    end
  end
  return false
end

function Engine.nextLivingMonIndex(party, currentIdx)
  if not party then return nil end
  for i, mon in ipairs(party) do
    if i ~= currentIdx and mon and (tonumber(mon.hp) or 0) > 0 then
      return i
    end
  end
  return nil
end

function Engine.isPursuit(move)
  if not move then return false end
  if type(move) == "string" and move:upper() == "PURSUIT" then return true end
  if type(move) == "number" and move == 228 then return true end
  if type(move) == "table" and (move.id == 228 or move.effect == 128 or (move.name and move.name:upper() == "PURSUIT")) then
    return true
  end
  return false
end

function Engine.checkEnd(st, adapter)
  if not st then return nil end
  if st.over then return st.result end

  if st.player and st.playerParty then
    State.syncBattlerToParty(st.player, st.playerParty)
  end
  if st.enemy and st.foeParty then
    State.syncBattlerToParty(st.enemy, st.foeParty)
  end

  local playerAlive = Engine.hasLivingMons(st.playerParty)
  if not playerAlive then
    st.over = true
    st.result = "lose"
    return "lose"
  end

  local foeAlive = Engine.hasLivingMons(st.foeParty)
  if not foeAlive then
    st.over = true
    st.result = "win"
    return "win"
  end

  return nil
end

return Engine
