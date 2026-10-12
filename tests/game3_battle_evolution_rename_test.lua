#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then print("[skip] game3_battle_evolution_rename_test: " .. tostring(Cache.reason)) os.exit(0) end
local Space = require("src.core.game3.scripting.space")
local ExtractScripts = require("src.import.gba.extract_scripts")
Space.bundle = ExtractScripts.loadBundle(Cache.cache(), cacheRoot, { allowIncomplete = true })

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local BattleBridge = require("src.core.game3.battle_bridge")
local Battle = require("src.core.game3.battle")
local Dataset = require("src.core.game3.dataset")
local Runtime = require("src.core.game3.runtime")
local Party = require("src.core.game3.party")
local Pokemon = require("src.core.game3.pokemon")
local Experience = require("src.core.game3.battle.experience")

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = "FR_PALLET_TOWN", x = 12, y = 20, facing = "down", flags = {}, vars = {}, party = {}, name = "RED" }
game.session = session
Runtime.start(nil, game, session, { reason = "new_game" })

local function evolve_in_battle(species, level, nickname)
  for i = #session.party, 1, -1 do session.party[i] = nil end
  Party.giveMon(session, species, level, nickname)
  local mon = session.party[1]
  mon.exp = Experience.expForLevel(mon, level + 1) - 1
  local ok = BattleBridge.start(nil, game, { species = 129, level = 30, moves = { 150 }, pp = { 40 }, item = 0 },
    { wild = true, headless = true, fade = false })
  check(ok, "battle starts")
  Battle._auto = true
  Battle._headless = true
  Battle.runToEnd()
  if Battle.isActive() then BattleBridge.finishPending("win") end
  return mon
end

print("[test] 1. un-nicknamed mon takes the new species name")
do
  local mon = evolve_in_battle(1, 15, Pokemon.name(1))
  check(Pokemon.speciesOf(mon) == 2, "BULBASAUR evolved into IVYSAUR")
  check(mon.nickname == Pokemon.name(2), "session nickname is IVYSAUR, got " .. tostring(mon.nickname))
  check(Pokemon.displayMonName(mon) == Pokemon.name(2), "party shows IVYSAUR")
  mon = evolve_in_battle(1, 15)
  check(Pokemon.displayMonName(mon) == Pokemon.name(2), "empty nickname shows IVYSAUR")
end

print("[test] 2. nicknamed mon keeps its nickname")
do
  local mon = evolve_in_battle(1, 15, "BUDDY")
  check(Pokemon.speciesOf(mon) == 2, "BULBASAUR evolved into IVYSAUR")
  check(Pokemon.displayMonName(mon) == "BUDDY", "party shows BUDDY")
end

print("[test] 3. Nincada splits into a renamed Ninjask and a Shedinja")
do
  local nincada = Pokemon.speciesFromName("NINCADA")
  local ninjask = Pokemon.speciesFromName("NINJASK")
  local shedinja = Pokemon.speciesFromName("SHEDINJA")
  session.national_dex_unlocked = true
  local mon = evolve_in_battle(nincada, 19, Pokemon.name(nincada))
  check(Pokemon.speciesOf(mon) == ninjask, "NINCADA evolved into NINJASK")
  check(Pokemon.displayMonName(mon) == Pokemon.name(ninjask), "party shows NINJASK")
  local shed = session.party[2]
  check(shed and Pokemon.speciesOf(shed) == shedinja, "SHEDINJA joined the party")
  check(shed and Pokemon.displayMonName(shed) == Pokemon.name(shedinja), "party shows SHEDINJA")
end

if failed > 0 then
  print(string.format("[result] %d failure(s)", failed))
  os.exit(1)
end
print("[result] all passed")
