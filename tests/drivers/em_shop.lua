local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_shop"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_shop failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local ShopMenu = require("src.ui.game3.shop_menu")
  local Marts = require("src.core.game3.marts")
  local DecorInv = require("src.core.game3.rse.decoration_inventory")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session and session.version == "emerald", "emerald session") then return finish() end
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_TORCHIC"), 5)
  local labels = Space.bundle and Space.bundle.labels or {}

  local function goTo(mapId, x, y, facing)
    try("Map.load " .. mapId, function() Map.load(nil, game, mapId, { x = x, y = y, facing = facing }) end)
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    U.wait(40)
  end
  local function waitFor(pred, frames, pressA)
    for i = 1, frames or 600 do
      if pred() then return true end
      if pressA and i % 12 == 0 then U.tap(game, "a") else U.wait(1) end
    end
    return pred()
  end
  local n = 0
  local function shot(name) n = n + 1 U.shot(game, string.format("%s/%02d_%s.png", DIR, n, name)) end
  local function settleFade() for _ = 1, 120 do if not ShopMenu._fading then break end U.wait(1) end U.wait(4) end

  -- pokeemerald/data/maps/OldaleTown_Mart/map.json:1
  goTo("EM_OLDALE_TOWN_MART", 3, 3, "left")
  U.wait(30)
  U.tap(game, "a")
  U.wait(30)
  print("[driver] after A: vm running " .. tostring(Space.vm:isRunning()) .. " key " .. tostring(Space.vm._scriptKey)
    .. " msg " .. tostring(Message.isOpen and Message.isOpen()) .. " facing " .. tostring(Player.facing))
  check(waitFor(function() return ShopMenu.isOpen() end, 600, true), "A across the counter runs the clerk and opens the mart")
  check(ShopMenu._rse ~= nil and ShopMenu._martType == "NORMAL", "Emerald shop path (MART_TYPE_NORMAL)")
  shot("mart_menu")
  local money0 = session.money
  U.tap(game, "a")
  settleFade()
  check(ShopMenu.state == "list" and ShopMenu.isShopCamera(), "BUY opens the buy list")
  local camera = ShopMenu.shopCameraOffset()
  check(camera and camera.x == -4 and camera.y == -4, "buy view offset from shop.c (-4,-4)")
  shot("buy_list")
  local potion = C:require("items", "ITEM_POTION")
  for _ = 1, 6 do
    if ShopMenu._items[ShopMenu.scroll + ShopMenu.row + 1] == potion then break end
    U.tap(game, "down")
    U.wait(4)
  end
  check(ShopMenu._items[ShopMenu.scroll + ShopMenu.row + 1] == potion, "cursor on POTION")
  shot("buy_list_potion")
  U.tap(game, "a")
  U.wait(4)
  check(ShopMenu.state == "qty", "how many prompt")
  U.tap(game, "up")
  U.wait(4)
  check(ShopMenu.qty == 2 and ShopMenu._totalCost == 600, "quantity 2 costs 600 (" .. tostring(ShopMenu._totalCost) .. ")")
  shot("how_many")
  U.tap(game, "a")
  U.wait(4)
  check(ShopMenu.state == "confirm", "YES/NO confirm")
  shot("confirm")
  U.tap(game, "a")
  U.wait(4)
  check(Bag.get(session.bag, potion) == 2 and session.money == money0 - 600,
    "bought 2 Potions (money " .. tostring(session.money) .. ")")
  shot("thanks")
  U.tap(game, "a")
  U.wait(4)
  check(ShopMenu.state == "list", "back to the list")
  U.tap(game, "b")
  settleFade()
  check(ShopMenu.state == "root" and not ShopMenu.isShopCamera(), "B returns to BUY/SELL/QUIT")
  shot("anything_else")
  U.tap(game, "down")
  U.wait(2)
  U.tap(game, "down")
  U.wait(2)
  U.tap(game, "a")
  check(waitFor(function() return not ShopMenu.isOpen() end, 120), "QUIT closes the mart")
  check(waitFor(function() return not Space.vm:isRunning() end, 600, true), "clerk script finishes")

  local key = 0x08000000 + require("src.import.gba.syms").of("emerald").off("LilycoveCity_DepartmentStore_5F_Pokemart_Dolls")
  local items, entry = Marts.itemsFor(key)
  check(items ~= nil and entry and entry.martType == "DECOR2", "Lilycove 5F doll list is a DECOR2 mart (" .. tostring(key) .. ")")
  goTo("EM_LILYCOVE_CITY_DEPARTMENT_STORE_5F", 7, 3, "up")
  session.money = 50000
  local closed = false
  try("openShop", function()
    Space.vm.adapters.openShop(key, function() closed = true end)
  end)
  check(ShopMenu.isOpen() and ShopMenu._martType == "DECOR2" and #ShopMenu._items == #items, "decoration shop opens (BUY/QUIT)")
  shot("decor_menu")
  U.tap(game, "a")
  settleFade()
  shot("decor_list")
  local doll = ShopMenu._items[1]
  local info = DecorInv.info(doll)
  check(info and info.category == 6, "first entry is a DOLL (" .. tostring(info and info.name) .. ")")
  U.tap(game, "a")
  U.wait(4)
  check(ShopMenu.state == "confirm", "decor goes straight to YES/NO")
  shot("decor_confirm")
  U.tap(game, "a")
  U.wait(4)
  check(DecorInv.has(doll, session) and DecorInv.countInCategory(6, session) == 1, "doll sent home into the DOLL inventory")
  check(session.money == 50000 - info.price, "doll price paid (" .. tostring(info.price) .. ")")
  shot("decor_thanks")
  U.tap(game, "a")
  U.wait(4)
  U.tap(game, "b")
  settleFade()
  U.tap(game, "b")
  U.wait(10)
  check(closed, "decoration shop returns to the script")
  local Ops = require("src.core.game3.scripting.ops_rse")
  local vmRse = require("src.core.game3.rse.init")
  local r, handled = vmRse.call("decorations", "checkSpace", "checkdecorspace", nil, doll)
  check(handled and r == true, "decorations system answers checkdecorspace")
  check(Ops.HANDLERS.checkdecor ~= nil, "ops_rse routes checkdecor")
  finish()
end
