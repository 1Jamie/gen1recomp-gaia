-- The player's item-storage PC (engine/menus/players_pc.asm):
-- WITHDRAW ITEM / DEPOSIT ITEM / TOSS ITEM / LOG OFF over
-- game.save.pcItems ({ ITEM_ID = count }; New Game seeds { POTION = 1 },
-- older saves may still be empty until first deposit).  Withdraw and
-- deposit ask "How many?" via the quantity selector (key items always
-- move one); toss discards after a YES/NO confirm.  Follows the
-- BoxMenu/BagMenu list idioms.

local ChoiceBox = require("src.ui.ChoiceBox")
local ListMenu = require("src.ui.ListMenu")
local Menu = require("src.ui.Menu")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
local romText = require("src.core.RomText")
local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")

local PlayerPC = { isMenu = true }

local function itemName(game, id)
  local def = game.data.items[id]
  return def and def.name or id
end

local function pcOrder(game)
  local save, pc = game.save, game.save.pcItems
  local order = type(save.pcOrder) == "table" and save.pcOrder or {}
  local kept, seen = {}, {}
  for _, id in ipairs(order) do
    if pc[id] and not seen[id] then kept[#kept + 1], seen[id] = id, true end
  end
  local added = {}
  for id in pairs(pc) do if not seen[id] then added[#added + 1] = id end end
  table.sort(added, function(a, b)
    local da, db = game.data.items[a], game.data.items[b]
    local ia = da and (da.index or da.itemId) or math.huge
    local ib = db and (db.index or db.itemId) or math.huge
    if ia ~= ib then
      if type(ia) == type(ib) then return ia < ib end
      return tostring(ia) < tostring(ib)
    end
    if type(a) == type(b) then return a < b end
    return tostring(a) < tostring(b)
  end)
  for _, id in ipairs(added) do kept[#kept + 1] = id end
  for i = #order, 1, -1 do order[i] = nil end
  for i, id in ipairs(kept) do order[i] = id end
  save.pcOrder = order
  return order
end

local function buildItems(game, store, order)
  local items = {}
  local ids = order
  if not ids then
    ids = {}
    for id in pairs(store) do table.insert(ids, id) end
    table.sort(ids)
  end
  for _, id in ipairs(ids) do
    if store[id] then
      local def = game.data.items[id]
      local keyItem = (def and def.keyItem) or id:find("^HM_") ~= nil
      table.insert(items, {
        value = id,
        label = itemName(game, id),
        count = not keyItem and store[id] or nil,
      })
    end
  end
  -- the $ff terminator's row (home/list_menu.asm:371-372, 523-528)
  items[#items + 1] = { cancel = true, label = Strings("CANCEL") }
  return items
end

-- A on CANCEL leaves the list exactly like B (home/list_menu.asm:105-110)
local function leftOnCancel(item, list)
  if item and item.cancel then
    list:close()
    return true
  end
  return false
end

-- Ask "How many?" (DepositHowManyText/WithdrawHowManyText →
-- DisplayChooseQuantityMenu) capped at the stack count.  Key items and
-- HMs always move one, with no prompt (IsKeyItem in players_pc.asm).
-- cb(qty) runs only on confirm.
local function askQuantity(game, list, count, id, cb)
  local def = game.data.items[id]
  if (def and def.keyItem) or id:find("^HM_") then
    cb(1)
    return
  end
  local prompt = list.footer
  list.footer = Strings("How many?")
  local QuantityBox = require("src.ui.QuantityBox")
  game.stack:push(QuantityBox.new(game, {
    max = count,
    onDone = function(qty)
      if qty then cb(qty) else list.footer = prompt end
    end,
  }))
end

-- refresh the chosen row's count from `store` (or drop the row)
local function refreshRow(list, store, id)
  for i, it in ipairs(list.items) do
    if it.value == id then
      if store[id] then
        it.count = store[id]
      else
        table.remove(list.items, i)
        list.index, list.scroll = 1, 0 -- engine/items/inventory.asm:131
      end
      break
    end
  end
  list.index = math.max(1, math.min(list.index, #list.items))
end

local function pcList(game, items, opts)
  local list = ListMenu.new(game, nil, items, opts)
  list.pcPrompt = list.footer
  list.pcCompletionBlink = 0
  local draw = list.draw
  list.draw = function(self)
    draw(self)
    if self.pcCompletion
       and self.pcCompletionBlink % 60 < 30 then
      Font.drawCode(Theme.moreArrow, 144, 128)
    end
  end
  local update = list.update
  list.update = function(self, dt)
    if self.pcCompletion then
      self.pcCompletionBlink = (self.pcCompletionBlink + 1) % 60
      local input = game.input
      if input:wasPressed("a") or input:wasPressed("b") then
        Sound.playPress(game.data)
        self.pcCompletion = nil
        local after = self.pcAfter
        self.pcAfter = nil
        if after then after() end
        self.footer = self.pcPrompt
      end
      return
    end
    update(self, dt)
  end
  function list:showCompletion(text, after)
    self.footer = text
    self.pcCompletion = true
    self.pcCompletionBlink = 0
    self.pcAfter = after
  end
  return list
end

local function withdraw(game)
  local pc = game.save.pcItems
  -- players_pc.asm:144-149: an empty list is never opened
  if next(pc) == nil then
    game.stack:push(TextBox.new(game, romText(game.data, "_NothingStoredText",
      "There is nothing\nstored."), nil, { noSound = true }))
    return
  end
  game.stack:push(pcList(game, buildItems(game, pc, pcOrder(game)), {
    kind = "pc_item_withdraw",
    messageBox = true,
    -- players_pc.asm:151-152 WhatToWithdrawText, printed before the list
    footer = romText(game.data, "_WhatToWithdrawText",
      "What do you want\nto withdraw?"),
    noSound = true, -- PlayerPCMenu holds BIT_NO_MENU_BUTTON_SOUND (#570)
    onChoose = function(item, list)
      if leftOnCancel(item, list) then return end
      list.hollowIndex = list.index -- home/list_menu.asm:91
      askQuantity(game, list, pc[item.value] or 1, item.value, function(qty)
        local Bag = require("src.inventory.Bag")
        if not Bag.add(game.save, item.value, qty, game.data) then
          list.footer = Strings("You can't carry\nany more items.")
          return
        end
        pc[item.value] = pc[item.value] - qty
        if pc[item.value] <= 0 then
          pc[item.value] = nil
          pcOrder(game)
        end
        Sound.play(game.data, "Withdraw_Deposit")
        list:showCompletion(romText(game.data, "_WithdrewItemText",
          "Withdrew\n%s.{PROMPT}", itemName(game, item.value)),
          function() refreshRow(list, pc, item.value) end) -- engine/menus/players_pc.asm:191
      end)
    end,
  }))
end

-- wNumBoxItems capacity: 50 stacks (PC_ITEM_CAPACITY)
local function pcFull(game, pc, id)
  if pc[id] then return false end -- growing an existing stack is fine
  local cap = game.data.field.pcItemCap or 50
  local stacks = 0
  for _ in pairs(pc) do stacks = stacks + 1 end
  return stacks >= cap
end

local function deposit(game)
  local pc = game.save.pcItems
  local inv = game.save.inventory
  local Bag = require("src.inventory.Bag")
  -- engine/menus/players_pc.asm:99 wListPointer = wNumBagItems, so deposit order == bag order
  local order = Bag.order(game.save, game.data)
  -- players_pc.asm:90-95: an empty bag never reaches the list
  if #order == 0 then
    game.stack:push(TextBox.new(game, romText(game.data, "_NothingToDepositText",
      "You have nothing\nto deposit."), nil, { noSound = true }))
    return
  end
  game.stack:push(pcList(game, buildItems(game, inv, order), {
    kind = "pc_item_deposit",
    messageBox = true,
    -- players_pc.asm:97-98 WhatToDepositText, printed before the list
    footer = romText(game.data, "_WhatToDepositText",
      "What do you want\nto deposit?"),
    noSound = true, -- PlayerPCMenu holds BIT_NO_MENU_BUTTON_SOUND (#570)
    onChoose = function(item, list)
      if leftOnCancel(item, list) then return end
      list.hollowIndex = list.index -- home/list_menu.asm:91
      askQuantity(game, list, inv[item.value] or 1, item.value, function(qty)
        if pcFull(game, pc, item.value) then
          list.footer = Strings("No room left to\nstore items.")
          return
        end
        if not pc[item.value] then
          local order = pcOrder(game)
          order[#order + 1] = item.value
        end
        require("src.inventory.Bag").remove(game.save, item.value, qty)
        pc[item.value] = (pc[item.value] or 0) + qty
        Sound.play(game.data, "Withdraw_Deposit")
        list:showCompletion(romText(game.data, "_ItemWasStoredText",
          "%s was\nstored via PC.{PROMPT}", itemName(game, item.value)),
          function() refreshRow(list, inv, item.value) end) -- engine/menus/players_pc.asm:137
      end)
    end,
  }))
end

local function toss(game)
  local pc = game.save.pcItems
  -- players_pc.asm:196-201: an empty list is never opened
  if next(pc) == nil then
    game.stack:push(TextBox.new(game, romText(game.data, "_NothingStoredText",
      "There is nothing\nstored."), nil, { noSound = true }))
    return
  end
  game.stack:push(pcList(game, buildItems(game, pc, pcOrder(game)), {
    kind = "pc_item_toss",
    messageBox = true,
    -- players_pc.asm:205-206 WhatToTossText, printed before the list
    footer = romText(game.data, "_WhatToTossText",
      "What do you want\nto toss away?"),
    noSound = true, -- PlayerPCMenu holds BIT_NO_MENU_BUTTON_SOUND (#570)
    onChoose = function(item, list)
      if leftOnCancel(item, list) then return end
      list.hollowIndex = list.index -- home/list_menu.asm:91
      local def = game.data.items[item.value]
      if (def and def.keyItem) or item.value:find("^HM_") then
        list.footer = Strings("That's too impor-\ntant to toss!")
        return
      end
      local QuantityBox = require("src.ui.QuantityBox")
      game.stack:push(QuantityBox.new(game, {
        max = pc[item.value] or 1,
        onDone = function(qty)
          if not qty then return end
          list.footer = Strings("Toss %s?", itemName(game, item.value))
          game.stack:push(ChoiceBox.new(game, function(yes)
            if yes then
              pc[item.value] = pc[item.value] - qty
              if pc[item.value] <= 0 then
                pc[item.value] = nil
                pcOrder(game)
              end
              list:showCompletion(romText(game.data, "_ThrewAwayItemText",
                "Threw away\n%s.{PROMPT}", itemName(game, item.value)),
                function() refreshRow(list, pc, item.value) end) -- engine/menus/players_pc.asm:240
            else
              list.footer = nil
            end
          end, { noSound = true }))
        end,
      }))
    end,
  }))
end

-- opts.direct marks the bedroom PC (OpenRedsPC), the one entry outside the main menu
function PlayerPC.new(game, opts)
  game.save.pcItems = game.save.pcItems or {}
  -- ExitPlayerPC (players_pc.asm) rings SFX_TURN_OFF_PC only while
  -- BIT_USING_GENERIC_PC is clear (#960)
  local logOff = function()
    if opts and opts.direct then Sound.play(game.data, "Turn_Off_PC") end
  end
  local rows = {
    -- keepOpen so B in the item lists returns here instead of dropping the
    -- whole PC session (players_pc.asm re-shows the PC menu); same pattern
    -- as BoxMenu's rows
    { label = Strings("WITHDRAW ITEM"), keepOpen = true, onSelect = function() withdraw(game) end },
    { label = Strings("DEPOSIT ITEM"), keepOpen = true, onSelect = function() deposit(game) end },
    { label = Strings("TOSS ITEM"), keepOpen = true, onSelect = function() toss(game) end },
    { label = Strings("LOG OFF"), onSelect = logOff },
  }
  -- silent PC session (BIT_NO_MENU_BUTTON_SOUND); players_pc.asm
  -- PlayersPCMenu TextBoxBorder (0,0) b=8 c=14 → 16x10
  local menu = Menu.new(game, rows, { tx = 0, ty = 0, tw = 16, th = 10,
       noSound = true, onCancel = logOff })
  local prompt = TextBox.strip(romText(game.data, "_WhatDoYouWantText",
    "What do you want\nto do?"))
  for _, row in ipairs(rows) do
    local onSelect = row.onSelect
    if row.keepOpen and onSelect then
      row.onSelect = function()
        menu.hollowIndex = menu.index -- engine/menus/players_pc.asm:55
        onSelect()
      end
    end
  end
  local baseUpdate = menu.update
  function menu:update(dt)
    if self.game.stack:top() == self then self.hollowIndex = nil end
    return baseUpdate(self, dt)
  end
  local baseDraw = menu.draw
  function menu:draw()
    baseDraw(self)
    Font.drawBox(0, 12, 20, 6) -- engine/menus/players_pc.asm:50
    love.graphics.setColor(0, 0, 0, 1)
    local y = 112
    for line in (prompt .. "\n"):gmatch("([^\n]*)\n") do
      Font.draw(line, 8, y)
      y = y + 16
    end
    love.graphics.setColor(1, 1, 1, 1)
  end
  menu.isMenu = true
  return menu
end

return PlayerPC
