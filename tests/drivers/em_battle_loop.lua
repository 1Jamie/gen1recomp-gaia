local U = require("tests.drivers.util")

local L = {}

local function flat(t)
  if type(t) == "table" then
    local ok, s = pcall(require("src.core.game3.scripting.text_ir").toAscii, t, {})
    t = ok and s or ""
  end
  return (tostring(t):gsub("\\[lnp]", " "):gsub("[\n\r]", " "):gsub("  +", " "))
end

function L.logIndex(needle)
  local Ui = require("src.core.game3.battle.ui")
  needle = flat(needle)
  for i, t in ipairs(Ui.log and Ui.log() or {}) do
    if flat(t):find(needle, 1, true) then return i end
  end
  return nil
end

function L.logHas(needle)
  return L.logIndex(needle) ~= nil
end

function L.dumpLog(prefix)
  local Ui = require("src.core.game3.battle.ui")
  for i, t in ipairs(Ui.log and Ui.log() or {}) do
    print((prefix or "[log]") .. " " .. i .. " " .. flat(t))
  end
end

local function pickMove(st, id)
  local Commands = require("src.core.game3.battle.commands")
  local Moves = require("src.core.game3.battle.moves")
  local b = st and st.battlers and st.battlers[id]
  local mon = b and b.mon
  if not mon then return nil end
  local best, bestPow
  for slot = 1, 4 do
    local mv = mon.moves and mon.moves[slot]
    if mv and mv ~= 0 and Commands.moveUsable(st, slot, id) then
      local def = Moves.get(mv)
      local pow = def and tonumber(def.power) or 0
      if not best or pow > bestPow then best, bestPow = slot, pow end
    end
  end
  return best
end

function L.run(game, opts)
  opts = opts or {}
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Anim = require("src.core.game3.battle.anim")
  local PartyMenu = require("src.ui.game3.party_menu")
  local StatGrowth = require("src.ui.game3.stat_growth")
  local cap = opts.turnCap or 30
  local onFrame = opts.onFrame
  local guard = 0
  while Battle.isActive() and guard < (opts.guard or 30000) do
    guard = guard + 1
    local st = Battle._st
    if st and (st.turn or 0) > cap then break end
    if onFrame then onFrame(st, Battle._phase) end
    local phase = Battle._phase
    if PartyMenu.isOpen and PartyMenu.isOpen() then
      local pick
      for i = 1, #(PartyMenu._party or {}) do
        local ok = PartyMenu._validate == nil or PartyMenu._validate(i) == nil
        local mon = PartyMenu._party[i]
        if ok and mon and (tonumber(mon.hp) or 0) > 0 then pick = i break end
      end
      if not pick then return false, "no replacement" end
      PartyMenu.cursor = pick
      U.wait(10)
      U.tap(game, "a")
      U.wait(10)
      PartyMenu.actionCursor = 1
      U.tap(game, "a")
      U.wait(10)
    elseif phase == "command" and Ui._mode == "menu" and not Anim.busy() then
      U.tap(game, "a")
      U.wait(6)
    elseif phase == "command" and Ui._mode == "moves" then
      local who = Ui.activeBattler and Ui.activeBattler() or 0
      local slot = pickMove(st, who)
      if slot then
        for _ = 1, 6 do
          local cur = (Ui._moveIndex or 1) - 1
          local want = slot - 1
          if cur == want then break end
          local key
          if cur % 2 ~= want % 2 then
            key = (cur % 2 == 0) and "right" or "left"
          else
            key = (cur < want) and "down" or "up"
          end
          U.tap(game, key)
          U.wait(4)
        end
      end
      U.tap(game, "a")
      U.wait(6)
    elseif phase == "command" and (Ui._mode == "selmsg" or Ui._mode == "target") then
      U.tap(game, "a")
      U.wait(6)
    elseif StatGrowth.isOpen() then
      U.tap(game, "a")
      U.wait(4)
    else
      if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
      if Ui.choiceActive and Ui.choiceActive() then U.tap(game, "b") U.wait(4) end
    end
  end
  return not Battle.isActive()
end

return L
