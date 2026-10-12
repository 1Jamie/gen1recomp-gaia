local PcChrome = require("src.ui.game3.pc_chrome")
local Font = require("src.ui.game3.frlg_font")
local Popup = require("src.ui.game3.rs.storage_popup")

local M = {}

-- pokefirered/src/pokemon_storage_system_menu.c:488-511
M.SIDES = {
  sprites = { box_popup_sides = { rects = {
    { x = 0, y = 0, w = 8, h = 32 }, { x = 0, y = 32, w = 8, h = 16 },
    { x = 0, y = 48, w = 8, h = 32 }, { x = 0, y = 80, w = 8, h = 16 },
  } } },
  -- pokefirered/src/pokemon_storage_system_menu.c:554-564
  boxPopup = { sides = {
    { x = 124, y = 80, frame = 0 }, { x = 124, y = 112, frame = 1 },
    { x = 196, y = 80, frame = 2 }, { x = 196, y = 112, frame = 3 },
  } },
}
-- pokefirered/src/pokemon_storage_system_menu.c:543
M.CENTER_X, M.CENTER_Y = 160, 96

function M.boxCount(box)
  local count = 0
  for i = 1, 30 do if box and box.mons and box.mons[i] then count = count + 1 end end
  return count
end

-- pokefirered/src/pokemon_storage_system_menu.c:642
function M.arrowOffset(frames)
  return math.floor((tonumber(frames) or 0) / 4) % 6
end

local function count_text(n)
  -- pokefirered/src/pokemon_storage_system_menu.c:631
  return (n < 10 and " " or "") .. tostring(n)
end

local function colors()
  local P = assert(PcChrome._manifest and PcChrome._manifest.palettes and PcChrome._manifest.palettes.misc1,
    "storage choose-box palette missing from cache")
  local function c(i) local v = P[i]; return { v[1] / 255, v[2] / 255, v[3] / 255, 1 } end
  -- pokefirered/src/pokemon_storage_system_menu.c:639
  return { bg = c(4), fg = c(15), shadow = c(14) }
end

local function fill(col, x, y, w, h)
  love.graphics.setColor(col)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(1, 1, 1, 1)
end

-- pokefirered/src/pokemon_storage_system_menu.c:620
local function text_frlg(name, count, col)
  fill(col.bg, 128, 72, 64, 16)
  Font.draw(name, 128, 74, { colors = col, maxWidth = 64 })
  fill(col.bg, 152, 88, 40, 16)
  Font.draw(count_text(count), 152, 90, { colors = col, maxWidth = 16 })
  Font.draw("/30", 168, 90, { colors = col, maxWidth = 24 })
end

-- pokeemerald/src/pokemon_storage_system.c:1921
local function text_rse(name, count, col)
  fill(col.bg, 128, 72, 64, 32)
  local function centered(text, y)
    local w = Font.measure(text)
    Font.draw(text, 128 + math.max(0, math.floor((64 - w) / 2)), y, { colors = col, maxWidth = 64 })
  end
  centered(name, 73)
  centered(count_text(count) .. "/30", 89)
end

function M.draw(storage, boxId, frames, family)
  PcChrome.ensure()
  local center = assert(PcChrome._chooseBoxCenterImg, "storage choose-box center missing from cache")
  local sides = assert(PcChrome._chooseBoxSidesImg, "storage choose-box sides missing from cache")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(center, M.CENTER_X - 32, M.CENTER_Y - 32)
  for _, p in ipairs(Popup.sidePlacements(M.SIDES)) do
    local r = p.rect
    love.graphics.draw(sides, love.graphics.newQuad(r.x, r.y, r.w, r.h, sides:getDimensions()), p.x, p.y)
  end
  local arrow = PcChrome._arrowImg
  if arrow then
    local dx = M.arrowOffset(frames)
    -- pokefirered/src/pokemon_storage_system_menu.c:572
    for i = 0, 1 do
      local q = love.graphics.newQuad(0, i * 16, 8, 16, arrow:getDimensions())
      love.graphics.draw(arrow, q, 72 * i + 120 + (i == 0 and -dx or dx), 80)
    end
  end
  local box = assert(storage.boxes[boxId])
  local col = colors()
  if family == "rse" then text_rse(box.name or "", M.boxCount(box), col)
  else text_frlg(box.name or "", M.boxCount(box), col) end
end

return M
