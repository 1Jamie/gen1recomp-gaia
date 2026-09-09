-- Party menu — pret PARTY_LAYOUT_SINGLE (windows + FONT_SMALL + OAM sprites).

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local PartyChrome = require("src.ui.game3.party_chrome")
local Pokemon = require("src.core.game3.pokemon")
local Display = require("src.core.game3.display")
local Oam = require("src.core.game3.oam")
local SummaryMenu = require("src.ui.game3.summary_menu")
local ItemUse = require("src.core.game3.item_use")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")

local PartyMenu = {}

PartyMenu.open = false
PartyMenu.cursor = 1
PartyMenu.mode = "list" -- "list" | "action" | "item_action" | "switch" | "summary" | "use" | "give" | "message"
PartyMenu.actionCursor = 1
PartyMenu.itemActionCursor = 1
PartyMenu.switchFrom = nil
PartyMenu.summaryPage = 1
PartyMenu.ACTIONS = { "SUMMARY", "SWITCH", "ITEM", "CANCEL" }
PartyMenu.ITEM_ACTIONS = { "GIVE", "TAKE", "CANCEL" }
PartyMenu._oam = nil -- per-slot { mon, ball, status } sprite ids
PartyMenu._summaryIcon = nil
PartyMenu._messageText = nil
PartyMenu._onMessageDismiss = nil
PartyMenu._item = nil
PartyMenu._bag = nil

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

-- pret sSinglePartyMenuWindowTemplate
local SLOT_WIN = {
  { left = 1, top = 3, w = 10, h = 7, kind = "main" },
  { left = 12, top = 1, w = 18, h = 3, kind = "wide" },
  { left = 12, top = 4, w = 18, h = 3, kind = "wide" },
  { left = 12, top = 7, w = 18, h = 3, kind = "wide" },
  { left = 12, top = 10, w = 18, h = 3, kind = "wide" },
  { left = 12, top = 13, w = 18, h = 3, kind = "wide" },
}

-- pret sPartyMenuSpriteCoords[PARTY_LAYOUT_SINGLE]
-- monX, monY, itemX, itemY, statusX, statusY, ballX, ballY  (CENTER coords)
local SLOT_SPRITES = {
  { 16, 40, 20, 50, 56, 52, 16, 34 },
  { 104, 18, 108, 28, 144, 27, 102, 25 },
  { 104, 42, 108, 52, 144, 51, 102, 49 },
  { 104, 66, 108, 76, 144, 75, 102, 73 },
  { 104, 90, 108, 100, 144, 99, 102, 97 },
  { 104, 114, 108, 124, 144, 123, 102, 121 },
}

-- pret sPartyBoxInfoRects — x,y relative to window
local INFO_LEFT = {
  nick = { 24, 11 }, level = { 32, 20 }, gender = { 64, 20 },
  hp = { 38, 36 }, hpMax = { 53, 36 }, hpBar = { 24, 35 },
}
local INFO_RIGHT = {
  nick = { 22, 3 }, level = { 32, 12 }, gender = { 64, 12 },
  hp = { 102, 12 }, hpMax = { 117, 12 }, hpBar = { 88, 10 },
}

local function party_print(text, px, py, maxW)
  FrlgFont.draw(tostring(text or ""), px, py, {
    maxWidth = maxW or 40,
    colors = FrlgFont.COLOR.PARTY,
    small = true,
  })
end

local function right_align_3(n)
  n = math.floor(tonumber(n) or 0)
  if n < 0 then n = 0 end
  if n > 999 then n = 999 end
  return string.format("%3d", n)
end

local function destroy_id(id)
  if id ~= nil then Oam.destroySprite(id) end
end

local function destroy_party_oam()
  local slots = PartyMenu._oam
  if slots then
    for i = 1, 6 do
      local s = slots[i]
      if s then
        destroy_id(s.mon)
        destroy_id(s.ball)
        destroy_id(s.status)
      end
    end
  end
  destroy_id(PartyMenu._summaryIcon)
  PartyMenu._oam = nil
  PartyMenu._summaryIcon = nil
end

local SUB_STATUS = 0
local SUB_BALL = 4
local SUB_MON = 8

local function idle_mon_offset(slotIndex)
  local spr = SLOT_SPRITES[slotIndex]
  if spr and spr[1] == 16 then
    return 0, -4
  end
  return -4, 0
end

local function SpriteCB_BouncePartyMonIcon(sprite)
  sprite.data[1] = (sprite.data[1] or 0) + 1
  if sprite.data[1] % 8 == 0 then
    sprite.data[2] = 1 - (sprite.data[2] or 0)
  end
  sprite.x2 = 0
  if (sprite.data[2] or 0) == 0 then
    sprite.y2 = -3
  else
    sprite.y2 = 1
  end
end

local function ensure_slot_sprites(i, mon, selected)
  PartyMenu._oam = PartyMenu._oam or {}
  local slot = PartyMenu._oam[i]
  if not slot then
    slot = {}
    PartyMenu._oam[i] = slot
  end
  local spr = SLOT_SPRITES[i]
  if not spr or not mon then
    destroy_id(slot.mon); slot.mon = nil
    destroy_id(slot.ball); slot.ball = nil
    destroy_id(slot.status); slot.status = nil
    return
  end

  local mx, my = spr[1], spr[2]
  local bx, by = spr[7], spr[8]
  local sx, sy = spr[5], spr[6]

  local icon = Pokemon.icon(Pokemon.speciesOf(mon))
  if not slot.mon then
    local id = select(1, Oam.createSprite({
      dims = Oam.SQUARE_32,
      priority = 1,
      image = icon and icon.image,
      animPaused = true,
    }, mx, my, SUB_MON))
    slot.mon = id
  else
    Oam.setPos(slot.mon, mx, my)
    if icon and icon.image then Oam.setImage(slot.mon, icon.image, nil) end
    local ms = Oam.get(slot.mon)
    if ms then ms.subpriority = SUB_MON end
  end
  if slot.mon then
    if selected then
      Oam.setCallback(slot.mon, SpriteCB_BouncePartyMonIcon)
      if not slot._wasSelected then
        Oam.setOffset(slot.mon, 0, 0)
        local s = Oam.get(slot.mon)
        if s then s.data[1], s.data[2] = 0, 0 end
      end
      slot._wasSelected = true
    else
      Oam.setCallback(slot.mon, nil)
      local x2, y2 = idle_mon_offset(i)
      Oam.setOffset(slot.mon, x2, y2)
      slot._wasSelected = false
    end
    Oam.setInvisible(slot.mon, PartyMenu.mode == "summary")
  end

  local balls = PartyChrome.ballEntry()
  local ballFrame = selected and 1 or 0
  local bq = balls and balls.quads and balls.quads[ballFrame]
  if not slot.ball then
    local id = select(1, Oam.createSprite({
      dims = Oam.SQUARE_32,
      priority = 1,
      image = balls and balls.image,
      quad = bq,
    }, bx, by, SUB_BALL))
    slot.ball = id
  else
    Oam.setPos(slot.ball, bx, by)
    if balls and balls.image then Oam.setImage(slot.ball, balls.image, bq) end
    local bs = Oam.get(slot.ball)
    if bs then bs.subpriority = SUB_BALL end
  end
  if slot.ball then
    Oam.setOffset(slot.ball, 0, 0)
    Oam.setInvisible(slot.ball, PartyMenu.mode == "summary")
  end

  local statusFr = PartyChrome.statusFrameFor(mon.status)
  local stImg, stQ = PartyChrome.statusEntry(statusFr)
  if statusFr > 0 and stImg then
    if not slot.status then
      local id = select(1, Oam.createSprite({
        dims = Oam.HRECT_32x8,
        priority = 1,
        image = stImg,
        quad = stQ,
      }, sx, sy, SUB_STATUS))
      slot.status = id
    else
      Oam.setPos(slot.status, sx, sy)
      Oam.setImage(slot.status, stImg, stQ)
      local ss = Oam.get(slot.status)
      if ss then ss.subpriority = SUB_STATUS end
    end
    if slot.status then
      Oam.setInvisible(slot.status, PartyMenu.mode == "summary")
    end
  else
    destroy_id(slot.status)
    slot.status = nil
  end
end

local function sync_all_oam()
  local party = PartyMenu._party or {}
  for i = 1, 6 do
    local mon = party[i]
    local selected = (i == PartyMenu.cursor or PartyMenu.switchFrom == i)
    ensure_slot_sprites(i, mon, selected)
  end
end

function PartyMenu.show(sessionParty, moveOverlay, opts)
  if type(moveOverlay) == "table" and opts == nil and (moveOverlay.mode or moveOverlay.session or moveOverlay.battle or moveOverlay.onSelect or moveOverlay.activeSlot) then
    opts = moveOverlay
    moveOverlay = nil
  end
  opts = opts or {}
  destroy_party_oam()
  PartyMenu.open = true
  PartyMenu._party = sessionParty or (opts.session and opts.session.party)
  PartyMenu._overlay = moveOverlay or (opts.session and (opts.session.move_overlay or opts.session.moveOverlay))
  PartyMenu._session = opts.session
  PartyMenu._bag = opts.bag or (opts.session and (opts.session.bag or opts.session.inventory))
  PartyMenu._item = opts.item
  PartyMenu._activeSlot = opts.activeSlot or 1
  PartyMenu._battle = opts.battle or (opts.mode == "battle_switch" or opts.mode == "battle_faint")
  PartyMenu.cursor = (opts.mode == "battle_switch" and PartyMenu._activeSlot == 1 and #(PartyMenu._party or {}) > 1) and 2 or 1
  PartyMenu.mode = opts.mode or "list"
  PartyMenu._previousMode = PartyMenu.mode
  PartyMenu.summaryPage = 1
  PartyMenu.switchFrom = nil
  PartyMenu._onClose = opts.onClose
  PartyMenu._onSelect = opts.onSelect
  PartyMenu._messageText = nil
  PartyMenu._onMessageDismiss = nil
  PartyMenu.actionCursor = 1
  PartyMenu.itemActionCursor = 1
  if not Pokemon._names then Pokemon.install(nil) end
  PartyChrome.install(nil)
  Stack.push("party", PartyMenu, { hideBelow = true })
  sync_all_oam()
end

function PartyMenu.close()
  PartyMenu.open = false
  destroy_party_oam()
  Stack.pop("party")
  local cb = PartyMenu._onClose
  PartyMenu._onClose = nil
  if cb then cb() end
end

function PartyMenu.movesFor(slot)
  local mon = PartyMenu._party and PartyMenu._party[slot]
  if not mon then return {} end
  local moves = {}
  local ov = PartyMenu._overlay and PartyMenu._overlay[slot]
  for i = 1, 4 do
    local o = ov and ov[i]
    if o and o.frlgMoveId then
      moves[i] = { id = o.frlgMoveId, pp = o.pp, quarantined = true }
    else
      moves[i] = {
        id = mon.moves and mon.moves[i],
        pp = mon.pp and mon.pp[i],
        quarantined = false,
      }
    end
  end
  return moves
end

function PartyMenu.isOpen()
  return PartyMenu.open
end

local function party_count()
  return #(PartyMenu._party or {})
end

local function swap_slots(a, b)
  if not PartyMenu._party or a == b then return end
  PartyMenu._party[a], PartyMenu._party[b] = PartyMenu._party[b], PartyMenu._party[a]
  if PartyMenu._overlay then
    PartyMenu._overlay[a], PartyMenu._overlay[b] =
      PartyMenu._overlay[b], PartyMenu._overlay[a]
  end
end

function PartyMenu.dismissMessage()
  if PartyMenu.mode == "message" then
    local cb = PartyMenu._onMessageDismiss
    PartyMenu._messageText = nil
    PartyMenu._onMessageDismiss = nil
    if cb then
      cb()
    else
      PartyMenu.mode = "list"
    end
  end
end

function PartyMenu.showMessage(text, onDismiss)
  PartyMenu.mode = "message"
  PartyMenu._messageText = text
  PartyMenu._onMessageDismiss = onDismiss
end

PartyMenu._hpAnim = nil

function PartyMenu.startHpAnim(slot, startHp, targetHp, maxHp, onDone)
  PartyMenu._hpAnim = {
    slot = slot,
    current = startHp,
    target = targetHp,
    maxHp = maxHp,
    speed = math.max(25, math.abs(targetHp - startHp) * 2.5),
    onDone = onDone,
  }
end

function PartyMenu.update(dt)
  local anim = PartyMenu._hpAnim
  if not anim then return end
  dt = dt or (1 / 60)
  if anim.current < anim.target then
    anim.current = math.min(anim.target, anim.current + anim.speed * dt)
  elseif anim.current > anim.target then
    anim.current = math.max(anim.target, anim.current - anim.speed * dt)
  end
  if anim.current == anim.target then
    local cb = anim.onDone
    PartyMenu._hpAnim = nil
    if cb then cb() end
  end
end

function PartyMenu.handleInput(input)
  local n = party_count()
  if n < 1 then
    if input:wasPressed("b") or input:wasPressed("start") or input:wasPressed("a") then
      PartyMenu.close()
    end
    return
  end

  -- Fast-forward / complete HP animation on button press
  if PartyMenu._hpAnim then
    if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
      local anim = PartyMenu._hpAnim
      anim.current = anim.target
      local cb = anim.onDone
      PartyMenu._hpAnim = nil
      if cb then cb() end
    end
    return
  end

  if PartyMenu.mode == "message" then
    if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") then
      se(5)
      PartyMenu.dismissMessage()
    end
    return
  end

  if PartyMenu.mode == "summary" then
    if not SummaryMenu.isOpen() then
      destroy_party_oam()
      SummaryMenu.openMenu(PartyMenu._party, PartyMenu.cursor, {
        session = PartyMenu._session,
        onClose = function()
          PartyMenu.mode = "list"
          sync_all_oam()
        end,
      })
    end
    SummaryMenu.handleInput(input)
    return
  end

  if PartyMenu.mode == "switch" then
    if input:wasPressed("up") then
      PartyMenu.cursor = ((PartyMenu.cursor - 2) % n) + 1
      se(5)
    elseif input:wasPressed("down") then
      PartyMenu.cursor = (PartyMenu.cursor % n) + 1
      se(5)
    elseif input:wasPressed("a") then
      se(5)
      swap_slots(PartyMenu.switchFrom or PartyMenu.cursor, PartyMenu.cursor)
      PartyMenu.switchFrom = nil
      PartyMenu.mode = "list"
    elseif input:wasPressed("b") then
      se(9)
      PartyMenu.switchFrom = nil
      PartyMenu.mode = "list"
    end
    return
  end

  if PartyMenu.mode == "item_action" then
    local actions = PartyMenu.ITEM_ACTIONS
    if input:wasPressed("up") then
      PartyMenu.itemActionCursor = ((PartyMenu.itemActionCursor - 2) % #actions) + 1
      se(5)
    elseif input:wasPressed("down") then
      PartyMenu.itemActionCursor = (PartyMenu.itemActionCursor % #actions) + 1
      se(5)
    elseif input:wasPressed("a") then
      local act = actions[PartyMenu.itemActionCursor]
      if act == "TAKE" then
        local ok, reason, msgText = ItemUse.takeFromMon(PartyMenu._session, PartyMenu._bag, PartyMenu.cursor)
        if ok then se(5) else se(9) end
        PartyMenu.showMessage(msgText, function()
          PartyMenu.mode = "list"
        end)
      elseif act == "GIVE" then
        local BagMenu = require("src.ui.game3.bag_menu")
        BagMenu.show(PartyMenu._session, {
          bag = PartyMenu._bag,
          onClose = function()
            PartyMenu.mode = "list"
          end,
        })
      else
        se(9)
        PartyMenu.mode = "list"
      end
    elseif input:wasPressed("b") then
      se(9)
      PartyMenu.mode = "list"
    end
    return
  end

  if PartyMenu.mode == "action" then
    local actions = PartyMenu.ACTIONS
    if input:wasPressed("up") then
      PartyMenu.actionCursor = ((PartyMenu.actionCursor - 2) % #actions) + 1
      se(5)
    elseif input:wasPressed("down") then
      PartyMenu.actionCursor = (PartyMenu.actionCursor % #actions) + 1
      se(5)
    elseif input:wasPressed("a") then
      local act = actions[PartyMenu.actionCursor]
      if act == "SHIFT" or (PartyMenu._previousMode == "battle_switch" and act == "SWITCH") then
        se(5)
        local cb = PartyMenu._onSelect
        local chosen = PartyMenu.cursor
        PartyMenu.close()
        if cb then cb(chosen, PartyMenu._party and PartyMenu._party[chosen]) end
      elseif act == "SUMMARY" then
        local prevMode = PartyMenu._previousMode or "list"
        PartyMenu.mode = "list"
        destroy_party_oam()
        SummaryMenu.openMenu(PartyMenu._party, PartyMenu.cursor, {
          session = PartyMenu._session,
          onClose = function()
            PartyMenu.mode = prevMode
            sync_all_oam()
          end,
        })
      elseif act == "SWITCH" then
        se(5)
        PartyMenu.switchFrom = PartyMenu.cursor
        PartyMenu.mode = "switch"
      elseif act == "ITEM" then
        se(5)
        PartyMenu.mode = "item_action"
        PartyMenu.itemActionCursor = 1
      else
        se(9)
        PartyMenu.mode = PartyMenu._previousMode or "list"
      end
    elseif input:wasPressed("b") then
      se(9)
      PartyMenu.mode = PartyMenu._previousMode or "list"
    end
    return
  end

  -- Battle switch mode
  if PartyMenu.mode == "battle_switch" then
    if input:wasPressed("up") then
      PartyMenu.cursor = ((PartyMenu.cursor - 2) % n) + 1
      se(5)
    elseif input:wasPressed("down") then
      PartyMenu.cursor = (PartyMenu.cursor % n) + 1
      se(5)
    elseif input:wasPressed("a") then
      local mon = PartyMenu._party and PartyMenu._party[PartyMenu.cursor]
      local activeSlot = PartyMenu._activeSlot or 1
      local hp = tonumber(mon and mon.hp) or 0
      local name = mon and Pokemon.displayName(mon) or "POKéMON"
      if PartyMenu.cursor == activeSlot then
        se(9)
        PartyMenu.showMessage(name .. " is already in\nbattle!", function()
          PartyMenu.mode = "battle_switch"
        end)
      elseif hp <= 0 then
        se(9)
        PartyMenu.showMessage("There's no will to\nfight!", function()
          PartyMenu.mode = "battle_switch"
        end)
      elseif mon and mon.isEgg then
        se(9)
        PartyMenu.showMessage("An EGG can't battle!", function()
          PartyMenu.mode = "battle_switch"
        end)
      else
        se(5)
        PartyMenu.ACTIONS = { "SHIFT", "SUMMARY", "CANCEL" }
        PartyMenu._previousMode = "battle_switch"
        PartyMenu.mode = "action"
        PartyMenu.actionCursor = 1
      end
    elseif input:wasPressed("b") or input:wasPressed("start") then
      se(9)
      PartyMenu.close()
    end
    return
  end

  -- Battle faint forced replacement mode
  if PartyMenu.mode == "battle_faint" then
    if input:wasPressed("up") then
      PartyMenu.cursor = ((PartyMenu.cursor - 2) % n) + 1
      se(5)
    elseif input:wasPressed("down") then
      PartyMenu.cursor = (PartyMenu.cursor % n) + 1
      se(5)
    elseif input:wasPressed("a") then
      local mon = PartyMenu._party and PartyMenu._party[PartyMenu.cursor]
      local activeSlot = PartyMenu._activeSlot
      local hp = tonumber(mon and mon.hp) or 0
      local name = mon and Pokemon.displayName(mon) or "POKéMON"
      if activeSlot and PartyMenu.cursor == activeSlot and hp <= 0 then
        se(9)
        PartyMenu.showMessage(name .. " has no will\nto fight!", function()
          PartyMenu.mode = "battle_faint"
        end)
      elseif hp <= 0 then
        se(9)
        PartyMenu.showMessage("There's no will to\nfight!", function()
          PartyMenu.mode = "battle_faint"
        end)
      elseif mon and mon.isEgg then
        se(9)
        PartyMenu.showMessage("An EGG can't battle!", function()
          PartyMenu.mode = "battle_faint"
        end)
      else
        se(5)
        PartyMenu.ACTIONS = { "SHIFT", "SUMMARY", "CANCEL" }
        PartyMenu._previousMode = "battle_faint"
        PartyMenu.mode = "action"
        PartyMenu.actionCursor = 1
      end
    elseif input:wasPressed("b") or input:wasPressed("start") then
      se(9)
      PartyMenu.showMessage("Choose a POKéMON.", function()
        PartyMenu.mode = "battle_faint"
      end)
    end
    return
  end

  -- Selection mode for item USE
  if PartyMenu.mode == "use" then
    if input:wasPressed("up") then
      PartyMenu.cursor = ((PartyMenu.cursor - 2) % n) + 1
      se(5)
    elseif input:wasPressed("down") then
      PartyMenu.cursor = (PartyMenu.cursor % n) + 1
      se(5)
    elseif input:wasPressed("a") then
      local mon = PartyMenu._party and PartyMenu._party[PartyMenu.cursor]
      if mon and mon.isEgg then
        se(9)
        PartyMenu.showMessage("An EGG can't be used on.", function()
          PartyMenu.mode = "use"
        end)
      else
        local startHp = tonumber(mon and mon.hp) or 0
        local maxHp = tonumber(mon and (mon.maxHp or mon.maxhp)) or 1
        local ok, reason, msgText = ItemUse.useField(PartyMenu._session, PartyMenu._bag, PartyMenu._item, PartyMenu.cursor)
        local endHp = tonumber(mon and mon.hp) or startHp
        if ok then
          se(2)
          local hasRemaining = Bag.has(PartyMenu._bag, PartyMenu._item, 1)
          local isSingleUse = ItemsData.isTm(PartyMenu._item) or ItemsData.isEvolutionStone(PartyMenu._item) or not hasRemaining
          if endHp > startHp then
            PartyMenu.startHpAnim(PartyMenu.cursor, startHp, endHp, maxHp, function()
              PartyMenu.showMessage(msgText, function()
                if isSingleUse then
                  PartyMenu.close()
                else
                  PartyMenu.mode = "use"
                end
              end)
            end)
          else
            PartyMenu.showMessage(msgText, function()
              if isSingleUse then
                PartyMenu.close()
              else
                PartyMenu.mode = "use"
              end
            end)
          end
        else
          se(9)
          PartyMenu.showMessage(msgText or "It won't have any effect.", function()
            PartyMenu.mode = "use"
          end)
        end
      end
    elseif input:wasPressed("b") or input:wasPressed("start") then
      se(9)
      PartyMenu.close()
    end
    return
  end

  -- Selection mode for item GIVE
  if PartyMenu.mode == "give" then
    if input:wasPressed("up") then
      PartyMenu.cursor = ((PartyMenu.cursor - 2) % n) + 1
      se(5)
    elseif input:wasPressed("down") then
      PartyMenu.cursor = (PartyMenu.cursor % n) + 1
      se(5)
    elseif input:wasPressed("a") then
      local mon = PartyMenu._party and PartyMenu._party[PartyMenu.cursor]
      if mon and mon.isEgg then
        se(9)
        PartyMenu.showMessage("An EGG can't hold an item.", function()
          PartyMenu.close()
        end)
      else
        local ok, reason, msgText = ItemUse.giveToMon(PartyMenu._session, PartyMenu._bag, PartyMenu._item, PartyMenu.cursor)
        if ok then se(5) else se(9) end
        PartyMenu.showMessage(msgText, function()
          PartyMenu.close()
        end)
      end
    elseif input:wasPressed("b") or input:wasPressed("start") then
      se(9)
      PartyMenu.close()
    end
    return
  end

  -- Selection mode for generic choose
  if PartyMenu.mode == "choose" then
    if input:wasPressed("up") then
      PartyMenu.cursor = ((PartyMenu.cursor - 2) % n) + 1
      se(5)
    elseif input:wasPressed("down") then
      PartyMenu.cursor = (PartyMenu.cursor % n) + 1
      se(5)
    elseif input:wasPressed("a") then
      se(5)
      local cb = PartyMenu._onSelect
      PartyMenu.close()
      if cb then cb(PartyMenu.cursor, PartyMenu._party and PartyMenu._party[PartyMenu.cursor]) end
    elseif input:wasPressed("b") or input:wasPressed("start") then
      se(9)
      PartyMenu.close()
    end
    return
  end

  -- Default list mode
  if input:wasPressed("up") then
    PartyMenu.cursor = ((PartyMenu.cursor - 2) % n) + 1
    se(5)
  elseif input:wasPressed("down") then
    PartyMenu.cursor = (PartyMenu.cursor % n) + 1
    se(5)
  elseif input:wasPressed("a") then
    se(5)
    local mon = PartyMenu._party and PartyMenu._party[PartyMenu.cursor]
    if mon and mon.isEgg then
      PartyMenu.ACTIONS = { "SUMMARY", "SWITCH", "CANCEL" }
    else
      PartyMenu.ACTIONS = { "SUMMARY", "SWITCH", "ITEM", "CANCEL" }
    end
    PartyMenu.mode = "action"
    PartyMenu.actionCursor = 1
  elseif input:wasPressed("b") or input:wasPressed("start") then
    se(9)
    PartyMenu.close()
  end
end

local function hp_bar(hp, maxHp, px, py, width)
  width = width or 48
  hp = tonumber(hp) or 0
  maxHp = tonumber(maxHp) or 1
  if maxHp < 1 then maxHp = 1 end
  local ratio = math.max(0, math.min(1, hp / maxHp))
  local w = math.floor(width * ratio)
  if w <= 0 then return end
  if ratio > 0.5 then
    love.graphics.setColor(0.25, 0.85, 0.25, 1)
  elseif ratio > 0.2 then
    love.graphics.setColor(0.95, 0.85, 0.15, 1)
  else
    love.graphics.setColor(0.95, 0.2, 0.15, 1)
  end
  love.graphics.rectangle("fill", px, py, w, 3)
  love.graphics.setColor(1, 1, 1, 1)
end

-- BG + text only; OAM sprites flushed by Display.present.
local function draw_filled_slot(i, mon, selected)
  local win = SLOT_WIN[i]
  if not win then return end
  local T = Display.TILE or 8
  local baseX, baseY = win.left * T, win.top * T
  local info = (i == 1) and INFO_LEFT or INFO_RIGHT

  PartyChrome.drawSlot(win.kind, win.left, win.top, selected)

  local name = Pokemon.displayName(mon)
  party_print(name, baseX + info.nick[1], baseY + info.nick[2], 40)
  party_print("Lv" .. tostring(mon.level or 0), baseX + info.level[1], baseY + info.level[2], 32)

  local hp = tonumber(mon.hp) or 0
  local maxHp = tonumber(mon.maxHp) or tonumber(mon.maxhp) or 0
  local anim = PartyMenu._hpAnim
  local displayHp = hp
  if anim and anim.slot == i then
    displayHp = math.floor(anim.current + 0.5)
  end
  party_print(right_align_3(displayHp) .. "/", baseX + info.hp[1], baseY + info.hp[2], 24)
  party_print("/" .. right_align_3(maxHp), baseX + info.hpMax[1], baseY + info.hpMax[2], 24)
  hp_bar(displayHp, maxHp, baseX + info.hpBar[1], baseY + info.hpBar[2], 48)
end

function PartyMenu.draw()
  if not PartyMenu.open then return end
  local party = PartyMenu._party or {}

  PartyChrome.drawBg()
  sync_all_oam()

  if PartyMenu.mode == "summary" then
    SummaryMenu.draw()
    return
  end

  destroy_id(PartyMenu._summaryIcon)
  PartyMenu._summaryIcon = nil

  for i = 1, 6 do
    local mon = party[i]
    local win = SLOT_WIN[i]
    if mon then
      draw_filled_slot(i, mon, i == PartyMenu.cursor or PartyMenu.switchFrom == i)
    elseif i > 1 and win then
      PartyChrome.drawSlot("empty", win.left, win.top, false)
    end
  end

  if PartyMenu.mode == "message" then
    Window.stdFrame(Window.template(1, 15, 28, 4))
    if PartyMenu._messageText then
      local wrapped = FrlgFont.wrap(PartyMenu._messageText, 216)
      FrlgFont.draw(wrapped, 1 * 8 + 6, 15 * 8 + 4, { maxWidth = 216, linePitch = 15, colors = FrlgFont.COLOR.NORMAL })
    end
  elseif PartyMenu.mode == "item_action" then
    Window.stdFrame(Window.template(2, 15, 15, 4))
    FrlgFont.draw("Do what with an\nitem?", 2 * 8 + 4, 15 * 8 + 2, { linePitch = 15, colors = FrlgFont.COLOR.NORMAL })

    local actCount = #PartyMenu.ITEM_ACTIONS
    local popW = 8
    local popH = actCount * 2
    local popX = 21
    local popY = 19 - popH
    Window.stdFrame(Window.template(popX, popY, popW, popH))
    for i, act in ipairs(PartyMenu.ITEM_ACTIONS) do
      local rowY = (popY * 8) + (i - 1) * 16 + 2
      if i == PartyMenu.itemActionCursor then
        Window.cursorPx(popX * 8 + 1, rowY)
      end
      FrlgFont.draw(act, popX * 8 + 9, rowY, { colors = FrlgFont.COLOR.NORMAL })
    end
  elseif PartyMenu.mode == "action" then
    Window.stdFrame(Window.template(2, 15, 15, 4))
    FrlgFont.draw("Do what with this\nPOKéMON?", 2 * 8 + 4, 15 * 8 + 2, { linePitch = 15, colors = FrlgFont.COLOR.NORMAL })

    local actCount = #PartyMenu.ACTIONS
    local popW = 10
    local popH = actCount * 2
    local popX = 19
    local popY = 19 - popH
    Window.stdFrame(Window.template(popX, popY, popW, popH))
    for i, act in ipairs(PartyMenu.ACTIONS) do
      local rowY = (popY * 8) + (i - 1) * 16 + 2
      if i == PartyMenu.actionCursor then
        Window.cursorPx(popX * 8 + 1, rowY)
      end
      FrlgFont.draw(act, popX * 8 + 9, rowY, { colors = FrlgFont.COLOR.NORMAL })
    end
  else
    Window.stdFrame(Window.template(1, 15, 28, 4))
    if PartyMenu.mode == "switch" then
      FrlgFont.draw("Move to where?", 1 * 8 + 6, 15 * 8 + 4, { colors = FrlgFont.COLOR.NORMAL })
    elseif PartyMenu.mode == "use" then
      if PartyMenu._item and ItemsData.isTm(PartyMenu._item) then
        FrlgFont.draw("Teach which POKéMON?", 1 * 8 + 6, 15 * 8 + 4, { colors = FrlgFont.COLOR.NORMAL })
      else
        FrlgFont.draw("Use on which POKéMON?", 1 * 8 + 6, 15 * 8 + 4, { colors = FrlgFont.COLOR.NORMAL })
      end
    elseif PartyMenu.mode == "give" then
      FrlgFont.draw("Give to which POKéMON?", 1 * 8 + 6, 15 * 8 + 4, { colors = FrlgFont.COLOR.NORMAL })
    else
      FrlgFont.draw("Choose a POKéMON.", 1 * 8 + 6, 15 * 8 + 4, { colors = FrlgFont.COLOR.NORMAL })
    end
  end
end

return PartyMenu
