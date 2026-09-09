-- In-battle item use: balls (catch), medicine, X items, Poké Doll.
-- Catch odds follow pret battle_script_commands.c (simplified shake check).

local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local ItemUse = require("src.core.game3.item_use")
local Pokemon = require("src.core.game3.pokemon")
local Types = require("src.core.game3.battle.types")

local BattleItems = {}

-- pret sBallCatchBonuses (×10): Ultra=20, Great=15, Poke=10, Safari=15
local BALL_MULT = {
  [1] = 255, -- MASTER (handled specially)
  [2] = 20,  -- ULTRA
  [3] = 15,  -- GREAT
  [4] = 10,  -- POKE
  [5] = 15,  -- SAFARI
  [6] = 10,  -- NET (default; type boost below)
  [7] = 10,  -- DIVE
  [8] = 10,  -- NEST (level boost)
  [9] = 10,  -- REPEAT
  [10] = 10, -- TIMER
  [11] = 10, -- LUXURY
  [12] = 10, -- PREMIER
}

local X_STAT = {
  [75] = "attack",   -- X ATTACK
  [76] = "defense",  -- X DEFEND
  [77] = "speed",    -- X SPEED
  [78] = "accuracy", -- X ACCURACY
  [79] = "spAtk",    -- X SPECIAL
}

local function roll(rng, lo, hi)
  lo = lo or 0
  hi = hi or 255
  if type(rng) == "function" then
    local ok, v = pcall(rng, lo, hi)
    if ok and type(v) == "number" then return v end
  end
  return math.random(lo, hi)
end

local Catching = require("src.core.game3.battle.catching")

function BattleItems.isBall(id)
  return Catching.isBall(id)
end

function BattleItems.isBattleUsable(id)
  local info = ItemsData.info(id)
  if not info then return false end
  local bu = tonumber(info.battleUsage) or 0
  if bu > 0 then return true end
  local pocket = info.pocket
  return pocket == "POKE_BALLS" or pocket == "BERRY_POUCH"
end

function BattleItems.needsPartySelect(id)
  if not id then return false end
  if Catching.isBall(id) then return false end
  local num = ItemsData.toNumericId(id) or tonumber(id)
  if num == 80 then return false end -- POKE_DOLL
  if num and X_STAT[num] then return false end -- X items
  local use = ItemsData.fieldUseKind(id)
  local info = ItemsData.info(id)
  local bu = info and tonumber(info.battleUsage) or 0
  if bu == 1 or use == "heal" or use == "status" or use == "revive"
      or (info and info.pocket == "BERRY_POUCH") then
    return true
  end
  return false
end

function BattleItems.ballMultiplier(itemId, foeBattler, st, session)
  return Catching.ballMultiplier(itemId, foeBattler, st, session)
end

function BattleItems.catchOdds(itemId, foeBattler, st, session)
  return Catching.catchOdds(itemId, foeBattler, st, session)
end

function BattleItems.tryCatch(itemId, foeBattler, st, rng, session)
  return Catching.tryCatch(itemId, foeBattler, st, session, rng)
end

function BattleItems.storeCaught(session, foeBattler, ballId)
  local res = Catching.storeCaught(session, foeBattler, ballId)
  return res.location
end

local function sync_player_battler(st)
  local b = st.player
  if not b or not b.mon then return end
  b.fainted = (tonumber(b.mon.hp) or 0) <= 0
  b.status = b.mon.status
end

--- Use a battle item. Returns:
--   result: "catch"|"fail_catch"|"heal"|"xitem"|"doll"|"cancel"|"error"
--   msgs: string list
--   endsTurn: bool (enemy may still move unless endsBattle)
--   endsBattle: bool
function BattleItems.use(st, adapter, bag, session, itemId, partySlot)
  local msgs = {}
  local function say(t)
    msgs[#msgs + 1] = t
    if adapter and adapter.say then adapter:say(t) end
  end

  if not itemId or not bag then
    return "error", msgs, false, false
  end
  if not Bag.has(bag, itemId, 1) then
    say("You don't have that item.")
    return "error", msgs, false, false
  end

  local num = ItemsData.toNumericId(itemId) or tonumber(itemId)
  local name = ItemsData.displayName(itemId)

  -- Poké Doll → flee wild
  if num == 80 then
    if not st.wild then
      say("This can't be used right now.")
      return "error", msgs, false, false
    end
    Bag.remove(bag, itemId, 1)
    say(tostring(session and session.name or "RED") .. " used\nthe " .. name .. "!")
    say("Got away safely!")
    return "doll", msgs, true, true
  end

  -- Balls
  if BattleItems.isBall(itemId) then
    if not st.wild then
      say("The TRAINER blocked\nthe BALL!")
      return "error", msgs, false, false
    end
    Bag.remove(bag, itemId, 1)
    say(tostring(session and session.name or "RED") .. " used\nthe " .. name .. "!")
    local rng = adapter and adapter.rng and adapter:rng() or math.random
    local caught, shakes = BattleItems.tryCatch(itemId, st.enemy, st, rng, session)
    if caught then
      local res = Catching.storeCaught(session, st.enemy, itemId)
      local ename = (st.enemy and st.enemy.mon and (st.enemy.mon.nickname or st.enemy.mon.name))
        or Pokemon.name(st.enemy and st.enemy.species) or "POKéMON"
      say("Gotcha!\n" .. ename .. " was caught!")
      if res and res.firstTimeCaught then
        say(ename .. "'s data was\nadded to the POKéDEX.")
      end
      if res and res.location == "pc" then
        say(ename .. " was transferred\nto the PC.")
      end
      return "catch", msgs, true, true
    end
    if shakes == 0 then
      say("Oh no! The POKéMON broke free!")
    elseif shakes == 1 then
      say("Aww! It appeared to be caught!")
    elseif shakes == 2 then
      say("Aargh! Almost had it!")
    else
      say("Shoot! It was so close too!")
    end
    return "fail_catch", msgs, true, false
  end

  -- X items
  if num and X_STAT[num] then
    local stat = X_STAT[num]
    local battler = st.player
    if not battler or not battler.stages then
      return "error", msgs, false, false
    end
    local cur = battler.stages[stat] or 0
    if cur >= 6 then
      say("It won't have any effect.")
      return "error", msgs, false, false
    end
    Bag.remove(bag, itemId, 1)
    say(tostring(session and session.name or "RED") .. " used\nthe " .. name .. "!")
    if adapter and adapter.changeStages then
      adapter:changeStages(battler, { [stat] = 1 })
    else
      battler.stages[stat] = math.min(6, cur + 1)
    end
    local label = ({
      attack = "ATTACK", defense = "DEFENSE", speed = "SPEED",
      accuracy = "ACCURACY", spAtk = "SP. ATK",
    })[stat] or stat
    local pname = battler.mon and (battler.mon.nickname or battler.mon.name) or "POKéMON"
    say(pname .. "'s " .. label .. "\nrose!")
    return "xitem", msgs, true, false
  end

  -- Medicine / berries on party mon
  local use = ItemsData.fieldUseKind(itemId)
  local info = ItemsData.info(itemId)
  local bu = info and tonumber(info.battleUsage) or 0
  if bu == 1 or use == "heal" or use == "status" or use == "revive"
      or (info and info.pocket == "BERRY_POUCH") then
    -- Prefer in-battle party copy (writeback syncs to session).
    local party = st.playerParty or (session and session.party)
    if not partySlot then
      return "need_slot", msgs, false, false
    end
    local mon = party and party[partySlot]
    if not mon then
      say("It won't have any effect.")
      return "error", msgs, false, false
    end
    local ok = false
    local mk = ItemsData.medicineKind(itemId)
    if mk == "revive" or use == "revive" then
      local max = num == 25
      if num == 45 then
        ok = ItemUse.reviveAll(party)
      else
        ok = ItemUse.revive(mon, max)
      end
    elseif mk == "status" or use == "status" then
      ok = ItemUse.clearStatus(mon, itemId)
    else
      ok = ItemUse.healMon(session, mon, itemId)
    end
    if not ok then
      say("It won't have any effect.")
      return "error", msgs, false, false
    end
    Bag.remove(bag, itemId, 1)
    say(tostring(session and session.name or "RED") .. " used\nthe " .. name .. "!")
    if st.player and st.player.partyIndex == partySlot then
      sync_player_battler(st)
    end
    return "heal", msgs, true, false
  end

  say("This can't be used right now.")
  return "error", msgs, false, false
end

return BattleItems
