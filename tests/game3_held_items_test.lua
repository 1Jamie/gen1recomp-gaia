#!/usr/bin/env luajit
-- ROM-free comprehensive unit tests for Game 3 (FireRed / LeafGreen) held item behaviors:
-- HP restore berries, pinch stat berries, status berries, herbs, leftovers, focus band, etc.

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed, passed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Pokemon = require("src.core.game3.pokemon")
Pokemon._names = { [1] = "BULBASAUR", [4] = "CHARMANDER", [7] = "SQUIRTLE", [25] = "PIKACHU" }
Pokemon._types = { [1] = { 12, 3 }, [4] = { 10, 10 }, [7] = { 11, 11 }, [25] = { 13, 13 } }
Pokemon._stats = {
  [1] = { hp = 45, atk = 49, def = 49, spe = 45, spa = 65, spd = 65 },
  [4] = { hp = 39, atk = 52, def = 43, spe = 65, spa = 60, spd = 50 },
  [7] = { hp = 44, atk = 48, def = 65, spe = 43, spa = 50, spd = 64 },
  [25] = { hp = 35, atk = 55, def = 40, spe = 90, spa = 50, spd = 50 },
}
Pokemon._abilities = { [1] = { 65, 65 }, [4] = { 66, 66 }, [7] = { 67, 67 }, [25] = { 9, 9 } }

local RomText = require("src.core.game3.rom_text")
RomText.plain = function(key) return tostring(key) end
RomText.box = function(key) return tostring(key) end
RomText.ascii = function(key) return tostring(key) end
RomText.ir = function(key) return {} end

local BattleText = require("src.core.game3.battle.battle_text")
BattleText.get = function(id, fill)
  fill = fill or {}
  return string.format("[%s: item=%s buff1=%s]", id, tostring(fill.lastItem or ""), tostring(fill.buff1 or ""))
end

local Moves = require("src.core.game3.battle.moves")
local ROM_MOVES = {
  [1] = { name = "POUND", effect = 0, power = 40, type = 0, accuracy = 100, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [33] = { name = "TACKLE", effect = 0, power = 35, type = 0, accuracy = 95, pp = 35, secondaryChance = 0, target = 0, priority = 0, flags = 51 },
  [45] = { name = "GROWL", effect = 18, power = 0, type = 0, accuracy = 100, pp = 40, secondaryChance = 0, target = 8, priority = 0, flags = 22 },
  [86] = { name = "THUNDER WAVE", effect = 67, power = 0, type = 13, accuracy = 100, pp = 20, secondaryChance = 0, target = 0, priority = 0, flags = 22 },
}
for id, row in pairs(ROM_MOVES) do row.numId = id end
Moves._romLoaded = true
Moves._rom = ROM_MOVES
Moves._names = { [1] = "POUND", [33] = "TACKLE", [45] = "GROWL", [86] = "THUNDER WAVE" }
Pokemon._moveNames = Moves._names
Pokemon._romMoveNames = Moves._names

local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Adapter = require("src.core.game3.battle.adapter")
local HeldItems = require("src.core.game3.battle.held_items")
local Damage = require("src.core.game3.battle.damage")

local function mon(o)
  return {
    species = o.species or 1, level = o.level or 50,
    hp = o.hp or 100, maxHp = o.maxHp or 100,
    attack = o.attack or 50, defense = o.defense or 50,
    spAtk = o.spAtk or 50, spDef = o.spDef or 50,
    speed = o.speed or 50, ability = o.ability or 0,
    nickname = o.nickname, moves = o.moves or { 33 },
    pp = o.pp or { 20, 20, 20, 20 }, maxPp = o.maxPp,
    status = o.status, item = o.item, heldItem = o.item,
    gender = o.gender, personality = o.personality or 0,
  }
end

local function battle(p, e)
  local party = { mon(p) }
  local foeParty = { mon(e) }
  local st = State.new({ wild = true, playerParty = party, foeParty = foeParty })
  st.rng = function(lo, hi) return lo end
  local ad = Adapter.new(st)
  return st, ad
end

local function useMove(st, ad, user, move, slot)
  local target = (user == st.player) and st.enemy or st.player
  local out = {}
  Engine.resolveMove(user, target, move, slot or 1, ad, st, out)
  return out
end

local function eot(st, ad)
  return Engine.collectResidualEvents(st, ad)
end

print("=== 1. Oran Berry mid-turn damage consumption ===")
do
  -- Player starts with Oran Berry (139) at 60/100 HP.
  -- Enemy attacks with Tackle (power 35).
  local st, ad = battle({ item = 139, hp = 60, maxHp = 100 }, { moves = { 33 } })
  check(st.player.item == 139, "player battler holds Oran Berry before attack")
  check(st.playerParty[1].item == 139, "player party mon holds Oran Berry before attack")

  useMove(st, ad, st.enemy, 33)

  -- After taking damage, HP dropped below 50, berry activated, healed 10 HP, and was consumed.
  check(st.player.item == 0, "player battler item is cleared (0)")
  check(st.playerParty[1].item == nil, "player party mon item is nil")
  check(st.playerParty[1].heldItem == nil, "player party mon heldItem is nil")
  check(st.playerSide.expUsedHeldItem == 139, "expUsedHeldItem recorded for Recycle")
end

print("=== 2. Sitrus Berry mid-turn damage consumption ===")
do
  -- Sitrus Berry (142) heals 30 HP when HP <= 50%
  local st, ad = battle({ item = 142, hp = 60, maxHp = 100 }, { moves = { 33 } })
  useMove(st, ad, st.enemy, 33)
  check(st.player.item == 0, "Sitrus Berry consumed on battler")
  check(st.playerParty[1].item == nil, "Sitrus Berry consumed on party mon")
  check(st.playerSide.expUsedHeldItem == 142, "Sitrus Berry recorded for Recycle")
end

print("=== 3. Enemy mon consuming held berry mid-turn ===")
do
  -- Foe holds Oran Berry, player attacks foe
  local st, ad = battle({ moves = { 33 } }, { item = 139, hp = 60, maxHp = 100 })
  check(st.enemy.item == 139, "enemy battler holds Oran Berry")
  check(st.foeParty[1].item == 139, "enemy party mon holds Oran Berry")

  useMove(st, ad, st.player, 33)

  check(st.enemy.item == 0, "enemy battler item cleared after consumption")
  check(st.foeParty[1].item == nil, "enemy party mon item cleared after consumption")
  check(st.enemySide.expUsedHeldItem == 139, "enemy side recorded used held item")
end

print("=== 4. Status curing berries (Cheri / Pecha / Lum) at move end ===")
do
  -- Cheri Berry (133) cures paralysis immediately when Thunder Wave is used
  local st, ad = battle({ item = 133 }, { moves = { 86 } })
  useMove(st, ad, st.enemy, 86)
  check(ad:status(st.player) == nil, "paralysis was cured immediately")
  check(st.player.item == 0, "Cheri Berry was consumed")
  check(st.playerParty[1].item == nil, "party mon Cheri Berry consumed")
end

print("=== 5. Stat boosting pinch berries (Liechi Berry) mid-turn ===")
do
  -- Liechi Berry (168) boosts Attack when HP <= 25% (1/4 maxHp)
  local st, ad = battle({ item = 168, hp = 30, maxHp = 100 }, { moves = { 33 } })
  useMove(st, ad, st.enemy, 33)
  check(st.player.stages.attack == 1, "Attack rose by 1 stage from Liechi Berry")
  check(st.player.item == 0, "Liechi Berry consumed on battler")
  check(st.playerParty[1].item == nil, "Liechi Berry consumed on party mon")
end

print("=== 6. White Herb restores stat drop mid-turn ===")
do
  -- White Herb (180) restores lowered stats when Growl is used
  local st, ad = battle({ item = 180 }, { moves = { 45 } })
  useMove(st, ad, st.enemy, 45)
  check(st.player.stages.attack == 0, "Attack stat stage restored to 0 by White Herb")
  check(st.player.item == 0, "White Herb consumed on battler")
  check(st.playerParty[1].item == nil, "White Herb consumed on party mon")
end

print("=== 7. Leftovers activates only at end of turn (not mid-turn) ===")
do
  -- Leftovers (200) heals at end of turn, not during move resolution
  local st, ad = battle({ item = 200, hp = 80, maxHp = 100 }, { moves = { 45 } })
  -- Growl does no damage
  useMove(st, ad, st.enemy, 45)
  check(st.player.mon.hp == 80, "Leftovers did not trigger mid-turn")
  check(st.player.item == 200, "Leftovers is not consumed")

  eot(st, ad)
  check(st.player.mon.hp == 86, "Leftovers healed maxHp/16 (6 HP) at end of turn")
  check(st.player.item == 200, "Leftovers remains held after end of turn")
end

print("=== 8. Leppa Berry restores PP ===")
do
  -- Leppa Berry (138) restores 10 PP when a move is at 0 PP
  local st, ad = battle({ item = 138, moves = { 33 }, pp = { 0 }, maxPp = { 35 } }, {})
  Engine.afterAction(st, ad)
  check(st.player.mon.pp[1] == 10, "Leppa Berry restored 10 PP")
  check(st.player.item == 0, "Leppa Berry consumed")
  check(st.playerParty[1].item == nil, "party mon Leppa Berry consumed")
end

print("-----------------------------------------")
if failed > 0 then
  print(string.format("[result] %d test(s) FAILED, %d passed", failed, passed))
  os.exit(1)
else
  print(string.format("[result] ALL %d tests PASSED", passed))
  os.exit(0)
end
