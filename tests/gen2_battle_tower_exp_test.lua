-- engine/battle/core.asm:6990-6992, :2371-2373
--
--   luajit tests/gen2_battle_tower_exp_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle tower exp")
local check, eq = S.check, S.eq

local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" },
}

local POKEMON = {
  growthRates = {
    GROWTH_SLOW = { numerator = 5, denominator = 4, squared = 0, linear = 0,
      constant = 0 },
  },
  MACHOP = {
    id = "MACHOP", index = 66, name = "MACHOP",
    baseStats = { hp = 70, attack = 80, defense = 50, speed = 35,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 180, baseExp = 75,
    growthRate = "GROWTH_SLOW", genderRatio = 63,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  PIDGEY = {
    id = "PIDGEY", index = 16, name = "PIDGEY",
    baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_SLOW", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  type_chart = { types = TYPES, matchups = {} },
  items = {
    EXP_SHARE = { id = "EXP_SHARE", name = "EXP.SHARE",
      heldEffect = "HELD_NONE", heldParameter = 0 },
  },
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local PLAYER_ID = 31337

local function setup(tower)
  local party = {
    Mon.new(DATA, "MACHOP", 20, { dvs = perfect }),
    Mon.new(DATA, "MACHOP", 20, { dvs = perfect }),
  }
  for _, mon in ipairs(party) do mon.otId = PLAYER_ID end
  party[2].item = "EXP_SHARE"
  local foe = Mon.new(DATA, "PIDGEY", 14, { dvs = perfect })
  local save = { player = { id = PLAYER_ID, badges = {}, money = 1000 } }
  local battle = Battle.new({ data = DATA, party = party, wild = foe,
    save = save, battleTower = tower,
    random = function(n) return (n or 1) > 1 and 1 or 0 end })
  battle.trainer = { name = "FISHER", baseMoney = 40 }
  battle.participants = { [1] = true }
  return battle, party, foe, save
end

local function kinds(events)
  local out = {}
  for _, event in ipairs(events) do out[event.kind] = true end
  return out
end

do
  local battle, party, foe = setup(false)
  local before = party[1].experience
  battle:awardExperience(foe)
  check(party[1].experience > before, "outside the Tower a KO pays exp")
  check((party[1].statExp.attack or 0) > 0, "and stat exp")
end

do
  local battle, party, foe = setup(true)
  eq(battle.inBattleTowerBattle, true, "battleTower opt sets the flag")
  local exp = { party[1].experience, party[2].experience }
  local level = { party[1].level, party[2].level }
  battle:awardExperience(foe)
  eq(party[1].experience, exp[1], "a Tower KO pays the participant no exp")
  eq(party[2].experience, exp[2], "nor the EXP.SHARE holder")
  eq(party[1].level, level[1], "so no level is gained")
  eq(party[1].statExp.attack or 0, 0, "and no stat exp")
  eq(party[2].statExp.attack or 0, 0, "for the holder either")
  check(not kinds(battle:takeEvents()).experience,
    "and no GainedText is printed")
  eq(battle.participants[1], true, "participants still reset to the active mon")
end

do
  local battle, _, _, save = setup(false)
  check(battle:awardPrizeMoney() ~= nil, "outside the Tower a win pays money")
  check(save.player.money > 1000, "into the wallet")
end

do
  local battle, _, _, save = setup(true)
  eq(battle:awardPrizeMoney(), nil, "a Tower win skips .give_money")
  eq(save.player.money, 1000, "the wallet is untouched")
  check(not kinds(battle:takeEvents()).money, "and no money line is printed")
end

S.finish()
