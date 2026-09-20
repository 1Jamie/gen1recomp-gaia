#!/usr/bin/env luajit

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

local Disasm = require("src.core.game3.scripting.disasm")
local Ops = require("src.core.game3.scripting.ops_a")
local Oak = require("src.core.game3.battle.oak_advice")
local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")

print("[test] 1. trainerbattle_earlyrival operand decode")
do
  local function bytes(s)
    local t = {}
    for i = 1, #s do t[i] = s:byte(i) end
    return t
  end

  local oaksLab = bytes("\x5c\x09\x46\x01\x03\x00\x00\x00\x00\x08\x00\x00\x00\x08")
  local row = Disasm.decodeOne(oaksLab, 1)
  check(row.op == "trainerbattle", "opcode 0x5c decodes as trainerbattle")
  check(row.type == 9, "Oak's Lab type == TRAINER_BATTLE_EARLY_RIVAL (9)")
  check(row.trainer == 326, "Oak's Lab trainer == 326")
  check(row.flags == 3, "Oak's Lab flags == RIVAL_BATTLE_TUTORIAL (3)")

  local route22 = bytes("\x5c\x09\x49\x01\x00\x00\x00\x00\x00\x08\x00\x00\x00\x08")
  local row22 = Disasm.decodeOne(route22, 1)
  check(row22.type == 9, "Route 22 type == TRAINER_BATTLE_EARLY_RIVAL (9)")
  check(row22.trainer == 329, "Route 22 trainer == 329")
  check(row22.flags == 0, "Route 22 flags == 0 (not a tutorial)")
end

print("[test] 2. ops_a forwards firstBattle only for flags & RIVAL_BATTLE_TUTORIAL")
do
  local function dispatch(flags)
    local seen = nil
    local vm = {
      ctx = { pc = { listKey = "oak_test", index = 1 }, mode = "bytecode", status = "running" },
      store = { flags = {}, vars = {} },
      adapters = {
        openMessageAsync = function(_t, done) done() end,
        startTrainerBattle = function(_foe, done, opts)
          seen = opts
          done("win")
        end,
      },
      getText = function() return nil end,
      setPc = function() end,
    }
    Ops.dispatch(vm, {
      op = "trainerbattle",
      type = 9,
      trainer = 326,
      flags = flags,
      victoryText = nil,
    })
    return seen
  end

  local tut = dispatch(3)
  check(tut ~= nil, "flags=3 started a battle")
  check(tut and tut.earlyRival == true, "flags=3 earlyRival true")
  check(tut and tut.firstBattle == true, "flags=3 firstBattle true")
  check(tut and tut.rivalFlags == 3, "flags=3 rivalFlags forwarded")

  local heal = dispatch(1)
  check(heal and heal.firstBattle == true, "flags=1 firstBattle true (flags & 3 is two bits)")

  local r22 = dispatch(0)
  check(r22 ~= nil, "flags=0 started a battle")
  check(not (r22 and r22.firstBattle), "flags=0 (Route 22) firstBattle falsy")
end

print("[test] 3. Oak advice flag word + player-name expansion")
do
  local st = { firstBattle = true, playerName = "BLUE" }
  local out = {}
  local function sink(t) out[#out + 1] = t end

  check(Oak.active(st) == true, "Oak.active true on a first battle")
  check(Oak.active({ firstBattle = false }) == false, "Oak.active false otherwise")

  check(Oak.sayOnce(st, Oak.FLAG_INFLICT_DMG, "inflictingDamage", sink) == true, "first inflictingDamage says")
  check(#out == 1, "one page pushed")
  check(out[1]:find("Inflicting damage on the foe", 1, true) ~= nil, "pret gText_InflictingDamageIsKey text")
  check(Oak.sayOnce(st, Oak.FLAG_INFLICT_DMG, "inflictingDamage", sink) == false, "second inflictingDamage is a no-op")
  check(#out == 1, "still one page")

  check(Oak.sayOnce(st, Oak.FLAG_STAT_CHG, "loweringStats", sink) == true, "stat-chg mask is independent")
  check(Oak.sayOnce(st, Oak.FLAG_HP_RESTORE, "keepAnEyeOnHp", sink) == true, "hp-restore mask is independent")
  check(st.oakMsgFlags == 7, "all three once-only flags set (0x7)")

  local off = { firstBattle = false, playerName = "BLUE" }
  local none = {}
  check(Oak.say(off, "noRunning", function(t) none[#none + 1] = t end) == false, "inactive state says nothing")
  check(#none == 0, "no pages pushed when inactive")

  local pages = Oak.pages(st, "howDisappointing")
  check(pages and pages[1]:find("How disappointing", 1, true) ~= nil, "howDisappointing text present")
  check(pages and pages[1]:find("{B_PLAYER_NAME}", 1, true) == nil, "B_PLAYER_NAME placeholder expanded")
  check(pages and pages[1]:find("but if you lose, BLUE", 1, true) ~= nil
    or (pages and pages[1]:find("lose, BLUE,", 1, true) ~= nil), "player name substituted")

  local intro = Oak.pages(st, "forPetesSake")
  check(intro and #intro == 3, "opening Oak speech is three prints")
  check(intro and intro[2]:find("The TRAINER that makes the other", 1, true) ~= nil, "gText_TheTrainerThat present")
  check(intro and intro[3]:find("Try battling and see for yourself", 1, true) ~= nil, "gText_TryBattling present")
end

local function party(level, hp)
  return { { species = 1, level = level, hp = hp, maxHp = hp, moves = { 33 }, pp = { 35 }, maxPp = { 35 } } }
end

local function run(opts)
  if Battle.isActive() then Battle.abort("win") end
  local ok = Battle.start(opts)
  local res = Battle.runToEnd()
  local log = {}
  for i, t in ipairs(Ui.log() or {}) do log[i] = t end
  return ok, res, log, Battle._st
end

local function find(log, needle)
  for i, t in ipairs(log) do
    if t:find(needle, 1, true) then return i end
  end
  return nil
end

local function count(log, needle)
  local n = 0
  for _, t in ipairs(log) do
    if t:find(needle, 1, true) then n = n + 1 end
  end
  return n
end

print("[test] 4. firstBattle no longer hijacks the trainer's aiFlags")
do
  local ok, _res, _log, st = run({
    wild = false, headless = true, trainerId = 326,
    firstBattle = true, earlyRival = true, rivalFlags = 3,
    playerParty = party(60, 200),
    foe = { species = 7, level = 5, trainerId = 326, aiFlags = 7 },
  })
  check(ok, "tutorial battle started")
  check(st and st.aiFlags == 7, "st.aiFlags == 7 (CHECK_BAD_MOVE|TRY_TO_FAINT|CHECK_VIABILITY), not 0x80000000")
  check(st and st.firstBattle == true, "st.firstBattle set from opts")
end

print("[test] 5. Oak's advice fires in a tutorial win")
do
  local _ok, res, log = run({
    wild = false, headless = true, trainerId = 326,
    firstBattle = true, earlyRival = true, rivalFlags = 3,
    playerName = "RED",
    playerParty = party(60, 200),
    foe = { species = 7, level = 5, trainerId = 326 },
  })
  check(res == "win", "tutorial battle won")
  check(find(log, "Oh, for Pete's sake") ~= nil, "opening Oak speech logged")
  check(find(log, "The TRAINER that makes the other") ~= nil, "second opening page logged")
  check(find(log, "Try battling and see for yourself") ~= nil, "third opening page logged")
  check(count(log, "Inflicting damage on the foe") == 1, "first-damage advice fires exactly once")
  local iGo = find(log, "Go! ")
  local iOak = find(log, "Oh, for Pete's sake")
  check(iGo and iOak and iGo < iOak, "Oak speaks after the player sends out")
end

print("[test] 6. non-tutorial trainer battle stays silent")
do
  local _ok, res, log = run({
    wild = false, headless = true, trainerId = 326,
    playerParty = party(60, 200),
    foe = { species = 7, level = 5, trainerId = 326 },
  })
  check(res == "win", "plain trainer battle won")
  check(find(log, "Oh, for Pete's sake") == nil, "no Oak opening speech")
  check(find(log, "Inflicting damage on the foe") == nil, "no first-damage advice")
end

print("[test] 7. tutorial loss: rival victory speech + Oak, no white-out pair")
do
  local _ok, res, log = run({
    wild = false, headless = true, trainerId = 326,
    firstBattle = true, earlyRival = true, rivalFlags = 3,
    playerName = "RED",
    victoryText = "RIVAL: Yeah!\nAm I great or what?",
    playerParty = party(2, 1),
    foe = { species = 6, level = 80, trainerId = 326 },
  })
  check(res == "lose", "tutorial battle lost")
  local iWin = find(log, "Am I great or what?")
  local iOak = find(log, "How disappointing")
  check(iWin ~= nil, "rival victory speech displayed")
  check(iOak ~= nil, "Oak's 'How disappointing' displayed")
  check(iWin and iOak and iWin < iOak, "victory speech precedes Oak")
  check(find(log, "blacked out") == nil, "no 'blacked out!' on the tutorial loss")
  check(find(log, "You have no more") == nil, "no 'no more POKéMON left!' on the tutorial loss")
end

print("[test] 8. ordinary trainer loss still whites out")
do
  local _ok, res, log = run({
    wild = false, headless = true, trainerId = 326,
    playerName = "RED",
    victoryText = "RIVAL: Yeah!\nAm I great or what?",
    playerParty = party(2, 1),
    foe = { species = 6, level = 80, trainerId = 326 },
  })
  check(res == "lose", "plain trainer battle lost")
  check(find(log, "You have no more") ~= nil, "'no more POKéMON left!' still printed")
  check(find(log, "blacked out") ~= nil, "'blacked out!' still printed")
  check(find(log, "Am I great or what?") == nil, "no victory speech outside the early-rival path")
  check(find(log, "How disappointing") == nil, "no Oak text outside the tutorial")
end

print("[test] 9. Oak's prize-money advice after the money line")
do
  local Runtime = package.loaded["src.core.game3.runtime"]
  package.loaded["src.core.game3.runtime"] = {
    getSession = function()
      return { name = "RED", money = 0, party = {} }
    end,
  }
  local _ok, res, log = run({
    wild = false, headless = true, trainerId = 326,
    firstBattle = true, earlyRival = true, rivalFlags = 3,
    playerName = "RED",
    playerParty = party(60, 200),
    foe = { species = 7, level = 5, trainerId = 326 },
  })
  package.loaded["src.core.game3.runtime"] = Runtime
  check(res == "win", "tutorial battle won with a session")
  local iMoney = find(log, "for winning!")
  local iOak = find(log, "Hm! Excellent!")
  check(iMoney ~= nil, "prize money line printed")
  check(iOak ~= nil, "Oak's prize-money advice printed")
  check(iMoney and iOak and iMoney < iOak, "Oak speaks after the prize money line")
end

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[PASS] game3 oak first battle")
