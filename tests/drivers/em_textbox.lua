local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_textbox"
local REF = os.getenv("POKEPORT_EM_TEXTBOX_REF") or ".bazinga/emerald/ref/textbox_daycare_sign/frame-002100.png"

-- pokeemerald/data/maps/Route117/map.json:371
local SIGN_X, SIGN_Y = 49, 5
local SIGN_TEXT = "g3:081f3d8e"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_textbox failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function writePng(data, path)
  local fd = data:encode("png")
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(fd:getString())
  f:close()
  return true
end

local function loadPng(path)
  local f = io.open(path, "rb") or io.open(love.filesystem.getSource() .. "/" .. path, "rb")
  if not f then return nil end
  local bytes = f:read("*a")
  f:close()
  return love.image.newImageData(love.filesystem.newFileData(bytes, "ref.png"))
end

local function nativeFrame()
  local Display = require("src.core.game3.display")
  local canvas = Display._canvas
  return canvas and canvas:newImageData() or nil
end

local function frameMask()
  local Chrome = require("src.ui.game3.chrome")
  local canvas = love.graphics.newCanvas(240, 160)
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  Chrome.dialogueFrame()
  love.graphics.setCanvas()
  love.graphics.pop()
  return canvas:newImageData()
end

local function to8(v) return math.floor(v * 255 + 0.5) end

local function compareBox(ours, ref, mask, diffPath)
  local Chrome = require("src.ui.game3.chrome")
  local L, Top, W, H = Chrome.dialogueWindow()
  local x0, y0, x1, y1 = L * 8, Top * 8, (L + W) * 8 - 1, (Top + H) * 8 - 1
  local out = love.image.newImageData(240, 48 * 3)
  local stats = { frame = 0, frameBad = 0, frameOff1 = 0, window = 0, windowBad = 0, windowOff1 = 0 }
  for y = 112, 159 do
    for x = 0, 239 do
      local r1, g1, b1 = ours:getPixel(x, y)
      local r2, g2, b2 = ref:getPixel(x, y)
      local _, _, _, a = mask:getPixel(x, y)
      out:setPixel(x, y - 112, r1, g1, b1, 1)
      out:setPixel(x, y - 112 + 48, r2, g2, b2, 1)
      local inWindow = x >= x0 and x <= x1 and y >= y0 and y <= y1
      local d = math.max(math.abs(to8(r1) - to8(r2)), math.abs(to8(g1) - to8(g2)), math.abs(to8(b1) - to8(b2)))
      if inWindow or a > 0.5 then
        local key = inWindow and "window" or "frame"
        stats[key] = stats[key] + 1
        if d > 1 then
          stats[key .. "Bad"] = stats[key .. "Bad"] + 1
          out:setPixel(x, y - 112 + 96, 1, 0, 0, 1)
        elseif d == 1 then
          stats[key .. "Off1"] = stats[key .. "Off1"] + 1
          out:setPixel(x, y - 112 + 96, 1, 1, 0, 1)
        else
          out:setPixel(x, y - 112 + 96, 0, 0, 0, 1)
        end
      else
        out:setPixel(x, y - 112 + 96, 0.2, 0.2, 0.2, 1)
      end
    end
  end
  writePng(out, diffPath)
  return stats
end

return function(game)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Message = package.loaded["src.ui.game3.message"] or require("src.ui.game3.message")
  local TextIR = require("src.core.game3.scripting.text_ir")
  local FrlgFont = require("src.ui.game3.frlg_font")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  result(TextIR.dialectOf() == "rse", "text dialect is rse")

  local okLoad, errLoad = pcall(function()
    Map.load(nil, game, "EM_ROUTE117", { x = SIGN_X, y = SIGN_Y + 1, facing = "up" })
  end)
  result(okLoad, "Route 117 loads " .. tostring(errLoad or ""))
  session = Runtime.getSession()
  session.x, session.y, session.facing = SIGN_X, SIGN_Y + 1, "up"
  Player.cellX, Player.cellY = SIGN_X, SIGN_Y + 1
  Player.px, Player.py = SIGN_X * 16, (SIGN_Y + 1) * 16
  Player.targetX, Player.targetY = SIGN_X, SIGN_Y + 1
  Player.facing = "up"
  U.wait(60)

  U.tap(game, "a")
  local opened = false
  for _ = 1, 120 do
    if Message.isOpen() then opened = true break end
    U.wait(1)
  end
  result(opened, "A on the Day Care sign opened its message")
  if not opened then
    local CacheFs = require("src.import.CacheFs")
    local texts = CacheFs.loadActive("data/generated/gba/scripts/text.lua")
    local ir = type(texts) == "table" and texts[SIGN_TEXT]
    if not result(ir ~= nil, "cached sign text " .. SIGN_TEXT) then return finish() end
    Message.show(ir, { stay = true })
  end
  for _ = 1, 600 do
    if Message.isOpen() and not Message.isTyping() then break end
    U.wait(1)
  end
  result(Message.currentPage() == "POKéMON DAY CARE\n“Let us raise your POKéMON.”", "sign text: " .. Message.currentPage())
  U.wait(4)
  U.still(game, DIR .. "/em_textbox_01_daycare_sign.png")
  local ours = nativeFrame()
  if not result(ours ~= nil, "native 240x160 frame") then return finish() end
  writePng(ours, DIR .. "/em_textbox_02_daycare_sign_native.png")

  local ref = loadPng(REF)
  if result(ref ~= nil, "pygba reference " .. REF) then
    local s = compareBox(ours, ref, frameMask(), DIR .. "/em_textbox_03_box_ours_ref_diff.png")
    print(string.format("[driver] frame pixels %d: %d differ by more than 1, %d by exactly 1 (bgr555 rounding)",
      s.frame, s.frameBad, s.frameOff1))
    print(string.format("[driver] window pixels %d: %d differ by more than 1, %d by exactly 1",
      s.window, s.windowBad, s.windowOff1))
    result(s.frame > 0 and s.frameBad == 0, "dialogue frame matches pygba pixel for pixel (colour within 1/255)")
    result(s.window > 0 and s.windowBad == 0 and s.windowOff1 == 0, "window fill and glyphs match pygba exactly")
  end

  local rival = TextIR.toPlain(TextIR.decode({ 0xFD, 0x06, 0xFF }, { dialect = "rse" }), { rivalName = "BLUE" })
  result(rival == "MAY", "FD 06 for a male player reads the cached rival placeholder (" .. rival .. ")")

  Message.close()
  U.wait(2)
  Message.show(TextIR.fromAscii("PAGE ONE\\pPAGE TWO"), {})
  for _ = 1, 600 do
    if Message.isWaiting() then break end
    U.wait(1)
  end
  for i = 0, 3 do
    U.still(game, string.format("%s/em_textbox_04_down_arrow_%d.png", DIR, i))
    U.wait(9)
  end
  result(FrlgFont.linePitch() == 16, "FONT_NORMAL line pitch is 16")
  Message.close()
  finish()
end
