-- Battle commands: FIGHT / BAG / POKéMON / RUN (+ move slots).

local Commands = {}

Commands.MENU = { "FIGHT", "BAG", "POKEMON", "RUN" }

function Commands.defaultMenuIndex()
  return 1 -- FIGHT
end

--- Build a player action from menu selection.
-- menuIndex 1..4; moveSlot 1..4 when FIGHT.
function Commands.playerAction(st, menuIndex, moveSlot)
  menuIndex = menuIndex or 1
  local kind = Commands.MENU[menuIndex] or "FIGHT"
  if kind == "FIGHT" then
    local mon = st.player and st.player.mon
    local slot = moveSlot or 1
    local move = mon and mon.moves and mon.moves[slot]
    local pp = mon and mon.pp and mon.pp[slot]
    if not move or move == 0 or move == "" or (pp ~= nil and tonumber(pp) <= 0) then
      -- Fall back to first usable
      for i = 1, 4 do
        local mv = mon and mon.moves and mon.moves[i]
        local p = mon and mon.pp and mon.pp[i]
        if mv and mv ~= 0 and mv ~= "" and (p == nil or tonumber(p) > 0) then
          return { kind = "move", move = mv, slot = i, user = "player" }
        end
      end
      return { kind = "move", move = "STRUGGLE", slot = nil, user = "player" }
    end
    return { kind = "move", move = move, slot = slot, user = "player" }
  elseif kind == "RUN" then
    return { kind = "run", user = "player" }
  elseif kind == "BAG" then
    return { kind = "bag", user = "player" }
  elseif kind == "POKEMON" then
    return { kind = "switch", user = "player" }
  end
  return { kind = "move", move = "TACKLE", slot = 1, user = "player" }
end

local MOVE_STRUGGLE = 165
local ITEM_CHOICE_BAND = 186

local function move_num(mv)
  local n = tonumber(mv)
  if n then return n end
  if mv == nil or mv == "" then return 0 end
  local ok, Moves = pcall(require, "src.core.game3.battle.moves")
  if ok and Moves.numForName then return Moves.numForName(mv) or 0 end
  return 0
end

local function battler_name(b)
  local State = require("src.core.game3.battle.state")
  return State.displayName(b)
end

local function move_name(mv)
  local Moves = require("src.core.game3.battle.moves")
  return Moves.displayName(mv)
end

local function foe_of(st, b)
  if not st or not b then return nil end
  return (b.side == "enemy") and st.player or st.enemy
end

local function imprisoned(st, b, num)
  local foe = foe_of(st, b)
  if not (foe and foe.expImprison and foe.mon and foe.mon.moves) then return false end
  for i = 1, 4 do
    if move_num(foe.mon.moves[i]) == num and num ~= 0 then return true end
  end
  return false
end

local function choiced(b)
  local cm = b and move_num(b.choicedMove) or 0
  if (tonumber(b and b.item) or 0) ~= ITEM_CHOICE_BAND then return nil end
  if cm == 0 or cm == 0xFFFF then return nil end
  return cm
end

-- pokefirered/src/battle_util.c:302
function Commands.selectionError(st, slot)
  local b = st and st.player
  local mon = b and b.mon
  if not mon or not slot then return nil end
  local mv = mon.moves and mon.moves[slot]
  local num = move_num(mv)
  local name = battler_name(b)
  local err
  if b.expDisabledMove and move_num(b.expDisabledMove) == num and num ~= 0 then
    err = string.format("%s's %s\nis disabled!", name, move_name(mv))
  end
  if (b.expTormented or b.torment) and num ~= MOVE_STRUGGLE and num ~= 0
      and move_num(b.lastMoveId or b.lastMove) == num then
    err = string.format("%s can't use the same\nmove in a row due to the TORMENT!", name)
  end
  if (tonumber(b.expTauntedTurns) or 0) > 0 then
    local Moves = require("src.core.game3.battle.moves")
    local def = Moves.get(mv)
    if def and (tonumber(def.power) or 0) == 0 then
      err = string.format("%s can't use\n%s after the TAUNT!", name, move_name(mv))
    end
  end
  if imprisoned(st, b, num) then
    err = string.format("%s can't use the\nsealed %s!", name, move_name(mv))
  end
  local cm = choiced(b)
  if cm and cm ~= num then
    local okI, Items = pcall(require, "src.core.game3.items")
    local iname = okI and Items.displayName and Items.displayName(b.item) or "CHOICE BAND"
    err = string.format("%s's effect allows only\n%s to be used!", iname, move_name(cm))
  end
  local pp = mon.pp and tonumber(mon.pp[slot])
  if pp ~= nil and pp <= 0 then
    err = "There's no PP left for\nthis move!"
  end
  return err
end

-- pokefirered/src/battle_util.c:361
function Commands.moveUsable(st, slot)
  local mon = st and st.player and st.player.mon
  local mv = mon and mon.moves and mon.moves[slot]
  if move_num(mv) == 0 then return false end
  return Commands.selectionError(st, slot) == nil
end

-- pokefirered/src/battle_main.c:3146
function Commands.fightShortcut(st)
  local b = st and st.player
  if not b or not b.mon then return nil end
  local any = false
  for i = 1, 4 do
    if Commands.moveUsable(st, i) then any = true break end
  end
  if not any then
    return { kind = "move", move = "STRUGGLE", slot = nil, user = "player" },
      string.format("%s has no\nmoves left!", battler_name(b))
  end
  if b.expEncoreMove and (tonumber(b.expEncoreTurns) or 0) > 0 then
    local slot = b.expEncoreSlot
    if not slot then
      for i = 1, 4 do
        if move_num(b.mon.moves[i]) == move_num(b.expEncoreMove) then slot = i break end
      end
    end
    if slot then
      return { kind = "move", move = b.mon.moves[slot], slot = slot, user = "player" }
    end
  end
  return nil
end

-- pokefirered/src/party_menu.c:5916
function Commands.switchError(st, slot, forced)
  local party = st and st.playerParty
  local mon = party and party[slot]
  if not mon then return nil end
  local Pokemon = require("src.core.game3.pokemon")
  local name = Pokemon.displayMonName and Pokemon.displayMonName(mon) or "POKéMON"
  if (tonumber(mon.hp) or 0) <= 0 then return name .. " has no energy\nleft to battle!" end
  if st.player and st.player.partyIndex == slot then return name .. " is already\nin battle!" end
  if mon.isEgg then return "An EGG can't battle!" end
  if forced then return nil end
  local Engine = package.loaded["src.core.game3.battle.engine"]
  local Battle = package.loaded["src.core.game3.battle"]
  local ad = Battle and Battle._adapter
  if Engine and Engine.canSwitch and ad then
    local ok, why = Engine.canSwitch(st, ad, st.player)
    if not ok then return why end
  end
  return nil
end

function Commands.enemyAction(st)
  local ok, act = pcall(function()
    local Ai = require("src.core.game3.battle.ai")
    return Ai.chooseMove(st)
  end)
  if ok and act and act.kind == "move" then
    return act
  end
  local mon = st.enemy and st.enemy.mon
  for i = 1, 4 do
    local mv = mon and mon.moves and mon.moves[i]
    local p = mon and mon.pp and mon.pp[i]
    if mv and mv ~= 0 and mv ~= "" and (p == nil or tonumber(p) > 0) then
      return { kind = "move", move = mv, slot = i, user = "enemy" }
    end
  end
  return { kind = "move", move = "STRUGGLE", slot = nil, user = "enemy" }
end

--- Wild flee: pret-ish odds from speed (simplified).
function Commands.tryFlee(st, adapter)
  local Engine = package.loaded["src.core.game3.battle.engine"]
  if Engine and Engine.tryFlee then
    local ok = Engine.tryFlee(st, adapter, st.player)
    return ok and true or false
  end
  if not st.wild then
    adapter:say("No! There's no\nrunning from a\nTRAINER battle!")
    return false
  end
  local pSpe = tonumber(st.player.mon.speed or st.player.mon.spe) or 50
  local eSpe = tonumber(st.enemy.mon.speed or st.enemy.mon.spe) or 50
  local odds = math.floor((pSpe * 128) / math.max(1, eSpe)) + 30 * (st.fleeAttempts or 0)
  st.fleeAttempts = (st.fleeAttempts or 0) + 1
  local roll = adapter:rng()
  local r
  local ok, v = pcall(roll, 0, 255)
  if ok and type(v) == "number" then r = v else r = math.random(0, 255) end
  if r < odds then
    adapter:say("Got away safely!")
    return true
  end
  adapter:say("Can't escape!")
  return false
end

return Commands
