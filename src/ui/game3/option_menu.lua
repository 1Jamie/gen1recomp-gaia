-- FRLG Option menu (option_menu.c subset used on field).

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Options = require("src.core.game3.options")

local OptionMenu = {}

OptionMenu.open = false
OptionMenu.cursor = 1

local ROWS = {
  { key = "textSpeed", label = "TEXT SPEED", values = { "SLOW", "MID", "FAST" } },
  { key = "battleScene", label = "BATTLE SCENE", values = { "ON", "OFF" } },
  { key = "battleStyle", label = "BATTLE STYLE", values = { "SHIFT", "SET" } },
  { key = "sound", label = "SOUND", values = { "MONO", "STEREO" } },
  { key = "buttonMode", label = "BUTTON MODE", values = { "NORMAL", "LR", "L=A" } },
  { key = "_cancel", label = "CANCEL", values = nil },
}

local FIRST_ROW = 4

function OptionMenu.show(opts)
  opts = opts or {}
  OptionMenu.open = true
  OptionMenu.cursor = 1
  OptionMenu._session = opts.session
  OptionMenu._onClose = opts.onClose
  Options.ensure(opts.session)
  Stack.push("option", OptionMenu, { hideBelow = true })
end

function OptionMenu.close()
  OptionMenu.open = false
  Stack.pop("option")
  local cb = OptionMenu._onClose
  OptionMenu._onClose = nil
  if cb then cb() end
end

function OptionMenu.isOpen()
  return OptionMenu.open
end

function OptionMenu.move(delta)
  local n = #ROWS
  OptionMenu.cursor = ((OptionMenu.cursor - 1 + delta) % n) + 1
end

function OptionMenu.adjust(delta)
  local row = ROWS[OptionMenu.cursor]
  if not row or not row.values then return end
  local session = OptionMenu._session
  local o = Options.ensure(session)
  local cur = tonumber(o[row.key]) or 0
  local n = #row.values
  cur = ((cur + delta) % n + n) % n
  Options.set(session, row.key, cur)
end

function OptionMenu.confirm()
  local row = ROWS[OptionMenu.cursor]
  if not row then return end
  if row.key == "_cancel" then
    OptionMenu.close()
    return
  end
  OptionMenu.adjust(1)
end

function OptionMenu.draw()
  if not OptionMenu.open then return end
  local session = OptionMenu._session
  local o = Options.ensure(session)
  -- 6 rows × 2 tiles + header → need ~16 content tiles.
  Window.stdFrame(Window.template(1, 1, 28, 16))
  Window.print("OPTION", 2, 2)
  for i, row in ipairs(ROWS) do
    local y = Window.menuRowY(FIRST_ROW, i)
    if i == OptionMenu.cursor then Window.cursor(2, y) end
    Window.print(row.label, 3, y)
    if row.values then
      local idx = (tonumber(o[row.key]) or 0) + 1
      local lab = row.values[idx] or "?"
      Window.print(lab, 18, y)
    end
  end
  Window.print("LR:CHANGE  A:OK  B:CLOSE", 2, 17)
end

return OptionMenu
