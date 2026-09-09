-- FRLG setup effects (KR-sourced bodies; adapter-only; no KR require).

local H = require("src.core.game3.battle.effects._helpers")
local Rules = require("src.core.game3.battle.rules")
local Types = require("src.core.game3.battle.types")

local Setup = {}

function Setup.meanLook(ctx)
  local t = ctx.target
  if not t then return H.sayFail(ctx) end
  if t.expTrapped then return H.sayFail(ctx) end
  if H.hasType(ctx, t, Types.ID.GHOST) then return H.sayFail(ctx) end
  t.expTrapped = true
  ctx.adapter:say(H.displayName(ctx, t) .. " can no longer escape!")
end

function Setup.leechSeed(ctx)
  if Rules.substitute.blocks("status", ctx.target, ctx.adapter) then return H.sayFail(ctx) end
  if H.hasType(ctx, ctx.target, Types.ID.GRASS) then return H.sayFail(ctx) end
  if ctx.target.expSeeded then return H.sayFail(ctx) end
  ctx.target.expSeeded = true
  ctx.target.expSeedSource = ctx.user
  ctx.adapter:say(H.displayName(ctx, ctx.target) .. " was seeded!")
end

function Setup.destinyBond(ctx)
  ctx.user.expDestinyBond = true
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " is trying to\ntake its foe with it!")
end

function Setup.nightmare(ctx)
  if not ctx.adapter:hasStatus(ctx.target, "SLP", "sleep") then return H.sayFail(ctx) end
  if ctx.target.expNightmare then return H.sayFail(ctx) end
  ctx.target.expNightmare = true
  ctx.adapter:say(H.displayName(ctx, ctx.target) .. " began having\na NIGHTMARE!")
end

function Setup.focusEnergy(ctx)
  if ctx.user.expFocusEnergy then return H.sayFail(ctx) end
  ctx.user.expFocusEnergy = true
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " is getting\npumped!")
end

function Setup.foresight(ctx)
  ctx.target.expIdentified = true
  ctx.adapter:say(H.displayName(ctx, ctx.target) .. " was\nidentified!")
end

function Setup.lockOn(ctx)
  ctx.target.expLockedOn = true
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " took aim\nat " .. H.displayName(ctx, ctx.target) .. "!")
end

function Setup.magicCoat(ctx)
  ctx.user.expMagicCoat = true
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " shrouded\nitself with MAGIC COAT!")
end

function Setup.grudge(ctx)
  ctx.user.expGrudge = true
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " wants the\nfoe to take a GRUDGE!")
end

function Setup.imprison(ctx)
  ctx.user.expImprison = true
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " sealed\nthe opponent's moves!")
end

function Setup.snatch(ctx)
  ctx.user.expSnatch = true
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " waits for a\ntarget to make a move!")
end

function Setup.mudSport(ctx)
  ctx.adapter:fieldSet("expMudSport", true)
  ctx.adapter:say("Electricity's power\nwas weakened!")
end

function Setup.waterSport(ctx)
  ctx.adapter:fieldSet("expWaterSport", true)
  ctx.adapter:say("Fire's power\nwas weakened!")
end

function Setup.camouflage(ctx)
  -- FRLG: type from terrain; overworld terrain not wired → NORMAL (pret tall grass default is NORMAL outdoors often; keep simple).
  ctx.user.type1 = Types.ID.NORMAL
  ctx.user.type2 = nil
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. "'s type\nchanged to NORMAL!")
end

function Setup.rolePlay(ctx)
  local foeAb = ctx.adapter:abilityOf(ctx.target)
  if not foeAb then return H.sayFail(ctx) end
  ctx.user.expTracedAbility = foeAb
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " copied\n" .. H.displayName(ctx, ctx.target) .. "'s ability!")
end

function Setup.skillSwap(ctx)
  local a = ctx.adapter:abilityOf(ctx.user)
  local b = ctx.adapter:abilityOf(ctx.target)
  if not a and not b then return H.sayFail(ctx) end
  ctx.user.expTracedAbility = b
  ctx.target.expTracedAbility = a
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " swapped\nabilities with its target!")
end

function Setup.futureSight(ctx)
  local side = ctx.adapter:foeSide(ctx.user)
  if not side then return H.sayFail(ctx) end
  side.tokens = side.tokens or {}
  for _, tok in ipairs(side.tokens) do
    if tok.id == "EXP_FUTURE_SIGHT" then return H.sayFail(ctx) end
  end
  local move = ctx.move or {}
  local mon = ctx.adapter:mon(ctx.user)
  local power = move.power or 80
  local level = mon and mon.level or 50
  local dmg = math.max(1, math.floor(level * power / 50) + 2)
  side.tokens[#side.tokens + 1] = {
    id = "EXP_FUTURE_SIGHT",
    turns = 3,
    damage = dmg,
  }
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " foresaw\nan attack!")
end

function Setup.curse(ctx)
  local user = ctx.user
  if H.hasType(ctx, user, Types.ID.GHOST) then
    local maxHp = ctx.adapter:maxHp(user)
    local cost = math.max(1, math.floor(maxHp / 2))
    if ctx.adapter:hp(user) <= cost then return H.sayFail(ctx) end
    if ctx.target.expCursed then return H.sayFail(ctx) end
    ctx.adapter:applyHpLoss(user, cost)
    ctx.target.expCursed = true
    ctx.adapter:say(H.displayName(ctx, user) .. " cut its own HP\nand laid a CURSE\non " .. H.displayName(ctx, ctx.target) .. "!")
    return
  end
  local Stats = require("src.core.game3.battle.effects.stats")
  Stats.change(ctx, user, { speed = -1, attack = 1, defense = 1 }, false)
end

function Setup.batonPass(ctx)
  local party = ctx.adapter:partyMons(ctx.user)
  local userMon = ctx.adapter:mon(ctx.user)
  local hasOther = false
  for _, mon in ipairs(party) do
    if mon and (tonumber(mon.hp) or 0) > 0 and mon ~= userMon then
      hasOther = true
      break
    end
  end
  if not hasOther then return H.sayFail(ctx) end
  local stages = {}
  for k, v in pairs(ctx.user.stages or {}) do stages[k] = v end
  ctx.user.expBatonPass = {
    stages = stages,
    expFocusEnergy = ctx.user.expFocusEnergy,
    substituteHP = ctx.user.substituteHP,
    expIngrain = ctx.user.expIngrain,
    expPerishTurns = ctx.user.expPerishTurns,
    expCursed = ctx.user.expCursed,
    expTrapped = ctx.user.expTrapped,
    expSeeded = ctx.user.expSeeded,
  }
  ctx.user.expPendingBatonOpen = true
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " went back!")
end

function Setup.helpingHand(ctx)
  -- Singles: no ally.
  return H.sayFail(ctx)
end

function Setup.splash(_ctx)
  -- Message handled by engine ("But nothing happened!") if we say nothing;
  -- pret prints "But nothing happened!" — sayFail matches.
end

function Setup.confuse(ctx)
  if Rules.substitute.blocks("status", ctx.target, ctx.adapter) then return H.sayFail(ctx) end
  if ctx.target.confusionTurns and ctx.target.confusionTurns > 0 then return H.sayFail(ctx) end
  ctx.target.confusionTurns = 2 + (function()
    local ok, v = pcall(ctx.adapter:rng(), 1, 3)
    return ok and v or 2
  end)()
  ctx.adapter:say(H.displayName(ctx, ctx.target) .. " became\nconfused!")
end

function Setup.haze(ctx)
  for _, b in ipairs(ctx.adapter:activeBattlers()) do
    if b and b.stages then
      for k in pairs(b.stages) do b.stages[k] = 0 end
    end
  end
  ctx.adapter:say("All stat changes were\neliminated!")
end

function Setup.substitute(ctx)
  local user = ctx.user
  if (user.substituteHP or 0) > 0 then return H.sayFail(ctx) end
  local maxHp = ctx.adapter:maxHp(user)
  local cost = math.max(1, math.floor(maxHp / 4))
  local curHp = ctx.adapter:hp(user)
  if curHp <= cost then
    ctx.adapter:say("It was too weak to make\na SUBSTITUTE!")
    return
  end
  user._bypassingSubstitute = true
  ctx.adapter:applyHpLoss(user, cost)
  user._bypassingSubstitute = nil
  user.substituteHP = cost + 1
  ctx.adapter:say(H.displayName(ctx, user) .. " made a\nSUBSTITUTE!")
end

function Setup.teeterDance(ctx)
  return Setup.confuse(ctx)
end

return Setup
