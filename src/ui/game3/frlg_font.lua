-- FRLG Latin variable-width font (pret latin_normal + sFontNormalLatinGlyphWidths).
-- Field dialogue must use this — Gen2 Font.lua is fixed 8px and overflows the 208px box.

local TextIR = require("src.core.game3.scripting.text_ir")

local FrlgFont = {}

FrlgFont.CELL = 16
FrlgFont.MAX_LETTER_WIDTH = 10
FrlgFont.GLYPH_HEIGHT = 14
FrlgFont.LINE_PITCH = 15 -- maxLetterHeight(14) + lineSpacing(1)

-- Palette indices matching AddTextPrinterDiffStyle / stdpal_0
FrlgFont.COLOR = {
  NORMAL = { fg = { 98 / 255, 98 / 255, 98 / 255, 1 },
             shadow = { 213 / 255, 213 / 255, 205 / 255, 1 } },
  -- MALE: GBA scrolling_bg.pal (color 4 #7BBDFF, shadow color 5 #007BFF)
  MALE = { fg = { 123 / 255, 189 / 255, 255 / 255, 1 },
           shadow = { 0 / 255, 123 / 255, 255 / 255, 1 } },
  -- FEMALE: GBA scrolling_bg.pal (color 6 #FF8383, shadow color 7 #AC1818)
  FEMALE = { fg = { 255 / 255, 131 / 255, 131 / 255, 1 },
             shadow = { 172 / 255, 24 / 255, 24 / 255, 1 } },
  -- Party slot printers (FONT_SMALL on teal panels).
  PARTY = { fg = { 56 / 255, 56 / 255, 56 / 255, 1 },
            shadow = { 216 / 255, 216 / 255, 216 / 255, 1 } },
  -- Storage text / top-bar (GBA scrolling_bg.pal color 2 #FFFFFF, shadow color 3 #000000).
  WHITE = { fg = { 1, 1, 1, 1 },
            shadow = { 0, 0, 0, 1 } },
  -- Pikachu intro body (sTextColor_DarkGray).
  DARK_GRAY = { fg = { 0.35, 0.35, 0.38, 1 },
                shadow = { 0.75, 0.75, 0.78, 1 } },
}

-- pret DecompressGlyph_Small: height 13; widths ~4–8 (party nick/HP).
FrlgFont.SMALL_GLYPH_HEIGHT = 13
FrlgFont.SMALL_LINE_PITCH = 14

FrlgFont._fg = nil
FrlgFont._sh = nil
FrlgFont._quads = nil
FrlgFont._widths = nil
FrlgFont._small = nil -- { fg, sh, quads, widths }
FrlgFont._rev = nil -- UTF-8 char → glyph id
FrlgFont._logged = false

local FG_PATHS = {
  { path = "data/generated/gba/chrome/fonts/latin_normal_fg.rgba", w = 256, h = 512 },
  { path = "data/generated/gba/chrome/fonts/latin_normal_fg.png", w = 256, h = 512 },
  { path = "src/import/gba/chrome/fonts/latin_normal_fg.png", w = 256, h = 512 },
  { path = "mods/Kanto-Reforged/sevii/gba/chrome/fonts/latin_normal_fg.png", w = 256, h = 512 },
  { path = "sevii/gba/chrome/fonts/latin_normal_fg.png", w = 256, h = 512 },
}
local SH_PATHS = {
  { path = "data/generated/gba/chrome/fonts/latin_normal_shadow.rgba", w = 256, h = 512 },
  { path = "data/generated/gba/chrome/fonts/latin_normal_shadow.png", w = 256, h = 512 },
  { path = "src/import/gba/chrome/fonts/latin_normal_shadow.png", w = 256, h = 512 },
  { path = "mods/Kanto-Reforged/sevii/gba/chrome/fonts/latin_normal_shadow.png", w = 256, h = 512 },
  { path = "sevii/gba/chrome/fonts/latin_normal_shadow.png", w = 256, h = 512 },
}
local SMALL_FG_PATHS = {
  { path = "data/generated/gba/chrome/fonts/latin_small_fg.rgba", w = 256, h = 288 },
  { path = "data/generated/gba/chrome/fonts/latin_small_fg.png", w = 256, h = 288 },
  { path = "src/import/gba/chrome/fonts/latin_small_fg.png", w = 256, h = 288 },
  { path = "mods/Kanto-Reforged/sevii/gba/chrome/fonts/latin_small_fg.png", w = 256, h = 288 },
  { path = "sevii/gba/chrome/fonts/latin_small_fg.png", w = 256, h = 288 },
}
local SMALL_SH_PATHS = {
  { path = "data/generated/gba/chrome/fonts/latin_small_shadow.rgba", w = 256, h = 288 },
  { path = "data/generated/gba/chrome/fonts/latin_small_shadow.png", w = 256, h = 288 },
  { path = "src/import/gba/chrome/fonts/latin_small_shadow.png", w = 256, h = 288 },
  { path = "mods/Kanto-Reforged/sevii/gba/chrome/fonts/latin_small_shadow.png", w = 256, h = 288 },
  { path = "sevii/gba/chrome/fonts/latin_small_shadow.png", w = 256, h = 288 },
}

local function log(msg)
  print("[game3/frlg_font] " .. tostring(msg))
end

local function loadImage(candidates)
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  for _, item in ipairs(candidates) do
    local path = type(item) == "table" and item.path or item
    local w = type(item) == "table" and item.w or 256
    local h = type(item) == "table" and item.h or 512
    if okC and CacheFs and CacheFs.read then
      local data = CacheFs.read(path)
      if data and type(data) == "string" and #data > 0 then
        if #data == w * h * 4 and love and love.image and love.graphics then
          local okId, id = pcall(love.image.newImageData, w, h, "rgba8", data)
          if okId and id then
            local img = love.graphics.newImage(id)
            if img and img.setFilter then img:setFilter("nearest", "nearest") end
            return img, path
          end
        elseif love and love.filesystem and love.image and love.graphics then
          local okFd, fd = pcall(love.filesystem.newFileData, data, path)
          if okFd and fd then
            local okId, id = pcall(love.image.newImageData, fd)
            if okId and id then
              local img = love.graphics.newImage(id)
              if img and img.setFilter then img:setFilter("nearest", "nearest") end
              return img, path
            end
          end
        end
      end
    end
    if love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(path) then
      local ok, img = pcall(love.graphics.newImage, path)
      if ok and img then
        if img.setFilter then img:setFilter("nearest", "nearest") end
        return img, path
      end
    end
  end
  return nil, nil
end

local function ensure()
  if FrlgFont._fg and FrlgFont._widths and FrlgFont._quads then
    return true
  end
  local widths = FrlgFont._widths
  if not widths then
    local okC, CacheFs = pcall(require, "src.import.CacheFs")
    if okC and CacheFs and CacheFs.read then
      local src = CacheFs.read("data/generated/gba/chrome/fonts/latin_widths.lua")
      if src and type(src) == "string" then
        local chunk = load(src, "@latin_widths.lua", "t", {}) or load(src)
        if chunk then widths = chunk() end
      end
    end
  end
  if not widths then
    local ok, w = pcall(require, "src.import.gba.chrome.fonts.latin_widths")
    if ok and type(w) == "table" then
      widths = w
    else
      local path = "sevii/gba/chrome/fonts/latin_widths.lua"
      local chunk = loadfile(path)
      if chunk then widths = chunk() end
    end
  end
  FrlgFont._widths = widths or {}

  local fg, fgp = loadImage(FG_PATHS)
  local sh = loadImage(SH_PATHS)
  if not fg then
    if not FrlgFont._logged then
      log("latin_normal font missing")
      FrlgFont._logged = true
    end
    return false
  end
  FrlgFont._fg = fg
  FrlgFont._sh = sh
  local iw, ih = fg:getDimensions()
  local quads = {}
  for id = 0, 511 do
    local col = id % 16
    local row = math.floor(id / 16)
    quads[id] = love.graphics.newQuad(col * 16, row * 16, 16, 16, iw, ih)
  end
  FrlgFont._quads = quads
  if not FrlgFont._logged then
    log("latin_normal ready " .. tostring(fgp))
    FrlgFont._logged = true
  end
  return true
end

local function ensure_small()
  if FrlgFont._small and FrlgFont._small.fg and FrlgFont._small.quads then
    return true
  end
  local widths
  local okC, CacheFs = pcall(require, "src.import.CacheFs")
  if okC and CacheFs and CacheFs.read then
    local src = CacheFs.read("data/generated/gba/chrome/fonts/latin_small_widths.lua")
    if src and type(src) == "string" then
      local chunk = load(src, "@latin_small_widths.lua", "t", {}) or load(src)
      if chunk then widths = chunk() end
    end
  end
  if not widths then
    local ok, w = pcall(require, "src.import.gba.chrome.fonts.latin_small_widths")
    if ok and type(w) == "table" then
      widths = w
    else
      local chunk = loadfile("sevii/gba/chrome/fonts/latin_small_widths.lua")
      if chunk then widths = chunk() end
    end
  end
  local fg, fgp = loadImage(SMALL_FG_PATHS)
  local sh = loadImage(SMALL_SH_PATHS)
  if not fg then return false end
  local iw, ih = fg:getDimensions()
  local quads = {}
  local maxId = math.floor(iw / 16) * math.floor(ih / 16) - 1
  for id = 0, math.max(255, maxId) do
    local col = id % 16
    local row = math.floor(id / 16)
    if row * 16 + 16 <= ih then
      quads[id] = love.graphics.newQuad(col * 16, row * 16, 16, 16, iw, ih)
    end
  end
  -- Sheets from extract_latin_small.py (ROM hwlat @ 0x1EAF00), CHARMAP-ordered.
  FrlgFont._small = {
    fg = fg, sh = sh, quads = quads, widths = widths or {}, _romBaked = true,
  }
  log("latin_small ready " .. tostring(fgp) .. " (ROM FONT_SMALL)")
  return true
end

local function buildRev()
  if FrlgFont._rev then return FrlgFont._rev end
  local rev = {
    [" "] = 0x00,
    ["\n"] = 0xFE,
    ["№"] = 0x108,
    ["No"] = 0x108,
    ['"'] = 0xB2,
    ["“"] = 0xB1,
    ["”"] = 0xB2,
    ["‘"] = 0xB3,
    ["’"] = 0xB4,
    ["'"] = 0xB4,
  }
  for code, ch in pairs(TextIR.CHARMAP or {}) do
    if type(ch) == "string" and #ch > 0 and not rev[ch] then
      rev[ch] = code
    end
  end
  -- ASCII digits/letters already via CHARMAP; ensure common punctuation.
  FrlgFont._rev = rev
  return rev
end

--- UTF-8 iterate: yield (char, byteFrom, byteTo)
local function utf8Chars(s)
  local i, n = 1, #s
  return function()
    if i > n then return nil end
    local b = s:byte(i)
    local len = 1
    if b >= 0xF0 then len = 4
    elseif b >= 0xE0 then len = 3
    elseif b >= 0xC0 then len = 2
    end
    if i + len - 1 > n then len = 1 end
    local ch = s:sub(i, i + len - 1)
    local from = i
    i = i + len
    return ch, from, i - 1
  end
end

function FrlgFont.glyphId(ch)
  if not ch or ch == "" then return 0x00 end
  local rev = buildRev()
  local id = rev[ch]
  if id then return id end
  -- ASCII fallback for unmapped printable
  local b = ch:byte(1)
  if b and b >= 0x20 and b < 0x7F and #ch == 1 then
    -- try upper/lower via CHARMAP reverse already; unknown → space
    return 0x00
  end
  return 0x00
end

function FrlgFont.advance(glyphId, opts)
  opts = opts or {}
  if opts.small then
    ensure_small()
    local sw = FrlgFont._small and FrlgFont._small.widths
    local w = sw and sw[glyphId]
    if not w then
      if glyphId == 0x108 then return 8 end
      w = (sw and sw[0]) or 5
    end
    return w
  end
  ensure()
  local w = FrlgFont._widths[glyphId]
  if not w then
    if glyphId == 0x108 then return 9 end
    w = FrlgFont._widths[0] or 6
  end
  return w
end

function FrlgFont.measure(text, opts)
  opts = opts or {}
  local width, line, maxLine = 0, 0, 0
  for ch in utf8Chars(tostring(text or "")) do
    if ch == "\n" then
      if line > maxLine then maxLine = line end
      line = 0
    else
      line = line + FrlgFont.advance(FrlgFont.glyphId(ch), opts)
    end
  end
  if line > maxLine then maxLine = line end
  return maxLine
end

--- Word-wrap text to fit within maxWidth pixels.
function FrlgFont.wrap(text, maxWidth, opts)
  opts = opts or {}
  maxWidth = maxWidth or 200
  local spaceW = FrlgFont.measure(" ", opts)
  local outLines = {}
  local rawLines = {}
  local clean = tostring(text or ""):gsub("\\n", "\n"):gsub("\\p", "\n")
  for line in (clean .. "\n"):gmatch("(.-)\r?\n") do
    rawLines[#rawLines + 1] = line
  end
  for _, rawLine in ipairs(rawLines) do
    local words = {}
    for word in rawLine:gmatch("%S+") do
      words[#words + 1] = word
    end
    if #words == 0 then
      outLines[#outLines + 1] = ""
    else
      local curLine = words[1]
      local curW = FrlgFont.measure(curLine, opts)
      for i = 2, #words do
        local w = words[i]
        local wW = FrlgFont.measure(w, opts)
        if curW + spaceW + wW <= maxWidth then
          curLine = curLine .. " " .. w
          curW = curW + spaceW + wW
        else
          outLines[#outLines + 1] = curLine
          curLine = w
          curW = wW
        end
      end
      outLines[#outLines + 1] = curLine
    end
  end
  return table.concat(outLines, "\n")
end

--- Draw full string at pixel (x,y). English: no letterSpacing.
-- opts.maxWidth clips (CopyGlyphToWindow). opts.colors = COLOR.NORMAL etc.
-- opts.limitChars: only draw first N UTF-8 characters (typewriter).
-- opts.small: use FONT_SMALL (party menu).
function FrlgFont.draw(text, x, y, opts)
  opts = opts or {}
  -- FONT_SMALL: ROM-baked latin_small_* (hwlat). Fall back to normal if missing.
  local useSmall = false
  if opts.small then
    useSmall = ensure_small() and FrlgFont._small and FrlgFont._small._romBaked
  end
  if not useSmall and not ensure() then return 0 end
  local colors = opts.colors
  if not colors then
    if opts.color then
      colors = { fg = opts.color, shadow = opts.shadow or (opts.color == FrlgFont.COLOR.WHITE.fg and FrlgFont.COLOR.WHITE.shadow or FrlgFont.COLOR.NORMAL.shadow) }
    else
      colors = (useSmall and FrlgFont.COLOR.PARTY) or FrlgFont.COLOR.NORMAL
    end
  end
  local maxW = opts.maxWidth or 240
  local limit = opts.limitChars
  local penX, penY = 0, 0
  local drawn = 0
  local pitch = opts.linePitch
    or (useSmall and FrlgFont.SMALL_LINE_PITCH or FrlgFont.LINE_PITCH)
  local fg, sh, quads
  if useSmall then
    fg, sh, quads = FrlgFont._small.fg, FrlgFont._small.sh, FrlgFont._small.quads
  else
    fg, sh, quads = FrlgFont._fg, FrlgFont._sh, FrlgFont._quads
  end

  local function set_col(c)
    if type(c) == "table" then
      love.graphics.setColor(c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1)
    else
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  for ch in utf8Chars(tostring(text or "")) do
    if limit and drawn >= limit then break end
    if ch == "\n" then
      penX = 0
      penY = penY + pitch
      drawn = drawn + 1
    else
      local id = FrlgFont.glyphId(ch)
      local adv = FrlgFont.advance(id, useSmall and { small = true } or {})
      if penX + adv <= maxW or penX == 0 then
        local dx, dy = x + penX, y + penY
        local q = quads[id]
        if q then
          if sh and colors.shadow then
            set_col(colors.shadow)
            love.graphics.draw(sh, q, dx, dy)
          end
          set_col(colors.fg)
          love.graphics.draw(fg, q, dx, dy)
        end
        penX = penX + adv
      end
      drawn = drawn + 1
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  return drawn
end

--- Draw a single glyph by FRLG charset id (e.g. 0x7C = CHAR_RIGHT_ARROW).
-- opts.small: FONT_SMALL sheet (supports EXTRA ids like CHAR_LV_2 = 0x105).
function FrlgFont.drawGlyph(glyphId, x, y, opts)
  opts = opts or {}
  glyphId = tonumber(glyphId) or 0
  local useSmall = opts.small and ensure_small() and FrlgFont._small and FrlgFont._small._romBaked
  if useSmall then
    -- ok
  elseif not ensure() then
    return 0
  end
  local colors = opts.colors or (useSmall and FrlgFont.COLOR.PARTY) or FrlgFont.COLOR.NORMAL
  local fg, sh, quads
  if useSmall then
    fg, sh, quads = FrlgFont._small.fg, FrlgFont._small.sh, FrlgFont._small.quads
  else
    fg, sh, quads = FrlgFont._fg, FrlgFont._sh, FrlgFont._quads
  end
  local q = quads[glyphId]
  if not q then return 0 end
  if sh and colors.shadow then
    love.graphics.setColor(colors.shadow)
    love.graphics.draw(sh, q, x, y)
  end
  if colors.fg then
    love.graphics.setColor(colors.fg)
  else
    love.graphics.setColor(1, 1, 1, 1)
  end
  love.graphics.draw(fg, q, x, y)
  love.graphics.setColor(1, 1, 1, 1)
  return FrlgFont.advance(glyphId, useSmall and { small = true } or {})
end

-- pret CHAR_RIGHT_ARROW = 0x7C, but gText_SelectorArrow2 ("▶") is charmap 0xEF.
-- Menu_InitCursor / RedrawMenuCursor print SelectorArrow2 — use 0xEF for the pip.
FrlgFont.CHAR_RIGHT_ARROW = 0x7C
FrlgFont.CHAR_SELECTOR_ARROW = 0xEF -- gText_SelectorArrow2
FrlgFont.CHAR_LEFT_ARROW = 0x7B
FrlgFont.CHAR_UP_ARROW = 0x79
FrlgFont.CHAR_DOWN_ARROW = 0x7A
-- CHAR_EXTRA_SYMBOL|CHAR_LV_2 → glyph 0x105 in latin_small (UpdateLvlInHealthbox).
FrlgFont.CHAR_LV_2 = 0x105
FrlgFont.CHAR_MALE = 0xB5
FrlgFont.CHAR_FEMALE = 0xB6
FrlgFont.CHAR_SLASH = 0xBA

--- Count UTF-8 characters in text (including newlines as 1).
function FrlgFont.countChars(text)
  local n = 0
  for _ in utf8Chars(tostring(text or "")) do
    n = n + 1
  end
  return n
end

function FrlgFont.invalidate()
  FrlgFont._fg = nil
  FrlgFont._sh = nil
  FrlgFont._quads = nil
  FrlgFont._small = nil
  FrlgFont._logged = false
end

FrlgFont.utf8Chars = utf8Chars

return FrlgFont
