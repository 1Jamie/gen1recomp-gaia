-- FRLG PC Hub Menu & Player PC Item Storage (pret data/scripts/pc.inc).
--
-- Options:
-- 1. BILL'S PC / SOMEONE'S PC (Opens Pokémon Storage System)
-- 2. <PLAYER>'S PC (50-slot Item Storage: WITHDRAW / DEPOSIT / TOSS)
-- 3. PROF. OAK'S PC (Pokédex Rating)
-- 4. HALL OF FAME (Game Clear check)
-- 5. LOG OFF (Turns off PC with SE_PC_OFF)

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local Storage = require("src.core.game3.storage")

local PcMenu = {}

PcMenu.open = false
PcMenu.mode = "root" -- root | player_pc | withdraw_item | withdraw_qty | deposit_item | deposit_qty | toss_item | toss_qty | toss_confirm | oak_pc | msg
PcMenu.cursor = 1
PcMenu.itemCursor = 1
PcMenu.itemScroll = 0
PcMenu.itemQty = 1
PcMenu.yesNoCursor = 2
PcMenu.selectedPocket = "ITEMS"
PcMenu.pocketIdx = 1

local VISIBLE_ITEMS = 6

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

local function someone_or_bill_name(session)
  local flags = session and (session.flags or session.eventFlags) or {}
  -- FLAG_SYS_NOT_SOMEONES_PC = 0x828 (2088)
  local isBill = flags[0x828] or flags["FLAG_SYS_NOT_SOMEONES_PC"] or false
  return isBill and "BILL's PC" or "SOMEONE's PC"
end

local function player_pc_name(session)
  local name = (session and (session.name or session.playerName)) or "RED"
  return string.format("%s's PC", name)
end

function PcMenu.show(opts)
  opts = opts or {}
  PcMenu.open = true
  PcMenu._session = opts.session
  PcMenu._onClose = opts.onClose
  PcMenu.mode = "root"
  PcMenu.cursor = 1
  PcMenu._status = "Which PC would you like to access?"
  Storage.ensure(PcMenu._session)
  se(2) -- SE_PC_ON / SE_PC_LOGIN
  Stack.push("pc_menu", PcMenu, { hideBelow = false })
end

function PcMenu.close()
  PcMenu.open = false
  Stack.pop("pc_menu")
  se(3) -- SE_PC_OFF
  local cb = PcMenu._onClose
  PcMenu._onClose = nil
  if cb then cb() end
end

function PcMenu.isOpen()
  return PcMenu.open
end

local function clamp_item_cursor(items)
  items = items or {}
  local total = #items + 1 -- include CANCEL
  if PcMenu.itemCursor > total then PcMenu.itemCursor = total end
  if PcMenu.itemCursor < 1 then PcMenu.itemCursor = 1 end
  if PcMenu.itemCursor <= PcMenu.itemScroll then
    PcMenu.itemScroll = PcMenu.itemCursor - 1
  end
  if PcMenu.itemCursor > PcMenu.itemScroll + VISIBLE_ITEMS then
    PcMenu.itemScroll = PcMenu.itemCursor - VISIBLE_ITEMS
  end
  if PcMenu.itemScroll < 0 then PcMenu.itemScroll = 0 end
end

function PcMenu.handleInput(input)
  if not PcMenu.open then return end

  -- Message state
  if PcMenu.mode == "msg" then
    if input:wasPressed("a") or input:wasPressed("b") then
      PcMenu.mode = PcMenu._prevMode or "root"
      PcMenu._status = nil
      se(5)
    end
    return
  end

  -- Storage System Menu (WITHDRAW POKéMON, DEPOSIT POKéMON, MOVE POKéMON, MOVE ITEMS, SEE YA!)
  local STORAGE_OPTIONS = {
    { id = "withdraw", label = "WITHDRAW POKéMON", desc = "You can withdraw a POKéMON if you\nhave any in a BOX." },
    { id = "deposit", label = "DEPOSIT POKéMON", desc = "You can deposit your party\nPOKéMON in any BOX." },
    { id = "move", label = "MOVE POKéMON", desc = "You can move POKéMON that are\nstored in any BOX." },
    { id = "move_items", label = "MOVE ITEMS", desc = "You can move items held by any\nPOKéMON in a BOX or your party." },
    { id = "quit", label = "SEE YA!", desc = "See you later!" },
  }

  -- Root Menu
  if PcMenu.mode == "root" then
    local entries = {
      { id = "storage", label = someone_or_bill_name(PcMenu._session) },
      { id = "player", label = player_pc_name(PcMenu._session) },
      { id = "oak", label = "PROF. OAK's PC" },
      { id = "hall", label = "HALL OF FAME" },
      { id = "quit", label = "LOG OFF" },
    }

    if input:wasPressed("up") then
      PcMenu.cursor = ((PcMenu.cursor - 2) % #entries) + 1
      se(5)
    elseif input:wasPressed("down") then
      PcMenu.cursor = (PcMenu.cursor % #entries) + 1
      se(5)
    elseif input:wasPressed("a") then
      local choice = entries[PcMenu.cursor]
      if choice.id == "quit" then
        PcMenu.close()
      elseif choice.id == "storage" then
        se(5)
        PcMenu.mode = "storage_menu"
        PcMenu.storageCursor = PcMenu.storageCursor or 1
        PcMenu.cursor = PcMenu.storageCursor
        PcMenu._status = STORAGE_OPTIONS[PcMenu.cursor].desc
      elseif choice.id == "player" then
        se(5)
        PcMenu.mode = "player_pc"
        PcMenu.cursor = 1
        PcMenu._status = "What would you like to do?"
      elseif choice.id == "oak" then
        se(5)
        local Dex = require("src.core.game3.dex")
        local dex = PcMenu._session and PcMenu._session.dex
        local caught = dex and Dex.countCaught(dex, "kanto") or 0
        local seen = dex and Dex.countSeen(dex, "kanto") or 0
        PcMenu._status = string.format("Current POKéDEX status:\nSeen: %d   Owned: %d", seen, caught)
        PcMenu._prevMode = "root"
        PcMenu.mode = "msg"
      elseif choice.id == "hall" then
        se(5)
        PcMenu._status = "No records in the HALL OF FAME."
        PcMenu._prevMode = "root"
        PcMenu.mode = "msg"
      end
    elseif input:wasPressed("b") then
      PcMenu.close()
    end
    return
  end

  -- Storage Submenu (Withdraw, Deposit, Move Pokémon, Move Items, See Ya!)
  if PcMenu.mode == "storage_menu" then
    if input:wasPressed("up") then
      PcMenu.cursor = ((PcMenu.cursor - 2) % #STORAGE_OPTIONS) + 1
      PcMenu.storageCursor = PcMenu.cursor
      PcMenu._status = STORAGE_OPTIONS[PcMenu.cursor].desc
      se(5)
    elseif input:wasPressed("down") then
      PcMenu.cursor = (PcMenu.cursor % #STORAGE_OPTIONS) + 1
      PcMenu.storageCursor = PcMenu.cursor
      PcMenu._status = STORAGE_OPTIONS[PcMenu.cursor].desc
      se(5)
    elseif input:wasPressed("a") then
      local choice = STORAGE_OPTIONS[PcMenu.cursor]
      if choice.id == "quit" then
        PcMenu.mode = "root"
        PcMenu.cursor = 1
        PcMenu._status = "Which PC would you like to access?"
        se(5)
      elseif choice.id == "withdraw" then
        local party = (PcMenu._session and PcMenu._session.party) or {}
        if #party >= 6 then
          PcMenu._status = "Can't take any more POKéMON."
          PcMenu._prevMode = "storage_menu"
          PcMenu.mode = "msg"
          se(9)
        else
          se(5)
          local BoxStorageUI = require("src.ui.game3.box_storage_ui")
          BoxStorageUI.show({
            session = PcMenu._session,
            subMode = "withdraw",
            onClose = function()
              PcMenu.mode = "storage_menu"
              PcMenu.cursor = 1
              PcMenu._status = STORAGE_OPTIONS[1].desc
              se(2)
            end,
          })
        end
      elseif choice.id == "deposit" then
        local party = (PcMenu._session and PcMenu._session.party) or {}
        if #party <= 1 then
          PcMenu._status = "Can't deposit the last POKéMON!"
          PcMenu._prevMode = "storage_menu"
          PcMenu.mode = "msg"
          se(9)
        else
          se(5)
          local BoxStorageUI = require("src.ui.game3.box_storage_ui")
          BoxStorageUI.show({
            session = PcMenu._session,
            subMode = "deposit",
            onClose = function()
              PcMenu.mode = "storage_menu"
              PcMenu.cursor = 2
              PcMenu._status = STORAGE_OPTIONS[2].desc
              se(2)
            end,
          })
        end
      elseif choice.id == "move" or choice.id == "move_items" then
        se(5)
        local curIdx = PcMenu.cursor
        local BoxStorageUI = require("src.ui.game3.box_storage_ui")
        BoxStorageUI.show({
          session = PcMenu._session,
          subMode = choice.id,
          onClose = function()
            PcMenu.mode = "storage_menu"
            PcMenu.cursor = curIdx
            PcMenu._status = STORAGE_OPTIONS[curIdx].desc
            se(2)
          end,
        })
      end
    elseif input:wasPressed("b") then
      PcMenu.mode = "root"
      PcMenu.cursor = 1
      PcMenu._status = "Which PC would you like to access?"
      se(5)
    end
    return
  end

  -- Player's PC Submenu (Withdraw, Deposit, Toss, Log Off)
  if PcMenu.mode == "player_pc" then
    local playerOptions = {
      { id = "withdraw", label = "WITHDRAW ITEM" },
      { id = "deposit", label = "DEPOSIT ITEM" },
      { id = "toss", label = "TOSS ITEM" },
      { id = "logoff", label = "LOG OFF" },
    }

    if input:wasPressed("up") then
      PcMenu.cursor = ((PcMenu.cursor - 2) % #playerOptions) + 1
      se(5)
    elseif input:wasPressed("down") then
      PcMenu.cursor = (PcMenu.cursor % #playerOptions) + 1
      se(5)
    elseif input:wasPressed("a") then
      local choice = playerOptions[PcMenu.cursor]
      if choice.id == "logoff" then
        PcMenu.mode = "root"
        PcMenu.cursor = 2
        PcMenu._status = "Which PC would you like to access?"
        se(5)
      elseif choice.id == "withdraw" then
        local storage = Storage.ensure(PcMenu._session)
        if #storage.items < 1 then
          PcMenu._status = "There are no items in the PC."
          PcMenu._prevMode = "player_pc"
          PcMenu.mode = "msg"
          se(9)
        else
          PcMenu.mode = "withdraw_item"
          PcMenu.itemCursor = 1
          PcMenu.itemScroll = 0
          PcMenu._status = "What do you want to withdraw?"
          se(5)
        end
      elseif choice.id == "deposit" then
        PcMenu.mode = "deposit_item"
        PcMenu.itemCursor = 1
        PcMenu.itemScroll = 0
        PcMenu._status = "What do you want to deposit?"
        se(5)
      elseif choice.id == "toss" then
        local storage = Storage.ensure(PcMenu._session)
        if #storage.items < 1 then
          PcMenu._status = "There are no items in the PC."
          PcMenu._prevMode = "player_pc"
          PcMenu.mode = "msg"
          se(9)
        else
          PcMenu.mode = "toss_item"
          PcMenu.itemCursor = 1
          PcMenu.itemScroll = 0
          PcMenu._status = "What do you want to toss?"
          se(5)
        end
      end
    elseif input:wasPressed("b") then
      PcMenu.mode = "root"
      PcMenu.cursor = 2
      PcMenu._status = "Which PC would you like to access?"
      se(5)
    end
    return
  end

  -- Withdraw Item selection
  if PcMenu.mode == "withdraw_item" then
    local storage = Storage.ensure(PcMenu._session)
    local items = storage.items or {}
    clamp_item_cursor(items)

    if input:wasPressed("up") then
      PcMenu.itemCursor = ((PcMenu.itemCursor - 2) % (#items + 1)) + 1
      clamp_item_cursor(items)
      se(5)
    elseif input:wasPressed("down") then
      PcMenu.itemCursor = (PcMenu.itemCursor % (#items + 1)) + 1
      clamp_item_cursor(items)
      se(5)
    elseif input:wasPressed("a") then
      if PcMenu.itemCursor > #items then
        PcMenu.mode = "player_pc"
        PcMenu.cursor = 1
        se(5)
      else
        local entry = items[PcMenu.itemCursor]
        if (entry.qty or 1) > 1 then
          PcMenu.mode = "withdraw_qty"
          PcMenu.itemQty = 1
          PcMenu._pendingItem = entry
          PcMenu._status = "How many to withdraw?"
        else
          local ok, err = Storage.withdrawItem(PcMenu._session, PcMenu.itemCursor, 1)
          if ok then
            PcMenu._status = string.format("Withdrew 1 %s.", ItemsData.displayName(entry.id))
            PcMenu._prevMode = "player_pc"
            PcMenu.mode = "msg"
            se(246)
          else
            PcMenu._status = "The BAG is full."
            PcMenu._prevMode = "withdraw_item"
            PcMenu.mode = "msg"
            se(9)
          end
        end
      end
    elseif input:wasPressed("b") then
      PcMenu.mode = "player_pc"
      PcMenu.cursor = 1
      se(5)
    end
    return
  end

  -- Withdraw Quantity selection
  if PcMenu.mode == "withdraw_qty" then
    local entry = PcMenu._pendingItem
    local maxQ = entry and entry.qty or 1

    if input:wasPressed("up") then
      PcMenu.itemQty = (PcMenu.itemQty % maxQ) + 1
      se(5)
    elseif input:wasPressed("down") then
      PcMenu.itemQty = ((PcMenu.itemQty - 2) % maxQ) + 1
      se(5)
    elseif input:wasPressed("right") then
      PcMenu.itemQty = math.min(maxQ, PcMenu.itemQty + 10)
      se(5)
    elseif input:wasPressed("left") then
      PcMenu.itemQty = math.max(1, PcMenu.itemQty - 10)
      se(5)
    elseif input:wasPressed("a") then
      local ok, err = Storage.withdrawItem(PcMenu._session, PcMenu.itemCursor, PcMenu.itemQty)
      if ok then
        PcMenu._status = string.format("Withdrew %d %s.", PcMenu.itemQty, ItemsData.displayName(entry.id))
        PcMenu._prevMode = "player_pc"
        PcMenu.mode = "msg"
        se(246)
      else
        PcMenu._status = "The BAG is full."
        PcMenu._prevMode = "withdraw_item"
        PcMenu.mode = "msg"
        se(9)
      end
    elseif input:wasPressed("b") then
      PcMenu.mode = "withdraw_item"
      PcMenu._status = "What do you want to withdraw?"
      se(5)
    end
    return
  end

  -- Deposit Item selection (from bag)
  if PcMenu.mode == "deposit_item" then
    local bag = PcMenu._session and PcMenu._session.bag
    local items = bag and Bag.listPocket(bag, PcMenu.selectedPocket) or {}
    clamp_item_cursor(items)

    if input:wasPressed("up") then
      PcMenu.itemCursor = ((PcMenu.itemCursor - 2) % (#items + 1)) + 1
      clamp_item_cursor(items)
      se(5)
    elseif input:wasPressed("down") then
      PcMenu.itemCursor = (PcMenu.itemCursor % (#items + 1)) + 1
      clamp_item_cursor(items)
      se(5)
    elseif input:wasPressed("left") or input:wasPressed("right") then
      local pockets = ItemsData.POCKET_ORDER or { "ITEMS", "KEY_ITEMS", "POKE_BALLS", "TM_CASE", "BERRY_POUCH" }
      local pIdx = PcMenu.pocketIdx or 1
      if input:wasPressed("right") then
        pIdx = (pIdx % #pockets) + 1
      else
        pIdx = ((pIdx - 2) % #pockets) + 1
      end
      PcMenu.pocketIdx = pIdx
      PcMenu.selectedPocket = pockets[pIdx]
      PcMenu.itemCursor = 1
      PcMenu.itemScroll = 0
      se(5)
    elseif input:wasPressed("a") then
      if PcMenu.itemCursor > #items then
        PcMenu.mode = "player_pc"
        PcMenu.cursor = 2
        se(5)
      else
        local entry = items[PcMenu.itemCursor]
        local isKey = ItemsData.pocketOf(entry.id) == "KEY_ITEMS"
        if isKey then
          PcMenu._status = "That's much too important to deposit!"
          PcMenu._prevMode = "deposit_item"
          PcMenu.mode = "msg"
          se(9)
        elseif (entry.qty or 1) > 1 then
          PcMenu.mode = "deposit_qty"
          PcMenu.itemQty = 1
          PcMenu._pendingItem = entry
          PcMenu._status = "How many to deposit?"
        else
          local ok, err = Storage.depositItem(PcMenu._session, PcMenu.selectedPocket, PcMenu.itemCursor, 1)
          if ok then
            PcMenu._status = string.format("Stored 1 %s.", ItemsData.displayName(entry.id))
            PcMenu._prevMode = "player_pc"
            PcMenu.mode = "msg"
            se(246)
          else
            PcMenu._status = "The PC is full."
            PcMenu._prevMode = "deposit_item"
            PcMenu.mode = "msg"
            se(9)
          end
        end
      end
    elseif input:wasPressed("b") then
      PcMenu.mode = "player_pc"
      PcMenu.cursor = 2
      se(5)
    end
    return
  end

  -- Deposit Quantity selection
  if PcMenu.mode == "deposit_qty" then
    local entry = PcMenu._pendingItem
    local maxQ = entry and entry.qty or 1

    if input:wasPressed("up") then
      PcMenu.itemQty = (PcMenu.itemQty % maxQ) + 1
      se(5)
    elseif input:wasPressed("down") then
      PcMenu.itemQty = ((PcMenu.itemQty - 2) % maxQ) + 1
      se(5)
    elseif input:wasPressed("right") then
      PcMenu.itemQty = math.min(maxQ, PcMenu.itemQty + 10)
      se(5)
    elseif input:wasPressed("left") then
      PcMenu.itemQty = math.max(1, PcMenu.itemQty - 10)
      se(5)
    elseif input:wasPressed("a") then
      local ok, err = Storage.depositItem(PcMenu._session, PcMenu.selectedPocket, PcMenu.itemCursor, PcMenu.itemQty)
      if ok then
        PcMenu._status = string.format("Stored %d %s.", PcMenu.itemQty, ItemsData.displayName(entry.id))
        PcMenu._prevMode = "player_pc"
        PcMenu.mode = "msg"
        se(246)
      else
        PcMenu._status = "The PC is full."
        PcMenu._prevMode = "deposit_item"
        PcMenu.mode = "msg"
        se(9)
      end
    elseif input:wasPressed("b") then
      PcMenu.mode = "deposit_item"
      PcMenu._status = "What do you want to deposit?"
      se(5)
    end
    return
  end

  -- Toss Item selection
  if PcMenu.mode == "toss_item" then
    local storage = Storage.ensure(PcMenu._session)
    local items = storage.items or {}
    clamp_item_cursor(items)

    if input:wasPressed("up") then
      PcMenu.itemCursor = ((PcMenu.itemCursor - 2) % (#items + 1)) + 1
      clamp_item_cursor(items)
      se(5)
    elseif input:wasPressed("down") then
      PcMenu.itemCursor = (PcMenu.itemCursor % (#items + 1)) + 1
      clamp_item_cursor(items)
      se(5)
    elseif input:wasPressed("a") then
      if PcMenu.itemCursor > #items then
        PcMenu.mode = "player_pc"
        PcMenu.cursor = 3
        se(5)
      else
        local entry = items[PcMenu.itemCursor]
        PcMenu._pendingItem = entry
        PcMenu.mode = "toss_confirm"
        PcMenu.yesNoCursor = 2
        PcMenu._status = string.format("Throw away 1 %s?", ItemsData.displayName(entry.id))
        se(5)
      end
    elseif input:wasPressed("b") then
      PcMenu.mode = "player_pc"
      PcMenu.cursor = 3
      se(5)
    end
    return
  end

  -- Toss Confirm
  if PcMenu.mode == "toss_confirm" then
    if input:wasPressed("up") or input:wasPressed("down") then
      PcMenu.yesNoCursor = (PcMenu.yesNoCursor == 1) and 2 or 1
      se(5)
    elseif input:wasPressed("a") then
      if PcMenu.yesNoCursor == 1 then
        local entry = PcMenu._pendingItem
        Storage.tossItem(PcMenu._session, PcMenu.itemCursor, 1)
        PcMenu._status = string.format("Threw away 1 %s.", ItemsData.displayName(entry.id))
        PcMenu._prevMode = "player_pc"
        PcMenu.mode = "msg"
        se(9)
      else
        PcMenu.mode = "toss_item"
        PcMenu._status = "What do you want to toss?"
        se(5)
      end
    elseif input:wasPressed("b") then
      PcMenu.mode = "toss_item"
      PcMenu._status = "What do you want to toss?"
      se(5)
    end
    return
  end
end

function PcMenu.draw()
  if not PcMenu.open then return end

  -- Root Menu Box
  if PcMenu.mode == "root" then
    local entries = {
      { id = "storage", label = someone_or_bill_name(PcMenu._session) },
      { id = "player", label = player_pc_name(PcMenu._session) },
      { id = "oak", label = "PROF. OAK's PC" },
      { id = "hall", label = "HALL OF FAME" },
      { id = "quit", label = "LOG OFF" },
    }
    Window.stdFrame(Window.template(1, 1, 14, 10))
    for i, e in ipairs(entries) do
      local yPx = 10 + (i - 1) * 16
      if i == PcMenu.cursor then Window.cursorPx(12, yPx) end
      Window.printPx(e.label, 20, yPx)
    end

    -- Bottom Dialogue
    Window.dialogueFrame()
    if PcMenu._status then
      local lines = {}
      for line in tostring(PcMenu._status):gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
      end
      if #lines > 0 then Window.print(lines[1], 2, 15, { clipTiles = 26 }) end
      if #lines > 1 then Window.print(lines[2], 2, 17, { clipTiles = 26 }) end
    end
    return
  end

  -- Storage Submenu Box (WITHDRAW, DEPOSIT, MOVE, MOVE ITEMS, SEE YA!)
  if PcMenu.mode == "storage_menu" then
    local storageOptions = {
      "WITHDRAW POKéMON",
      "DEPOSIT POKéMON",
      "MOVE POKéMON",
      "MOVE ITEMS",
      "SEE YA!",
    }
    Window.stdFrame(Window.template(1, 1, 16, 10))
    for i, opt in ipairs(storageOptions) do
      local yPx = 10 + (i - 1) * 16
      if i == PcMenu.cursor then Window.cursorPx(12, yPx) end
      Window.printPx(opt, 20, yPx)
    end

    -- Bottom Dialogue
    Window.dialogueFrame()
    if PcMenu._status then
      local lines = {}
      for line in tostring(PcMenu._status):gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
      end
      if #lines > 0 then Window.print(lines[1], 2, 15, { clipTiles = 26 }) end
      if #lines > 1 then Window.print(lines[2], 2, 17, { clipTiles = 26 }) end
    end
    return
  end

  -- Player's PC Submenu
  if PcMenu.mode == "player_pc" then
    local playerOptions = {
      { id = "withdraw", label = "WITHDRAW ITEM" },
      { id = "deposit", label = "DEPOSIT ITEM" },
      { id = "toss", label = "TOSS ITEM" },
      { id = "logoff", label = "LOG OFF" },
    }
    Window.stdFrame(Window.template(1, 1, 14, 8))
    for i, e in ipairs(playerOptions) do
      local yPx = 10 + (i - 1) * 16
      if i == PcMenu.cursor then Window.cursorPx(12, yPx) end
      Window.printPx(e.label, 20, yPx)
    end

    -- Bottom Dialogue
    Window.dialogueFrame()
    if PcMenu._status then
      local lines = {}
      for line in tostring(PcMenu._status):gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
      end
      if #lines > 0 then Window.print(lines[1], 2, 15, { clipTiles = 26 }) end
      if #lines > 1 then Window.print(lines[2], 2, 17, { clipTiles = 26 }) end
    end
    return
  end

  -- Item List (Withdraw / Toss / Deposit)
  if PcMenu.mode == "withdraw_item" or PcMenu.mode == "toss_item" or PcMenu.mode == "deposit_item" then
    local items
    if PcMenu.mode == "deposit_item" then
      local bag = PcMenu._session and PcMenu._session.bag
      items = bag and Bag.listPocket(bag, PcMenu.selectedPocket) or {}
      -- Header showing active pocket
      Window.stdFrame(Window.template(1, 1, 12, 2))
      Window.printPx(PcMenu.selectedPocket, 12, 9, { small = true })
    else
      local storage = Storage.ensure(PcMenu._session)
      items = storage.items or {}
      Window.stdFrame(Window.template(1, 1, 12, 2))
      Window.printPx("PC ITEMS", 12, 9, { small = true })
    end

    -- Main item list window
    Window.stdFrame(Window.template(1, 4, 28, 10))
    for vis = 1, VISIBLE_ITEMS do
      local idx = PcMenu.itemScroll + vis
      if idx > #items + 1 then break end
      local yPx = 34 + (vis - 1) * 12
      if idx == PcMenu.itemCursor then Window.cursorPx(10, yPx) end
      if idx > #items then
        Window.printPx("CANCEL", 18, yPx)
      else
        local entry = items[idx]
        local nameStr = ItemsData.displayName(entry.id) or ("ITEM " .. tostring(entry.id))
        Window.printPx(nameStr, 18, yPx)
        local qStr = string.format("×%02d", entry.qty or 1)
        Window.printPx(qStr, 190, yPx)
      end
    end

    -- Bottom Dialogue
    Window.dialogueFrame()
    if PcMenu._status then
      Window.printPx(PcMenu._status, 16, 120)
    end
    return
  end

  -- Quantity Selection (Withdraw / Deposit)
  if PcMenu.mode == "withdraw_qty" or PcMenu.mode == "deposit_qty" then
    Window.stdFrame(Window.template(17, 8, 12, 4))
    love.graphics.setColor(220 / 255, 60 / 255, 30 / 255, 1)
    Window.printPx("▲", 152, 60)
    Window.printPx("▼", 152, 92)
    love.graphics.setColor(1, 1, 1, 1)
    local qStr = string.format("×%02d", PcMenu.itemQty)
    Window.printPx(qStr, 142, 74, { small = true })

    Window.dialogueFrame()
    if PcMenu._status then Window.printPx(PcMenu._status, 16, 120) end
    return
  end

  -- Toss Confirm Dialogue
  if PcMenu.mode == "toss_confirm" then
    Window.dialogueFrame()
    if PcMenu._status then Window.printPx(PcMenu._status, 16, 120) end
    Window.stdFrame(Window.template(21, 8, 6, 4))
    Window.printPx("YES", 184, 68)
    Window.printPx("NO", 184, 84)
    Window.cursorPx(174, PcMenu.yesNoCursor == 1 and 68 or 84)
    return
  end

  -- Plain Message Box
  if PcMenu.mode == "msg" then
    Window.dialogueFrame()
    if PcMenu._status then Window.printPx(PcMenu._status, 16, 120) end
    return
  end
end

return PcMenu
