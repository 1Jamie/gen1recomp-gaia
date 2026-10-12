local U = dofile("tests/drivers/util.lua")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/2907_trainer_card_pic"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS 2907_trainer_card_pic")
    love.event.quit(0)
  else
    print("FAIL 2907_trainer_card_pic failures=" .. failures)
    love.event.quit(1)
  end
end

local function loadShot(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local bytes = f:read("*a")
  f:close()
  return love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
end

local function sameTile(img, ax, ay, bx, by)
  local w, h = img:getDimensions()
  local s = math.floor(math.min(w / 160, h / 144))
  local ox, oy = math.floor((w - 160 * s) / 2), math.floor((h - 144 * s) / 2)
  for j = 0, 8 * s - 1 do
    for i = 0, 8 * s - 1 do
      local r1, g1, b1 = img:getPixel(ox + ax * 8 * s + i, oy + ay * 8 * s + j)
      local r2, g2, b2 = img:getPixel(ox + bx * 8 * s + i, oy + by * 8 * s + j)
      if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 then return false end
    end
  end
  return true
end

return function(game)
  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  game.save.player.name = "RED"

  local TrainerCard = require("src.ui.TrainerCard")
  local card = TrainerCard.new(game)
  if not result(card.picQuad ~= nil, "player pic loaded") then return finish() end
  local qx, qy, qw, qh = card.picQuad:getViewport()
  -- engine/menus/start_sub_menus.asm:488
  result(qx == 8 and qy == 0, ("pic starts at pic column 1 (viewport %d,%d)"):format(qx, qy))
  result(qw == 32, ("four pic columns visible (w=%d)"):format(qw))
  -- engine/menus/start_sub_menus.asm:599
  result(qh == 48, ("six pic rows visible (h=%d)"):format(qh))

  game.stack:push(card)
  U.wait(5)
  local path = DIR .. "/2907_01_trainer_card_pic.png"
  U.shot(game, path)
  local img = loadShot(path)
  if result(img ~= nil, "screenshot readable") then
    local rightOk = true
    for row = 1, 6 do
      if not sameTile(img, 19, row, 18, 11) then rightOk = false end
    end
    result(rightOk, "card right edge at column 19 rows 1-6 not covered by the pic")
    local bottomOk = true
    for col = 15, 18 do
      if not sameTile(img, col, 7, 1, 7) then bottomOk = false end
    end
    result(bottomOk, "card bottom edge at row 7 hides the pic's feet")
  end
  U.tap(game, "b")
  U.wait(3)
  finish()
end
