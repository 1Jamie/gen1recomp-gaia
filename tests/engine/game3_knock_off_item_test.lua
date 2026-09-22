-- KNOCK_OFF renders the held item unusable for the rest of the battle.
--
-- FRLG semantics (Bulbapedia: "prevent its use during the battle"; pret
-- pokefirered/src/battle_script_commands.c:2730-2752): the effect clears the
-- battler's item and sets the battle-scoped knockedOffMons bit.  The party mon
-- keeps the item -- "it still remains visible on the status screen" -- and the
-- bit masks the battler back to ITEM_NONE on every later send-out
-- (battle_script_commands.c:4489), so the item does not come back on
-- switch-out.  It is usable again after the battle.
--
-- History: an earlier workaround also wrote the removal through to the party
-- mon.  That is wrong for FRLG -- the party copy has to survive the battle --
-- and it is not what stops the item returning on switch-out; the send-out mask
-- below is.
--
-- persist_item resolves the party mon via State.partyMon(b) (= b._partyMon or
-- b.mon), so this drives the real effect with plain battler tables.
--   luajit tests/engine/game3_knock_off_item_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Secondary = require("src.core.game3.battle.effects.secondary")
local State = require("src.core.game3.battle.state")

local function adapter()
  return {
    abilityOf = function(_, b) return b.ability end,
    hp = function(_, b) return b.hp or 100 end,
    ownSide = function() return nil end,
    displayName = function(_, b) return b.name or "MON" end,
    playAnim = function() end,
    say = function() end,
    roll = function(_, lo) return lo end,
  }
end

-- A battler and its party mon carrying the same item, like State.makeBattler
-- builds from held_item(mon).
local function battler(side, item, ability)
  return {
    side = side,
    name = side == "player" and "CHARMANDER" or "RATTATA",
    hp = 100, item = item, ability = ability,
    mon = item and { item = item, heldItem = item } or {},
  }
end

local function knock_off(user, target)
  return Secondary.set({
    adapter = adapter(), user = user, target = target,
    move = { moveName = "KNOCK OFF" },
  }, "KNOCK_OFF", false, true, false)
end

-- 1. The battler loses the item, the party mon keeps it (usable again after
--    the battle); the send-out mask below is what hides it for the rest of
--    this battle.
local user, target = battler("enemy", 0), battler("player", 13)
check(knock_off(user, target), "KNOCK_OFF reports the item was removed")
eq(target.item, 0, "the battler's item is cleared")
eq(target.mon.item, 13, "the party mon keeps the item for after the battle")
eq(target.mon.heldItem, 13, "heldItem is kept as well")

-- 2. The enemy side behaves the same.
local user2, target2 = battler("player", 0), battler("enemy", 13)
knock_off(user2, target2)
eq(target2.item, 0, "the enemy battler's item is cleared")
eq(target2.mon.item, 13, "the enemy party mon keeps the item")

-- 3. STICKY_HOLD refuses and must leave the item intact everywhere.
local user3, target3 = battler("enemy", 0), battler("player", 13, "STICKY_HOLD")
check(not knock_off(user3, target3), "STICKY_HOLD refuses KNOCK_OFF")
eq(target3.item, 13, "STICKY_HOLD keeps the battler item")
eq(target3.mon.item, 13, "STICKY_HOLD keeps the party item")

-- 4. A target with no item is a no-op.
local user4, target4 = battler("enemy", 0), battler("player", 0)
check(not knock_off(user4, target4), "a target with no item is a no-op")

-- 5. Send-out mask: State.makeBattler re-reads the item from the party, so a
--    marked mon must come back in with ITEM_NONE while its party copy stays.
local st = {}
State.markKnockedOff(st, { side = "enemy", partyIndex = 1 })
local mon = { species = 1, level = 5, hp = 20, maxHp = 20, moves = {}, pp = {}, item = 13, heldItem = 13 }
local rebuilt = State.makeBattler(mon, "enemy", { partyIndex = 1, st = st })
eq(rebuilt.item, 0, "send-out masks the item while the knock-off mark is set")
eq(rebuilt.expKnockedOff, true, "the rebuilt battler keeps the volatile mark")
eq(mon.item, 13, "the party mon still holds the item after the send-out")
local control = State.makeBattler(mon, "enemy", { partyIndex = 1, st = {} })
eq(control.item, 13, "without the mark the send-out reads the item back")

T.finish("game3_knock_off_item_test")
