local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/2909_frlg_map_popup"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " 2909_frlg_map_popup failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Popup = require("src.ui.game3.map_name_popup")
  local Chrome = require("src.ui.game3.chrome")
  if not check(Runtime.getSession() ~= nil, "new game reached the field") then return finish() end

  local frames, lastTranslate = {}, nil
  local origFrame = Chrome.fixedStdFrame
  Chrome.fixedStdFrame = function(tx, ty, tw, th)
    frames[#frames + 1] = { tx, ty, tw, th, lastTranslate }
    return origFrame(tx, ty, tw, th)
  end
  local origDraw = Popup.draw
  Popup.draw = function(...)
    local tr = love.graphics.translate
    love.graphics.translate = function(x, y)
      lastTranslate = y
      return tr(x, y)
    end
    local ok, err = pcall(origDraw, ...)
    love.graphics.translate = tr
    if not ok then error(err) end
  end

  local okLoad = pcall(Map.load, Runtime._mod, game, "FR_ROUTE_1", { x = 12, y = 38, facing = "down" })
  check(okLoad and Map.current == "FR_ROUTE_1", "Route 1 loads")
  local s = Runtime.getSession()
  s.x, s.y, s.facing = 12, 38, "down"
  Player.reset(12, 38, "down")
  U.wait(40)
  local Space = require("src.core.game3.scripting.space")
  if Space.vm and Space.vm:isRunning() then Space.vm:halt(true) end
  require("src.core.game3.field").unlock()
  U.wait(5)
  Popup.dismiss()

  local entered, slideShot = false, false
  for _ = 1, 3 do
    Player.tryMove("down", game, false)
    for _ = 1, 90 do
      if Popup._state == Popup.STATE.SLIDE_IN and Popup._tPos == 12 and not slideShot then
        slideShot = U.still(game, DIR .. "/2909_01_slide_in.png")
      end
      U.wait(1)
      if not Player.moving and (tonumber(Player.turnTimer) or 0) <= 0 then break end
    end
    if Map.current == "FR_PALLET_TOWN" then entered = true break end
  end
  check(entered, "walking south from Route 1 enters Pallet Town")
  check(Popup._state ~= Popup.STATE.IDLE, "connection shows the FRLG map name popup")
  check(Popup._name == "PALLET TOWN", "popup name " .. tostring(Popup._name))

  local slid = 0
  while Popup._state == Popup.STATE.SLIDE_IN and slid < 60 do
    if Popup._tPos == 12 and not slideShot then
      slideShot = U.still(game, DIR .. "/2909_01_slide_in.png")
    end
    U.wait(1)
    slid = slid + 1
  end
  check(Popup._state == Popup.STATE.HOLD, "popup reached hold")
  U.wait(30)
  frames = {}
  U.still(game, DIR .. "/2909_02_pallet_popup_hold.png")
  U.wait(2)
  local f = frames[#frames]
  check(f ~= nil, "popup drew a std window frame")
  if f then
    check(f[1] == 1 and f[2] == 1 and f[3] == 14 and f[4] == 2,
      string.format("window is 14x2 tiles at tilemapLeft 1 (got %s,%s,%s,%s)", f[1], f[2], f[3], f[4]))
    check(f[5] == 0, "held popup shows its top border row at y=0 (translate " .. tostring(f[5]) .. ")")
  end

  for _ = 1, 400 do
    if Popup._state == Popup.STATE.IDLE then break end
    U.wait(1)
  end
  check(Popup._state == Popup.STATE.IDLE, "popup slides out and ends")
  Chrome.fixedStdFrame = origFrame
  Popup.draw = origDraw
  return finish()
end
