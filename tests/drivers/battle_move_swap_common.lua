local U = require("tests.drivers.util")

local M = {}

function M.run(game, opts)
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or opts.dir
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end
  local function finish()
    love.event.quit(fails == 0 and 0 or 1)
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction(opts.newGame)
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local C = require("src.core.game3.constants").of(opts.version)
  local session = Runtime.getSession()
  result(session ~= nil, "field session exists")
  if not session then finish() return end

  local function sp(name) return C.species.byName["SPECIES_" .. name] end
  local function mv(name) return C.moves.byName["MOVE_" .. name] end

  local function set_party(moves, pp)
    session.party = {}
    Party.giveMon(session, sp("CHARIZARD"), 50, "CHARIZARD")
    local m = session.party[1]
    m.moves = moves
    m.pp = pp
    m.maxPp = { 35, 40, 25, 30 }
    m.ppBonusesPacked = 57
    m.hp = m.maxHp or m.hp
    return m
  end

  local lastTap = 0
  local f = 0
  local function pump_text()
    f = f + 1
    if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
      lastTap = f
      U.tap(game, "a")
      return true
    end
    return false
  end
  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  local function open_moves(tag)
    local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = sp("ZIGZAGOON"), level = 3 }, {})
    result(ok == true, tag .. " battle started " .. tostring(err or ""))
    if not ok then return false end
    for _ = 1, 6000 do
      if at_command() then break end
      if not pump_text() then U.wait(1) end
    end
    result(at_command(), tag .. " reached command menu")
    if not at_command() then return false end
    local st = Battle.getState()
    st.enemy.mon.maxHp = 999
    st.enemy.mon.hp = 999
    U.wait(30)
    U.tap(game, "a")
    U.wait(30)
    result(Ui._mode == "moves", tag .. " move menu open")
    return Ui._mode == "moves"
  end

  local function end_battle()
    Battle.abort("run")
    for _ = 1, 600 do
      if not Battle.isActive() then break end
      U.wait(1)
    end
    U.wait(60)
  end

  local function same(a, b)
    for i = 1, 4 do if (a[i] or 0) ~= (b[i] or 0) then return false end end
    return true
  end

  local base = { mv("FLAMETHROWER"), mv("GROWL"), mv("SLASH"), mv("EMBER") }
  local basePp = { 11, 22, 13, 24 }

  local mon = set_party({ base[1], base[2], base[3], base[4] }, { basePp[1], basePp[2], basePp[3], basePp[4] })
  if not open_moves("four") then finish() return end
  local st = Battle.getState()

  st.link = true
  U.tap(game, "select")
  U.wait(6)
  result(Ui._swap == nil, "SELECT ignored in link battle")
  st.link = nil

  U.tap(game, "select")
  U.wait(6)
  result(Ui._swap ~= nil and Ui._swap.cursor == 1, "SELECT opens swap with second cursor on slot 2")
  U.wait(10)
  U.still(game, DIR .. "/" .. opts.tag .. "_01_swap_start.png")

  U.tap(game, "down")
  U.wait(6)
  result(Ui._swap and Ui._swap.cursor == 3, "down moves second cursor to slot 4")
  U.tap(game, "left")
  U.wait(6)
  result(Ui._swap and Ui._swap.cursor == 2, "left moves second cursor to slot 3")
  U.wait(10)
  U.still(game, DIR .. "/" .. opts.tag .. "_02_swap_cursor_slot3.png")

  U.tap(game, "b")
  U.wait(6)
  result(Ui._swap == nil, "B leaves swap mode")
  result(same(st.player.mon.moves, base), "cancel leaves battler order unchanged")
  result(same(st.player.mon.pp, basePp), "cancel leaves battler pp unchanged")
  result(Ui._mode == "moves" and Ui._moveIndex == 1, "cancel keeps move cursor")

  U.tap(game, "select")
  U.wait(6)
  U.tap(game, "left")
  U.wait(6)
  U.tap(game, "select")
  U.wait(6)
  local bmon = st.player.mon
  result(Ui._swap == nil, "SELECT confirms; same slot is a no-op")
  result(same(bmon.moves, base), "same-slot confirm leaves order unchanged")

  U.tap(game, "select")
  U.wait(6)
  U.tap(game, "down")
  U.wait(6)
  U.tap(game, "left")
  U.wait(6)
  U.tap(game, "a")
  U.wait(10)
  local want = { base[3], base[2], base[1], base[4] }
  local wantPp = { basePp[3], basePp[2], basePp[1], basePp[4] }
  local wantMax = { 25, 40, 35, 30 }
  result(Ui._swap == nil, "A confirms swap")
  result(same(bmon.moves, want), "battler moves swapped 1<->3")
  result(same(bmon.pp, wantPp), "battler pp swapped 1<->3")
  result(same(bmon.maxPp, wantMax), "battler maxPp swapped 1<->3")
  result(bmon.ppBonusesPacked == 27, "battler pp bonuses swapped 1<->3")
  result(Ui._moveIndex == 3, "move cursor lands on the swapped-to slot")
  U.wait(10)
  U.still(game, DIR .. "/" .. opts.tag .. "_03_after_swap.png")

  U.tap(game, "b")
  U.wait(20)
  result(Ui._mode == "menu", "B from move menu returns to action menu")
  U.tap(game, "a")
  U.wait(20)
  result(Ui._mode == "moves" and same(st.player.mon.moves, want), "reopened move menu keeps order")
  end_battle()
  result(same(mon.moves, want) and same(mon.pp, wantPp), "session party order persists after the battle")
  result(same(mon.maxPp, wantMax) and mon.ppBonusesPacked == 27, "session party maxPp and bonuses persist after the battle")

  local mon1 = set_party({ mv("TACKLE"), 0, 0, 0 }, { 35, 0, 0, 0 })
  if not open_moves("single") then finish() return end
  U.tap(game, "select")
  U.wait(6)
  result(Ui._swap == nil, "SELECT ignored with one move")
  result(mon1.moves[1] == mv("TACKLE"), "single move untouched")
  end_battle()

  finish()
end

return M
