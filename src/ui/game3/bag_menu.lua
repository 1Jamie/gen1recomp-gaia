-- FRLG Bag menu (item_menu.c field) — pockets, cursor, USE/TOSS/GIVE/REGISTER.
-- Layout matching pret GBA layout: left pocket & bag art + bottom icon/desc, right item list.

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local ItemUse = require("src.core.game3.item_use")

local BagMenu = {}

BagMenu.open = false
BagMenu.cursor = 1
BagMenu.pocketIdx = 1
BagMenu.scroll = 0
BagMenu.mode = "list" -- list | action | party | toss
BagMenu.actionCursor = 1
BagMenu.partyCursor = 1
BagMenu.partyPurpose = "use" -- use | give
BagMenu.tossQty = 1
BagMenu.ACTIONS = { "USE", "TOSS", "GIVE", "CANCEL" }

local VISIBLE = 6
local LIST_TOP = 1
local LIST_LEFT = 11
local LIST_W = 18
local LIST_H = 13

local function actions_for_pocket(pocket, row)
  if BagMenu._battle then
    return { "USE", "CANCEL" }
  end
  pocket = pocket or "ITEMS"
  local info = row and (row.info or ItemsData.info(row.id))
  local registrable = info and (tonumber(info.registrability) or 0) > 0
  if pocket == "KEY_ITEMS" then
    if registrable then
      return { "USE", "SET", "CANCEL" }
    end
    return { "USE", "CANCEL" }
  elseif pocket == "POKE_BALLS" then
    return { "GIVE", "TOSS", "CANCEL" }
  elseif pocket == "TM_CASE" then
    return { "USE", "CANCEL" }
  elseif pocket == "BERRY_POUCH" then
    return { "USE", "GIVE", "TOSS", "CANCEL" }
  end
  return { "USE", "GIVE", "TOSS", "CANCEL" }
end

function BagMenu.isOpen()
  return BagMenu.open
end

function BagMenu.currentPocket()
  return ItemsData.POCKET_ORDER[BagMenu.pocketIdx] or "ITEMS"
end

function BagMenu.list(pocket)
  pocket = pocket or BagMenu.currentPocket()
  local bag = BagMenu._bag
  if not bag then return {} end
  local rows
  if bag.pockets then
    rows = Bag.listPocket(bag, pocket)
  else
    if not bag.stacks then return {} end
    rows = {}
    for id, qty in pairs(bag.stacks) do
      if ItemsData.pocketOf(id) == pocket and qty and qty > 0 then
        rows[#rows + 1] = {
          id = id,
          qty = qty,
          name = ItemsData.displayName(id),
          info = ItemsData.info(id),
          description = ItemsData.description(id),
        }
      end
    end
    table.sort(rows, function(a, b)
      return tostring(a.name) < tostring(b.name)
    end)
  end
  if BagMenu._battle then
    if pocket == "KEY_ITEMS" or pocket == "TM_CASE" then
      return {}
    end
    local BattleItems = require("src.core.game3.battle.items")
    local filtered = {}
    for _, r in ipairs(rows) do
      if BattleItems.isBattleUsable(r.id) then
        filtered[#filtered + 1] = r
      end
    end
    return filtered
  end
  return rows
end

local function clamp_cursor()
  local rows = BagMenu.list()
  local n = #rows
  if n < 1 then
    BagMenu.cursor = 1
    BagMenu.scroll = 0
    return rows
  end
  if BagMenu.cursor > n then BagMenu.cursor = n end
  if BagMenu.cursor < 1 then BagMenu.cursor = 1 end
  if BagMenu.cursor <= BagMenu.scroll then
    BagMenu.scroll = BagMenu.cursor - 1
  end
  if BagMenu.cursor > BagMenu.scroll + VISIBLE then
    BagMenu.scroll = BagMenu.cursor - VISIBLE
  end
  if BagMenu.scroll < 0 then BagMenu.scroll = 0 end
  return rows
end

function BagMenu.show(sessionBag, opts)
  opts = opts or {}
  BagMenu.open = true
  if sessionBag and sessionBag.pockets then
    BagMenu._bag = sessionBag
    BagMenu._session = opts.session or (sessionBag.party and sessionBag)
  elseif sessionBag and (sessionBag.bag or sessionBag.party) then
    BagMenu._bag = sessionBag.bag or opts.bag
    BagMenu._session = opts.session or sessionBag
  else
    BagMenu._bag = opts.bag or sessionBag
    BagMenu._session = opts.session or (type(sessionBag) == "table" and sessionBag.party and sessionBag)
  end
  BagMenu._battle = opts.battle and true or false
  BagMenu._onBattleUse = opts.onBattleUse
  BagMenu.cursor = 1
  BagMenu.pocketIdx = opts.pocketIdx or 1
  BagMenu.scroll = 0
  BagMenu.mode = "list"
  BagMenu.partyPurpose = "use"
  BagMenu.tossQty = 1
  BagMenu._onClose = opts.onClose
  if opts.pocket then
    for i, p in ipairs(ItemsData.POCKET_ORDER) do
      if p == opts.pocket then BagMenu.pocketIdx = i; break end
    end
  elseif BagMenu._battle then
    BagMenu.pocketIdx = 1
  end
  clamp_cursor()
  Stack.push("bag", BagMenu, { hideBelow = not BagMenu._battle })
end

function BagMenu.close()
  BagMenu.open = false
  local battleCb = BagMenu._onBattleUse
  local wasBattle = BagMenu._battle
  BagMenu._battle = false
  BagMenu._onBattleUse = nil
  Stack.pop("bag")
  local cb = BagMenu._onClose
  BagMenu._onClose = nil
  if cb then cb() end
  if wasBattle and battleCb and not BagMenu._battleUsed then
    battleCb(nil)
  end
  BagMenu._battleUsed = nil
end

local function refresh_actions()
  local rows = BagMenu.list()
  local row = rows[BagMenu.cursor]
  BagMenu.ACTIONS = actions_for_pocket(BagMenu.currentPocket(), row)
  if BagMenu.actionCursor > #BagMenu.ACTIONS then
    BagMenu.actionCursor = 1
  end
end

function BagMenu.handleInput(input)
  local function se(id)
    pcall(function() require("src.core.game3.audio").playSe(id) end)
  end

  if BagMenu.mode == "toss" then
    local rows = BagMenu.list()
    local row = rows[BagMenu.cursor]
    local maxQ = row and (tonumber(row.qty) or 1) or 1
    if input:wasPressed("up") or input:wasPressed("right") then
      BagMenu.tossQty = math.min(maxQ, BagMenu.tossQty + 1)
      se(5)
    elseif input:wasPressed("down") or input:wasPressed("left") then
      BagMenu.tossQty = math.max(1, BagMenu.tossQty - 1)
      se(5)
    elseif input:wasPressed("a") then
      se(5)
      if row then
        Bag.remove(BagMenu._bag, row.id, BagMenu.tossQty)
      end
      BagMenu.mode = "list"
      clamp_cursor()
    elseif input:wasPressed("b") then
      se(9)
      BagMenu.mode = "action"
    end
    return
  end

  if BagMenu.mode == "message" then
    if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
      se(5)
      BagMenu.mode = "list"
      BagMenu.messageText = nil
      clamp_cursor()
    end
    return
  end

  if BagMenu.mode == "action" then
    refresh_actions()
    if input:wasPressed("up") then
      BagMenu.actionCursor = ((BagMenu.actionCursor - 2) % #BagMenu.ACTIONS) + 1
      se(5)
    elseif input:wasPressed("down") then
      BagMenu.actionCursor = (BagMenu.actionCursor % #BagMenu.ACTIONS) + 1
      se(5)
    elseif input:wasPressed("a") then
      se(5)
      local act = BagMenu.ACTIONS[BagMenu.actionCursor]
      local rows = clamp_cursor()
      local row = rows[BagMenu.cursor]
      local party = (BagMenu._session and BagMenu._session.party) or {}
      if act == "CANCEL" or not row then
        BagMenu.mode = "list"
      elseif act == "USE" then
        if BagMenu._battle and BagMenu._onBattleUse then
          local BattleItems = require("src.core.game3.battle.items")
          if BattleItems.needsPartySelect(row.id) then
            local PartyMenu = require("src.ui.game3.party_menu")
            PartyMenu.show(party, BagMenu._session and BagMenu._session.moveOverlay, {
              session = BagMenu._session,
              bag = BagMenu._bag,
              item = row.id,
              mode = "use",
              onClose = function()
                BagMenu.mode = "list"
                clamp_cursor()
              end,
            })
          else
            local cb = BagMenu._onBattleUse
            BagMenu._battleUsed = true
            BagMenu.open = false
            BagMenu._battle = false
            BagMenu._onBattleUse = nil
            Stack.pop("bag")
            cb(row.id, nil)
            return
          end
        else
          if ItemUse.needsPartyTarget(row.id) then
            if #party == 0 then
              BagMenu.mode = "message"
              BagMenu.messageText = "There is no POKéMON."
            else
              local PartyMenu = require("src.ui.game3.party_menu")
              PartyMenu.show(party, BagMenu._session and BagMenu._session.moveOverlay, {
                session = BagMenu._session,
                bag = BagMenu._bag,
                item = row.id,
                mode = "use",
                onClose = function()
                  BagMenu.mode = "list"
                  clamp_cursor()
                end,
              })
            end
          else
            ItemUse.useField(BagMenu._session, BagMenu._bag, row.id, nil)
            BagMenu.mode = "list"
            clamp_cursor()
          end
        end
      elseif act == "GIVE" then
        local pocket = BagMenu.currentPocket()
        if pocket == "KEY_ITEMS" or pocket == "TM_CASE" then
          BagMenu.mode = "message"
          BagMenu.messageText = "This item can't be held."
        elseif #party == 0 then
          BagMenu.mode = "message"
          BagMenu.messageText = "There is no POKéMON."
        else
          local PartyMenu = require("src.ui.game3.party_menu")
          PartyMenu.show(party, BagMenu._session and BagMenu._session.moveOverlay, {
            session = BagMenu._session,
            bag = BagMenu._bag,
            item = row.id,
            mode = "give",
            onClose = function()
              BagMenu.mode = "list"
              clamp_cursor()
            end,
          })
        end
      elseif act == "TOSS" then
        BagMenu.mode = "toss"
        BagMenu.tossQty = 1
      elseif act == "SET" or act == "REGISTER" then
        if BagMenu._session and row then
          if BagMenu._session.registeredItem == row.id then
            BagMenu._session.registeredItem = nil
          else
            BagMenu._session.registeredItem = row.id
          end
        end
        BagMenu.mode = "list"
      end
    elseif input:wasPressed("b") then
      se(9)
      BagMenu.mode = "list"
    end
    return
  end

  -- Battle pocket navigation restriction
  if BagMenu._battle then
    local order = { "ITEMS", "POKE_BALLS", "BERRY_POUCH" }
    if input:wasPressed("left") or input:wasPressed("l") then
      local cur = BagMenu.currentPocket()
      local idx = 1
      for i, p in ipairs(order) do if p == cur then idx = i break end end
      idx = ((idx - 2) % #order) + 1
      for i, p in ipairs(ItemsData.POCKET_ORDER) do
        if p == order[idx] then BagMenu.pocketIdx = i break end
      end
      BagMenu.cursor = 1
      BagMenu.scroll = 0
      se(5)
      return
    elseif input:wasPressed("right") or input:wasPressed("r") then
      local cur = BagMenu.currentPocket()
      local idx = 1
      for i, p in ipairs(order) do if p == cur then idx = i break end end
      idx = (idx % #order) + 1
      for i, p in ipairs(ItemsData.POCKET_ORDER) do
        if p == order[idx] then BagMenu.pocketIdx = i break end
      end
      BagMenu.cursor = 1
      BagMenu.scroll = 0
      se(5)
      return
    end
  end

  -- list mode
  if input:wasPressed("left") or input:wasPressed("l") then
    BagMenu.pocketIdx = ((BagMenu.pocketIdx - 2) % #ItemsData.POCKET_ORDER) + 1
    BagMenu.cursor = 1
    BagMenu.scroll = 0
    se(5)
  elseif input:wasPressed("right") or input:wasPressed("r") then
    BagMenu.pocketIdx = (BagMenu.pocketIdx % #ItemsData.POCKET_ORDER) + 1
    BagMenu.cursor = 1
    BagMenu.scroll = 0
    se(5)
  elseif input:wasPressed("up") then
    local rows = clamp_cursor()
    if #rows > 0 then
      BagMenu.cursor = ((BagMenu.cursor - 2) % #rows) + 1
      clamp_cursor()
      se(5)
    end
  elseif input:wasPressed("down") then
    local rows = clamp_cursor()
    if #rows > 0 then
      BagMenu.cursor = (BagMenu.cursor % #rows) + 1
      clamp_cursor()
      se(5)
    end
  elseif input:wasPressed("a") then
    local rows = clamp_cursor()
    if #rows > 0 then
      BagMenu.mode = "action"
      BagMenu.actionCursor = 1
      refresh_actions()
      se(5)
    end
  elseif input:wasPressed("b") or input:wasPressed("start") then
    se(9)
    BagMenu.close()
  end
end

function BagMenu.draw()
  if not BagMenu.open then return end
  local pocket = BagMenu.currentPocket()
  local rows = clamp_cursor()

  local okC, BagChrome = pcall(require, "src.ui.game3.bag_chrome")
  local chrome = okC and BagChrome and BagChrome.ready and BagChrome.ready()
  if chrome then
    BagChrome.drawBg(0, 0)
    local female = false
    local session = BagMenu._session
    if session and (session.gender == 1 or session.gender == "female"
        or session.playerGender == 1) then
      female = true
    end
    BagChrome.drawBag(8, 36, { female = female, pocketIdx = BagMenu.pocketIdx })
  end

  -- Pocket Name Header (left pane: 72px wide box at x=8, y=8, text centered at y=9)
  local pLabel = ItemsData.POCKET_LABEL[pocket] or pocket
  local tw = FrlgFont.measure(pLabel)
  local px = 8 + math.floor((72 - tw) / 2)
  FrlgFont.draw(pLabel, px, 9, { colors = FrlgFont.COLOR.NORMAL })
  -- Pocket switch indicators (GBA OAM scroll arrows at x=8 and x=72, y=70)
  FrlgFont.draw("◀", 8, 68, { colors = FrlgFont.COLOR.DARK_GRAY })
  FrlgFont.draw("▶", 74, 68, { colors = FrlgFont.COLOR.DARK_GRAY })

  -- Right List Pane (Window 0: x=88, y=8, item rows at y = 10 + (i-1)*16)
  if not chrome then
    Window.stdFrame(Window.template(LIST_LEFT, LIST_TOP, LIST_W, LIST_H))
  end
  if #rows < 1 then
    Window.printPx("No items.", 97, 10)
  else
    -- Scroll Up indicator (x=224, y=10)
    if BagMenu.scroll > 0 then
      FrlgFont.draw("▲", 224, 10, { colors = FrlgFont.COLOR.DARK_GRAY })
    end
    -- Scroll Down indicator (x=224, y=90)
    if BagMenu.scroll + VISIBLE < #rows then
      FrlgFont.draw("▼", 224, 90, { colors = FrlgFont.COLOR.DARK_GRAY })
    end

    for i = 1, VISIBLE do
      local idx = BagMenu.scroll + i
      local r = rows[idx]
      if not r then break end
      local y = 10 + (i - 1) * 16
      if idx == BagMenu.cursor and BagMenu.mode == "list" then
        Window.cursorPx(89, y)
      end
      local label = r.name
      local session = BagMenu._session
      if session and session.registeredItem
          and ItemsData.toNumericId(session.registeredItem) == ItemsData.toNumericId(r.id) then
        label = "►" .. label
      end
      FrlgFont.draw(label, 97, y, { maxWidth = 96, colors = FrlgFont.COLOR.NORMAL })
      if pocket ~= "KEY_ITEMS" and pocket ~= "TM_CASE" then
        FrlgFont.draw(string.format("×%2d", r.qty or 1), 198, y, { colors = FrlgFont.COLOR.NORMAL })
      end
    end
  end

  -- Bottom-left Item Icon Viewport (top-left of 32x32 viewport at (8,124))
  local sel = rows[BagMenu.cursor]
  if chrome and sel then
    BagChrome.drawItemIcon(sel.id, 8, 124)
  end

  -- Bottom Description Window (Window 1: tile (5,14) -> px (40,112), text at (40,115))
  if BagMenu.mode ~= "action" then
    if not chrome then
      Window.stdFrame(Window.template(5, 14, 25, 6))
    end
    if sel and sel.description then
      local desc = FrlgFont.wrap(sel.description, 192)
      FrlgFont.draw(desc, 40, 115, { maxWidth = 192, linePitch = 15, colors = FrlgFont.COLOR.NORMAL })
    end
  end

  -- Action Pop-up Menu (pret bag.c: tilemapLeft = 22, tilemapTop = 19 - actCount * 2, width = 7, height = actCount * 2)
  if BagMenu.mode == "action" then
    -- Bottom left prompt window (pret bag.c: sWindowTemplates[6] = (6, 15, 14, 4))
    if sel then
      Window.stdFrame(Window.template(6, 15, 14, 4))
      FrlgFont.draw((sel.name or "ITEM") .. " is\nselected.", 6 * 8 + 4, 15 * 8 + 2, { maxWidth = 14 * 8, linePitch = 15, colors = FrlgFont.COLOR.NORMAL })
    end

    refresh_actions()
    local actCount = #BagMenu.ACTIONS
    local popW = 7
    local popH = actCount * 2
    local popX = 22
    local popY = 19 - popH
    Window.stdFrame(Window.template(popX, popY, popW, popH))
    for i, act in ipairs(BagMenu.ACTIONS) do
      local rowY = (popY * 8) + (i - 1) * 16 + 2
      if i == BagMenu.actionCursor then
        Window.cursorPx(popX * 8 + 1, rowY)
      end
      FrlgFont.draw(act, popX * 8 + 9, rowY, { colors = FrlgFont.COLOR.NORMAL })
    end
  end

  -- Toss Quantity Pop-up
  if BagMenu.mode == "toss" and sel then
    local popX = 16
    local popY = 10
    local popW = 12
    local popH = 4
    Window.stdFrame(Window.template(popX, popY, popW, popH))
    FrlgFont.draw("TOSS HOW MANY?", popX * 8 + 4, popY * 8 + 2, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(string.format("× %02d", BagMenu.tossQty), popX * 8 + 24, (popY + 2) * 8 + 2, { colors = FrlgFont.COLOR.NORMAL })
  end

  -- In-bag message modal
  if BagMenu.mode == "message" and BagMenu.messageText then
    Window.stdFrame(Window.template(5, 14, 25, 6))
    local wrapped = FrlgFont.wrap(BagMenu.messageText, 192)
    FrlgFont.draw(wrapped, 40, 115, { maxWidth = 192, linePitch = 15, colors = FrlgFont.COLOR.NORMAL })
  end
end

return BagMenu
