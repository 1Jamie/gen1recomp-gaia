-- Game3 battle rules (owned). Crit / weather mods / residual phase labels.

local Capabilities = require("src.core.game3.battle.capabilities")

local Rules = {}

Rules.PHASE_ORDER = {
  "weather_continue",
  "weather_chip",
  "weather_tick",
  "status_chip",
  "leech_seed",
  "partial_trap_chip",
  "partial_trap_tick",
  "volatiles",
  "held_items",
  "abilities_eot",
}

Rules.FAINT_HALT_PHASES = {
  weather_chip = true,
  status_chip = true,
  leech_seed = true,
  partial_trap_chip = true,
  volatiles = true,
}

Rules.FIELD_PHASES = {
  weather_continue = true,
  weather_chip = true,
  weather_tick = true,
}

function Rules.isFieldPhase(phase)
  return Rules.FIELD_PHASES[phase] == true
end

function Rules.phaseOrder()
  return Rules.PHASE_ORDER
end

function Rules.shouldHaltBattlerOnFaint(phase)
  return Rules.FAINT_HALT_PHASES[phase] == true
end

-- Partial trap (Gen3)
Rules.partialTrap = {}

function Rules.partialTrap.chipAmount(maxHp)
  return math.max(1, math.floor((maxHp or 16) / Capabilities.partialTrapChipDenom))
end

function Rules.partialTrap.rollTurns(rng)
  rng = rng or math.random
  local minT = Capabilities.partialTrapMinTurns
  local maxT = Capabilities.partialTrapMaxTurns
  local ok, n = pcall(rng, minT, maxT)
  if not (ok and type(n) == "number") then
    n = minT + math.random(0, maxT - minT)
  end
  return math.max(minT, math.min(maxT, math.floor(n)))
end

function Rules.partialTrap.active()
  return Capabilities.gen3PartialTrap
end

-- Weather type power mods (FRLG Sunny Day / Rain Dance).
Rules.weather = {}

function Rules.weather.typeModifier(weather, moveTypeName)
  local mods = {
    SUNNY = { FIRE = 1.5, WATER = 0.5 },
    RAINY = { WATER = 1.5, FIRE = 0.5 },
  }
  local row = weather and mods[weather]
  if row and moveTypeName and row[moveTypeName] then return row[moveTypeName] end
  return 1
end

function Rules.weather.chipAmount(maxHp)
  return math.max(1, math.floor((maxHp or 16) / Capabilities.weatherChipDenom))
end

-- Crit (Gen3 stage ladder)
Rules.crit = {}

local STAGE_NUM = { [0] = 1, [1] = 2, [2] = 4, [3] = 1, [4] = 1 }
local STAGE_DEN = { [0] = 16, [1] = 8, [2] = 4, [3] = 3, [4] = 2 }

local HIGH_CRIT = {
  KARATE_CHOP = true, RAZOR_LEAF = true, CRABHAMMER = true, SLASH = true,
  AEROBLAST = true, AIR_CUTTER = true, CROSS_CHOP = true, LEAF_BLADE = true,
  POISON_TAIL = true, STONE_EDGE = true,
}

function Rules.crit.stage(attacker, moveId, highCrit)
  if not Capabilities.gen3Crit then return 0 end
  local stage = 0
  if attacker and (attacker.focusEnergy or attacker.expFocusEnergy) then
    stage = stage + 2
  end
  if highCrit == nil then highCrit = HIGH_CRIT[moveId] end
  if highCrit then stage = stage + 1 end
  if stage > 4 then stage = 4 end
  return stage
end

local function rollZeroTo(rng, den)
  if den <= 1 then return 0 end
  if type(rng) ~= "function" then
    return math.random(0, den - 1)
  end
  local ok, a = pcall(rng, 0, den - 1)
  if ok and type(a) == "number" then return a % den end
  ok, a = pcall(rng, den)
  if ok and type(a) == "number" then return a % den end
  return math.random(0, den - 1)
end

function Rules.crit.roll(attacker, moveId, highCrit, rng)
  local stage = Rules.crit.stage(attacker, moveId, highCrit)
  local num = STAGE_NUM[stage] or 1
  local den = STAGE_DEN[stage] or 2
  return rollZeroTo(rng, den) < num
end

function Rules.crit.multiplier()
  return Capabilities.critMultiplier or 2
end

Rules.weather.SAND_IMMUNE = { ROCK = true, GROUND = true, STEEL = true }
Rules.weather.HAIL_IMMUNE = { ICE = true }

function Rules.weather.hits(types, kind)
  kind = kind or "SANDSTORM"
  local immune = (kind == "HAIL" or kind == "SNOWY")
    and Rules.weather.HAIL_IMMUNE or Rules.weather.SAND_IMMUNE
  for _, t in ipairs(types or {}) do
    if immune[t] then return false end
  end
  return true
end

-- Substitute guard
Rules.substitute = {}

function Rules.substitute.hasSubstitute(battler, adapter)
  if not battler then return false end
  if adapter and type(adapter.hasSubstitute) == "function" then
    return adapter:hasSubstitute(battler)
  end
  return (battler.substituteHP or 0) > 0
end

function Rules.substitute.blocks(effectKind, target, adapter)
  if not Rules.substitute.hasSubstitute(target, adapter) then return false end
  local blocked = {
    status = true, stat_drop = true, taunt = true, yawn = true,
    burn = true, attract = true, pain_split = true,
  }
  return blocked[effectKind] == true
end

return Rules
