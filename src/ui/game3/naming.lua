-- FRLG naming screen as a reusable Stack modal (pret naming_screen.c).
-- Keyboard letters sit on pret sPageColumnXPos cells; cursor uses CreateSprite centers.
-- Player icon is field OW (Red/Leaf), same as NamingScreen_CreatePlayerIcon.
-- Preset name lists stay in Oak; this modal is keyboard-only.

local Display = require("src.core.game3.display")
local FrlgFont = require("src.ui.game3.frlg_font")
local Stack = require("src.ui.game3.stack")
local Audio = require("src.core.game3.audio")
local NamingChrome = require("src.ui.game3.naming_chrome")
local OwSprites = require("src.core.game3.ow_sprites")
local Versions = require("src.import.gba.versions")

local Naming = {}

Naming.MAX_LEN = 7
Naming.openFlag = false
Naming._state = nil

Naming.TEMPLATE = {
  PLAYER = "PLAYER",
  RIVAL = "RIVAL",
  BOX = "BOX",
  CAUGHT_MON = "CAUGHT_MON",
  NICKNAME = "NICKNAME",
}

-- pret sKeyboardChars + sPageColumnXPos (cursor). Letters drawn via ROW_TEXT CLEARs.
local PAGES = {
  {
    id = "UPPER",
    label = "UPPER",
    rows = {
      { "A", "B", "C", "D", "E", "F", " ", "." },
      { "G", "H", "I", "J", "K", "L", " ", "," },
      { "M", "N", "O", "P", "Q", "R", "S" },
      { "T", "U", "V", "W", "X", "Y", "Z" },
    },
    -- pret gText_NamingScreenKeyboard_* with {CLEAR N} → drawClearRow
    rowText = {
      "{CLEAR 11}A{CLEAR 6}B{CLEAR 6}C{CLEAR 26}D{CLEAR 6}E{CLEAR 6}F{CLEAR 6} {CLEAR 26}.",
      "{CLEAR 11}G{CLEAR 6}H{CLEAR 6}I{CLEAR 26}J{CLEAR 6}K{CLEAR 6}L{CLEAR 6} {CLEAR 26},",
      "{CLEAR 11}M{CLEAR 6}N{CLEAR 6}O{CLEAR 26}P{CLEAR 6}Q{CLEAR 6}R{CLEAR 6}S{CLEAR 26} ",
      "{CLEAR 11}T{CLEAR 6}U{CLEAR 6}V{CLEAR 26}W{CLEAR 6}X{CLEAR 6}Y{CLEAR 6}Z{CLEAR 26} ",
    },
    colX = { 0, 12, 24, 56, 68, 80, 92, 123 },
  },
  {
    id = "LOWER",
    label = "lower",
    rows = {
      { "a", "b", "c", "d", "e", "f", " ", "." },
      { "g", "h", "i", "j", "k", "l", " ", "," },
      { "m", "n", "o", "p", "q", "r", "s" },
      { "t", "u", "v", "w", "x", "y", "z" },
    },
    rowText = {
      "{CLEAR 11}a{CLEAR 6}b{CLEAR 6}c{CLEAR 26}d{CLEAR 6}e{CLEAR 6}f{CLEAR 6} {CLEAR 26}.",
      "{CLEAR 11}g{CLEAR 6}h{CLEAR 7}i{CLEAR 27}j{CLEAR 6}k{CLEAR 6}l{CLEAR 7} {CLEAR 26},",
      "{CLEAR 11}m{CLEAR 6}n{CLEAR 7}o{CLEAR 26}p{CLEAR 6}q{CLEAR 7}r{CLEAR 6}s{CLEAR 27} ",
      "{CLEAR 12}t{CLEAR 6}u{CLEAR 6}v{CLEAR 26}w{CLEAR 6}x{CLEAR 6}y{CLEAR 6}z{CLEAR 26} ",
    },
    colX = { 0, 12, 24, 56, 68, 80, 92, 123 },
  },
  {
    id = "OTHERS",
    label = "OTHERS",
    rows = {
      { "0", "1", "2", "3", "4" },
      { "5", "6", "7", "8", "9" },
      { "!", "?", "♂", "♀", "/", "-" },
      { "…", "“", "”", "‘", "'" },
    },
    rowText = {
      "{CLEAR 11}0{CLEAR 16}1{CLEAR 16}2{CLEAR 16}3{CLEAR 16}4{CLEAR 16} ",
      "{CLEAR 11}5{CLEAR 16}6{CLEAR 16}7{CLEAR 16}8{CLEAR 16}9{CLEAR 16} ",
      "{CLEAR 11}!{CLEAR 16}?{CLEAR 16}♂{CLEAR 16}♀{CLEAR 16}/{CLEAR 16}-",
      "{CLEAR 11}…{CLEAR 16}“{CLEAR 16}”{CLEAR 18}‘{CLEAR 18}'{CLEAR 18} ",
    },
    colX = { 0, 22, 44, 66, 88, 110 },
  },
}

local KEY_TO_BTN = { 0, 1, 1, 2 }
local BTN_TO_KEY = { 0, 0, 3 }
local SIDE = { "PAGE", "BACK", "OK" }

-- pret naming_screen.c CreateSprite coords are *centers*; OAM top-left =
-- center + centerToCornerVec. Subsprite sheets draw at first-subsprite TL.
-- Values below are on-screen top-left blit positions (px).
local L = {
  titleX = 73, titleY = 33,
  -- Player/rival icon CreateSprite(56,37); 16×32 → TL (48,21)
  iconCX = 56, iconCY = 37,
  iconW = 16, iconH = 32,
  charY = 49,
  -- Underscore CreateSprite(base+3,60) 8×8 → TL (base-1, 56)
  underscoreBaseY = 56,
  underscoreXOfs = -1,
  -- Input arrow CreateSprite(base-5,56) 8×8 → TL (base-9, 52)
  arrowXOfs = -9,
  arrowY = 52,
  -- Cursor CreateSprite(colX+38, row*16+88) 16×16 → TL (colX+30, row*16+80)
  cursorBaseX = 30,
  cursorBaseY = 80,
  kbX = 24,
  kbY = 80,
  -- Keyboard chrome blit (border + SELECT tab); letters stay at kbX/kbY
  kbChromeX = 16,
  kbChromeY = 72,
  -- First letter after {CLEAR 11}; colX aligns cursor to this grid
  keyTextOx = 11,
  keyTextOy = 1,
  -- pret PrintControls WIN_BANNER: 240×16, stdpal_2[15] = RGB(0,123,197)
  bannerH = 16,
  bannerR = 0 / 255,
  bannerG = 123 / 255,
  bannerB = 197 / 255,
  -- Page frame CreateSprite(204,88) + subsprite (-20,-16) → (184,72)
  pageFrameX = 184, pageFrameY = 72,
  -- Page button CreateSprite(204,83) 32×16 → TL (188,75)
  pageBtnX = 188, pageBtnY = 75,
  -- Page text CreateSprite(204,84) + subsprite (-12,-4) → (192,80)
  pageLabelX = 192, pageLabelY = 80,
  -- BACK/OK CreateSprite(204,116/140) + subsprite (-20,-12) → (184,104/128)
  backX = 184, backY = 104,
  okX = 184, okY = 128,
}

local function playSe(id)
  Audio.playSe(id or 5)
end

local function utf8Len(s)
  local n = 0
  for _ in tostring(s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    n = n + 1
  end
  return n
end

local function utf8Trim(s, maxLen)
  local out, n = {}, 0
  for ch in tostring(s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if n >= maxLen then break end
    out[#out + 1] = ch
    n = n + 1
  end
  return table.concat(out)
end

local function pageInfo(st)
  return PAGES[st.page]
end

local function colCount(st)
  local page = pageInfo(st)
  local row = page.rows[st.row]
  return row and #row or 0
end

local function onButtonCol(st)
  return st.col > colCount(st)
end

local function clampCursor(st)
  local n = colCount(st)
  if st.col < 1 then st.col = 1 end
  if st.col > n + 1 then st.col = n + 1 end
  if st.row < 1 then st.row = 1 end
  if st.row > 4 then st.row = 4 end
  if onButtonCol(st) then
    st.btn = KEY_TO_BTN[st.row] + 1
  end
end

local function cellAt(st)
  if onButtonCol(st) then return nil end
  local page = pageInfo(st)
  local row = page.rows[st.row]
  return row and row[st.col]
end

local function appendChar(st, ch)
  if not ch then return end
  if utf8Len(st.name) >= st.maxLen then return end
  st.name = st.name .. ch
  if utf8Len(st.name) >= st.maxLen then
    st.col = colCount(st) + 1
    st.row = 4
    st.btn = 3
  end
end

local function backspace(st)
  if st.name == "" then return end
  st.name = st.name:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
end

local function cyclePage(st)
  st.page = st.page % #PAGES + 1
  st.swapT = 0
  if not onButtonCol(st) then
    local n = colCount(st)
    if st.col > n then st.col = n end
  end
  playSe(6)
end

local function confirm(st)
  local name = st.name
  if name == nil or name:match("^%s*$") then
    return st.seed
  end
  return utf8Trim(name, st.maxLen)
end

--- Draw keyboard letters at fixed colX cells (matches cursor grid; ignores glyph-width drift).
local function drawKeyboardKeys(page, colors)
  local rows = page.rows
  local colX = page.colX
  if not rows or not colX then return end
  for r = 1, #rows do
    local row = rows[r]
    local y = L.kbY + (r - 1) * 16 + L.keyTextOy
    for c = 1, #row do
      local ch = row[c]
      if ch and ch ~= "" and ch ~= " " then
        local x = L.kbX + L.keyTextOx + (colX[c] or 0)
        FrlgFont.draw(ch, x, y, {
          colors = colors,
          maxWidth = 16,
        })
      end
    end
  end
end

local function playerOwId(gender)
  if gender == 1 or gender == "female" or gender == "F" then
    return Versions.OW_PLAYER_FEMALE or 7
  end
  return Versions.OW_PLAYER_MALE or 0
end

local function drawPlayerIcon(st)
  love.graphics.setColor(1, 1, 1, 1)
  local tlX = L.iconCX - L.iconW / 2
  local tlY = L.iconCY - L.iconH / 2

  if st.template == "NICKNAME" or st.template == "CAUGHT_MON" then
    local species = tonumber(st.species) or 0
    if species > 0 then
      local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
      if ok and Pokemon then
        local entry = Pokemon.icon and Pokemon.icon(species)
        if not entry then
          entry = Pokemon.frontPic and Pokemon.frontPic(species)
        end
        if entry and entry.image then
          local iw = entry.w or entry.image:getWidth()
          local ih = entry.h or entry.image:getHeight()
          local sc = math.min(L.iconW / iw, L.iconH / ih)
          love.graphics.draw(entry.image, L.iconCX, L.iconCY, 0, sc, sc, iw / 2, ih / 2)
          return
        end
      end
    end
  end

  if st.template == "RIVAL" then
    local rival = NamingChrome.get("rival")
    if rival then
      local q = love.graphics.newQuad and love.graphics.newQuad(0, 0, 16, 32, rival:getDimensions())
      if q then
        love.graphics.draw(rival, q, tlX, tlY)
        return
      end
    end
  end

  local gid = playerOwId(st.gender)
  local spr = OwSprites.get(gid)
  if spr and spr.image then
    local frame = OwSprites.pose(spr, "down", false, false)
    local q = spr.quads[frame]
    if q then
      local ox = tlX + (L.iconW - spr.width) / 2
      local oy = tlY + (L.iconH - spr.height)
      love.graphics.draw(spr.image, q, ox, oy)
      return
    end
  end

  -- Fallback: explicit icon image (e.g. tests). Scale portraits into the OW slot.
  if st.icon then
    local iw, ih = st.icon:getDimensions()
    if iw > 24 or ih > 40 then
      local sc = math.min(L.iconW / iw, L.iconH / ih)
      love.graphics.draw(st.icon, L.iconCX, L.iconCY, 0, sc, sc, iw / 2, ih / 2)
    else
      love.graphics.draw(st.icon, tlX, tlY)
    end
  end
end

function Naming.open(opts)
  opts = opts or {}
  NamingChrome.ready()
  local st = {
    title = opts.title or "YOUR NAME?",
    maxLen = opts.maxLen or Naming.MAX_LEN,
    name = "",
    seed = opts.seed,
    page = 1,
    row = 1,
    col = 1,
    btn = 1,
    blink = 0,
    swapT = nil,
    icon = opts.icon,
    gender = opts.gender or 0,
    template = opts.template or "PLAYER",
    species = opts.species,
    personality = opts.personality,
    onDone = opts.onDone,
  }
  Naming._state = st
  Naming.openFlag = true
  Stack.push("naming", Naming, { hideBelow = true })
  return st
end

function Naming.isOpen()
  return Naming.openFlag
end

function Naming.close(result)
  local st = Naming._state
  local cb = st and st.onDone
  Naming.openFlag = false
  Naming._state = nil
  Stack.pop("naming")
  if cb then cb(result) end
end

function Naming.update(input, dt)
  if not Naming.openFlag or not Naming._state then return end
  local st = Naming._state
  st.blink = (st.blink or 0) + (dt or 1 / 60)
  if st.swapT ~= nil then
    st.swapT = st.swapT + 4
    if st.swapT >= 128 then st.swapT = nil end
    return
  end

  local function pressed(k)
    return input and input.wasPressed and input:wasPressed(k)
  end

  if pressed("select") then
    cyclePage(st)
    return
  end
  if pressed("b") then
    playSe(23)
    backspace(st)
    return
  end
  if pressed("start") then
    st.col = colCount(st) + 1
    st.row = 4
    st.btn = 3
    playSe(5)
    return
  end

  if pressed("up") then
    playSe(5)
    if onButtonCol(st) then
      st.btn = st.btn - 1
      if st.btn < 1 then st.btn = 3 end
      st.row = ({ 1, 2, 4 })[st.btn]
    else
      st.row = st.row - 1
      if st.row < 1 then st.row = 4 end
      clampCursor(st)
    end
  elseif pressed("down") then
    playSe(5)
    if onButtonCol(st) then
      st.btn = st.btn + 1
      if st.btn > 3 then st.btn = 1 end
      st.row = ({ 1, 2, 4 })[st.btn]
    else
      st.row = st.row + 1
      if st.row > 4 then st.row = 1 end
      clampCursor(st)
    end
  elseif pressed("left") then
    playSe(5)
    if onButtonCol(st) then
      st.col = colCount(st)
      st.row = BTN_TO_KEY[st.btn] + 1
    else
      st.col = st.col - 1
      if st.col < 1 then
        st.col = colCount(st) + 1
        st.btn = KEY_TO_BTN[st.row] + 1
      end
    end
  elseif pressed("right") then
    playSe(5)
    if onButtonCol(st) then
      st.col = 1
      st.row = BTN_TO_KEY[st.btn] + 1
    else
      local n = colCount(st)
      if st.col >= n then
        st.col = n + 1
        st.btn = KEY_TO_BTN[st.row] + 1
      else
        st.col = st.col + 1
      end
    end
  elseif pressed("a") then
    playSe(5)
    if onButtonCol(st) then
      local role = SIDE[st.btn]
      if role == "PAGE" then
        cyclePage(st)
      elseif role == "BACK" then
        playSe(23)
        backspace(st)
      elseif role == "OK" then
        Naming.close(confirm(st))
      end
    else
      appendChar(st, cellAt(st))
    end
  end
end

local function drawText(str, x, y, opts)
  opts = opts or {}
  FrlgFont.draw(tostring(str or ""), x, y, {
    colors = opts.colors or FrlgFont.COLOR.NORMAL,
    small = opts.small,
    maxWidth = opts.maxWidth or 240,
  })
end

local function blit(key, x, y)
  local img = NamingChrome.get(key)
  if img then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, x, y)
  end
end

function Naming.draw()
  if not Naming.openFlag or not Naming._state then return end
  local st = Naming._state
  local W, H = Display.W, Display.H
  local page = pageInfo(st)

  -- 1) Background (240×160)
  local bg = NamingChrome.get("bg")
  if bg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(bg, 0, 0)
  else
    love.graphics.setColor(0.42, 0.61, 0.84, 1)
    love.graphics.rectangle("fill", 0, 0, W, H)
  end

  -- 2) Keyboard chrome (border + SELECT tab; extract v3 is 176×80 at 16,72)
  local kbKey = (st.page == 1 and "kb_upper") or (st.page == 2 and "kb_lower") or "kb_symbols"
  local kb = NamingChrome.get(kbKey)
  if kb then
    love.graphics.setColor(1, 1, 1, 1)
    local iw, ih = kb:getDimensions()
    if iw >= 160 and ih >= 72 then
      -- v3 frame crop (includes border/tab)
      love.graphics.draw(kb, L.kbChromeX, L.kbChromeY)
    elseif iw <= 160 and ih <= 70 then
      -- v2 inner-only crop (missing border) — legacy fallback
      love.graphics.draw(kb, L.kbX, L.kbY)
    else
      local img, q = NamingChrome.kbQuad(kbKey)
      if img and q then
        love.graphics.draw(img, q, L.kbChromeX, L.kbChromeY)
      elseif img then
        love.graphics.draw(img, L.kbChromeX, L.kbChromeY)
      end
    end
  end

  -- 3) Keyboard letters (fixed colX grid — same as pret cursor)
  drawKeyboardKeys(page, FrlgFont.COLOR.WHITE)

  -- 4) Side buttons (subsprite / center-compensated top-lefts)
  -- pret shows the *next* page on the swap button (PageToNextGfxId).
  local nextPage = st.page % #PAGES + 1
  blit("page_swap_frame", L.pageFrameX, L.pageFrameY)
  blit("page_swap_button", L.pageBtnX, L.pageBtnY)
  blit(({ "page_swap_upper", "page_swap_lower", "page_swap_others" })[nextPage], L.pageLabelX, L.pageLabelY)
  blit("back_button", L.backX, L.backY)
  blit("ok_button", L.okX, L.okY)

  -- 5) Title + icon + typed name (above KB)
  love.graphics.setColor(1, 1, 1, 1)
  drawText(st.title, L.titleX, L.titleY)

  drawPlayerIcon(st)

  local baseX = math.floor((W - st.maxLen * 8) / 2) + 6
  local chars = {}
  for ch in tostring(st.name):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    chars[#chars + 1] = ch
  end
  local caret = #chars + 1
  for i = 1, st.maxLen do
    local x = baseX + (i - 1) * 8
    if chars[i] then
      drawText(chars[i], x, L.charY)
    end
    local und = NamingChrome.get("underscore")
    if und then
      local bobY = 0
      if i == caret then
        local bob = math.floor(st.blink * 8) % 4
        bobY = ({ 2, 3, 2, 1 })[bob + 1] or 2
      end
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(und, x + L.underscoreXOfs, L.underscoreBaseY + bobY)
    end
  end
  local arrow = NamingChrome.get("input_arrow")
  if arrow then
    local bob = math.floor(st.blink * 8) % 4
    local x2 = ({ 0, -4, -2, -1 })[bob + 1] or 0
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(arrow, baseX + L.arrowXOfs + x2, L.arrowY)
  end

  -- 6) Cursor (pret center (38+colX, 88+row*16) → TL via -8,-8)
  if not onButtonCol(st) then
    local x = L.cursorBaseX + (page.colX[st.col] or 0)
    local y = L.cursorBaseY + (st.row - 1) * 16
    local img, q = NamingChrome.cursorQuad(0)
    if img and q then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, q, x, y)
    else
      love.graphics.setColor(1, 0.1, 0.1, 1)
      love.graphics.rectangle("line", x, y, 16, 16)
    end
  else
    local hy = ({ L.pageFrameY, L.backY, L.okY })[st.btn] or L.pageFrameY
    love.graphics.setColor(1, 1, 0.35, 0.35)
    love.graphics.rectangle("fill", L.pageFrameX, hy, 40, 24)
  end

  -- 7) Banner — pret PrintControls / WIN_BANNER (bg0, 30×2 tiles).
  -- Fill PIXEL_FILL(15) of GetTextWindowPalette(2) = RGB(0,123,197), then
  -- gText_MoveOkBack right-aligned in FONT_SMALL (keypad icons ≈ + / A / B).
  love.graphics.setColor(L.bannerR, L.bannerG, L.bannerB, 1)
  love.graphics.rectangle("fill", 0, 0, W, L.bannerH)
  local banner = "+MOVE  A OK  B BACK"
  local tw = FrlgFont.measure(banner, { small = true })
  if tw < 1 then tw = FrlgFont.measure(banner) end
  drawText(banner, W - 4 - tw, 0, {
    colors = FrlgFont.COLOR.WHITE,
    small = true,
  })
end

function Naming.begin(opts)
  opts = opts or {}
  return {
    title = opts.title or "YOUR NAME?",
    maxLen = opts.maxLen or Naming.MAX_LEN,
    name = "",
    seed = opts.default or opts.seed,
    page = 1, row = 1, col = 1, btn = 1, blink = 0,
    onDone = opts.onDone,
  }
end

return Naming
