-- Battle state: battlers, sides, weather, result.

local Damage = require("src.core.game3.battle.damage")
local Pokemon = require("src.core.game3.pokemon")

local State = {}

local function species_id(mon)
  if not mon then return 1 end
  local s = mon.species or mon.id
  if type(s) == "number" then return s end
  if type(s) == "string" then
    local id = Pokemon.speciesFromName(s)
    if id then return id end
    return tonumber(s) or 1
  end
  return 1
end

local function types_for(species)
  if not Pokemon._types then pcall(Pokemon.install, nil) end
  local t = Pokemon.types(species)
  return t[1] or 0, t[2] or 0
end

local function held_item(mon)
  if not mon then return 0 end
  return tonumber(mon.item or mon.heldItem) or 0
end

function State.makeBattler(mon, side, opts)
  opts = opts or {}
  mon = Damage.ensureStats(mon, mon and mon.level)
  local species = species_id(mon)
  local t1, t2 = types_for(species)
  local ability = mon.ability or mon.abilityId
  if not ability and Pokemon.abilityId then
    ability = Pokemon.abilityId(species, mon.personality or 0)
  end
  return {
    mon = mon,
    side = side, -- "player" | "enemy"
    partyIndex = opts.partyIndex or 1,
    species = species,
    type1 = t1,
    type2 = (t2 ~= t1) and t2 or nil,
    ability = ability,
    item = held_item(mon),
    stages = {
      attack = 0, defense = 0, spAtk = 0, spDef = 0, speed = 0,
      accuracy = 0, evasion = 0,
    },
    status = mon.status,
    fainted = (tonumber(mon.hp) or 0) <= 0,
    -- pokefirered/src/battle_main.c:2228
    isFirstTurn = 2,
  }
end

function State.new(opts)
  opts = opts or {}
  local playerParty = opts.playerParty or {}
  local pi = opts.playerIndex or 1
  local foeMon = opts.foeMon
  local st = {
    kind = opts.wild and "wild" or "trainer",
    wild = opts.wild and true or false,
    playerParty = playerParty,
    foeParty = opts.foeParty or { foeMon },
    player = nil,
    enemy = nil,
    playerSide = { hazards = {}, id = "player" },
    enemySide = { hazards = {}, id = "enemy" },
    weather = opts.weather,
    weatherTurns = 0,
    terrain = opts.terrain,
    turn = 0,
    over = false,
    result = nil,
    rng = opts.rng or require("src.core.game3.rng").compat,
    fleeAttempts = 0,
    log = {},
  }
  local pMon = playerParty[pi]
  st.player = State.makeBattler(pMon, "player", { partyIndex = pi })
  local eMon = foeMon or st.foeParty[1]
  st.enemy = State.makeBattler(eMon, "enemy", { partyIndex = 1 })
  State.trackParticipant(st, st.enemy, pi)
  return st
end

function State.displayName(battler)
  if not battler then return "POKéMON" end
  local mon = battler.mon
  if mon and mon.nickname and mon.nickname ~= "" then return mon.nickname end
  pcall(function()
    if not Pokemon._names then Pokemon.install(nil) end
  end)
  return Pokemon.name(battler.species)
end

function State.isFainted(battler)
  if not battler then return true end
  if type(battler) == "string" then return false end
  return battler.fainted or (tonumber(battler.mon and battler.mon.hp) or 0) <= 0
end

function State.applyHpLoss(battler, amount)
  if not battler or not battler.mon then return 0 end
  amount = math.floor(tonumber(amount) or 0)
  if amount < 0 then amount = 0 end
  local hp = tonumber(battler.mon.hp) or 0
  local lost = math.min(hp, amount)
  battler.mon.hp = hp - lost
  if battler.mon.hp <= 0 then
    battler.mon.hp = 0
    battler.fainted = true
  end
  return lost
end

function State.heal(battler, amount)
  if not battler or not battler.mon then return 0 end
  amount = math.floor(tonumber(amount) or 0)
  local hp = tonumber(battler.mon.hp) or 0
  local maxHp = tonumber(battler.mon.maxHp) or hp
  local nextHp = math.min(maxHp, hp + amount)
  local gained = nextHp - hp
  battler.mon.hp = nextHp
  if nextHp > 0 then battler.fainted = false end
  return gained
end

function State.ensureBattleMoves(battler)
  if not battler or not battler.mon then return nil end
  if battler._partyMon then return battler.mon end
  local base = battler.mon
  local moves, pp = {}, {}
  for i = 1, 4 do
    moves[i] = base.moves and base.moves[i] or nil
    pp[i] = base.pp and base.pp[i] or nil
  end
  local proxy = setmetatable({ moves = moves, pp = pp }, {
    __index = base,
    __newindex = base,
  })
  battler._partyMon = base
  battler.mon = proxy
  battler.permanentSlots = battler.permanentSlots or { true, true, true, true }
  return proxy
end

function State.partyMon(battler)
  if not battler then return nil end
  return battler._partyMon or battler.mon
end

function State.wipeVolatilesAndStages(battler, opts)
  opts = opts or {}
  if not battler then return end
  if not opts.batonPass then
    battler.stages = {
      attack = 0, defense = 0, spAtk = 0, spDef = 0, speed = 0,
      accuracy = 0, evasion = 0,
    }
  end
  -- Volatile status conditions
  battler.volatiles = opts.batonPass and battler.volatiles or {}
  battler.confusion = opts.batonPass and battler.confusion or nil
  battler.seeded = nil
  battler.trapped = nil
  battler.attracted = nil
  battler.substitute = opts.batonPass and battler.substitute or nil
  battler.focusEnergy = opts.batonPass and battler.focusEnergy or nil
  battler.toxicCounter = nil
  battler.disabled = nil
  battler.encore = nil
  battler.taunt = nil
  battler.bide = nil
  battler.rage = nil
  battler.endure = nil
  battler.protect = nil
  battler.destinyBond = nil
  battler.perishSong = opts.batonPass and battler.perishSong or nil
end

function State.syncBattlerToParty(battler, party)
  if not battler or not party then return end
  local idx = battler.partyIndex or 1
  local mon = party[idx]
  if not mon then return end
  local bMon = battler.mon
  if not bMon then return end
  mon.hp = tonumber(bMon.hp) or 0
  mon.maxHp = tonumber(bMon.maxHp) or mon.maxHp
  local status = battler.status or bMon.status
  if status == 0 then status = nil end
  mon.status = status
  mon.sleep = bMon.sleep
  mon.level = bMon.level or mon.level
  mon.exp = bMon.exp or mon.exp
  if battler._partyMon then
    -- pokefirered/include/battle.h:28
    local perm = battler.permanentSlots or {}
    mon.pp = mon.pp or {}
    mon.moves = mon.moves or {}
    for i = 1, 4 do
      if perm[i] and not battler.transformed then
        mon.pp[i] = bMon.pp and bMon.pp[i] or mon.pp[i]
        if battler.sketched and battler.sketched[i] then
          mon.moves[i] = bMon.moves[i]
        end
      end
    end
    return
  end
  if bMon.pp then mon.pp = bMon.pp end
  if bMon.moves then mon.moves = bMon.moves end
end

function State.trackParticipant(st, foeBattler, partyIndex)
  if not st or not foeBattler then return end
  foeBattler.participants = foeBattler.participants or {}
  partyIndex = partyIndex or (st.player and st.player.partyIndex) or 1
  foeBattler.participants[partyIndex] = true
end

return State
