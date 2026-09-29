local T = require("tests.harness")
local check, eq = T.check, T.eq

local function romTextPlain(key) return key end
package.loaded["src.core.game3.rom_text"] = {
  plain = romTextPlain, box = romTextPlain, ascii = romTextPlain, has = function() return true end,
  key = function(n, i, j) return n end, at = function(n, i, j) return n end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local StartMenu = require("src.ui.game3.start_menu")
local Window = require("src.ui.game3.window")
local RseData = require("src.ui.game3.rse.start_menu_data")

-- Mock love for draw test
local loveStub = require("tests.love_stub")
_G.love = _G.love or loveStub

-- 1. Test standard 8-or-fewer entries (Vanilla Emerald without MODS)
do
  StartMenu.resetCursor()
  eq(StartMenu.cursor, 1, "Cursor is 1 after reset")
  eq(StartMenu._scrollOffset, 0, "Scroll offset is 0 after reset")

  local fakeSession = { name = "MAY", version = "emerald", bag = {}, party = {}, dex = {} }
  local fakeGame = { modStatus = { available = {} } } -- No mods -> 8 vanilla items (Dex, Mon, Bag, Nav, Name, Save, Option, Exit)

  StartMenu.show({ session = fakeSession, game = fakeGame })
  check(StartMenu.isOpen(), "StartMenu is open")
  eq(#StartMenu.ENTRIES, 8, "Vanilla Emerald has 8 entries with pokedex/pokemon/pokenav flags")

  local tpl = StartMenu.contentTemplate()
  eq(tpl.h, 18, "8 items window height is (8*2)+2 = 18 tiles")
  eq(tpl.top + tpl.h, 19, "Top(1) + Height(18) = 19 <= 19 (fits in 20-tile screen)")
  eq(StartMenu._scrollOffset, 0, "Scroll offset stays 0")

  -- Move down through all 8 items
  for i = 2, 8 do
    StartMenu.move(1)
    eq(StartMenu.cursor, i, "Cursor moved to " .. i)
    eq(StartMenu._scrollOffset, 0, "Scroll offset stays 0 for <= 8 items")
  end

  -- Wrap down from 8 to 1
  StartMenu.move(1)
  eq(StartMenu.cursor, 1, "Cursor wrapped to 1")
  eq(StartMenu._scrollOffset, 0, "Scroll offset stays 0")

  -- Wrap up from 1 to 8
  StartMenu.move(-1)
  eq(StartMenu.cursor, 8, "Cursor wrapped to 8")
  eq(StartMenu._scrollOffset, 0, "Scroll offset stays 0")

  StartMenu.close(true)
end

-- 2. Test 9 entries (Emerald with MODS menu entry)
do
  StartMenu.resetCursor()
  local fakeSession = { name = "MAY", version = "emerald", bag = {}, party = {}, dex = {} }
  local fakeGame = {
    modStatus = {
      available = {
        { id = "test_mod", name = "Test Mod", enabled = true },
      },
    },
  }

  StartMenu.show({ session = fakeSession, game = fakeGame })
  check(StartMenu.isOpen(), "StartMenu is open with mods")
  eq(#StartMenu.ENTRIES, 9, "Emerald with MODS has 9 entries")

  -- Window template must be capped at 8 visible entries
  local tpl = StartMenu.contentTemplate()
  eq(tpl.h, 18, "Window height is capped at (8*2)+2 = 18 tiles despite 9 entries")
  eq(tpl.top + tpl.h, 19, "Window bottom frame is within row 19 (no viewport clipping)")
  eq(StartMenu._scrollOffset, 0, "Initial scroll offset is 0")

  -- Navigate down to item 8
  for i = 2, 8 do
    StartMenu.move(1)
    eq(StartMenu.cursor, i, "Cursor is " .. i)
    eq(StartMenu._scrollOffset, 0, "Scroll offset is 0 while on items 1..8")
  end

  -- Navigate down to item 9 (EXIT) -> should scroll
  StartMenu.move(1)
  eq(StartMenu.cursor, 9, "Cursor is on item 9 (EXIT)")
  eq(StartMenu._scrollOffset, 1, "Scroll offset shifted to 1 to show items 2..9")

  -- Navigate down from item 9 -> wraps to item 1 (POKéDEX) and resets scroll
  StartMenu.move(1)
  eq(StartMenu.cursor, 1, "Cursor wrapped to item 1 (POKéDEX)")
  eq(StartMenu._scrollOffset, 0, "Scroll offset reset to 0 on wrap to top")

  -- Navigate up from item 1 -> wraps to item 9 (EXIT) and shifts scroll to bottom
  StartMenu.move(-1)
  eq(StartMenu.cursor, 9, "Cursor wrapped to item 9 (EXIT)")
  eq(StartMenu._scrollOffset, 1, "Scroll offset shifted to 1 on wrap to bottom")

  -- Navigate up to item 8 (MODS) -> scroll stays 1, cursor row is 7
  StartMenu.move(-1)
  eq(StartMenu.cursor, 8, "Cursor moved to item 8 (MODS)")
  eq(StartMenu._scrollOffset, 1, "Scroll offset stays 1")

  -- Navigate up until item 1
  for i = 7, 2, -1 do
    StartMenu.move(-1)
    eq(StartMenu.cursor, i, "Cursor is " .. i)
  end
  eq(StartMenu._scrollOffset, 1, "Scroll offset stays 1 until item 1 is reached")

  StartMenu.move(-1)
  eq(StartMenu.cursor, 1, "Cursor is 1")
  eq(StartMenu._scrollOffset, 0, "Scroll offset adjusted to 0 when cursor hits row 1")

  -- Verify draw executes cleanly when scrolled
  StartMenu.move(-1) -- Move to 9 (scrolled)
  local ok, err = pcall(StartMenu.draw)
  check(ok, "StartMenu.draw() executes cleanly while scrolled: " .. tostring(err))

  StartMenu.close(true)
end

-- 3. Test arbitrary large list (e.g. 14 modded entries)
do
  StartMenu.resetCursor()
  StartMenu.ENTRIES = {}
  for i = 1, 14 do
    table.insert(StartMenu.ENTRIES, { id = "item" .. i, label = "ITEM " .. i })
  end
  StartMenu._data = RseData
  StartMenu.open = true
  StartMenu.cursor = 1
  StartMenu.clampScroll()

  eq(StartMenu._scrollOffset, 0, "Scroll is 0")
  local tpl = StartMenu.contentTemplate()
  eq(tpl.h, 18, "Height is still 18 tiles max")

  -- Step down 10 times (to item 11)
  for i = 2, 11 do
    StartMenu.move(1)
  end
  eq(StartMenu.cursor, 11, "Cursor is 11")
  eq(StartMenu._scrollOffset, 3, "Scroll offset is 11 - 8 = 3 (showing items 4..11)")

  -- Step up 5 times (to item 6)
  for _ = 1, 5 do
    StartMenu.move(-1)
  end
  eq(StartMenu.cursor, 6, "Cursor is 6")
  eq(StartMenu._scrollOffset, 3, "Scroll offset remains 3 (item 6 is visible in 4..11)")

  -- Direct cursor assignment & clampScroll
  StartMenu.cursor = 14
  StartMenu.clampScroll()
  eq(StartMenu._scrollOffset, 6, "clampScroll sets scroll to 14 - 8 = 6 for item 14")

  StartMenu.cursor = 2
  StartMenu.clampScroll()
  eq(StartMenu._scrollOffset, 1, "clampScroll sets scroll to 1 for item 2")

  StartMenu.close(true)
end

-- 4. Test scroll arrow indicators during draw
do
  local ListMenu = require("src.ui.game3.list_menu")
  local capturedArrows = {}
  local origDrawScrollArrows = ListMenu.drawScrollArrows
  ListMenu.drawScrollArrows = function(tpl, showUp, showDown, t)
    capturedArrows[#capturedArrows + 1] = { up = showUp, down = showDown }
  end

  StartMenu.resetCursor()
  StartMenu.ENTRIES = {}
  for i = 1, 9 do
    table.insert(StartMenu.ENTRIES, { id = "item" .. i, label = "ITEM " .. i })
  end
  StartMenu._data = RseData
  StartMenu.open = true

  -- At top (scroll = 0): down arrow should be visible, up arrow hidden
  StartMenu.cursor = 1
  StartMenu.clampScroll()
  capturedArrows = {}
  StartMenu.draw()
  eq(#capturedArrows, 1, "drawScrollArrows called once")
  eq(capturedArrows[1].up, false, "Up arrow hidden at top")
  eq(capturedArrows[1].down, true, "Down arrow shown at top to indicate more items below")

  -- At bottom (scroll = 1): up arrow should be visible, down arrow hidden
  StartMenu.cursor = 9
  StartMenu.clampScroll()
  capturedArrows = {}
  StartMenu.draw()
  eq(#capturedArrows, 1, "drawScrollArrows called once")
  eq(capturedArrows[1].up, true, "Up arrow shown at bottom to indicate more items above")
  eq(capturedArrows[1].down, false, "Down arrow hidden at bottom")

  -- In middle of 14 items: both up and down arrows visible
  StartMenu.ENTRIES = {}
  for i = 1, 14 do
    table.insert(StartMenu.ENTRIES, { id = "item" .. i, label = "ITEM " .. i })
  end
  StartMenu.cursor = 6
  StartMenu._scrollOffset = 3
  capturedArrows = {}
  StartMenu.draw()
  eq(#capturedArrows, 1, "drawScrollArrows called once in middle")
  eq(capturedArrows[1].up, true, "Up arrow shown in middle")
  eq(capturedArrows[1].down, true, "Down arrow shown in middle")

  ListMenu.drawScrollArrows = origDrawScrollArrows
  StartMenu.close(true)
end

T.finish("game3_start_menu_scroll_test")
