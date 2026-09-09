-- FRLG experience award (pret Cmd_getexp + gExperienceTables).
-- Yields / growth rates come from ROM species meta (pokemon/meta.lua).
-- Level thresholds come from SummaryData (= pret experience_tables.h).

local Pokemon = require("src.core.game3.pokemon")
local SummaryData = require("src.core.game3.summary_data")

local Experience = {}

Experience.MAX_LEVEL = 100

function Experience.expYield(species)
  species = tonumber(species) or (species and species.species) or 0
  local meta = Pokemon.speciesMeta(species)
  return (meta and tonumber(meta.expYield)) or 0
end

--- pret GROWTH_* index for this mon/species (ROM BaseStats.growthRate).
function Experience.growthRate(monOrSpecies)
  if type(monOrSpecies) == "table" then
    local gr = tonumber(monOrSpecies.growthRate)
    if gr then return gr % 6 end
    local sp = tonumber(monOrSpecies.species or monOrSpecies.speciesId)
    local meta = sp and Pokemon.speciesMeta(sp)
    return (meta and tonumber(meta.growthRate) or 0) % 6
  end
  local meta = Pokemon.speciesMeta(tonumber(monOrSpecies))
  return (meta and tonumber(meta.growthRate) or 0) % 6
end

function Experience.expForLevel(monOrGrowth, level)
  local growth = type(monOrGrowth) == "table" and Experience.growthRate(monOrGrowth) or (tonumber(monOrGrowth) or 0) % 6
  return SummaryData.expForLevel(growth, level)
end

--- Highest level whose threshold <= exp (pret GetLevelFromMonExp).
function Experience.levelForExp(monOrGrowth, exp)
  local growth = type(monOrGrowth) == "table" and Experience.growthRate(monOrGrowth) or (tonumber(monOrGrowth) or 0) % 6
  exp = math.max(0, tonumber(exp) or 0)
  local lv = 1
  while lv < Experience.MAX_LEVEL do
    local nextThresh = SummaryData.expForLevel(growth, lv + 1)
    if exp < nextThresh then break end
    lv = lv + 1
  end
  return lv
end

function Experience.progress(mon)
  return SummaryData.expProgress(mon, Experience.growthRate(mon))
end

--- Ensure mon.exp matches its growth curve at current level (new gifts / bad saves).
function Experience.syncExpToLevel(mon)
  if type(mon) ~= "table" then return mon end
  local growth = Experience.growthRate(mon)
  mon.growthRate = growth
  local level = math.max(1, math.min(Experience.MAX_LEVEL, tonumber(mon.level) or 1))
  mon.level = level
  local atLevel = SummaryData.expForLevel(growth, level)
  local nextLevel = level >= Experience.MAX_LEVEL and atLevel or SummaryData.expForLevel(growth, level + 1)
  local exp = tonumber(mon.exp)
  if exp == nil or exp < atLevel or (level < Experience.MAX_LEVEL and exp >= nextLevel) then
    mon.exp = atLevel
  end
  return mon
end

--- pret: calculatedExp = expYield * foeLevel / 7
-- then SAFE_DIV by participants (halved when any Exp.Share holder — deferred).
-- Per-recipient boosts: Lucky Egg ×1.5, trainer ×1.5, traded ×1.5 (floored *150/100).
function Experience.gainFor(foeSpecies, foeLevel, opts)
  opts = opts or {}
  local yield = Experience.expYield(foeSpecies)
  foeLevel = math.max(1, tonumber(foeLevel) or 1)
  local participants = math.max(1, tonumber(opts.participants) or 1)
  local calculated = math.floor(yield * foeLevel / 7)
  local amount = math.floor(calculated / participants)
  if amount < 1 then amount = 1 end
  -- Exp.Share party pass deferred: opts.expShareShare would add half-pool share
  if opts.luckyEgg then
    amount = math.floor(amount * 150 / 100)
  end
  if opts.trainer then
    amount = math.floor(amount * 150 / 100)
  end
  if opts.traded then
    amount = math.floor(amount * 150 / 100)
  end
  if amount < 1 then amount = 1 end
  return amount
end

local function apply_level_stats(mon, newLevel)
  local oldMax = tonumber(mon.maxHp) or 1
  local oldHp = tonumber(mon.hp) or oldMax
  mon.level = newLevel
  Pokemon.applyStats(mon)
  local newMax = tonumber(mon.maxHp) or oldMax
  mon.hp = math.min(newMax, oldHp + math.max(0, newMax - oldMax))
end

--- Add XP to mon using its ROM growth curve. Mutates mon.
-- Returns {
--   gained, fromLevel, toLevel, fromExp, toExp,
--   levels = {N,...},  -- each level reached
--   steps = {{level, fromRatio, toRatio, fillToOne}, ...} for bar anim
-- }
function Experience.apply(mon, amount)
  amount = math.max(0, math.floor(tonumber(amount) or 0))
  Experience.syncExpToLevel(mon)
  local growth = Experience.growthRate(mon)
  local fromLevel = tonumber(mon.level) or 1
  local fromExp = tonumber(mon.exp) or Experience.expForLevel(growth, fromLevel)
  local cap = SummaryData.expForLevel(growth, Experience.MAX_LEVEL)

  if fromLevel >= Experience.MAX_LEVEL or amount <= 0 then
    return {
      gained = 0,
      fromLevel = fromLevel,
      toLevel = fromLevel,
      fromExp = fromExp,
      toExp = fromExp,
      levels = {},
      steps = {},
    }
  end

  local rawGained = amount
  local newExp = math.min(cap, fromExp + amount)
  local applied = newExp - fromExp
  mon.exp = newExp

  local toLevel = Experience.levelForExp(growth, newExp)
  local levels, steps = {}, {}

  -- Bar steps: from current ratio → (fill to 1 per level-up) → final ratio
  local curLevel = fromLevel
  local curExp = fromExp
  while curLevel < toLevel do
    local nextThresh = SummaryData.expForLevel(growth, curLevel + 1)
    local curThresh = SummaryData.expForLevel(growth, curLevel)
    local span = math.max(1, nextThresh - curThresh)
    local fromRatio = math.max(0, math.min(1, (curExp - curThresh) / span))
    steps[#steps + 1] = {
      level = curLevel,
      fromRatio = fromRatio,
      toRatio = 1,
      grewTo = curLevel + 1,
    }
    curLevel = curLevel + 1
    curExp = nextThresh
    levels[#levels + 1] = curLevel
    apply_level_stats(mon, curLevel)
    steps[#steps].hp = tonumber(mon.hp)
    steps[#steps].maxHp = tonumber(mon.maxHp)
  end

  -- Remainder into final level
  do
    local curThresh = SummaryData.expForLevel(growth, toLevel)
    local nextThresh = toLevel >= Experience.MAX_LEVEL and curThresh
      or SummaryData.expForLevel(growth, toLevel + 1)
    local span = math.max(1, nextThresh - curThresh)
    local fromRatio = (curLevel == fromLevel)
      and math.max(0, math.min(1, (fromExp - curThresh) / span))
      or 0
    local toRatio = toLevel >= Experience.MAX_LEVEL and 1
      or math.max(0, math.min(1, (newExp - curThresh) / span))
    if toRatio > fromRatio + 0.0001 or (#steps == 0 and applied > 0) then
      steps[#steps + 1] = {
        level = toLevel,
        fromRatio = fromRatio,
        toRatio = toRatio,
        grewTo = nil,
      }
    end
  end

  if toLevel > fromLevel then
    -- stats already applied per level; ensure final
    apply_level_stats(mon, toLevel)
  end

  return {
    gained = applied,
    rawGained = rawGained,
    fromLevel = fromLevel,
    toLevel = toLevel,
    fromExp = fromExp,
    toExp = newExp,
    levels = levels,
    steps = steps,
  }
end

--- Award XP for a defeated foe to participant party mons.
-- opts: trainer, participants (count), getOpts(mon, partyIndex) → luckyEgg/traded
-- Returns list of { mon, partyIndex, battler?, result }
function Experience.awardFoe(st, foeBattler, opts)
  opts = opts or {}
  if not st or not foeBattler then return {} end
  local foeMon = foeBattler.mon
  local foeSpecies = foeBattler.species or (foeMon and (foeMon.species or foeMon.speciesId))
  local foeLevel = (foeMon and foeMon.level) or foeBattler.level or 1
  local isTrainer = opts.trainer
  if isTrainer == nil then isTrainer = not st.wild end

  local indices = opts.partyIndices
  if not indices then
    -- MVP: active player participant if alive
    indices = {}
    local p = st.player
    if p and p.mon and (tonumber(p.mon.hp) or 0) > 0 then
      indices[1] = p.partyIndex or 1
    end
  end
  local nPart = math.max(1, #indices)
  local out = {}
  for _, pi in ipairs(indices) do
    local mon = st.playerParty and st.playerParty[pi]
    if mon and (tonumber(mon.hp) or 0) > 0 and (tonumber(mon.level) or 1) < Experience.MAX_LEVEL then
      local per = opts.getOpts and opts.getOpts(mon, pi) or {}
      local amount = Experience.gainFor(foeSpecies, foeLevel, {
        participants = nPart,
        trainer = isTrainer,
        luckyEgg = per.luckyEgg,
        traded = per.traded,
      })
      local result = Experience.apply(mon, amount)
      -- Keep active battler fields in sync
      if st.player and st.player.partyIndex == pi then
        st.player.mon = mon
        st.player.fainted = (tonumber(mon.hp) or 0) <= 0
      end
      out[#out + 1] = {
        mon = mon,
        partyIndex = pi,
        battler = (st.player and st.player.partyIndex == pi) and st.player or nil,
        amount = amount,
        result = result,
      }
    end
  end
  return out
end

return Experience
