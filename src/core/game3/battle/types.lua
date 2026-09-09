-- FRLG type ids + Gen3 singles type chart (owned game3 battle).

local Types = {}

-- pret pokemon.h TYPE_*
Types.ID = {
  NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4,
  ROCK = 5, BUG = 6, GHOST = 7, STEEL = 8, MYSTERY = 9,
  FIRE = 10, WATER = 11, GRASS = 12, ELECTRIC = 13, PSYCHIC = 14,
  ICE = 15, DRAGON = 16, DARK = 17,
}

Types.NAME = {}
for name, id in pairs(Types.ID) do
  Types.NAME[id] = name
end

-- Gen3 physical/special split by type (before move category override).
Types.PHYSICAL = {
  [0] = true, [1] = true, [2] = true, [3] = true, [4] = true,
  [5] = true, [6] = true, [7] = true, [8] = true,
}

function Types.name(id)
  return Types.NAME[tonumber(id) or -1] or "NORMAL"
end

-- Alias used by battle menus / effects.
function Types.get(id)
  return Types.name(id)
end

function Types.isPhysical(typeId)
  return Types.PHYSICAL[tonumber(typeId) or 0] == true
end

-- Multipliers in tenths. Chart[atk][def]; missing = 10.
local C = {}

local function set(atk, def, mult)
  C[atk] = C[atk] or {}
  C[atk][def] = mult
end

local N, FI, FL, PO, GR, RO, BU, GH, ST =
  0, 1, 2, 3, 4, 5, 6, 7, 8
local FIR, WA, GS, EL, PSY, IC, DR, DA =
  10, 11, 12, 13, 14, 15, 16, 17

-- NORMAL
set(N, RO, 5); set(N, GH, 0); set(N, ST, 5)
-- FIGHTING
set(FI, N, 20); set(FI, FL, 5); set(FI, PO, 5); set(FI, RO, 20)
set(FI, BU, 5); set(FI, GH, 0); set(FI, ST, 20); set(FI, PSY, 5)
set(FI, IC, 20); set(FI, DA, 20)
-- FLYING
set(FL, FI, 20); set(FL, RO, 5); set(FL, BU, 20); set(FL, ST, 5)
set(FL, GS, 20); set(FL, EL, 5)
-- POISON
set(PO, PO, 5); set(PO, GR, 5); set(PO, RO, 5); set(PO, GH, 5)
set(PO, ST, 0); set(PO, GS, 20)
-- GROUND
set(GR, PO, 20); set(GR, RO, 20); set(GR, BU, 5); set(GR, ST, 20)
set(GR, FIR, 20); set(GR, GS, 5); set(GR, EL, 20); set(GR, FL, 0)
-- ROCK
set(RO, FI, 5); set(RO, FL, 20); set(RO, GR, 5); set(RO, BU, 20)
set(RO, ST, 5); set(RO, FIR, 20); set(RO, IC, 20)
-- BUG
set(BU, FI, 5); set(BU, FL, 5); set(BU, PO, 5); set(BU, GH, 5)
set(BU, ST, 5); set(BU, FIR, 5); set(BU, GS, 20); set(BU, PSY, 20)
set(BU, DA, 20)
-- GHOST
set(GH, N, 0); set(GH, PSY, 20); set(GH, DA, 5); set(GH, ST, 5); set(GH, GH, 20)
-- STEEL
set(ST, RO, 20); set(ST, ST, 5); set(ST, FIR, 5); set(ST, WA, 5)
set(ST, EL, 5); set(ST, IC, 20)
-- FIRE
set(FIR, RO, 5); set(FIR, BU, 20); set(FIR, ST, 20); set(FIR, FIR, 5)
set(FIR, WA, 5); set(FIR, GS, 20); set(FIR, IC, 20); set(FIR, DR, 5)
-- WATER
set(WA, GR, 20); set(WA, RO, 20); set(WA, FIR, 20); set(WA, WA, 5)
set(WA, GS, 5); set(WA, DR, 5)
-- GRASS
set(GS, FL, 5); set(GS, PO, 5); set(GS, GR, 20); set(GS, BU, 5)
set(GS, ST, 5); set(GS, FIR, 5); set(GS, WA, 20); set(GS, GS, 5); set(GS, DR, 5)
-- ELECTRIC
set(EL, FL, 20); set(EL, GR, 0); set(EL, WA, 20); set(EL, GS, 5)
set(EL, EL, 5); set(EL, DR, 5); set(EL, ST, 5)
-- PSYCHIC
set(PSY, FI, 20); set(PSY, PO, 20); set(PSY, ST, 5); set(PSY, PSY, 5); set(PSY, DA, 0)
-- ICE
set(IC, FL, 20); set(IC, GR, 20); set(IC, ST, 5); set(IC, FIR, 5)
set(IC, WA, 5); set(IC, GS, 20); set(IC, IC, 5); set(IC, DR, 20)
-- DRAGON
set(DR, ST, 5); set(DR, DR, 20)
-- DARK
set(DA, FI, 5); set(DA, GH, 20); set(DA, PSY, 20); set(DA, DA, 5); set(DA, ST, 5)

function Types.effectiveness(atkType, defType1, defType2)
  atkType = tonumber(atkType) or 0
  defType1 = tonumber(defType1) or 0
  defType2 = tonumber(defType2)
  local function one(def)
    if not def or def == 9 then return 10 end
    local row = C[atkType]
    return (row and row[def]) or 10
  end
  local m1 = one(defType1)
  local m2 = 10
  if defType2 and defType2 ~= defType1 then
    m2 = one(defType2)
  end
  return (m1 * m2) / 100
end

-- pret AI_EFFECTIVENESS_* (battle_ai.h) — units used by if_type_effectiveness.
-- TypeCalc starts at 40 (x1), multiplies by matchups (+ optional STAB 1.5),
-- then remaps STAB-distorted values back to the enum (Cmd_if_type_effectiveness).
Types.AI_EFFECTIVENESS = {
  x0 = 0,
  x0_25 = 10,
  x0_5 = 20,
  x1 = 40,
  x2 = 80,
  x4 = 160,
}

function Types.aiTypeCalcUnits(atkType, defType1, defType2, hasStab)
  local m = Types.effectiveness(atkType, defType1, defType2)
  if m <= 0 then return Types.AI_EFFECTIVENESS.x0 end
  local dmg = Types.AI_EFFECTIVENESS.x1 * m
  if hasStab then dmg = dmg * 1.5 end
  dmg = math.floor(dmg + 1e-9)
  if dmg == 120 then dmg = Types.AI_EFFECTIVENESS.x2 end
  if dmg == 240 then dmg = Types.AI_EFFECTIVENESS.x4 end
  if dmg == 30 then dmg = Types.AI_EFFECTIVENESS.x0_5 end
  if dmg == 15 then dmg = Types.AI_EFFECTIVENESS.x0_25 end
  return dmg
end

-- Back-compat alias (prefer aiTypeCalcUnits for script comparisons).
function Types.aiEffectiveness(atkType, defType1, defType2)
  return Types.aiTypeCalcUnits(atkType, defType1, defType2, false)
end

return Types
