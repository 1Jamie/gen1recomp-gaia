local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Options = require("src.core.game3.options")
local Rows = require("src.ui.game3.option_rows")

local OptionMenu = {}

OptionMenu.open = false
OptionMenu.cursor = 1

local FIRST_ROW = 4
local VISIBLE = 6
local LABEL_COL = 3
local VALUE_COL = 17

local function ctx()
  return OptionMenu._ctx
end

local function page()
  local pages = OptionMenu._pages
  return pages and pages[#pages]
end

local function pushPage(title, rows)
  OptionMenu._pages[#OptionMenu._pages + 1] = {
    title = title, rows = rows, index = 1, scroll = 0,
  }
end

local function buildTop()
  local c = ctx()
  local flat = Rows.build(c)
  OptionMenu._flat = flat
  return Rows.group(flat, function(title, members)
    pushPage(title, members)
  end)
end

function OptionMenu.show(opts)
  opts = opts or {}
  OptionMenu.open = true
  OptionMenu._session = opts.session
  OptionMenu._onClose = opts.onClose
  local Runtime = package.loaded["src.core.game3.runtime"]
  OptionMenu._game = opts.game or (Runtime and Runtime._game)
  local engine = Options.engine(opts.session)
    or (OptionMenu._game and OptionMenu._game.options)
    or (opts.session and opts.session.options)
    or {}
  Options.bind(opts.session or {}, engine)
  OptionMenu._ctx = {
    session = opts.session,
    game = OptionMenu._game,
    options = engine,
  }
  OptionMenu._pages = {}
  pushPage("OPTION", buildTop())
  OptionMenu.cursor = 1
  Stack.push("option", OptionMenu, { hideBelow = true })
end

function OptionMenu.close()
  OptionMenu.open = false
  OptionMenu._pages = nil
  Stack.pop("option")
  local cb = OptionMenu._onClose
  OptionMenu._onClose = nil
  if cb then cb() end
end

function OptionMenu.isOpen()
  return OptionMenu.open
end

local function rowCount(p)
  return #p.rows + 1
end

local function clampScroll(p)
  local total = rowCount(p)
  if total <= VISIBLE then
    p.scroll = 0
    return
  end
  if p.index - 1 < p.scroll then p.scroll = p.index - 1 end
  if p.index > p.scroll + VISIBLE then p.scroll = p.index - VISIBLE end
  if p.scroll < 0 then p.scroll = 0 end
  if p.scroll > total - VISIBLE then p.scroll = total - VISIBLE end
end

function OptionMenu.move(delta)
  local p = page()
  if not p then return end
  local total = rowCount(p)
  p.index = ((p.index - 1 + delta) % total) + 1
  OptionMenu.cursor = p.index
  clampScroll(p)
end

local function persist()
  local c = ctx()
  local g = c and c.game
  if g and g.writeOptions then g:writeOptions() end
end

function OptionMenu.adjust(delta)
  local p = page()
  if not p then return end
  local row = p.rows[p.index]
  if not row or not row.step then return end
  if row.step(ctx(), delta) then persist() end
end

function OptionMenu.confirm()
  local p = page()
  if not p then return end
  if p.index > #p.rows then
    OptionMenu.back()
    return
  end
  local row = p.rows[p.index]
  if not row then return end
  if row.activate then
    row.activate(ctx())
    return
  end
  OptionMenu.adjust(1)
end

function OptionMenu.back()
  local pages = OptionMenu._pages
  if pages and #pages > 1 then
    pages[#pages] = nil
    local p = page()
    OptionMenu.cursor = p and p.index or 1
    return
  end
  OptionMenu.close()
end

function OptionMenu.handleInput(input)
  if not input then return end
  if input:wasPressed("up") then OptionMenu.move(-1)
  elseif input:wasPressed("down") then OptionMenu.move(1)
  elseif input:wasPressed("left") then OptionMenu.adjust(-1)
  elseif input:wasPressed("right") then OptionMenu.adjust(1)
  elseif input:wasPressed("a") then OptionMenu.confirm()
  elseif input:wasPressed("b") or input:wasPressed("start") then OptionMenu.back()
  end
end

function OptionMenu.draw()
  if not OptionMenu.open then return end
  local p = page()
  if not p then return end
  local c = ctx()
  local frameType = tonumber(Options.block(c.options).frameType) or 0
  Window.userFrame(Window.template(1, 1, 28, 17), frameType)
  Window.print(p.title or "OPTION", 2, 2)

  local total = rowCount(p)
  clampScroll(p)
  for slot = 1, VISIBLE do
    local idx = p.scroll + slot
    if idx <= total then
      local y = Window.menuRowY(FIRST_ROW, slot)
      if idx == p.index then Window.cursor(2, y) end
      if idx > #p.rows then
        Window.print("BACK", LABEL_COL, y)
      else
        local row = p.rows[idx]
        Window.print(row.label or "?", LABEL_COL, y)
        if row.value then
          local ok, text = pcall(row.value, c)
          Window.print(ok and tostring(text) or "----", VALUE_COL, y)
        end
      end
    end
  end

  if total > VISIBLE then
    local FrlgFont = require("src.ui.game3.frlg_font")
    if p.scroll > 0 then
      FrlgFont.drawGlyph(FrlgFont.CHAR_UP_ARROW, 224, 26)
    end
    if p.scroll + VISIBLE < total then
      FrlgFont.drawGlyph(FrlgFont.CHAR_DOWN_ARROW, 224, 106)
    end
  end

  Window.print("LEFT/RIGHT:CHANGE  B:BACK", 2, 16)
end

return OptionMenu
