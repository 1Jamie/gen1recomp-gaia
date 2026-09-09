-- Stat stage effects. ROM effect byte → STAT_CHANGES drives generic path.

local Rules = require("src.core.game3.battle.rules")
local H = require("src.core.game3.battle.effects._helpers")
local EffectIds = require("src.core.game3.battle.effect_ids")

local Stats = {}

local STAT_NAME = {
  attack = "ATTACK", defense = "DEFENSE",
  spAtk = "SP. ATK", spDef = "SP. DEF", speed = "SPEED",
  accuracy = "accuracy", evasion = "evasiveness",
}

function Stats.change(ctx, target, changes, failOnSub)
  if failOnSub then
    if Rules.substitute.blocks("stat_drop", target, ctx.adapter) then
      return H.sayFail(ctx)
    end
    local side = ctx.adapter:ownSide(target)
    if side and (side.expMistTurns or 0) > 0 then
      ctx.adapter:say(H.displayName(ctx, target) .. " is protected\nby MIST!")
      return
    end
  end
  ctx.adapter:changeStages(target, changes)
  for k, d in pairs(changes) do
    local name = STAT_NAME[k] or k
    local dir = (tonumber(d) or 0) > 0 and "rose" or "fell"
    if math.abs(tonumber(d) or 0) >= 2 then
      dir = (tonumber(d) or 0) > 0 and "sharply rose" or "harshly fell"
    end
    ctx.adapter:say(H.displayName(ctx, target) .. "'s " .. name .. "\n" .. dir .. "!")
  end
end

--- Driven by ROM gBattleMoves.effect via EffectIds.STAT_CHANGES.
function Stats.fromRomEffect(ctx)
  local effect = tonumber(ctx.move and ctx.move.effect)
  local spec = effect and EffectIds.STAT_CHANGES[effect]
  if not spec then return H.sayFail(ctx) end
  local target = spec.self and ctx.user or ctx.target
  Stats.change(ctx, target, spec.stages, not spec.self)
end

function Stats.growl(ctx)
  Stats.change(ctx, ctx.target, { attack = -1 }, true)
end

function Stats.tailWhip(ctx)
  Stats.change(ctx, ctx.target, { defense = -1 }, true)
end

function Stats.leer(ctx)
  Stats.change(ctx, ctx.target, { defense = -1 }, true)
end

function Stats.harden(ctx)
  Stats.change(ctx, ctx.user, { defense = 1 }, false)
end

function Stats.calmMind(ctx)
  Stats.change(ctx, ctx.user, { spAtk = 1, spDef = 1 }, false)
end

function Stats.bulkUp(ctx)
  Stats.change(ctx, ctx.user, { attack = 1, defense = 1 }, false)
end

function Stats.dragonDance(ctx)
  Stats.change(ctx, ctx.user, { attack = 1, speed = 1 }, false)
end

function Stats.swordsDance(ctx)
  Stats.change(ctx, ctx.user, { attack = 2 }, false)
end

function Stats.agility(ctx)
  Stats.change(ctx, ctx.user, { speed = 2 }, false)
end

function Stats.amnesia(ctx)
  Stats.change(ctx, ctx.user, { spDef = 2 }, false)
end

function Stats.tickle(ctx)
  Stats.change(ctx, ctx.target, { attack = -1, defense = -1 }, true)
end

function Stats.cosmicPower(ctx)
  Stats.change(ctx, ctx.user, { defense = 1, spDef = 1 }, false)
end

function Stats.swagger(ctx)
  local target = ctx.target
  if Rules.substitute.blocks("stat_drop", target, ctx.adapter) then return H.sayFail(ctx) end
  Stats.change(ctx, target, { attack = 2 }, false)
  if ctx.adapter:abilityOf(target) == "OWN_TEMPO" then return end
  if target.confusedTurns and target.confusedTurns > 0 then return end
  ctx.adapter:applyConfusion(target, nil, ctx.user)
  ctx.adapter:say(H.displayName(ctx, target) .. " became\nconfused!")
end

function Stats.flatter(ctx)
  local target = ctx.target
  if Rules.substitute.blocks("stat_drop", target, ctx.adapter) then return H.sayFail(ctx) end
  Stats.change(ctx, target, { spAtk = 1 }, false)
  if ctx.adapter:abilityOf(target) == "OWN_TEMPO" then return end
  if target.confusedTurns and target.confusedTurns > 0 then return end
  ctx.adapter:applyConfusion(target, nil, ctx.user)
  ctx.adapter:say(H.displayName(ctx, target) .. " became\nconfused!")
end

function Stats.psychUp(ctx)
  local target = ctx.target
  if not target or not target.stages then return H.sayFail(ctx) end
  ctx.user.stages = ctx.user.stages or {}
  for stat, val in pairs(target.stages) do
    ctx.user.stages[stat] = val
  end
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " copied\nthe foe's stats!")
end

function Stats.stockpile(ctx)
  local n = ctx.user.expStockpile or 0
  if n >= 3 then return H.sayFail(ctx) end
  ctx.user.expStockpile = n + 1
  Stats.change(ctx, ctx.user, { defense = 1, spDef = 1 }, false)
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " stockpiled " .. tostring(ctx.user.expStockpile) .. "!")
end

function Stats.charge(ctx)
  ctx.user.expCharged = true
  Stats.change(ctx, ctx.user, { spDef = 1 }, false)
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " began\ncharging power!")
end

function Stats.memento(ctx)
  Stats.change(ctx, ctx.target, { attack = -2, spAtk = -2 }, true)
  local mon = ctx.adapter:mon(ctx.user)
  if mon then mon.hp = 0 end
  ctx.adapter:emitFaint(ctx.user)
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " went all out\nand fainted!")
end

return Stats
