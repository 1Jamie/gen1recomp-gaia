local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/bag_select_icon_2892"

-- pokefirered/include/constants/items.h:438
local ITEM_TEACHY_TV = 366

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS bag_select_icon_2892")
    love.event.quit(0)
  else
    print("FAIL bag_select_icon_2892 failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Bag = require("src.core.game3.bag")
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local BagChrome = require("src.ui.game3.bag_chrome")
  local FrlgFont = require("src.ui.game3.frlg_font")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_TEACHY_TV, 1)
  session.registeredItem = ITEM_TEACHY_TV

  local selectDraws = {}
  local origSelect = BagChrome.drawSelectButton
  BagChrome.drawSelectButton = function(x, y)
    selectDraws[#selectDraws + 1] = { x = x, y = y }
    return origSelect(x, y)
  end
  local labels = {}
  local origDraw = FrlgFont.draw
  FrlgFont.draw = function(text, x, y, opts)
    if x == 97 and type(text) == "string" and text:find("TEACHY", 1, true) then
      labels[#labels + 1] = text
    end
    return origDraw(text, x, y, opts)
  end

  U.tap(game, "start")
  U.wait(30)
  for _ = 1, 12 do
    local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
    if e and e.id == "bag" then break end
    U.tap(game, "down")
    U.wait(8)
  end
  U.tap(game, "a")
  U.wait(60)
  if not result(BagMenu.isOpen(), "bag opened") then return finish() end
  for _ = 1, 4 do
    if BagMenu.currentPocket() == "KEY_ITEMS" then break end
    U.tap(game, "right")
    U.wait(15)
  end
  result(BagMenu.currentPocket() == "KEY_ITEMS", "on KEY ITEMS")
  U.wait(30)
  selectDraws, labels = {}, {}
  U.still(game, DIR .. "/2892_01_key_items_registered.png")
  U.wait(2)

  -- pokefirered/src/item_menu.c:668
  result(#labels > 0 and labels[1] == "TEACHY TV",
    "the row prints the bare item name, got '" .. tostring(labels[1]) .. "'")
  -- pokefirered/src/item_menu.c:720
  local d = selectDraws[1]
  result(d ~= nil and d.x == 88 + 0x70, "the SELECT icon is blitted at window x 0x70, got " .. tostring(d and d.x))

  session.registeredItem = nil
  selectDraws = {}
  U.wait(4)
  result(#selectDraws == 0, "no SELECT icon once nothing is registered")

  BagChrome.drawSelectButton = origSelect
  FrlgFont.draw = origDraw
  finish()
end
