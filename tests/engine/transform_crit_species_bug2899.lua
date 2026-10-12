-- engine/battle/core.asm:4478
-- engine/battle/move_effects/transform.asm:57
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Damage = require("src.battle.Damage")
local MoveEffects = require("src.battle.MoveEffects")
local faithful = require("src.battle.rulesets.gen1_faithful")

local function battler(name, baseSpeed)
  return {
    name = name, isPlayer = name == "DITTO", stages = {},
    def = { name = name, baseStats = { speed = baseSpeed } },
    curStats = { hp = 100, attack = 50, defense = 50, speed = 50, special = 50 },
    curTypes = { "NORMAL" }, curMoves = { { id = "TACKLE", pp = 35 } },
    mon = { species = name, status = nil, hp = 100, stats = { hp = 100 } },
  }
end

local function threshold(attacker)
  local hits = 0
  for r = 0, 255 do
    if Damage.critRoll(faithful, attacker, "TACKLE", function() return r end, false) then
      hits = hits + 1
    end
  end
  return hits
end

local battle = { data = Data, ruleset = faithful,
                 speciesSprite = function() return nil end }

do
  local ditto, target = battler("DITTO", 48), battler("ELECTRODE", 140)
  T.eq(threshold(ditto), 24, "DITTO crits on base speed 48 (24/256)")
  MoveEffects.primary.TRANSFORM_EFFECT(battle, ditto, target)
  T.eq(threshold(ditto), 70, "transformed into ELECTRODE it crits on base speed 140")
end

do
  local a, b = battler("DITTO", 48), battler("DITTO2", 48)
  local c = battler("ELECTRODE", 140)
  MoveEffects.primary.TRANSFORM_EFFECT(battle, b, c)
  MoveEffects.primary.TRANSFORM_EFFECT(battle, a, b)
  T.eq(threshold(a), 70, "copying a transformed mon reads the species it became")
end

T.finish("a transformed mon crits on the copied species' base speed (#2899)")
