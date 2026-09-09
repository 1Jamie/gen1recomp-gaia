-- Healing / recover / wish / stockpile swallow (FRLG; KR-sourced; no KR require).

local H = require("src.core.game3.battle.effects._helpers")
local Rules = require("src.core.game3.battle.rules")

local Healing = {}

function Healing.refresh(ctx)
  local st = ctx.adapter:status(ctx.user)
  if not st then return H.sayFail(ctx) end
  local ok = st == "BRN" or st == "PSN" or st == "PAR" or st == "TOX"
  if not ok then return H.sayFail(ctx) end
  ctx.adapter:clearStatus(ctx.user)
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. "'s status\nreturned to normal!")
end

function Healing.ingrain(ctx)
  if ctx.user.expIngrain then return H.sayFail(ctx) end
  ctx.user.expIngrain = true
  ctx.user.expTrapped = true
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " planted its roots!")
end

function Healing.recover(ctx)
  local maxHp = ctx.adapter:maxHp(ctx.user)
  local hp = ctx.adapter:hp(ctx.user)
  if hp >= maxHp then return H.sayFail(ctx) end
  local heal = math.floor(maxHp / 2)
  ctx.adapter:heal(ctx.user, heal)
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " regained health!")
end

function Healing.softboiled(ctx)
  return Healing.recover(ctx)
end

function Healing.rest(ctx)
  local user = ctx.user
  local maxHp = ctx.adapter:maxHp(user)
  local hp = ctx.adapter:hp(user)
  if hp >= maxHp then return H.sayFail(ctx) end
  local mon = user.mon or user
  local ability = mon.ability or mon.abilityId or user.ability
  if ability == 15 or ability == 72 or ability == "INSOMNIA" or ability == "VITAL_SPIRIT" then
    ctx.adapter:say(H.displayName(ctx, user) .. " stayed awake!")
    return
  end
  ctx.adapter:clearStatus(user)
  ctx.adapter:heal(user, maxHp - hp)
  user.status = "SLP"
  if user.mon then user.mon.status = "SLP" end
  local sleepTurns = 2
  if ability == 48 or ability == "EARLY_BIRD" then sleepTurns = 1 end
  user.sleepTurns = sleepTurns
  ctx.adapter:say(H.displayName(ctx, user) .. " went to sleep\nand became healthy!")
end

function Healing.bellyDrum(ctx)
  local maxHp = ctx.adapter:maxHp(ctx.user)
  local cost = math.floor(maxHp / 2)
  if ctx.adapter:hp(ctx.user) <= cost then return H.sayFail(ctx) end
  ctx.adapter:applyHpLoss(ctx.user, cost)
  local stages = ctx.adapter:stages(ctx.user)
  if stages then stages.attack = 6 end
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " cut its own HP\nand maximized\nATTACK!")
end

function Healing.wish(ctx)
  local side = ctx.adapter:ownSide(ctx.user)
  if not side then return H.sayFail(ctx) end
  side.tokens = side.tokens or {}
  for _, tok in ipairs(side.tokens) do
    if tok.id == "EXP_WISH" then return H.sayFail(ctx) end
  end
  local heal = math.max(1, math.floor(ctx.adapter:maxHp(ctx.user) / 2))
  side.tokens[#side.tokens + 1] = {
    id = "EXP_WISH",
    turns = 2,
    heal = heal,
  }
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " made\na WISH!")
end

function Healing.healBell(ctx)
  for _, mon in ipairs(ctx.adapter:partyMons(ctx.user)) do
    if mon and mon.status then mon.status = nil end
  end
  ctx.adapter:clearStatus(ctx.user)
  local move = ctx.move or {}
  local label = (move.numId == 312 or move.id == "AROMATHERAPY") and "A soothing aroma" or "A bell chimed"
  ctx.adapter:say(label .. " wafted\nthrough the area!")
end

function Healing.painSplit(ctx)
  if Rules.substitute.blocks("pain_split", ctx.target, ctx.adapter) then return H.sayFail(ctx) end
  local uHp = ctx.adapter:hp(ctx.user)
  local tHp = ctx.adapter:hp(ctx.target)
  local avg = math.floor((uHp + tHp) / 2)
  local uMon = ctx.adapter:mon(ctx.user)
  local tMon = ctx.adapter:mon(ctx.target)
  if not uMon or not tMon then return H.sayFail(ctx) end
  uMon.hp = math.min(ctx.adapter:maxHp(ctx.user), avg)
  tMon.hp = math.min(ctx.adapter:maxHp(ctx.target), avg)
  ctx.adapter:say("The battlers shared\ntheir pain!")
end

function Healing.swallow(ctx)
  local n = ctx.user.expStockpile or 0
  if n <= 0 then return H.sayFail(ctx) end
  local frac = ({ 4, 2, 1 })[n] or 1
  local maxHp = ctx.adapter:maxHp(ctx.user)
  local heal = math.max(1, math.floor(maxHp / frac))
  ctx.user.expStockpile = nil
  if ctx.adapter:hp(ctx.user) >= maxHp then return H.sayFail(ctx) end
  ctx.adapter:heal(ctx.user, heal)
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. " regained\nhealth!")
end

return Healing
