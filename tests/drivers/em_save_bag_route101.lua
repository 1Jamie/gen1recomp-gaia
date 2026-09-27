local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_save_bag_route101"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_save_bag_route101 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  try("new_game", function()
    game:_handleBootAction({ action = "new_game", name = "MAY", gender = 1 })
  end)
  U.wait(30)

  local Runtime = require("src.core.game3.runtime")
  local C = require("src.core.game3.constants").of("emerald")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local ItemsData = require("src.core.game3.items_data")
  local Bag = require("src.core.game3.bag")
  local Party = require("src.core.game3.party")
  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field session exists") then return finish() end

  -- pokeemerald/src/new_game.c:149
  check(session.version == "emerald", "session version emerald")
  check(session.money == 3000, "money 3000 (" .. tostring(session.money) .. ")")
  check(session.storage.items[1] and session.storage.items[1].id == C:require("items", "ITEM_POTION"), "PC holds a Potion")
  check(session.encryptionKey == 0, "encryption key 0")
  check(type(session.localTimeOffset) == "table", "RTC offset in the session")
  local store = Space.store or session
  check(Flags.getFlag(store, nil, C:require("flags", "FLAG_HIDE_LITTLEROOT_TOWN_BIRCHS_LAB_BIRCH")),
    "EventScript_ResetAllMapFlags hid Birch in his lab")
  check(session.specialVars[0x8015] ~= nil, "special var 0x8015 slot")
  check(#ItemsData.BAG_POCKET_ORDER == 5, "five bag pockets (" .. table.concat(ItemsData.BAG_POCKET_ORDER, ",") .. ")")

  -- pokeemerald/src/strings.c:288
  local okL1, l1 = pcall(function() return ItemsData.POCKET_LABEL.TM_CASE end)
  check(okL1 and l1 == "TMs & HMs", "TM pocket label from ROM (" .. tostring(l1) .. ")")
  local okL2, l2 = pcall(function() return ItemsData.POCKET_LABEL.BERRY_POUCH end)
  check(okL2 and l2 == "BERRIES", "berry pocket label from ROM (" .. tostring(l2) .. ")")
  local potion = C:require("items", "ITEM_POTION")
  check(Bag.add(session.bag, potion, 150), "150 Potions go in")
  check(#session.bag.pockets.ITEMS == 2, "99 + 51 slots")
  check(Bag.add(session.bag, C:require("items", "ITEM_TM01"), 1), "TM01 into TMs & HMs")
  check(Bag.get(session.bag, C:require("items", "ITEM_TM_CASE")) == 0, "no FRLG TM Case")

  Party.giveMon(session, C:require("species", "SPECIES_TREECKO"), 5, "TREECKO")
  check(#session.party == 1, "starter in the party")
  check(session.party[1].metGame == 3, "metGame is Emerald (3)")

  local okSave = game:saveGame()
  check(okSave ~= false, "saveGame wrote the slot")
  local okL, raw = pcall(SaveData.load)
  check(okL and raw and raw.version == "emerald", "save reloads as emerald")
  if raw then
    local _, summary = SaveData.slotSummary(raw)
    check(summary and summary.badges == 0, "slot summary badges 0")
    local back = Schema.fromSaveTable(raw)
    check(back.money == 3000, "money survives")
    check(Bag.get(back.bag, potion) == 150, "150 Potions survive (" .. tostring(Bag.get(back.bag, potion)) .. ")")
    check(back.encryptionKey == 0, "encryption key survives")
    check(type(back.localTimeOffset) == "table", "RTC offset survives")
    check(back.party[1] and back.party[1].species == C:require("species", "SPECIES_TREECKO"), "party survives")
  end

  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Encounters = require("src.core.game3.encounters")
  local Battle = require("src.core.game3.battle")
  local VARS = Flags.forVersion("emerald").VAR_IDS
  local IDS = Flags.forVersion("emerald").IDS
  Flags.setVar(Space.store, nil, VARS.VAR_LITTLEROOT_TOWN_STATE, 4)
  Flags.setVar(Space.store, nil, VARS.VAR_ROUTE101_STATE, 3)
  Flags.setFlag(Space.store, nil, IDS.FLAG_RESCUED_BIRCH, true)

  local rules = Encounters.rules()
  local CollRse = package.loaded["src.core.game3.scripting.collision_rse"]
  print("[driver] INFO sTileBitAttributes installed: " .. tostring(CollRse and CollRse._tileBits ~= nil))
  local function grass(cx, cy)
    local kind = rules.classify(Collision.behavior(cx, cy), Encounters.terrainAt(cx, cy))
    return kind == "land" and Collision.isWalkable(cx, cy)
  end
  local gx, gy
  try("Map.load", function()
    Map.load(nil, game, "EM_ROUTE101", { x = 10, y = 10, facing = "down" })
  end)
  U.wait(30)
  local layout = Collision._mapDef and Collision._mapDef.midLayout
  for cy = 1, (layout and layout.height or 0) - 2 do
    for cx = 1, (layout and layout.width or 0) - 2 do
      if not gx and grass(cx, cy) and grass(cx + 1, cy) then gx, gy = cx, cy end
    end
  end
  if not check(gx ~= nil, "Route 101 has encounter grass (" .. tostring(gx) .. "," .. tostring(gy) .. ")") then
    return finish()
  end
  try("Map.load grass", function()
    Map.load(nil, game, "EM_ROUTE101", { x = gx, y = gy, facing = "right" })
  end)
  local s = Runtime.getSession()
  s.x, s.y = gx, gy
  Player.cellX, Player.cellY, Player.px, Player.py = gx, gy, gx * 16, gy * 16
  Player.targetX, Player.targetY = gx, gy
  U.wait(30)
  check(Encounters._immunitySteps == 0, "map load restarts the immunity counter")

  local steps, started = 0, false
  for i = 1, 400 do
    U.hold(game, (i % 2 == 1) and "right" or "left", 16)
    steps = steps + 1
    for _ = 1, 30 do
      if Battle.isActive and Battle.isActive() then started = true break end
      U.wait(1)
    end
    if started then break end
  end
  check(started, "a Route 101 wild battle starts (" .. steps .. " steps)")
  check(steps > 4, "not before the four immunity steps (field_control_avatar.c:670)")
  if started then
    for _ = 1, 240 do U.wait(1) end
    U.still(game, DIR .. "/route101_wild_battle.png")
    local st = Battle.getState and Battle.getState()
    local foe = st and st.enemy and st.enemy.mon
    local sp = foe and tonumber(foe.species)
    local ok = sp == C:require("species", "SPECIES_WURMPLE") or sp == C:require("species", "SPECIES_POOCHYENA")
      or sp == C:require("species", "SPECIES_ZIGZAGOON")
    check(ok, "foe is a Route 101 species (" .. tostring(sp) .. ")")
    check(foe and (foe.level == 2 or foe.level == 3), "foe level 2-3 (" .. tostring(foe and foe.level) .. ")")
  end
  return finish()
end
