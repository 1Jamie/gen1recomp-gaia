-- Pokémon Summary Screen Menu for Game3.
-- 1:1 replication of Pokémon FireRed summary screen:
-- Pages: INFO (0), SKILLS (1), MOVES (2), MOVES_INFO (3), EGG (4).
-- Features: Animated page slide (with anchored foreground), full move swapping (anti-PP swap trap),
-- dynamic trainer memo diffing, and ROM-baked chrome graphics.

local Display = require("src.core.game3.display")
local Stack = require("src.ui.game3.stack")
local FrlgFont = require("src.ui.game3.frlg_font")
local Pokemon = require("src.core.game3.pokemon")
local SummaryChrome = require("src.ui.game3.summary_chrome")
local SummaryData = require("src.core.game3.summary_data")

local SummaryMenu = {}

SummaryMenu.open = false
SummaryMenu._party = nil
SummaryMenu._cursor = 1
SummaryMenu._page = 0
SummaryMenu._moveCursor = 1
SummaryMenu._swapSlot = nil
SummaryMenu._onClose = nil
SummaryMenu._playerState = nil
SummaryMenu._slide = {
  active = false,
  direction = 0,
  timer = 0,
  duration = 0.12,
  prevPage = 0,
}

local PAGE_INFO = 0
local PAGE_SKILLS = 1
local PAGE_MOVES = 2
local PAGE_MOVES_INFO = 3
local PAGE_EGG = 4

local STAT_COLORS = {
  NORMAL = FrlgFont.COLOR.NORMAL,
  UP = { fg = { 210 / 255, 60 / 255, 60 / 255, 1 }, shadow = { 240 / 255, 200 / 255, 200 / 255, 1 } },
  DOWN = { fg = { 60 / 255, 90 / 255, 210 / 255, 1 }, shadow = { 200 / 255, 210 / 255, 240 / 255, 1 } },
}

local function current_mon()
  if not SummaryMenu._party then return nil end
  return SummaryMenu._party[SummaryMenu._cursor]
end

local function party_count()
  return #(SummaryMenu._party or {})
end

local function moves_for_mon(mon)
  if not mon then return {} end
  local out = {}
  local rawMoves = mon.moves or {}
  local rawPp = mon.pp or {}

  for i = 1, 4 do
    local entry = rawMoves[i]
    local moveId, pp, maxPp, mdef
    if type(entry) == "table" then
      moveId = entry.id or entry.move or entry.moveId or entry.num or entry.name or entry[1]
      pp = entry.pp
    else
      moveId = entry
      pp = rawPp[i]
    end

    if moveId and (type(moveId) ~= "number" or moveId > 0) and moveId ~= "" and moveId ~= "-------" then
      mdef = Pokemon.battleMove(moveId)
      maxPp = (mdef and mdef.pp) or 5
      if not pp then pp = maxPp end
      local name = Pokemon.moveName(moveId)
      if not name or name == "" or name:match("^MOVE ") then
        name = (mdef and mdef.name) or name or ("MOVE " .. tostring(moveId))
      end
      local mType = (mdef and (mdef.type or mdef.kind)) or "NORMAL"
      local power = (mdef and mdef.power and mdef.power > 0) and tostring(mdef.power) or "---"
      local acc = (mdef and mdef.accuracy and mdef.accuracy > 0) and tostring(mdef.accuracy) or "---"
      out[i] = {
        id = moveId,
        name = name,
        pp = pp,
        maxPp = maxPp,
        type = mType,
        power = power,
        accuracy = acc,
      }
    end
  end
  return out
end

function SummaryMenu.isOpen()
  return SummaryMenu.open
end

function SummaryMenu.openMenu(party, startIndex, opts)
  opts = opts or {}
  SummaryMenu.open = true
  SummaryMenu._party = party or {}
  SummaryMenu._cursor = math.max(1, math.min(#SummaryMenu._party, tonumber(startIndex) or 1))
  SummaryMenu._playerState = opts.playerState or opts.session
  SummaryMenu._context = opts.context or "party"
  SummaryMenu._onClose = opts.onClose
  SummaryMenu._moveCursor = 1
  SummaryMenu._swapSlot = nil
  SummaryMenu._slide.active = false

  local mon = current_mon()
  if mon and mon.isEgg then
    SummaryMenu._page = PAGE_EGG
  else
    SummaryMenu._page = tonumber(opts.page) or PAGE_INFO
  end

  SummaryChrome.install(opts.cache)
  Stack.push("summary", SummaryMenu, { hideBelow = true })
end

function SummaryMenu.close()
  SummaryMenu.open = false
  SummaryMenu._slide.active = false
  SummaryMenu._swapSlot = nil
  Stack.pop("summary")
  if SummaryMenu._onClose then
    local cb = SummaryMenu._onClose
    SummaryMenu._onClose = nil
    cb()
  end
end

local function change_mon(delta)
  local n = party_count()
  if n <= 1 then return end
  local nextCursor = ((SummaryMenu._cursor - 1 + delta) % n) + 1
  SummaryMenu._cursor = nextCursor
  SummaryMenu._moveCursor = 1
  SummaryMenu._swapSlot = nil
  local mon = current_mon()
  if mon and mon.isEgg then
    SummaryMenu._page = PAGE_EGG
  elseif SummaryMenu._page == PAGE_EGG then
    SummaryMenu._page = PAGE_INFO
  end
end

local function start_page_slide(newPage, dir)
  if SummaryMenu._page == newPage then return end
  SummaryMenu._slide.active = true
  SummaryMenu._slide.direction = dir
  SummaryMenu._slide.timer = 0
  SummaryMenu._slide.prevPage = SummaryMenu._page
  SummaryMenu._page = newPage
  SummaryMenu._moveCursor = 1
  SummaryMenu._swapSlot = nil
end

function SummaryMenu.update(dt)
  dt = tonumber(dt) or (1 / 60)
  if SummaryMenu._slide.active then
    SummaryMenu._slide.timer = SummaryMenu._slide.timer + dt
    if SummaryMenu._slide.timer >= SummaryMenu._slide.duration then
      SummaryMenu._slide.active = false
    end
  end
end

function SummaryMenu.handleInput(input)
  if not input then return end
  if SummaryMenu._slide.active then
    if SummaryMenu._slide.timer >= SummaryMenu._slide.duration then
      SummaryMenu._slide.active = false
    else
      return
    end
  end

  local mon = current_mon()
  if not mon then
    if input:wasPressed("b") or input:wasPressed("a") or input:wasPressed("start") then
      SummaryMenu.close()
    end
    return
  end

  -- Egg page navigation
  if SummaryMenu._page == PAGE_EGG then
    if input:wasPressed("up") then
      change_mon(-1)
    elseif input:wasPressed("down") then
      change_mon(1)
    elseif input:wasPressed("b") or input:wasPressed("a") or input:wasPressed("start") then
      SummaryMenu.close()
    end
    return
  end

  -- Move detail & swap mode
  if SummaryMenu._page == PAGE_MOVES_INFO then
    local moves = moves_for_mon(mon)
    local nMoves = #moves
    if nMoves < 1 then nMoves = 1 end

    if input:wasPressed("up") then
      SummaryMenu._moveCursor = ((SummaryMenu._moveCursor - 2) % nMoves) + 1
    elseif input:wasPressed("down") then
      SummaryMenu._moveCursor = (SummaryMenu._moveCursor % nMoves) + 1
    elseif input:wasPressed("a") then
      if SummaryMenu._swapSlot == nil then
        -- Begin move swap
        SummaryMenu._swapSlot = SummaryMenu._moveCursor
      else
        -- Complete atomic move swap
        local slotA = SummaryMenu._swapSlot
        local slotB = SummaryMenu._moveCursor
        SummaryMenu._swapSlot = nil
        Pokemon.swapMoves(mon, slotA, slotB)
      end
    elseif input:wasPressed("b") then
      if SummaryMenu._swapSlot ~= nil then
        -- Cancel swapping
        SummaryMenu._swapSlot = nil
      else
        -- Return to regular moves page
        SummaryMenu._page = PAGE_MOVES
      end
    end
    return
  end

  -- Standard 3-page summary
  if input:wasPressed("left") then
    if SummaryMenu._page == PAGE_INFO then
      start_page_slide(PAGE_MOVES, -1)
    elseif SummaryMenu._page == PAGE_SKILLS then
      start_page_slide(PAGE_INFO, -1)
    elseif SummaryMenu._page == PAGE_MOVES then
      start_page_slide(PAGE_SKILLS, -1)
    end
  elseif input:wasPressed("right") then
    if SummaryMenu._page == PAGE_INFO then
      start_page_slide(PAGE_SKILLS, 1)
    elseif SummaryMenu._page == PAGE_SKILLS then
      start_page_slide(PAGE_MOVES, 1)
    elseif SummaryMenu._page == PAGE_MOVES then
      start_page_slide(PAGE_INFO, 1)
    end
  elseif input:wasPressed("up") then
    change_mon(-1)
  elseif input:wasPressed("down") then
    change_mon(1)
  elseif input:wasPressed("a") then
    if SummaryMenu._page == PAGE_MOVES then
      SummaryMenu._page = PAGE_MOVES_INFO
      SummaryMenu._moveCursor = 1
      SummaryMenu._swapSlot = nil
    end
  elseif input:wasPressed("b") or input:wasPressed("start") then
    SummaryMenu.close()
  end
end

local function draw_text(str, x, y, maxW, colorKey)
  local colors = STAT_COLORS[colorKey] or FrlgFont.COLOR.NORMAL
  FrlgFont.draw(tostring(str or ""), x, y, {
    maxWidth = maxW,
    colors = colors,
    small = true,
  })
end

local function coords()
  local m = SummaryChrome.manifest()
  return (m and m.coords) or {}
end

local function move_slots()
  local m = SummaryChrome.manifest()
  return (m and m.moveSlots) or {}
end

local function moves_info_coords()
  local m = SummaryChrome.manifest()
  return (m and m.movesInfo) or {}
end

local function cxy(key, fx, fy)
  local c = coords()[key]
  if c then return c.x or fx or 0, c.y or fy or 0 end
  return fx or 0, fy or 0
end

local function species_name(mon)
  local species = Pokemon.speciesOf(mon)
  if Pokemon.name then
    local n = Pokemon.name(species)
    if n and n ~= "" then return n end
  end
  return Pokemon.displayName(mon)
end

local function draw_header(mon)
  local c = coords()
  local species = Pokemon.speciesOf(mon)

  -- Nickname + level + gender live in the left LVL_NICK strip (not the right pane).
  local nick = Pokemon.displayName(mon)
  local nx, ny = cxy("name", 40, 18)
  draw_text(nick, nx, ny, 64, "NORMAL")

  local lv = tonumber(mon.level) or 1
  local lx, ly = cxy("level", 4, 18)
  draw_text(string.format("Lv%d", lv), lx, ly, 36, "NORMAL")

  local gender = SummaryData.gender(mon)
  local gx, gy = cxy("gender", 105, 18)
  if gender == "M" then
    FrlgFont.draw("♂", gx, gy, { colors = FrlgFont.COLOR.MALE, small = true })
  elseif gender == "F" then
    FrlgFont.draw("♀", gx, gy, { colors = FrlgFont.COLOR.FEMALE, small = true })
  end

  if SummaryData.isShiny(mon) then
    local sx, sy = cxy("shinyStar", 8, 40)
    SummaryChrome.drawShinyStar(sx, sy)
  end

  local ailment = SummaryData.statusAilment(mon)
  if ailment > 0 then
    local key = (SummaryMenu._page == PAGE_MOVES_INFO) and "statusMovesInfo" or "status"
    local ax, ay = cxy(key, 16, 38)
    SummaryChrome.drawStatusIcon(ax, ay, ailment)
  end

  -- pret CreateMonPicSprite(..., 60, 65): CreateSprite center of 64×64 (see mon_pic.lua).
  local pic = c.monPic or { x = 60, y = 65 }
  local cx, cy = pic.x or 60, pic.y or 65
  local front = Pokemon.frontPic(species)
  if front and front.image and love and love.graphics then
    local iw = front.w or 64
    local ih = front.h or 64
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(front.image, cx - iw / 2, cy - ih / 2)
  else
    local icon = Pokemon.icon(species)
    if icon and icon.image and love and love.graphics then
      local iw = icon.w or 32
      local ih = icon.h or 32
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(icon.image, cx - iw / 2, cy - ih / 2)
    end
  end
end


local function draw_page_info(mon)
  local species = Pokemon.speciesOf(mon)
  local t1 = mon.type1 or (Pokemon.types and Pokemon.types(species) and Pokemon.types(species)[1]) or "NORMAL"
  local t2 = mon.type2 or (Pokemon.types and Pokemon.types(species) and Pokemon.types(species)[2])

  local dexNo = tonumber(mon.dexNo or mon.species or species) or 0
  local dx, dy = cxy("dexNo", 167, 21)
  draw_text(string.format("%03d", dexNo), dx, dy, 40, "NORMAL")

  local sx, sy = cxy("species", 167, 35)
  draw_text(species_name(mon), sx, sy, 64, "NORMAL")

  local t1x, t1y = cxy("type1", 167, 51)
  SummaryChrome.drawTypeBadge(t1, t1x, t1y)
  if t2 and t2 ~= t1 and t2 ~= "" then
    local t2x, t2y = cxy("type2", 203, 51)
    SummaryChrome.drawTypeBadge(t2, t2x, t2y)
  end

  local otName = mon.otName or mon.originalTrainer or "RED"
  local ox, oy = cxy("otName", 167, 65)
  draw_text(otName, ox, oy, 60, "NORMAL")

  local otId = tonumber(mon.otId) or 0
  local ix, iy = cxy("otId", 167, 80)
  draw_text(string.format("%05d", bit.band(otId, 0xFFFF)), ix, iy, 48, "NORMAL")

  local item = mon.item or mon.heldItem or "NONE"
  local itx, ity = cxy("item", 167, 95)
  draw_text(tostring(item), itx, ity, 64, "NORMAL")

  local memo = coords().memo or { x = 8, y = 115, w = 224 }
  local memoLines = SummaryData.formatTrainerMemo(mon, SummaryMenu._playerState)
  local memoY = memo.y or 115
  for _, line in ipairs(memoLines) do
    draw_text(line, memo.x or 8, memoY, memo.w or 224, "NORMAL")
    memoY = memoY + 14
  end
end

local function draw_page_skills(mon)
  local curHp = tonumber(mon.hp or mon.currentHp) or 0
  local maxHp = tonumber(mon.maxHp or mon.maxhp) or 1
  local hx, hy = cxy("hpText", 174, 20)
  draw_text(string.format("%d/%d", curHp, maxHp), hx, hy, 56, "NORMAL")

  local bar = coords().hpBar or { x = 172, y = 34 }
  SummaryChrome.drawHpBar(bar.x or 172, bar.y or 34, curHp, maxHp)

  local natureId = SummaryData.nature(mon)
  local stats = {
    { key = "atk", val = mon.attack or mon.atk or 0, coord = "atk", fy = 38 },
    { key = "def", val = mon.defense or mon.def or 0, coord = "def", fy = 51 },
    { key = "spAtk", val = mon.spAtk or mon.spatk or 0, coord = "spAtk", fy = 64 },
    { key = "spDef", val = mon.spDef or mon.spdef or 0, coord = "spDef", fy = 77 },
    { key = "spd", val = mon.speed or mon.spe or 0, coord = "spd", fy = 90 },
  }

  for _, st in ipairs(stats) do
    local mod = SummaryData.natureStatModifier(natureId, st.key)
    local color = "NORMAL"
    if mod > 1.0 then color = "UP"
    elseif mod < 1.0 then color = "DOWN" end
    local x, y = cxy(st.coord, 210, st.fy)
    draw_text(string.format("%d", tonumber(st.val) or 0), x, y, 32, color)
  end

  local prog = SummaryData.expProgress(mon)
  local ex, ey = cxy("expTotal", 175, 103)
  draw_text(string.format("%d", prog.totalExp), ex, ey, 56, "NORMAL")
  local nx, ny = cxy("expNext", 175, 116)
  draw_text(string.format("%d", prog.expNeeded), nx, ny, 56, "NORMAL")

  local expBar = coords().expBar or { x = 156, y = 130 }
  SummaryChrome.drawExpBar(expBar.x or 156, expBar.y or 130, prog.progressPercent)

  -- Party stores ability as numeric id (e.g. 65 = OVERGROW); resolve to name.
  local abilityId = tonumber(mon.abilityId) or tonumber(mon.ability)
  local ability = mon.abilityName
  if type(mon.ability) == "string" and mon.ability ~= "" and not tonumber(mon.ability) then
    ability = mon.ability
  end
  if (not ability or ability == "") and abilityId and abilityId > 0 then
    ability = Pokemon.abilityName(abilityId)
  end
  if not ability or ability == "" then
    local aid = Pokemon.abilityId and Pokemon.abilityId(Pokemon.speciesOf(mon), mon.personality or 0)
    if aid and aid > 0 then
      abilityId = aid
      ability = Pokemon.abilityName(aid)
    end
  end
  ability = ability or "—"
  local ax, ay = cxy("abilityName", 74, 129)
  draw_text(tostring(ability), ax, ay, 80, "NORMAL")
  local desc = SummaryData.abilityDescription(abilityId, tostring(ability))
  local ad = coords().abilityDesc or { x = 10, y = 143, w = 232 }
  draw_text(desc, ad.x or 10, ad.y or 143, ad.w or 232, "NORMAL")
end


local function draw_page_moves(mon, isDetail)
  local moves = moves_for_mon(mon)
  local slots = move_slots()

  for i = 1, 4 do
    local slot = slots[i] or {
      nameX = 163, nameY = 21 + (i - 1) * 28,
      typeX = 123, typeY = 21 + (i - 1) * 28,
      ppX = 196, ppY = 32 + (i - 1) * 28,
    }
    local m = moves[i]
    if m then
      SummaryChrome.drawTypeBadge(m.type, slot.typeX, slot.typeY)
      draw_text(m.name, slot.nameX, slot.nameY, 64, "NORMAL")
      draw_text(string.format("%d/%d", m.pp, m.maxPp), slot.ppX, slot.ppY, 40, "NORMAL")
    else
      draw_text("-", slot.typeX + 8, slot.typeY + 2, 16, "NORMAL")
      draw_text("----------", slot.nameX, slot.nameY, 64, "NORMAL")
    end
  end

  if isDetail then
    local cur = slots[SummaryMenu._moveCursor] or slots[1]
    if cur then
      SummaryChrome.drawMoveSelectionCursor(120, cur.nameY - 5, 114, 26, false)
    end
    if SummaryMenu._swapSlot then
      local swap = slots[SummaryMenu._swapSlot]
      if swap then
        SummaryChrome.drawMoveSelectionCursor(120, swap.nameY - 5, 114, 26, true)
      end
    end

    local selMove = moves[SummaryMenu._moveCursor]
    if selMove then
      local mi = moves_info_coords()
      local power = mi.power or { x = 57, y = 57 }
      local accuracy = mi.accuracy or { x = 57, y = 71 }
      local descBox = mi.desc or { x = 7, y = 98, w = 112 }
      draw_text(selMove.power, power.x, power.y, 32, "NORMAL")
      draw_text(selMove.accuracy, accuracy.x, accuracy.y, 32, "NORMAL")
      local desc = SummaryData.moveDescription(selMove.id, selMove.name)
      draw_text(desc, descBox.x, descBox.y, descBox.w or 112, "NORMAL")
    end
  end
end

local function draw_page_egg(mon)
  local species = Pokemon.speciesOf(mon)
  local nx, ny = cxy("name", 40, 18)
  draw_text("EGG", nx, ny, 64, "NORMAL")

  local pic = coords().monPic or { x = 60, y = 65 }
  local cx, cy = pic.x or 60, pic.y or 65
  local front = Pokemon.frontPic(species)
  if front and front.image and love and love.graphics then
    local iw = front.w or 64
    local ih = front.h or 64
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(front.image, cx - iw / 2, cy - ih / 2)
  end


  local memo = coords().memo or { x = 8, y = 115, w = 224 }
  local memoLines = SummaryData.formatTrainerMemo(mon, SummaryMenu._playerState)
  local memoY = memo.y or 80
  for _, line in ipairs(memoLines) do
    draw_text(line, memo.x or 8, memoY, memo.w or 224, "NORMAL")
    memoY = memoY + 28
  end
end

local PAGE_TITLES = {
  [PAGE_INFO] = "POKéMON INFO",
  [PAGE_SKILLS] = "POKéMON SKILLS",
  [PAGE_MOVES] = "KNOWN MOVES",
  [PAGE_MOVES_INFO] = "KNOWN MOVES",
  [PAGE_EGG] = "POKéMON INFO",
}

local function get_controls_str(page, isEgg)
  if isEgg then return "CANCEL" end
  if page == PAGE_INFO then return "CANCEL   PAGE"
  elseif page == PAGE_SKILLS then return "PAGE"
  elseif page == PAGE_MOVES then return "PAGE   DETAIL"
  elseif page == PAGE_MOVES_INFO then return "SWITCH   CANCEL"
  end
  return "PAGE"
end

local function draw_top_bar_text(page, isEgg)
  local title = PAGE_TITLES[page] or "POKéMON INFO"
  FrlgFont.draw(title, 4, 1, {
    colors = FrlgFont.COLOR.WHITE,
    small = false,
  })

  local ctrl = get_controls_str(page, isEgg)
  local w = FrlgFont.measure(ctrl, { small = true })
  FrlgFont.draw(ctrl, 236 - w, 1, {
    colors = FrlgFont.COLOR.WHITE,
    small = true,
  })
end

function SummaryMenu.draw()
  if not SummaryMenu.open then return end
  local mon = current_mon()
  if not mon then return end

  -- 1. BACKGROUND LAYER (Transforms during page slide transitions)
  if SummaryMenu._slide.active then
    local p = SummaryMenu._slide.timer / SummaryMenu._slide.duration
    p = math.max(0.0, math.min(1.0, p))
    local dir = SummaryMenu._slide.direction
    local curOffset = math.floor(240 * (1.0 - p) * dir)
    local prevOffset = math.floor(-240 * p * dir)

    SummaryChrome.drawPageBg(SummaryMenu._slide.prevPage, prevOffset)
    SummaryChrome.drawPageBg(SummaryMenu._page, curOffset)
  else
    SummaryChrome.drawPageBg(SummaryMenu._page, 0)
  end

  -- 2. OVERLAY LAYER (Foreground elements anchored to screen coordinates)
  draw_top_bar_text(SummaryMenu._page, mon.isEgg)
  if SummaryMenu._page == PAGE_EGG then
    draw_page_egg(mon)
  else
    draw_header(mon)
    if SummaryMenu._page == PAGE_INFO then
      draw_page_info(mon)
    elseif SummaryMenu._page == PAGE_SKILLS then
      draw_page_skills(mon)
    elseif SummaryMenu._page == PAGE_MOVES then
      draw_page_moves(mon, false)
    elseif SummaryMenu._page == PAGE_MOVES_INFO then
      draw_page_moves(mon, true)
    end
  end
end

return SummaryMenu
