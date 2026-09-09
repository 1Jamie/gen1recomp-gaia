-- After-hit secondaries for damaging moves (owned game3).

local EffectIds = require("src.core.game3.battle.effect_ids")
local Rules = require("src.core.game3.battle.rules")

local Damaging = {}

local function roll_chance(adapter, percent)
  percent = tonumber(percent) or 0
  if percent <= 0 then return false end
  if percent >= 100 then return true end
  local ok, r = pcall(adapter:rng(), 1, 100)
  if not (ok and type(r) == "number") then r = math.random(1, 100) end
  return r <= percent
end

--- Apply after-damage secondary from ROM effect id / move fields.
function Damaging.afterHit(adapter, user, target, move, dmg)
  if not move or (dmg or 0) <= 0 then return end
  if adapter:isFainted(target) and move.effect ~= EffectIds.ABSORB
      and move.effect ~= EffectIds.DREAM_EATER then
    -- Still allow recoil on user
  end

  local spec = EffectIds.AFTER_HIT[tonumber(move.effect) or -1]
  if not spec and move.afterHit then spec = move.afterHit end
  if not spec then return end

  local chance = tonumber(move.secondaryChance) or 100
  if spec.kind == "recoil" or spec.kind == "drain" or spec.kind == "stat_user" then
    chance = 100
  end
  if not roll_chance(adapter, chance) then return end

  if spec.kind == "status" then
    if Rules.substitute.blocks("status", target, adapter) then return end
    if adapter:applyStatus(target, spec.status, user, { secondary = true }) then
      local msg = {
        BRN = " was burned!",
        PSN = " was poisoned!",
        TOX = " was badly poisoned!",
        PAR = " is paralyzed!",
        FRZ = " was frozen solid!",
        SLP = " fell asleep!",
      }
      adapter:say(adapter:displayName(target) .. (msg[spec.status] or " was afflicted!"))
    end
  elseif spec.kind == "flinch" then
    if Rules.substitute.hasSubstitute(target, adapter) then return end
    target.flinched = true
  elseif spec.kind == "drain" then
    local heal = math.max(1, math.floor((dmg or 0) * (spec.fraction or 0.5)))
    adapter:heal(user, heal)
    adapter:say(adapter:displayName(user) .. " had its energy\ndrained!")
  elseif spec.kind == "recoil" then
    local loss = math.max(1, math.floor((dmg or 0) * (spec.fraction or 0.25)))
    adapter:applyHpLoss(user, loss)
    adapter:say(adapter:displayName(user) .. " is hit\nwith recoil!")
  elseif spec.kind == "stat" then
    if Rules.substitute.blocks("stat_drop", target, adapter) then return end
    local side = adapter:ownSide(target)
    if side and (side.expMistTurns or 0) > 0 then return end
    adapter:changeStages(target, spec.stages)
    adapter:say(adapter:displayName(target) .. "'s stats fell!")
  elseif spec.kind == "stat_user" then
    adapter:changeStages(user, spec.stages)
    adapter:say(adapter:displayName(user) .. "'s stats changed!")
  elseif spec.kind == "confuse" then
    target.confusionTurns = 2 + (tonumber((function()
      local ok, v = pcall(adapter:rng(), 1, 3)
      return ok and v or 2
    end)()) or 2)
    adapter:say(adapter:displayName(target) .. " became confused!")
  end
end

--- Brick Break: clear foe Reflect / Light Screen.
function Damaging.brickBreak(adapter, target)
  local side = adapter:ownSide(target)
  if not side then return false end
  local cleared = false
  if (side.expReflectTurns or 0) > 0 then
    side.expReflectTurns = nil
    cleared = true
  end
  if (side.expLightScreenTurns or 0) > 0 then
    side.expLightScreenTurns = nil
    cleared = true
  end
  if cleared then
    adapter:say("The wall shattered!")
  end
  return cleared
end

return Damaging
