local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_shop_sell"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_shop_sell failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    print("[driver] " .. label .. " error: " .. tostring(err))
    failures = failures + 1
  end
  return ok
end

local function body(game)
  local Runtime = require("src.core.game3.runtime")
  local Bag = require("src.core.game3.bag")
  local BagMenu = require("src.ui.game3.bag_menu")
  local ItemsData = require("src.core.game3.items_data")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session and session.version == "emerald", "emerald session") then return end

  session.bag = session.bag or Bag.new()
  local POTION = C:require("items", "ITEM_POTION")
  local BAG_PACK = C:require("items", "ITEM_POKE_BALL")
  Bag.add(session.bag, POTION, 3)
  session.money = 1000
  local Q = require("src.core.game3.quest_log_recorder")
  check(select(1, pcall(Q.event, session, "SoldItemsIncludingItem", { D0 = "X", D1 = "Y", D2 = 1 })), "quest log event is a no-op on Emerald")

  BagMenu.show(session.bag, { session = session, location = "shop" })
  U.wait(30)
  local row
  for i, r in ipairs(BagMenu.list()) do
    if tonumber(r.id) == POTION then row = i break end
  end
  check(row ~= nil, "potion in the bag")
  if not row then return end
  for _ = 1, 20 do
    if BagMenu.cursor == row then break end
    U.tap(game, "down")
    U.wait(6)
  end
  U.tap(game, "a")
  U.wait(20)
  check(BagMenu.mode == "sell" and BagMenu._sell ~= nil, "sell flow started")
  local flow = BagMenu._sell
  if not flow then return end
  check(flow.state == "qty", "quantity prompt for a stack of 3")
  check(flow.text:find("How many", 1, true) ~= nil, "how many text: " .. tostring(flow.text))
  U.wait(10)
  U.still(game, DIR .. "/qty.png")
  U.tap(game, "up")
  U.wait(6)
  check(flow.qty == 2, "quantity went to 2")
  U.tap(game, "a")
  U.wait(10)
  check(flow.state == "confirm", "confirm prompt")
  check(flow.text:find("I can pay", 1, true) ~= nil and flow.text:find(tostring(flow.unit * 2), 1, true) ~= nil,
    "price text: " .. tostring(flow.text))
  U.still(game, DIR .. "/confirm.png")
  local before = session.money
  U.tap(game, "a")
  U.wait(10)
  check(flow.state == "done" or flow.state == nil, "sale committed")
  check(session.money == before + flow.unit * 2, "money increased by " .. tostring(flow.unit * 2))
  check(Bag.get(session.bag, POTION) == 1, "two potions removed")
  check(flow.text:find(ItemsData.displayName(POTION), 1, true) ~= nil, "turned over text names the item: " .. tostring(flow.text))
  U.still(game, DIR .. "/done.png")
  U.tap(game, "a")
  U.wait(20)
  check(BagMenu.mode == "list", "back to the bag list")

  local SellFlow = require("src.ui.game3.sell_flow")
  local cant = SellFlow.start({ itemId = C:require("items", "ITEM_POKE_FLUTE"), session = session, bag = session.bag, owned = 1 })
  check(cant.state == "cant" and cant.text:find("can't buy", 1, true) ~= nil, "key item refusal text: " .. tostring(cant.text))
  check(pcall(function() cant:draw() end), "cant state draws")

  local CoinsBox = require("src.ui.game3.coins_box")
  CoinsBox.show(1, 1, 1234)
  check(pcall(function() CoinsBox.draw() end), "coins box draws on Emerald")
  U.wait(2)
  U.still(game, DIR .. "/coins.png")
  CoinsBox.hide()
  for _ = 1, 6 do
    U.tap(game, "b")
    U.wait(15)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  check(game.boot ~= nil, "boot reached")
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(30)
  try("body", function() body(game) end)
  return finish()
end
