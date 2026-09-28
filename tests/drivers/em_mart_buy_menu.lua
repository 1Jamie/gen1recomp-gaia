local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_mart_buy_menu"
local MAP = os.getenv("MART_MAP") or "EM_OLDALE_TOWN_MART"
local MX, MY = tonumber(os.getenv("MART_X")) or 3, tonumber(os.getenv("MART_Y")) or 3
local FACE = os.getenv("MART_FACE") or "left"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_mart_buy_menu failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function resize(w, h)
  love.window.setMode(w, h, { resizable = true })
  if love.resize then love.resize(w, h) end
  U.wait(6)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local ShopMenu = require("src.ui.game3.shop_menu")
  local session = Runtime.getSession()
  local mapId = require("src.import.gba.map_catalog").resolve(MAP) or MAP
  Map.load(nil, game, mapId, { x = MX, y = MY, facing = FACE })
  session.x, session.y, session.facing = MX, MY, FACE
  Player.cellX, Player.cellY, Player.px, Player.py = MX, MY, MX * 16, MY * 16
  Player.targetX, Player.targetY, Player.facing = MX, MY, FACE
  U.wait(40)
  for i = 1, 600 do
    if ShopMenu.isOpen() then break end
    if i % 12 == 0 then U.tap(game, "a") else U.wait(1) end
  end
  if not check(ShopMenu.isOpen(), "mart opened") then return finish() end
  U.tap(game, "a")
  for _ = 1, 120 do if not ShopMenu._fading and ShopMenu.isShopCamera() then break end U.wait(1) end
  U.wait(6)
  check(ShopMenu.isShopCamera(), "buy list open")
  local shapes = { { "land", 960, 640 }, { "portrait", 460, 1000 } }
  for _, s in ipairs(shapes) do
    resize(s[2], s[3])
    U.still(game, DIR .. "/" .. s[1] .. "_01_buy.png")
    U.tap(game, "down")
    U.wait(4)
    U.still(game, DIR .. "/" .. s[1] .. "_02_down.png")
    U.tap(game, "up")
    U.wait(4)
  end
  for _ = 1, 12 do U.tap(game, "down") U.wait(3) end
  U.still(game, DIR .. "/portrait_03_cancel.png")
  local Tilt, Zoom = require("src.render.Tilt"), require("src.render.Zoom")
  Tilt.enabled = true
  Tilt.setLevel(2)
  Zoom.offset = -1
  resize(1600, 900)
  U.wait(60)
  U.still(game, DIR .. "/wide_zoom_tilt.png")
  finish()
end
