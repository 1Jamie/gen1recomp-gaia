local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_pc"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_pc failures=" .. failures)
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
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Space = require("src.core.game3.scripting.space")
  local Stack = require("src.ui.game3.stack")
  local Message = require("src.ui.game3.message")
  local Party = require("src.core.game3.party")
  local Storage = require("src.core.game3.storage")
  local Bag = require("src.core.game3.bag")
  local Mail = require("src.core.game3.mail")
  local PcMenu = require("src.ui.game3.pc_menu")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session and session.version == "emerald", "emerald session") then return finish() end

  Party.giveMonToPlayer(session, C:require("species", "SPECIES_TORCHIC"), 5)
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_ZIGZAGOON"), 3)
  local potion = C:require("items", "ITEM_POTION")
  local antidote = C:require("items", "ITEM_ANTIDOTE")
  Storage.addPcItem(session, antidote, 3)
  local pool = Mail.pool(session)
  local slot = pool[Mail.PARTY_SIZE + 1]
  Mail.clear(slot)
  slot.itemId = C:require("items", "ITEM_WAVE_MAIL")
  slot.playerName = "WALLY"
  local EC = require("src.core.game3.easy_chat_text")
  local g = EC.group(C:require("easy_chat", "EC_GROUP_GREETINGS"))
  slot.words[1], slot.words[2], slot.words[3] = g.words[1].id, g.words[2].id, g.words[3].id

  local function top() local t = Stack.top() return t and t.id or "none" end
  local labels = Space.bundle and Space.bundle.labels or {}
  local function goTo(mapId, x, y, facing)
    try("Map.load " .. mapId, function() Map.load(nil, game, mapId, { x = x, y = y, facing = facing }) end)
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    U.wait(40)
  end
  local function waitFor(pred, frames, pressA)
    for i = 1, frames or 600 do
      if pred() then return true end
      if pressA and i % 12 == 0 then U.tap(game, "a") else U.wait(1) end
    end
    return pred()
  end
  local function msgHas(s)
    return Message.isOpen and Message.isOpen() and tostring(Message.currentPage() or ""):find(s, 1, true) ~= nil
  end
  local n = 0
  local function shot(name) n = n + 1 U.shot(game, string.format("%s/%02d_%s.png", DIR, n, name)) end

  goTo("EM_OLDALE_TOWN_POKEMON_CENTER_1F", 7, 5, "up")
  try("start", function() Space.vm:startTalk(labels["EventScript_PC"], nil, 2) end)
  check(waitFor(function() return PcMenu.isOpen() and PcMenu.mode == "root" end, 900, true),
    "EventScript_PC reaches ScriptMenu_CreatePCMultichoice")
  local rows = PcMenu._rootEntries()
  check(#rows == 3 and rows[1].label == "SOMEONE'S PC" and rows[3].id == "quit",
    "PC hub rows SOMEONE'S PC / BRENDAN's PC / LOG OFF (" .. tostring(rows[1] and rows[1].label) .. ", " .. #rows .. ")")
  shot("pc_hub")

  U.tap(game, "a")
  check(waitFor(function() return PcMenu.isOpen() and PcMenu.mode == "storage_menu" end, 900, true),
    "SOMEONE'S PC opens the storage system menu")
  shot("storage_menu")
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "a")
  check(waitFor(function() return top() == "box_storage" end, 200), "DEPOSIT POKeMON opens the box UI")
  U.wait(10)
  U.tap(game, "down")
  U.wait(4)
  shot("deposit_party_drawer")
  U.tap(game, "a")
  U.wait(6)
  U.tap(game, "a")
  U.wait(10)
  local box1 = Storage.ensure(session).boxes[1]
  check(#session.party == 1 and box1.mons[1] ~= nil, "Zigzagoon deposited into BOX 1 (party " .. #session.party .. ")")
  shot("after_deposit")
  U.tap(game, "b")
  U.wait(10)
  check(waitFor(function() return top() == "pc_menu" end, 200, false), "B leaves the box back to the storage menu")
  U.tap(game, "up")
  U.wait(4)
  PcMenu.cursor = 1
  U.tap(game, "a")
  check(waitFor(function() return top() == "box_storage" end, 200), "WITHDRAW POKeMON opens the box UI")
  U.wait(10)
  shot("withdraw_box")
  U.tap(game, "a")
  U.wait(6)
  U.tap(game, "a")
  U.wait(10)
  check(#session.party == 2 and box1.mons[1] == nil, "Zigzagoon withdrawn back to the party")
  U.tap(game, "b")
  U.wait(10)

  check(waitFor(function() return top() == "pc_menu" end, 200), "back on the storage menu")
  for _ = 1, 4 do U.tap(game, "down") U.wait(3) end
  U.tap(game, "a")
  check(waitFor(function() return PcMenu.isOpen() and PcMenu.mode == "root" end, 900, true), "SEE YA! returns to the PC hub")
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "a")
  check(waitFor(function() return PcMenu.isOpen() and PcMenu.mode == "player_pc" end, 900, true), "BRENDAN's PC runs PlayerPC")
  shot("player_pc")
  local order = require("src.ui.game3.rse.player_pc").topOrder(PcMenu)
  check(#order == 3 and order[3] == "turn_off", "Pokemon Center player PC has no DECORATION row")
  U.tap(game, "a")
  U.wait(4)
  check(PcMenu.mode == "item_storage", "ITEM STORAGE menu")
  shot("item_storage_menu")
  U.tap(game, "a")
  local IS = require("src.ui.game3.rse.item_storage")
  check(waitFor(function() return IS.isOpen() end, 60), "WITHDRAW ITEM opens the item list")
  U.wait(4)
  shot("withdraw_list")
  local before = Bag.get(session.bag, potion)
  U.tap(game, "a")
  U.wait(6)
  U.tap(game, "a")
  U.wait(6)
  check(Bag.get(session.bag, potion) == before + 1, "withdrew the Potion (bag " .. Bag.get(session.bag, potion) .. ")")
  local items = Storage.ensure(session).items
  check(#items == 1 and items[1].id == antidote, "PC list compacts to the Antidote")
  U.tap(game, "b")
  U.wait(6)
  check(PcMenu.mode == "item_storage" and PcMenu.cursor == 1, "B returns to the storage menu on WITHDRAW")
  U.tap(game, "down") U.wait(3) U.tap(game, "down") U.wait(3)
  U.tap(game, "a")
  check(waitFor(function() return IS.isOpen() end, 60), "TOSS ITEM opens the item list")
  U.tap(game, "a")
  U.wait(6)
  U.tap(game, "up")
  U.wait(4)
  check(IS.state == "quantity" and IS.quantity == 2, "toss quantity rolls to 2")
  shot("toss_quantity")
  U.tap(game, "a")
  U.wait(6)
  shot("toss_confirm")
  U.tap(game, "a")
  U.wait(6)
  U.tap(game, "a")
  U.wait(6)
  check(items[1] and items[1].qty == 1, "tossed 2 Antidotes (" .. tostring(items[1] and items[1].qty) .. " left)")
  U.tap(game, "b")
  U.wait(6)
  U.tap(game, "b")
  U.wait(6)
  check(PcMenu.mode == "player_pc", "CANCEL returns to the player PC menu")
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "a")
  local MB = require("src.ui.game3.rse.mailbox")
  check(waitFor(function() return MB.isOpen() end, 60), "MAILBOX opens with one letter")
  U.wait(4)
  shot("mailbox")
  U.tap(game, "a")
  U.wait(6)
  check(MB.state == "options", "mail options (READ / MOVE TO BAG / GIVE / CANCEL)")
  shot("mail_options")
  U.tap(game, "a")
  local MR = require("src.ui.game3.rse.mail")
  check(waitFor(function() return MR.isOpen() end, 60), "READ opens the mail")
  U.wait(30)
  check(MR._design == 5 and MR._lines[1] ~= "", "Wave Mail design 5 with easy chat text (" .. tostring(MR._lines[1]) .. ")")
  U.still(game, DIR .. "/" .. string.format("%02d", n + 1) .. "_mail_read.png")
  n = n + 1
  U.tap(game, "b")
  check(waitFor(function() return not MR.isOpen() end, 120), "B closes the mail")
  U.tap(game, "b")
  U.wait(6)
  check(PcMenu.mode == "player_pc", "mailbox B returns to the player PC")
  U.tap(game, "b")
  check(waitFor(function() return PcMenu.isOpen() and PcMenu.mode == "root" end, 600, true), "TURN OFF returns to the PC hub")
  U.tap(game, "b")
  check(waitFor(function() return not PcMenu.isOpen() and not Space.vm:isRunning() end, 600, true), "B logs off and ends the script")

  goTo("EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", 0, 2, "up")
  try("bedroom", function() Space.vm:startTalk(labels["LittlerootTown_BrendansHouse_2F_EventScript_PC"], nil, 2) end)
  check(waitFor(function() return PcMenu.isOpen() and PcMenu.mode == "player_pc" end, 600, true), "bedroom PC runs BedroomPC")
  order = require("src.ui.game3.rse.player_pc").topOrder(PcMenu)
  check(#order == 4 and order[3] == "decoration", "bedroom PC shows DECORATION")
  shot("bedroom_pc")
  U.tap(game, "b")
  check(waitFor(function() return not PcMenu.isOpen() and not Space.vm:isRunning() end, 600, true), "bedroom PC turns off")
  local Field = require("src.core.game3.field")
  local o = Field.metatileOverrides and Field.metatileOverrides["EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F"]
  local cell = o and o[1 * 1024 + 0]
  check(cell and cell.metatile == C:require("metatile_labels", "METATILE_BrendansMaysHouse_BrendanPC_Off"),
    "DoPCTurnOffEffect sets BrendanPC_Off (" .. tostring(cell and cell.metatile) .. ")")
  local logs = 0
  check(true, "em_pc flow done " .. logs)
  finish()
end
