local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/teachy_fade_2891"

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
    print("PASS teachy_fade_2891")
    love.event.quit(0)
  else
    print("FAIL teachy_fade_2891 failures=" .. failures)
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
  local TvUi = require("src.ui.game3.teachy_tv")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_TEACHY_TV, 1)

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
  local function selectedName()
    local row = BagMenu.list()[BagMenu.cursor]
    return row and tostring(row.name) or nil
  end
  for _ = 1, 20 do
    if selectedName() == "TEACHY TV" then break end
    U.tap(game, "down")
    U.wait(8)
  end
  if not result(selectedName() == "TEACHY TV", "cursor on TEACHY TV") then return finish() end

  U.tap(game, "a")
  U.wait(25)
  U.tap(game, "a")

  -- pokefirered/src/item_menu.c:895
  local bagFading = false
  for _ = 1, 6 do
    U.wait(1)
    if BagMenu._exit and not TvUi.isOpen() then bagFading = true end
  end
  result(bagFading, "USE fades the bag out before the TV opens")
  U.still(game, DIR .. "/2891_01_bag_fading_out.png")

  local sawFadeIn = false
  for _ = 1, 30 do
    U.wait(1)
    if TvUi.isOpen() then
      local t = TvUi.fadeLevel()
      if t > 4 and t < 12 and not sawFadeIn then
        sawFadeIn = true
        U.still(game, DIR .. "/2891_02_tv_fading_in.png")
      end
    end
  end
  result(TvUi.isOpen(), "TV opened")
  -- pokefirered/src/teachy_tv.c:499
  result(sawFadeIn, "TV fades in from black")
  U.wait(30)
  U.still(game, DIR .. "/2891_03_tv_menu.png")

  U.tap(game, "b")
  local sawFadeOut = false
  for _ = 1, 20 do
    U.wait(1)
    if TvUi.isOpen() then
      local t = TvUi.fadeLevel()
      if t > 4 and t < 12 and not sawFadeOut then
        sawFadeOut = true
        U.still(game, DIR .. "/2891_04_tv_fading_out.png")
      end
    end
  end
  -- pokefirered/src/teachy_tv.c:691
  result(sawFadeOut, "B fades the TV out to black")
  result(not TvUi.isOpen(), "TV closed after the quit fade")

  local sawBagFadeIn = false
  for _ = 1, 4 do
    if BagMenu._open and BagMenu._open.k > 2 and BagMenu._open.k < 10 then
      sawBagFadeIn = true
      U.still(game, DIR .. "/2891_05_bag_fading_in.png")
      break
    end
    U.wait(1)
  end
  result(sawBagFadeIn, "bag fades back in from black")
  U.wait(40)
  result(BagMenu.isOpen() and BagMenu.mode == "list", "back on the bag list")
  U.still(game, DIR .. "/2891_06_bag_back.png")

  finish()
end
