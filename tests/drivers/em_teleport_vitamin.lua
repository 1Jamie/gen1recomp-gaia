local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_teleport_vitamin"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_teleport_vitamin failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    print("[driver] " .. label .. " error: " .. tostring(err))
    failures = failures + 1
  end
  return ok
end

local function body(game)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Pokemon = require("src.core.game3.pokemon")
  local PartyMenu = require("src.ui.game3.party_menu")
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local Field = require("src.core.game3.field")
  local FieldEffects = require("src.core.game3.field_effects")
  local C = require("src.core.game3.constants").of("emerald")

  local session = Runtime.getSession()
  if not check(session and session.version == "emerald", "emerald session") then return end

  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  Flags.setFlag(Space.store, nil, C:require("flags", "FLAG_SYS_POKEMON_GET"), true)
  print("[driver] fresh healMap=" .. tostring(session.healMap) .. " map=" .. tostring(session.map))

  session.party = {}
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_TORCHIC"), 30)
  local mon = session.party[1]
  mon.moves[1] = C:require("moves", "MOVE_TELEPORT")
  session.bag = session.bag or Bag.new()
  local ITEM_HP_UP = C:require("items", "ITEM_HP_UP")
  Bag.add(session.bag, ITEM_HP_UP, 3)

  Map.load(nil, game, "EM_ROUTE101", { x = 10, y = 12, facing = "down" })
  session.x, session.y, session.facing = 10, 12, "down"
  Player.cellX, Player.cellY = 10, 12
  Player.px, Player.py = 160, 192
  Player.targetX, Player.targetY = 10, 12
  Player.facing = "down"
  U.wait(90)
  local startMap = session.map

  local function openStart(entryId)
    for _ = 1, 40 do
      if StartMenu.isOpen and StartMenu.isOpen() then break end
      U.tap(game, "start")
      U.wait(8)
    end
    for _ = 1, 20 do
      local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
      if e and e.id == entryId then break end
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    U.wait(40)
  end

  local function teleportStage()
    U.tap(game, "start")
    U.wait(30)
    local ids = {}
    for _, e in ipairs(StartMenu.ENTRIES or {}) do ids[#ids + 1] = tostring(e.id) end
    print("[driver] start entries: " .. table.concat(ids, ","))
    U.tap(game, "b")
    U.wait(20)
    openStart("pokemon")
    check(PartyMenu.isOpen and PartyMenu.isOpen(), "party menu opens")
    U.tap(game, "a")
    U.wait(12)
    local target
    for i, name in ipairs(PartyMenu.ACTIONS or {}) do
      if name == "TELEPORT" then target = i end
    end
    check(target ~= nil, "TELEPORT is on the action list")
    if not target then return end
    for _ = 1, 12 do
      if PartyMenu.actionCursor == target then break end
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    U.wait(20)
    U.tap(game, "a")
    U.wait(6)

    local sawOut, sawIn = false, false
    for _ = 1, 1500 do
      for _, a in ipairs(FieldEffects._anims or {}) do
        if a.kind == "teleport_out" then sawOut = true end
        if a.kind == "teleport_in" then sawIn = true end
      end
      if sawIn and not Field.locked then break end
      U.wait(1)
    end
    check(sawOut, "teleport_out ran")
    check(sawIn, "teleport_in ran")
    check(Field.locked == false, "field unlocked after teleport")
    print("[driver] teleport " .. tostring(startMap) .. " -> " .. tostring(session.map))
    check(session.map ~= nil and session.map ~= startMap, "landed on a different map")
    U.wait(30)
    U.still(game, DIR .. "/after_teleport.png")
  end
  if not os.getenv("EM_TV_SKIP_TELEPORT") then teleportStage() end

  local beforeHp = mon.maxHp
  local beforeEv = Pokemon.evCount(mon)
  openStart("bag")
  check(BagMenu.isOpen(), "bag opens")
  local row
  for i, r in ipairs(BagMenu.list()) do
    if tonumber(r.id) == ITEM_HP_UP then row = i break end
  end
  check(row ~= nil, "HP UP in the bag")
  if not row then return end
  for _ = 1, 30 do
    if BagMenu.cursor == row then break end
    U.tap(game, "down")
    U.wait(6)
  end
  U.tap(game, "a")
  U.wait(30)
  for _ = 1, 10 do
    if BagMenu.ACTIONS[BagMenu.actionCursor] == "USE" then break end
    U.tap(game, "down")
    U.wait(6)
  end
  U.tap(game, "a")
  U.wait(60)
  check(PartyMenu.open and PartyMenu.mode == "use", "party menu opened for HP UP")
  U.tap(game, "a")
  U.wait(60)
  U.tap(game, "a")
  U.wait(30)
  check(Pokemon.evCount(mon) == beforeEv + 10, "HP UP added 10 EVs (" .. tostring(Pokemon.evCount(mon)) .. ")")
  check(mon.maxHp >= beforeHp, "max HP did not drop")
  for _ = 1, 6 do
    U.tap(game, "b")
    U.wait(20)
  end
  U.wait(30)
  check(Field.locked ~= true, "field not locked after closing menus")
  U.still(game, DIR .. "/after_hpup.png")
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  check(game.boot ~= nil, "boot reached")
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(30)
  try("body", function() body(game) end)
  return finish()
end
