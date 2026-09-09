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
