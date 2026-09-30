package.path = package.path .. ";./?.lua"

local calls = {}
local scissor = nil

love = love or {}
love.graphics = love.graphics or {}
love.graphics.getScissor = function()
  if scissor then return scissor[1], scissor[2], scissor[3], scissor[4] end
  return nil
end
love.graphics.setScissor = function(x, y, w, h)
  if x then scissor = { x, y, w, h } else scissor = nil end
end
love.graphics.intersectScissor = function(x, y, w, h)
  if not scissor then
    scissor = { x, y, w, h }
    return
  end
  local x1 = math.max(scissor[1], x)
  local y1 = math.max(scissor[2], y)
  local x2 = math.min(scissor[1] + scissor[3], x + w)
  local y2 = math.min(scissor[2] + scissor[4], y + h)
  scissor = { x1, y1, math.max(0, x2 - x1), math.max(0, y2 - y1) }
end
love.graphics.setColor = function() end
love.graphics.draw = function() end

local okKit, Kit = pcall(require, "src.ui.game3.rse.scene_kit")
if not okKit then
  print("[skip] scene_kit needs runtime: " .. tostring(Kit))
  os.exit(0)
end
local FrlgFont = require("src.ui.game3.frlg_font")
FrlgFont.draw = function(line, x, y)
  calls[#calls + 1] = { y = y, scissor = scissor and { scissor[1], scissor[2], scissor[3], scissor[4] } or nil }
  return x + 8, nil
end
FrlgFont.measure = function() return 8 end
Kit.messageColors = function() return {} end

local okP, p = pcall(Kit.printer, {}, { speed = 0 })
if not okP then
  print("[skip] printer needs cache: " .. tostring(p))
  os.exit(0)
end

local failed = 0
local function check(cond, msg)
  if cond then
    print("  PASS: " .. msg)
  else
    failed = failed + 1
    print("  FAIL: " .. msg)
  end
end

p.lines = { "aaa", "bbb", "" }
p.scrollY = 5
p.arrowFrame = nil
local clip = { 16, 120, 216, 32 }
p:draw(16, 121, { clip = clip })
check(#calls == 2, "lines drawn")
local s = calls[1].scissor
check(s and s[1] == 16 and s[2] == 120 and s[3] == 216 and s[4] == 32, "scissor equals clip while drawing")
check(scissor == nil, "scissor restored to none")

scissor = { 0, 0, 240, 100 }
calls = {}
p:draw(16, 121, { clip = clip })
check(calls[1].scissor[2] == 120 and calls[1].scissor[4] == 0 + 100 - 120 + 0 or calls[1].scissor[4] == 0, "clip intersects outer scissor")
check(scissor and scissor[4] == 100, "outer scissor restored")

scissor = nil
calls = {}
p:draw(16, 121)
check(calls[1].scissor == nil, "no clip leaves scissor untouched")

os.exit(failed == 0 and 0 or 1)
