-- KNOCK_OFF must persist the removed item to the party mon.
--
-- Regression: the KNOCK_OFF branch of Secondary.set cleared effBattler.item and
-- set effBattler.expKnockedOff, but never wrote through to the party mon.  The
-- battler is a battle-local view: State.makeBattler rebuilds `item` from
-- held_item(mon) on the next send-out, so the knocked-off item came back on
-- switch-out (and could then be stolen or knocked off again).
--
-- persist_item resolves the party mon via State.partyMon(b) (= b._partyMon or
-- b.mon), so this drives the real effect with plain battler tables.
--   luajit tests/engine/game3_knock_off_item_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Secondary = require("src.core.game3.battle.effects.secondary")

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

-- 1. A knocked-off item must not survive on the party mon, or it returns on
--    switch-out (State.makeBattler reads held_item(mon)).
local user, target = battler("enemy", 0), battler("player", 13)
check(knock_off(user, target), "KNOCK_OFF reports the item was removed")
eq(target.item, 0, "the battler's item is cleared")
eq(target.mon.item, nil, "the party mon no longer holds the item (does not return on switch-out)")
eq(target.mon.heldItem, nil, "heldItem is cleared too")

-- 2. The enemy side persists as well.
local user2, target2 = battler("player", 0), battler("enemy", 13)
knock_off(user2, target2)
eq(target2.item, 0, "the enemy battler's item is cleared")
eq(target2.mon.item, nil, "the enemy party mon no longer holds the item")

-- 3. STICKY_HOLD refuses and must leave the item intact everywhere.
local user3, target3 = battler("enemy", 0), battler("player", 13, "STICKY_HOLD")
check(not knock_off(user3, target3), "STICKY_HOLD refuses KNOCK_OFF")
eq(target3.item, 13, "STICKY_HOLD keeps the battler item")
eq(target3.mon.item, 13, "STICKY_HOLD keeps the party item")

-- 4. A target with no item is a no-op.
local user4, target4 = battler("enemy", 0), battler("player", 0)
check(not knock_off(user4, target4), "a target with no item is a no-op")

T.finish("game3_knock_off_item_test")
