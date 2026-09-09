-- Gen3-shaped damage formula (owned game3 battle).

local Rules = require("src.core.game3.battle.rules")
local Types = require("src.core.game3.battle.types")
local Moves = require("src.core.game3.battle.moves")
local EffectIds = require("src.core.game3.battle.effect_ids")

local Damage = {}

local STAGE_MULT = {
  [-6] = 2 / 8, [-5] = 2 / 7, [-4] = 2 / 6, [-3] = 2 / 5, [-2] = 2 / 4, [-1] = 2 / 3,
  [0] = 1,
  [1] = 3 / 2, [2] = 4 / 2, [3] = 5 / 2, [4] = 6 / 2, [5] = 7 / 2, [6] = 8 / 2,
}

local function clamp_stage(s)
  s = tonumber(s) or 0
  if s < -6 then return -6 end
  if s > 6 then return 6 end
  return s
end

function Damage.stageMul(stage)
  return STAGE_MULT[clamp_stage(stage)] or 1
end

local function mon_stat(mon, key, fallback)
  if not mon then return fallback end
  local v = mon[key]
  if v == nil and key == "spAtk" then v = mon.spa or mon.specialAttack end
  if v == nil and key == "spDef" then v = mon.spd or mon.specialDefense end
  if v == nil and key == "attack" then v = mon.atk end
  if v == nil and key == "defense" then v = mon.def end
  if v == nil and key == "speed" then v = mon.spe end
  return tonumber(v) or fallback
end

--- Fill missing battle stats from extracted species base stats + IVs.
function Damage.ensureStats(mon, level)
  level = tonumber(level or mon and mon.level) or 5
  mon = mon or {}
  mon.level = level

  local Pokemon = require("src.core.game3.pokemon")
  local species = tonumber(mon.species or mon.speciesId)
  if species and Pokemon.stats and Pokemon.stats(species) then
    if not mon.ivs then
      mon.ivs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
    end
    if not mon.evs then
      mon.evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
    end
    if mon.personality == nil then mon.personality = 0 end
    -- Only recompute when battle stats are missing.
    local need = (not mon.maxHp or mon.maxHp <= 0)
      or (mon_stat(mon, "attack", 0) <= 0)
      or (mon_stat(mon, "defense", 0) <= 0)
      or (mon_stat(mon, "spAtk", 0) <= 0)
      or (mon_stat(mon, "spDef", 0) <= 0)
      or (mon_stat(mon, "speed", 0) <= 0)
    if need then
      local keepHp = mon.hp
      Pokemon.applyStats(mon)
      if keepHp ~= nil and keepHp >= 0 then
        mon.hp = math.min(keepHp, mon.maxHp)
      end
    end
    if not mon.ability and not mon.abilityId and Pokemon.abilityId then
      mon.ability = Pokemon.abilityId(species, mon.personality)
      mon.abilityId = mon.ability
    end
    return mon
  end

  -- Fallback when species pack missing.
  local base = 50
  if not mon.maxHp or mon.maxHp <= 0 then
    mon.maxHp = math.floor(((2 * base) * level) / 100) + level + 10
  end
  if not mon.hp or mon.hp < 0 then mon.hp = mon.maxHp end
  if mon.hp > mon.maxHp then mon.hp = mon.maxHp end
  local function fill(key, b)
    if mon_stat(mon, key, 0) <= 0 then
      mon[key] = math.floor(((2 * b) * level) / 100) + 5
    end
  end
  fill("attack", 55)
  fill("defense", 50)
  fill("spAtk", 50)
  fill("spDef", 50)
  fill("speed", 50)
  return mon
end

function Damage.calc(attacker, defender, moveId, opts)
  opts = opts or {}
  local move = Moves.get(moveId)
  local power = tonumber(move.power) or 0
  if power <= 0 then
    return 0, { move = move, effectiveness = 1, critical = false, status = true }
  end

  local aMon = attacker.mon or attacker
  local dMon = defender.mon or defender
  Damage.ensureStats(aMon, aMon.level)
  Damage.ensureStats(dMon, dMon.level)

  local effectByte = tonumber(move.effect)
  local moveType = move.type
  local magnitudeVal = nil

  -- Dynamic power and type calculations (Phase 3 moves)
  if effectByte == EffectIds.MAGNITUDE then
    local rng = opts.rng or math.random
    local r
    local ok, v = pcall(rng, 0, 99)
    if ok and type(v) == "number" then r = v else r = math.random(0, 99) end
    if r < 5 then
      magnitudeVal, power = 4, 10
    elseif r < 15 then
      magnitudeVal, power = 5, 30
    elseif r < 35 then
      magnitudeVal, power = 6, 50
    elseif r < 65 then
      magnitudeVal, power = 7, 70
    elseif r < 85 then
      magnitudeVal, power = 8, 90
    elseif r < 95 then
      magnitudeVal, power = 9, 110
    else
      magnitudeVal, power = 10, 150
    end
  elseif effectByte == EffectIds.RETURN then
    local friendship = tonumber(aMon.friendship) or 70
    power = math.max(1, math.floor(friendship * 2 / 5))
  elseif effectByte == EffectIds.FRUSTRATION then
    local friendship = tonumber(aMon.friendship) or 70
    power = math.max(1, math.floor((255 - friendship) * 2 / 5))
  elseif effectByte == EffectIds.ERUPTION then
    local curHp = aMon.hp or attacker.hp or 1
    local maxHp = aMon.maxHp or attacker.maxHp or 1
    power = math.max(1, math.floor(150 * curHp / maxHp))
  elseif effectByte == EffectIds.FLAIL then
    local curHp = aMon.hp or attacker.hp or 1
    local maxHp = aMon.maxHp or attacker.maxHp or 1
    local n = math.floor(48 * curHp / maxHp)
    if n <= 1 then
      power = 200
    elseif n <= 4 then
      power = 150
    elseif n <= 9 then
      power = 100
    elseif n <= 16 then
      power = 80
    elseif n <= 32 then
      power = 40
    else
      power = 20
    end
  elseif effectByte == EffectIds.PURSUIT and opts.pursuitSwitch then
    power = power * 2
  elseif effectByte == EffectIds.FACADE then
    local st = aMon.status or attacker.status or attacker.expStatus
    if st == "BRN" or st == "PAR" or st == "PSN" or st == "TOX" then
      power = power * 2
    end
  elseif effectByte == EffectIds.REVENGE then
    if (attacker.damageTakenThisTurn or 0) > 0 then
      power = power * 2
    end
  elseif effectByte == EffectIds.SMELLINGSALT then
    local st = dMon.status or defender.status or defender.expStatus
    if st == "PAR" then
      power = power * 2
    end
  elseif effectByte == EffectIds.WEATHER_BALL then
    local weather = opts.weather
    if weather == "sun" or weather == "sunny" then
      power = 100
      moveType = Types.ID.FIRE
    elseif weather == "rain" or weather == "rainy" then
      power = 100
      moveType = Types.ID.WATER
    elseif weather == "sand" or weather == "sandstorm" then
      power = 100
      moveType = Types.ID.ROCK
    elseif weather == "hail" then
      power = 100
      moveType = Types.ID.ICE
    end
  elseif effectByte == EffectIds.LOW_KICK then
    local wt = 0
    if dMon.weight then
      wt = tonumber(dMon.weight) or 0
    else
      local Pokemon = require("src.core.game3.pokemon")
      local sp = Pokemon.speciesOf(dMon)
      local dex = sp and Pokemon.dexEntry(sp)
      if dex and dex.weight then
        wt = tonumber(dex.weight) or 0
      end
    end
    -- Gen 3 Low Kick weight thresholds (wt is in tenths of a kg: 100 = 10.0kg)
    if wt < 100 then
      power = 20
    elseif wt < 250 then
      power = 40
    elseif wt < 500 then
      power = 60
    elseif wt < 1000 then
      power = 80
    elseif wt < 2000 then
      power = 100
    else
      power = 120
    end
  end

  local physical = move.category == "physical"
    or (move.category ~= "special" and Types.isPhysical(moveType))

  local aStages = attacker.stages or {}
  local dStages = defender.stages or {}
  local atkStat, defStat
  if physical then
    atkStat = mon_stat(aMon, "attack", 50) * Damage.stageMul(aStages.attack)
    defStat = mon_stat(dMon, "defense", 50) * Damage.stageMul(dStages.defense)
    local aSt = aMon.status or attacker.status or attacker.expStatus
    if aSt == "BRN" and effectByte ~= EffectIds.FACADE then
      atkStat = math.floor(atkStat * 0.5)
    end
  else
    atkStat = mon_stat(aMon, "spAtk", 50) * Damage.stageMul(aStages.spAtk)
    defStat = mon_stat(dMon, "spDef", 50) * Damage.stageMul(dStages.spDef)
  end
  if defStat < 1 then defStat = 1 end
  local level = tonumber(aMon.level or attacker.level) or 5
  local base = math.floor(math.floor((2 * level / 5 + 2) * power * atkStat / defStat) / 50) + 2

  -- STAB
  local stab = 1
  local t1, t2 = attacker.type1, attacker.type2
  if t1 == moveType or t2 == moveType then stab = 1.5 end

  local eff = Types.effectiveness(moveType, defender.type1, defender.type2)
  if eff == 0 then
    return 0, {
      move = move,
      effectiveness = 0,
      critical = false,
      physical = physical,
      stab = stab,
      magnitude = magnitudeVal,
    }
  end

  local effectByte = tonumber(move.effect)
  if effectByte == EffectIds.COUNTER then
    local taken = attacker.lastPhysicalDamageTaken or 0
    if taken <= 0 then
      return 0, {
        move = move,
        effectiveness = eff,
        critical = false,
        physical = physical,
        failed = true,
      }
    end
    return taken * 2, {
      move = move,
      effectiveness = eff,
      critical = false,
      physical = physical,
      fixed = true,
    }
  elseif effectByte == EffectIds.MIRROR_COAT then
    local taken = attacker.lastSpecialDamageTaken or 0
    if taken <= 0 then
      return 0, {
        move = move,
        effectiveness = eff,
        critical = false,
        physical = physical,
        failed = true,
      }
    end
    return taken * 2, {
      move = move,
      effectiveness = eff,
      critical = false,
      physical = physical,
      fixed = true,
    }
  elseif effectByte == EffectIds.DRAGON_RAGE then
    return 40, {
      move = move,
      effectiveness = eff,
      critical = false,
      physical = physical,
      fixed = true,
    }
  elseif effectByte == EffectIds.SONICBOOM then
    return 20, {
      move = move,
      effectiveness = eff,
      critical = false,
      physical = physical,
      fixed = true,
    }
  elseif effectByte == EffectIds.LEVEL_DAMAGE then
    return level, {
      move = move,
      effectiveness = eff,
      critical = false,
      physical = physical,
      fixed = true,
    }
  elseif effectByte == EffectIds.SUPER_FANG then
    local dHp = defender.mon and defender.mon.hp or defender.hp or 1
    return math.max(1, math.floor(dHp / 2)), {
      move = move,
      effectiveness = eff,
      critical = false,
      physical = physical,
      fixed = true,
    }
  elseif effectByte == EffectIds.ENDEAVOR then
    local uHp = attacker.mon and attacker.mon.hp or attacker.hp or 0
    local dHp = defender.mon and defender.mon.hp or defender.hp or 0
    if uHp >= dHp then
      return 0, {
        move = move,
        effectiveness = eff,
        critical = false,
        physical = physical,
        failed = true,
      }
    end
    return dHp - uHp, {
      move = move,
      effectiveness = eff,
      critical = false,
      physical = physical,
      fixed = true,
    }
  elseif effectByte == EffectIds.PSYWAVE then
    local rng = opts.rng or math.random
    local r
    local ok, v = pcall(rng, 0, 100)
    if ok and type(v) == "number" then r = v else r = math.random(0, 100) end
    local dmg = math.max(1, math.floor(level * (r + 50) / 100))
    return dmg, {
      move = move,
      effectiveness = eff,
      critical = false,
      physical = physical,
      fixed = true,
    }
  end

  local weather = opts.weather
  local wmod = Rules.weather.typeModifier(weather, Types.name(move.type))

  local crit = false
  if opts.forceCrit ~= nil then
    crit = opts.forceCrit and true or false
  else
    crit = Rules.crit.roll(attacker, move.id, opts.highCrit, opts.rng)
  end
  local critMul = crit and Rules.crit.multiplier() or 1

  local dmg = math.floor(base * stab * eff * wmod * critMul)

  -- Random 85–100%
  local rng = opts.rng or math.random
  local roll
  if opts.forceRoll then
    roll = opts.forceRoll
  else
    local ok, r = pcall(rng, 85, 100)
    if ok and type(r) == "number" then
      roll = r
    else
      roll = 85 + (math.random(0, 15))
    end
  end
  dmg = math.floor(dmg * roll / 100)
  if dmg < 1 and eff > 0 then dmg = 1 end
  if eff == 0 then dmg = 0 end

  if effectByte == EffectIds.FALSE_SWIPE and eff > 0 then
    local dMon = defender.mon or defender
    local curHp = tonumber(dMon.hp) or 1
    if curHp <= 1 then
      dmg = 0
    elseif dmg >= curHp then
      dmg = curHp - 1
    end
  end

  return dmg, {
    move = move,
    effectiveness = eff,
    critical = crit,
    physical = physical,
    stab = stab,
    magnitude = magnitudeVal,
    moveType = moveType,
  }
end

return Damage
