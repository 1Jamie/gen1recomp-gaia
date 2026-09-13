#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

package.loaded["src.core.game3.audio"] = { playSe = function() return true end }
package.loaded["src.ui.game3.window"] = package.loaded["src.ui.game3.window"] or {}
package.loaded["src.core.game3.scripting.space"] = nil
package.loaded["src.core.game3.scripting.flags"] = nil

local Stack = require("src.ui.game3.stack")
local StartMenu = require("src.ui.game3.start_menu")

local function rowOf(id)
  for i, e in ipairs(StartMenu.ENTRIES) do
    if e.id == id then return i end
  end
end

Stack.clear()
StartMenu.resetCursor()
StartMenu.show({ session = { name = "RED" } })
check(StartMenu.cursor == 1, "fresh boot opens on row 1")
StartMenu.move(1)
StartMenu.move(1)
StartMenu.move(1)
check(StartMenu.cursor == 4, "moved to row 4")
StartMenu.close()
check(not StartMenu.isOpen() and Stack.depth() == 0, "B/START close pops the menu")

StartMenu.show({ session = { name = "RED" } })
check(StartMenu.cursor == 4, "reopen keeps row 4 (start_menu.c:64/329)")

local exitRow = rowOf("exit")
StartMenu.cursor = exitRow
StartMenu.confirm()
check(not StartMenu.isOpen() and Stack.depth() == 0, "EXIT closes")
StartMenu.show({ session = { name = "RED" } })
check(StartMenu.cursor == exitRow, "reopen after EXIT stays on EXIT")
StartMenu.close()

StartMenu.cursor = 9
StartMenu.show({ session = { name = "RED" } })
check(StartMenu.cursor == 1, "out-of-range saved row falls back to row 1 (menu.c:276)")
StartMenu.close()

StartMenu.cursor = 5
StartMenu.resetCursor()
StartMenu.show({ session = { name = "RED" } })
check(StartMenu.cursor == 1, "resetCursor returns to row 1")
StartMenu.close()

local f = io.open("src/core/Game3.lua", "r")
local src = f and f:read("*a") or ""
if f then f:close() end
local loadBody = src:match("function Game3:load%(.-\nend\n") or ""
check(loadBody:find("resetCursor", 1, true) ~= nil, "Game3:load resets the cursor on boot (main.c:134)")
local enterBody = src:match("function Game3:_enterField%(.-\nend\n") or ""
check(enterBody:find("resetCursor", 1, true) == nil, "continue / new game do not reset the cursor")

if failed > 0 then
  print(("game3_start_menu_cursor_test: %d failure(s)"):format(failed))
  os.exit(1)
end
print("game3_start_menu_cursor_test: all passed")
