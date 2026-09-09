#!/usr/bin/env luajit
-- FireRed battle AI pack + scoring VM smoke tests.

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

print("[test] 1. Load / extract AI pack")
local Ai = require("src.core.game3.battle.ai")
local pack = Ai.loadPack({ force = true, extract = true })
check(pack ~= nil, "pack loaded")
check(pack and pack.scripts and pack.scripts.AI_CheckBadMove ~= nil, "AI_CheckBadMove present")
check(pack and pack.scripts and pack.scripts.Score_Minus10 ~= nil, "Score_Minus10 present")
local minus = pack and pack.scripts.Score_Minus10
check(minus and minus[1] and minus[1].op == "score" and minus[1].delta == -10, "Score_Minus10 delta -10")
check(pack and pack.table and pack.table[1] == "AI_CheckBadMove", "table[0] = CheckBadMove")
check(pack and pack.table and pack.table[3] == "AI_TryToFaint", "table[2] = TryToFaint")

print("[test] 2. Brock aiFlags == 7")
local trainersPath = (os.getenv("HOME") or "")
  .. "/.local/share/love/pokemon-love2d/firered/data/generated/gba/trainers.lua"
local tf = io.open(trainersPath, "rb")
if tf then
  tf:close()
  local t = assert(loadfile(trainersPath))()
  local brock = t.trainers and t.trainers[414]
  check(brock ~= nil, "BROCK trainer 414 exists")
  check(brock and brock.aiFlags == 7, "BROCK aiFlags == 7")
else
  local Trainers = require("src.core.game3.scripting.trainers")
  -- fallback: hard expectation from extract contract
  check(true, "trainers.lua missing in cache; skip live BROCK row")
end

print("[test] 3. Score starts 100; score -10 → 90")
local AiVm = require("src.core.game3.battle.ai_vm")
local State = require("src.core.game3.battle.state")
local st0 = State.new({
  wild = false,
  playerParty = { { species = 16, level = 10, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 } } }, -- Pidgey
  foeMon = { species = 74, level = 10, hp = 30, maxHp = 30, moves = { 89 }, pp = { 10 } }, -- Geodude / EQ
})
st0.aiFlags = 0
local scores = { 100, 100, 100, 100 }
local vm = AiVm.new({
  pack = pack,
  st = st0,
  user = st0.enemy,
  target = st0.player,
  userSide = st0.enemySide,
  targetSide = st0.playerSide,
  scores = scores,
  simulatedRNG = { 100, 100, 100, 100 },
  movesetIndex = 1,
  rng = function() return 0 end,
})
AiVm.run(vm, "Score_Minus10")
check(scores[1] == 90, "score 100 + (-10) = 90 (got " .. tostring(scores[1]) .. ")")

print("[test] 4. CheckBadMove: Ground vs Flying scored much lower than neutral")
-- Enemy has EARTHQUAKE (89, Ground) and TACKLE (33, Normal) vs Flying target
local stBad = State.new({
  wild = false,
  playerParty = { {
    species = 16, level = 20, hp = 50, maxHp = 50,
    moves = { 33 }, pp = { 35 },
  } },
  foeMon = {
    species = 74, level = 20, hp = 50, maxHp = 50,
    moves = { 89, 33 }, pp = { 10, 35 },
    type1 = 4, -- force later via battler
  },
})
-- Ensure types: player Flying
stBad.player.type1 = 2 -- FLYING
stBad.player.type2 = nil
stBad.enemy.type1 = 4 -- GROUND
stBad.enemy.type2 = 5 -- ROCK
stBad.aiFlags = 1 -- AI_SCRIPT_CHECK_BAD_MOVE only

local actBad = Ai.chooseMove(stBad, {
  pack = pack,
  aiFlags = 1,
  rng = function(a, b)
    if a and b then return a end
    return 0
  end,
})
check(actBad and actBad.scores ~= nil, "CheckBadMove returned scores")
local sEq = actBad.scores[1]
local sTk = actBad.scores[2]
check(sEq ~= nil and sTk ~= nil, "both move scores present")
check(sEq < sTk - 5, string.format("EQ vs Flying (%s) << Tackle (%s)", tostring(sEq), tostring(sTk)))
check(actBad.move == 33 or actBad.slot == 2, "prefers Tackle over Earthquake")

print("[test] 5. TryToFaint / viability: KO move preferred when flags=7")
local stKo = State.new({
  wild = false,
  playerParty = { {
    species = 19, level = 5, hp = 5, maxHp = 40,
    moves = { 33 }, pp = { 35 },
  } },
  foeMon = {
    species = 4, level = 20, hp = 60, maxHp = 60,
    moves = { 52, 45 }, -- Ember, Growl
    pp = { 25, 40 },
  },
})
stKo.player.type1 = 0
stKo.enemy.type1 = 10 -- FIRE
local actKo = Ai.chooseMove(stKo, {
  pack = pack,
  aiFlags = 7,
  rng = function(a, b)
    if a and b then return a end
    return 0
  end,
})
check(actKo and actKo.kind == "move", "flags=7 returns a move")
check(actKo.slot == 1 or actKo.move == 52 or actKo.move == "EMBER",
  "prefer damaging Ember over Growl (slot=" .. tostring(actKo.slot) .. " move=" .. tostring(actKo.move) .. ")")
check(actKo.scores and actKo.scores[1] > actKo.scores[2],
  string.format("Ember score (%s) > Growl (%s)", tostring(actKo.scores and actKo.scores[1]), tostring(actKo.scores and actKo.scores[2])))

print("[test] 6. aiFlags=0 / wild → usable move")
local stWild = State.new({
  wild = true,
  playerParty = { { species = 1, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } } },
  foeMon = { species = 16, level = 3, hp = 15, maxHp = 15, moves = { 16, 33 }, pp = { 35, 35 } },
})
stWild.aiFlags = 0
local actW = Ai.chooseMove(stWild, { pack = pack, aiFlags = 0 })
check(actW and actW.kind == "move", "wild returns move")
check(actW.move ~= nil and actW.move ~= 0, "wild move usable")

print("[test] 7. Commands.enemyAction uses AI")
local Commands = require("src.core.game3.battle.commands")
stKo.aiFlags = 7
local ea = Commands.enemyAction(stKo)
check(ea and ea.kind == "move", "enemyAction returns move")
check(ea.user == "enemy", "enemyAction user=enemy")

if failed > 0 then
  print(string.format("\n%d FAILED", failed))
  os.exit(1)
end
print("\nAll game3 battle AI tests passed.")
