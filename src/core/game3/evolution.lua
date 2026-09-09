-- Post-battle evolution (pret TryEvolvePokemon / EVO_MODE_NORMAL).
-- MVP: ROM EVO_LEVEL (method 4) only. Stones/trade/friendship later.

local Pokemon = require("src.core.game3.pokemon")

local Evolution = {}

-- pret constants/pokemon.h
Evolution.EVO_FRIENDSHIP = 1
Evolution.EVO_FRIENDSHIP_DAY = 2
Evolution.EVO_FRIENDSHIP_NIGHT = 3
Evolution.EVO_LEVEL = 4
Evolution.EVO_TRADE = 5
Evolution.EVO_TRADE_ITEM = 6
Evolution.EVO_ITEM = 7

local EVERSTONE = 197 -- FRLG ITEM_EVERSTONE

local function held_is_everstone(mon)
  local item = mon and (mon.item or mon.heldItem)
  if item == nil then return false end
  if tonumber(item) == EVERSTONE then return true end
  if type(item) == "string" and item:upper():find("EVERSTONE", 1, true) then
    return true
  end
  return false
end

local function is_national_unlocked(session)
  local PokedexData = require("src.core.game3.pokedex_data")
  return PokedexData.isNationalUnlocked(session)
end

--- Target species for level-up evolution, or nil.
function Evolution.levelTarget(mon, session)
  if not mon then return nil end
  if held_is_everstone(mon) then return nil end
  local species = tonumber(mon.species or mon.speciesId)
  local level = tonumber(mon.level) or 1
  if not species then return nil end
  for _, evo in ipairs(Pokemon.evolutions(species)) do
    local method = tonumber(evo.method or evo[1]) or 0
    local param = tonumber(evo.param or evo[2]) or 0
    local target = tonumber(evo.target or evo[3]) or 0
    if method == Evolution.EVO_LEVEL and target > 0 and level >= param then
      -- National Dex gating: prevent evolving into non-Kanto species (target > 151) if locked
      if target > 151 and not is_national_unlocked(session) then
        return nil
      end
      return target, param
    elseif (method == Evolution.EVO_FRIENDSHIP or method == Evolution.EVO_FRIENDSHIP_DAY or method == Evolution.EVO_FRIENDSHIP_NIGHT) and target > 0 then
      local friendship = tonumber(mon.friendship) or 220
      if friendship >= 220 then
        if target > 151 and not is_national_unlocked(session) then
          return nil
        end
        return target, 0
      end
    end
  end
  return nil
end

--- Target species for item/stone evolution, or nil.
function Evolution.itemTarget(mon, itemId, session)
  if not mon then return nil end
  if held_is_everstone(mon) then return nil end
  local species = tonumber(mon.species or mon.speciesId)
  local ItemsData = require("src.core.game3.items_data")
  local num = ItemsData.toNumericId(itemId) or tonumber(itemId)
  if not species or not num then return nil end
  for _, evo in ipairs(Pokemon.evolutions(species)) do
    local method = tonumber(evo.method or evo[1]) or 0
    local param = tonumber(evo.param or evo[2]) or 0
    local target = tonumber(evo.target or evo[3]) or 0
    if (method == Evolution.EVO_ITEM or method == Evolution.EVO_TRADE_ITEM) and param == num and target > 0 then
      -- National Dex gating: prevent evolving into non-Kanto species (target > 151) if locked
      if target > 151 and not is_national_unlocked(session) then
        return nil
      end
      return target
    end
  end
  return nil
end

--- Apply species change + stats. Preserves HP ratio-ish via maxHp delta.
function Evolution.apply(mon, newSpecies)
  newSpecies = tonumber(newSpecies)
  if not mon or not newSpecies then return false end
  local oldMax = tonumber(mon.maxHp) or 1
  local oldHp = tonumber(mon.hp) or oldMax
  mon.species = newSpecies
  mon.speciesId = newSpecies
  local nm = Pokemon.name(newSpecies)
  if nm then
    -- Only replace species name if no nickname
    if not mon.nickname or mon.nickname == "" then
      mon.name = nm
    end
  end
  Pokemon.applyStats(mon)
  local newMax = tonumber(mon.maxHp) or oldMax
  mon.hp = math.min(newMax, oldHp + math.max(0, newMax - oldMax))
  return true
end

--- Scan party (or indices) for pending level evolutions.
-- leveledSet: optional {[partyIndex]=true} from battle.
-- Returns { {mon, partyIndex, fromSpecies, toSpecies}, ... }
function Evolution.pending(party, leveledSet)
  local out = {}
  if type(party) ~= "table" then return out end
  for i, mon in ipairs(party) do
    if mon and (not leveledSet or leveledSet[i]) then
      local target = Evolution.levelTarget(mon)
      if target then
        out[#out + 1] = {
          mon = mon,
          partyIndex = i,
          fromSpecies = tonumber(mon.species or mon.speciesId),
          toSpecies = target,
        }
      end
    end
  end
  return out
end

return Evolution
