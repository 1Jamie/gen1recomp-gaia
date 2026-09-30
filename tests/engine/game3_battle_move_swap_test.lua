package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

local MoveSwap = require("src.core.game3.battle.move_swap")
local State = require("src.core.game3.battle.state")

local function mon()
  return {
    moves = { 10, 20, 30, 40 }, pp = { 1, 2, 3, 4 }, maxPp = { 11, 12, 13, 14 },
    ppBonusesPacked = 1 + 2 * 4 + 3 * 16,
  }
end

local function list(t) return table.concat(t, ",") end

eq(MoveSwap.canStart({}, { mon = mon() }), true, "four moves can start")
eq(MoveSwap.canStart({ link = true }, { mon = mon() }), false, "link battle blocks swap")
eq(MoveSwap.canStart({}, { mon = { moves = { 10, 0, 0, 0 } } }), false, "one move blocks swap")
eq(MoveSwap.canStart({}, nil), false, "no battler blocks swap")

eq(MoveSwap.initialCursor(0), 1, "cursor 0 starts on 1")
eq(MoveSwap.initialCursor(3), 0, "other cursor starts on 0")

eq(MoveSwap.step(1, "left", 4), 0, "left")
eq(MoveSwap.step(0, "left", 4), 0, "left edge")
eq(MoveSwap.step(0, "right", 1), 0, "right clamps to move count")
eq(MoveSwap.step(0, "right", 4), 1, "right")
eq(MoveSwap.step(2, "up", 4), 0, "up")
eq(MoveSwap.step(0, "down", 2), 0, "down clamps to move count")
eq(MoveSwap.step(1, "down", 4), 3, "down")

local plain = { mon = mon() }
eq(MoveSwap.apply(plain, 1, 3), true, "apply returns true")
eq(list(plain.mon.moves), "30,20,10,40", "moves swapped")
eq(list(plain.mon.pp), "3,2,1,4", "pp swapped")
eq(list(plain.mon.maxPp), "13,12,11,14", "maxPp swapped")
eq(plain.mon.ppBonusesPacked, 3 + 2 * 4 + 1 * 16, "pp bonuses swapped")
eq(MoveSwap.apply(plain, 2, 2), false, "same slot is a no-op")

local party = mon()
local b = { mon = party, expLockedSlot = 1, expEncoreSlot = 3 }
State.ensureBattleMoves(b)
b.permanentSlots[1] = false
b.sketched = { [3] = true }
local proxy = b.mon
proxy.moves[1] = 99
proxy.pp[1] = 5
MoveSwap.apply(b, 1, 3)
eq(list(proxy.moves), "30,20,99,40", "proxy moves swapped")
eq(list(proxy.pp), "3,2,5,4", "proxy pp swapped")
eq(list(party.moves), "30,20,10,40", "party moves swapped with proxy")
eq(list(party.pp), "3,2,1,4", "party pp swapped with proxy")
eq(list(party.maxPp), "13,12,11,14", "party maxPp swapped once")
eq(party.ppBonusesPacked, 3 + 2 * 4 + 1 * 16, "party bonuses swapped once")
eq(b.permanentSlots[3], false, "mimicked flag follows the move")
eq(b.permanentSlots[1], true, "swapped slot keeps permanence")
eq(b.sketched[1], true, "sketched flag follows the move")
eq(b.expLockedSlot, 3, "locked slot follows the move")
eq(b.expEncoreSlot, 1, "encore slot follows the move")

local party2 = mon()
local t = { mon = party2, transformed = true }
State.ensureBattleMoves(t)
t.mon.moves = { 1, 2, 3, 4 }
t.mon.pp = { 5, 5, 5, 5 }
MoveSwap.apply(t, 1, 2)
eq(list(t.mon.moves), "2,1,3,4", "transformed battler moves swapped")
eq(list(party2.moves), "10,20,30,40", "transformed swap leaves party alone")

T.finish("game3_battle_move_swap_test")
