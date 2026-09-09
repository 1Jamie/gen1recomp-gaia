-- Sevii region map UI — page art + landmark cursor (pret region_map field).

local RegionData = require("src.import.gba.region_map_sevii")
local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Display = require("src.core.game3.display")

local RegionMap = {}

RegionMap.open = false
RegionMap.page = 1
RegionMap.cursor = 1
RegionMap._images = {}

local function load_page_image(page)
  if not page or not page.image then return nil end
  local key = page.image
  if RegionMap._images[key] ~= nil then
    return RegionMap._images[key] or nil
  end
  local candidates = {
    "mods/Kanto-Reforged/" .. key,
    key,
    "sevii/" .. key,
    "mods/Kanto-Reforged/sevii/gba/chrome/menus/region_map/" .. (page.id or "page") .. ".png",
  }
  local okA, Assets = pcall(require, "src.render.Assets")
  for _, path in ipairs(candidates) do
    if okA and Assets and Assets.image then
      local ok, img = pcall(Assets.image, path)
      if ok and img then
        if img.setFilter then img:setFilter("nearest", "nearest") end
        RegionMap._images[key] = img
        return img
      end
    end
    local ok, img = pcall(love.graphics.newImage, path)
    if ok and img then
      if img.setFilter then img:setFilter("nearest", "nearest") end
      RegionMap._images[key] = img
      return img
    end
  end
  RegionMap._images[key] = false
  return nil
end

function RegionMap.show(opts)
  opts = opts or {}
  RegionMap.open = true
  RegionMap.page = 1
  RegionMap.cursor = 1
  RegionMap._onClose = opts.onClose
  RegionMap._session = opts.session
  Stack.push("region_map", RegionMap, { hideBelow = true })
end

function RegionMap.close()
  RegionMap.open = false
  Stack.pop("region_map")
  local cb = RegionMap._onClose
  RegionMap._onClose = nil
  if cb then cb() end
end

function RegionMap.pageCount()
  return #(RegionData.PAGES or {})
end

function RegionMap.currentPage()
  return RegionData.PAGES[RegionMap.page]
end

function RegionMap.togglePage(delta)
  local n = RegionMap.pageCount()
  if n < 1 then return end
  RegionMap.page = ((RegionMap.page - 1 + (delta or 1)) % n) + 1
  RegionMap.cursor = 1
end

function RegionMap.moveCursor(delta)
  local page = RegionMap.currentPage()
  local marks = page and page.landmarks or {}
  local n = #marks
  if n < 1 then return end
  RegionMap.cursor = ((RegionMap.cursor - 1 + delta) % n) + 1
end

function RegionMap.currentLandmark()
  local page = RegionMap.currentPage()
  local marks = page and page.landmarks or {}
  return marks[RegionMap.cursor]
end

function RegionMap.isOpen()
  return RegionMap.open
end

function RegionMap.draw()
  if not RegionMap.open then return end
  local page = RegionMap.currentPage()
  local img = load_page_image(page)

  -- Full-screen map layer.
  love.graphics.setColor(0.10, 0.35, 0.55, 1)
  love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
  love.graphics.setColor(1, 1, 1, 1)
  if img then
    local iw, ih = img:getDimensions()
    local sx = Display.W / iw
    local sy = Display.H / ih
    love.graphics.draw(img, 0, 0, 0, sx, sy)
  else
    -- Procedural placeholder matching page landmarks.
    Window.print(page and page.label or "SEVII", 1, 1)
    local marks = page and page.landmarks or {}
    for i, lm in ipairs(marks) do
      local px = lm.px or 40
      local py = lm.py or 40
      if i == RegionMap.cursor then
        love.graphics.setColor(1, 0.2, 0.2, 1)
      else
        love.graphics.setColor(1, 1, 0.3, 1)
      end
      love.graphics.rectangle("fill", px - 2, py - 2, 5, 5)
    end
    love.graphics.setColor(1, 1, 1, 1)
  end

  local lm = RegionMap.currentLandmark()
  -- Name plate (bottom).
  Window.stdFrame(Window.template(2, 16, 26, 2))
  Window.print(lm and lm.name or (page and page.label) or "", 3, 16)
  if img then
    -- Cursor crosshair on landmark.
    if lm and lm.px and lm.py then
      love.graphics.setColor(1, 0.15, 0.15, 1)
      love.graphics.rectangle("line", lm.px - 4, lm.py - 4, 9, 9)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
end

return RegionMap
