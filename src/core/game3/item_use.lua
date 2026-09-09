-- FRLG field item-use handlers for game3 bag.

local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local Pokemon = require("src.core.game3.pokemon")

local ItemUse = {}

local function msg(text)
  local Hud = require("src.ui.game3.hud")
  if Hud and Hud.openMessage then
    Hud.openMessage(nil, text)
  end
end

local function heal_amount(id)
  local n = ItemsData.HEAL_AMOUNT[id]
  if n then return n end
  local num = ItemsData.toNumericId(id) or tonumber(id)
  if num and ItemsData.HEAL_AMOUNT[num] then return ItemsData.HEAL_AMOUNT[num] end
  -- Pack holdEffectParam: Potion=20, Super=50, Hyper=200, Full Restore=255→full
  local info = ItemsData.info(id)
  local param = info and tonumber(info.holdEffectParam)
  if param and param > 0 then
    if param >= 255 then return 9999 end
    return param
  end
  return nil
end

local function mon_status(mon)
  if not mon then return nil, 0 end
  local st = mon.status
  local sleep = tonumber(mon.sleep) or 0
  if type(st) == "string" and st ~= "" and st ~= "0" then return st, sleep end
  local n = tonumber(st) or 0
  if n ~= 0 then return n, sleep end
  if sleep > 0 then return "SLP", sleep end
  return nil, 0
end

--- Apply heal to one party slot. Returns ok, restoredAmount
function ItemUse.healMon(session, mon, id)
  if not mon then return false, 0 end
  local kind = ItemsData.medicineKind(id)
  local maxHp = tonumber(mon.maxHp) or tonumber(mon.maxhp) or 0
  local hp = tonumber(mon.hp) or 0
  if maxHp <= 0 then return false, 0 end

  if kind == "full_restore" then
    if hp <= 0 then return false, 0 end
    local changed = false
    local restored = 0
    if hp < maxHp then
      restored = maxHp - hp
      mon.hp = maxHp
      changed = true
    end
    local st = mon_status(mon)
    if st then
      mon.status = nil
      mon.sleep = 0
      changed = true
    end
    return changed, restored
  end

  local amt = heal_amount(id)
  if not amt then return false, 0 end
  if hp <= 0 then return false, 0 end
  if hp >= maxHp then return false, 0 end
  local newHp
  if amt >= 9999 then
    newHp = maxHp
  else
    newHp = math.min(maxHp, hp + amt)
  end
  local restored = newHp - hp
  mon.hp = newHp
  return true, restored
end

function ItemUse.clearStatus(mon, id)
  if not mon then return false, nil end
  local st, sleep = mon_status(mon)
  if not st and sleep <= 0 then return false, nil end
  local num = ItemsData.toNumericId(id) or tonumber(id)
  local cured = "status"
  -- Specific cures when known; FULL HEAL / powder clear all.
  if num == 14 then -- ANTIDOTE
    if st ~= "PSN" and st ~= "TOX" and st ~= 1 and st ~= 2 then return false, nil end
    cured = "poison"
  elseif num == 15 then -- BURN
    if st ~= "BRN" and st ~= 3 then return false, nil end
    cured = "burn"
  elseif num == 16 then -- ICE / FREEZE
    if st ~= "FRZ" and st ~= 4 then return false, nil end
    cured = "freeze"
  elseif num == 17 then -- AWAKENING
    if st ~= "SLP" and sleep <= 0 and st ~= 5 then return false, nil end
    cured = "sleep"
  elseif num == 18 then -- PARLYZ
    if st ~= "PAR" and st ~= 6 then return false, nil end
    cured = "paralysis"
  end
  mon.status = nil
  mon.sleep = 0
  return true, cured
end

function ItemUse.revive(mon, max)
  if not mon then return false, 0 end
  local maxHp = tonumber(mon.maxHp) or tonumber(mon.maxhp) or 0
  local hp = tonumber(mon.hp) or 0
  if hp > 0 or maxHp <= 0 then return false, 0 end
  if max then
    mon.hp = maxHp
  else
    mon.hp = math.max(1, math.floor(maxHp / 2))
  end
  mon.status = nil
  mon.sleep = 0
  return true, mon.hp
end

function ItemUse.reviveAll(party)
  local any = false
  for _, mon in ipairs(party or {}) do
    if ItemUse.revive(mon, true) then any = true end
  end
  return any
end

--- Give item to party mon as held item. Returns ok, reason, messageText.
function ItemUse.giveToMon(session, bag, id, partySlot)
  local party = session and session.party
  local mon = party and party[partySlot]
  if not mon then return false, "noparty", "There's no POKéMON!" end
  local pocket = ItemsData.pocketOf(id)
  if pocket == "KEY_ITEMS" or pocket == "TM_CASE" then
    local t = "This item can't be held."
    msg(t)
    return false, "cant_hold", t
  end
  if not Bag.has(bag, id, 1) then
    return false, "none", "You don't have that item."
  end
  local prev = mon.item or mon.heldItem
  if prev and prev ~= 0 and prev ~= "" and prev ~= "NONE" then
    -- Swap: return previous to bag if possible
    if not Bag.canAdd(bag, prev, 1) then
      local t = "The BAG is full."
      msg(t)
      return false, "bag_full", t
    end
  end
  Bag.remove(bag, id, 1)
  if prev and prev ~= 0 and prev ~= "" and prev ~= "NONE" then
    Bag.add(bag, prev, 1)
  end
  mon.item = ItemsData.toNumericId(id) or id
  mon.heldItem = mon.item
  local monName = Pokemon.displayMonName(mon)
  local text
  if prev and prev ~= 0 and prev ~= "" and prev ~= "NONE" then
    text = string.format("Took the %s and\ngave the %s to\n%s.", ItemsData.displayName(prev), ItemsData.displayName(id), monName)
  else
    text = string.format("%s was given\nto %s.", ItemsData.displayName(id), monName)
  end
  msg(text)
  return true, "give", text
end

--- Take held item from party mon. Returns ok, reason, messageText.
function ItemUse.takeFromMon(session, bag, partySlot)
  local party = session and session.party
  local mon = party and party[partySlot]
  if not mon then return false, "noparty", "There's no POKéMON!" end
  local held = mon.item or mon.heldItem
  local monName = Pokemon.displayMonName(mon)
  if not held or held == 0 or held == "" or held == "NONE" then
    local t = monName .. " isn't\nholding anything."
    msg(t)
    return false, "none", t
  end
  if not Bag.canAdd(bag, held, 1) then
    local t = "The BAG is full. The\nitem could not be removed."
    msg(t)
    return false, "bag_full", t
  end
  mon.item = nil
  mon.heldItem = nil
  Bag.add(bag, held, 1)
  local text = string.format("Took the %s from\n%s and put it in the BAG.", ItemsData.displayName(held), monName)
  msg(text)
  return true, "take", text
end

local function is_outdoor(session)
  local mapId = session and session.map
  if type(mapId) ~= "string" then return false end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  local data = game and game.data and game.data.maps
  local def = data and data[mapId]
  local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
  if type(pair) == "string" and pair:find("outdoor", 1, true) then
    return true
  end
  -- Heuristic when layout pair missing
  if mapId:find("HOUSE", 1, true) or mapId:find("CENTER", 1, true)
      or mapId:find("GYM", 1, true) or mapId:find("MART", 1, true)
      or mapId:find("LAB", 1, true) or mapId:find("CAVE", 1, true)
      or mapId:find("TUNNEL", 1, true) or mapId:find("TOWER", 1, true)
      or mapId:find("MANSION", 1, true) then
    return false
  end
  if mapId:find("ROUTE", 1, true) or mapId:find("TOWN", 1, true)
      or mapId:find("CITY", 1, true) or mapId:find("ISLAND", 1, true) then
    return true
  end
  return false
end

local function can_escape(session)
  if not session or not session.healMap then return false end
  if session.map == session.healMap then return false end
  -- pret: caves / indoors that aren't the heal point. Deny pure outdoors.
  return not is_outdoor(session)
end

function ItemUse.useEscapeRope(session, bag, id)
  if not can_escape(session) then
    local t = "OAK: This isn't the\ntime to use that!"
    msg(t)
    return false, "escape", t
  end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local mod = Runtime and Runtime._mod
  local game = Runtime and Runtime._game
  local Field = package.loaded["src.core.game3.field"]
  Bag.remove(bag, id, 1)
  local t = tostring(session.name or "RED") .. " used\nESCAPE ROPE."
  msg(t)
  local hx = session.healX or 8
  local hy = session.healY or 5
  local mapId = session.healMap
  local Warp = require("src.core.game3.warp")
  if mod and game then
    Warp.request(mod, game, mapId, hx, hy, "down", { fade = true })
  elseif Field and Field.respawnAtHeal then
    -- Fallback: heal warp without consuming party heal intent
    local Map = require("src.core.game3.map")
    Map.load(mod, game, mapId, { x = hx, y = hy, facing = "down" })
  end
  return true, "escape", t
end

function ItemUse.useBike(session)
  if not is_outdoor(session) then
    local t = "OAK: This isn't the\ntime to use that!"
    msg(t)
    return false, "bike", t
  end
  local Player = require("src.core.game3.player")
  Player.biking = not Player.biking
  local t
  if Player.biking then
    t = tostring(session.name or "RED") .. " got on the\nBICYCLE."
  else
    t = tostring(session.name or "RED") .. " got off the\nBICYCLE."
  end
  msg(t)
  return true, "bike", t
end

--- Teach TM/HM. partySlot required. Consumes TM (not HM).
function ItemUse.useTm(session, bag, id, partySlot)
  local party = session and session.party
  local mon = party and party[partySlot]
  if not mon then
    local t = "There's no POKéMON!"
    msg(t)
    return false, "noparty", t
  end
  local moveId = Pokemon.moveFromTmItem(id)
  local tmName = ItemsData.displayName(id) or "TM"
  local monName = Pokemon.displayMonName(mon)
  if not moveId then
    local t = "This isn't the time to use\nthat!"
    msg(t)
    return false, "tm", t
  end
  local species = tonumber(mon.species or mon.speciesId)
  if not Pokemon.canLearnTmItem(species, id) then
    local t = string.format("%s and %s\nare not compatible.\nIt can't be learned.", monName, tmName)
    msg(t)
    return false, "cant_learn", t
  end
  if Pokemon.knowsMove(mon, moveId) then
    local t = string.format("%s already knows\n%s.", monName, Pokemon.moveName(moveId) or "this move")
    msg(t)
    return false, "knows", t
  end

  local LearnMove = require("src.core.game3.battle.learn_move")
  local isHm = ItemsData.isHm(id)
  local consumed = false

  local function finish_consume(learned)
    if learned and not isHm and not consumed then
      Bag.remove(bag, id, 1)
      consumed = true
    end
  end

  if Pokemon.moveSlotCount(mon) < 4 then
    local ok = Pokemon.teachMove(mon, moveId)
    if ok then
      finish_consume(true)
      local t = string.format("%s learned\n%s!", monName, Pokemon.moveName(moveId))
      msg(t)
      return true, "tm", t
    end
  end

  LearnMove.begin({
    mon = mon,
    moveId = moveId,
    displayName = monName,
    headless = true,
    pushMsg = msg,
    onDone = function(learned)
      finish_consume(learned)
    end,
  })
  if Pokemon.moveSlotCount(mon) >= 4 then
    local t = monName .. " can't learn\nmore than four moves."
    msg(t)
    return false, "full", t
  end
  local t = string.format("%s learned\n%s!", monName, Pokemon.moveName(moveId))
  return true, "tm", t
end

--- Check if using this item requires selecting a party Pokémon target.
function ItemUse.needsPartyTarget(id)
  if not id then return false end
  local info = ItemsData.info(id)
  if not info then return false end
  local use = ItemsData.fieldUseKind(id)
  if use == "heal" or use == "status" or use == "revive" or use == "tm"
      or use == "pp" or use == "level" or use == "evo" or use == "vitamin" then
    return true
  end
  if info.pocket == "TM_CASE" then return true end
  return false
end

function ItemUse.useRareCandy(session, mon)
  if not mon then return false, "none", "There's no POKéMON!" end
  local lvl = tonumber(mon.level) or 1
  if lvl >= 100 then
    local t = "It won't have any effect."
    msg(t)
    return false, "max_level", t
  end
  mon.level = lvl + 1
  local oldMax = tonumber(mon.maxHp) or tonumber(mon.maxhp) or 1
  local oldHp = tonumber(mon.hp) or oldMax
  Pokemon.applyStats(mon)
  local newMax = tonumber(mon.maxHp) or tonumber(mon.maxhp) or oldMax
  mon.hp = math.min(newMax, oldHp + math.max(0, newMax - oldMax))
  local t = string.format("%s grew to\nLv. %d!", Pokemon.displayMonName(mon), mon.level)
  msg(t)
  return true, "level", t
end

function ItemUse.useEvolutionStone(session, mon, itemId)
  local Evolution = require("src.core.game3.evolution")
  local target = Evolution.itemTarget and Evolution.itemTarget(mon, itemId, session)
  if not target then
    local t = "It won't have any effect."
    msg(t)
    return false, "no_evo", t
  end
  local oldName = Pokemon.displayMonName(mon)
  Evolution.apply(mon, target)
  local newName = Pokemon.name(target) or "POKéMON"
  local t = string.format("%s evolved into\n%s!", oldName, newName)
  msg(t)
  return true, "evo", t
end

--- Try field use. partySlot optional for heal/status/revive/tm/give.
-- Returns ok, reason, messageText
function ItemUse.useField(session, bag, id, partySlot)
  local info = ItemsData.info(id)
  if not info then return false, "unknown", "Unknown item." end
  local use = ItemsData.fieldUseKind(id)

  if use == "battle" then
    local t = "This can't be used outside\nof battle."
    msg(t)
    return false, "battle", t
  end

  if use == "map" then
    local RegionMap = require("src.ui.game3.region_map")
    RegionMap.show({ session = session })
    return true, "map", "Used TOWN MAP."
  end

  if use == "bike" then
    return ItemUse.useBike(session)
  end

  if use == "escape" then
    return ItemUse.useEscapeRope(session, bag, id)
  end

  if use == "repel" then
    local steps = ItemsData.REPEL_STEPS[id]
      or ItemsData.REPEL_STEPS[ItemsData.toNumericId(id) or -1]
      or 100
    session.repelSteps = steps
    Bag.remove(bag, id, 1)
    local t = "The repelling effect wore\non for a while."
    msg(t)
    return true, "repel", t
  end

  if use == "key" or use == "rod" or use == "berry" or use == "mail"
      or use == "flute" or use == "none" then
    if ItemsData.toNumericId(id) == ItemsData.ITEM_TM_CASE
        or ItemsData.toNumericId(id) == ItemsData.ITEM_BERRY_POUCH then
      return false, "open_pocket", "Opened pocket."
    end
    local t = "OAK: This isn't the\ntime to use that!"
    msg(t)
    return false, use, t
  end

  if use == "heal" or use == "status" or use == "revive" or use == "tm"
      or use == "pp" or use == "level" or use == "evo" or use == "vitamin" then
    local party = session and session.party
    if not party or #party < 1 then
      local t = "There is no POKéMON."
      msg(t)
      return false, "noparty", t
    end
    if not partySlot then
      return false, "need_slot", "Select a POKéMON."
    end
    local mon = party[partySlot]
    if not mon then
      local t = "There is no POKéMON."
      msg(t)
      return false, "noparty", t
    end
    local ok = false
    local text = nil
    local num = ItemsData.toNumericId(id) or tonumber(id)
    local monName = Pokemon.displayMonName(mon)

    if use == "tm" then
      return ItemUse.useTm(session, bag, id, partySlot)
    elseif use == "evo" then
      ok, _, text = ItemUse.useEvolutionStone(session, mon, id)
    elseif use == "level" then
      ok, _, text = ItemUse.useRareCandy(session, mon)
    elseif use == "revive" then
      if num == 45 then -- Sacred Ash
        ok = ItemUse.reviveAll(party)
        text = "All POKéMON's HP was\nfully restored!"
      else
        local max = num == 25 or tostring(id) == "MAX_REVIVE"
        ok = ItemUse.revive(mon, max)
        text = string.format("%s's HP was\nrestored!", monName)
      end
    elseif use == "status" then
      local stOk, cured = ItemUse.clearStatus(mon, id)
      ok = stOk
      if cured == "poison" then
        text = string.format("%s was\ncured of poison.", monName)
      elseif cured == "paralysis" then
        text = string.format("%s was\ncured of paralysis.", monName)
      elseif cured == "burn" then
        text = string.format("%s's burn\nwas healed.", monName)
      elseif cured == "freeze" then
        text = string.format("%s was\ndefrosted.", monName)
      elseif cured == "sleep" then
        text = string.format("%s woke up.", monName)
      else
        text = string.format("%s recovered\nfrom illness!", monName)
      end
    elseif use == "pp" then
      local t = "It won't have any effect."
      msg(t)
      return false, "pp", t
    elseif use == "vitamin" then
      local t = "It won't have any effect."
      msg(t)
      return false, "vitamin", t
    else
      local healOk, restored = ItemUse.healMon(session, mon, id)
      ok = healOk
      if restored and restored > 0 then
        text = string.format("%s's HP was\nrestored by %d points.", monName, restored)
      else
        text = string.format("%s's HP was\nrestored!", monName)
      end
    end

    if ok then
      Bag.remove(bag, id, 1)
      if text then msg(text) end
      return true, use, text or "It restored health!"
    end
    local noEff = "It won't have any effect."
    msg(noEff)
    return false, "noeffect", noEff
  end

  local t = "OAK: This isn't the\ntime to use that!"
  msg(t)
  return false, "none", t
end

return ItemUse
