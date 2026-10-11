package.path = package.path .. ";./?.lua"

local passed, failed = 0, 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print("  PASS: " .. name)
  else
    failed = failed + 1
    print("  FAIL: " .. name .. " -> " .. tostring(err))
  end
end

local uploads = 0

local Data = {}
Data.__index = Data
local function newData(w, h)
  return setmetatable({ w = w, h = h, px = {} }, Data)
end
function Data:getWidth() return self.w end
function Data:getHeight() return self.h end
function Data:getDimensions() return self.w, self.h end
function Data:getFormat() return "rgba8" end
function Data:paste(src, dx, dy, sx, sy, sw, sh)
  for y = 0, sh - 1 do
    for x = 0, sw - 1 do
      self.px[(dy + y) * self.w + dx + x] = src.px[(sy + y) * src.w + sx + x]
    end
  end
end
function Data:setFilter() end

local Image = setmetatable({}, { __index = Data })
Image.__index = Image
function Image:replacePixels(src, _, _, x, y)
  uploads = uploads + 1
  self:paste(src, x or 0, y or 0, 0, 0, src.w, src.h)
end
local function newImage(data)
  local img = setmetatable({ w = data.w, h = data.h, px = {} }, Image)
  img:paste(data, 0, 0, 0, 0, data.w, data.h)
  return img
end

love = {
  graphics = { newImage = newImage },
  image = { newImageData = function(w, h) return newData(w, h) end },
}

local NativeTileset = require("src.core.game3.tileset_native")

local COLS, ROWS = 16, 64
local W, H = COLS * 16, ROWS * 16

local function atlas()
  local data = newData(W, H)
  for i = 0, W * H - 1 do data.px[i] = i % 7 end
  return { cols = COLS, imageData = data, image = newImage(data), imageAlt = newImage(data) }
end

local function same(img, data)
  for i = 0, W * H - 1 do
    if img.px[i] ~= data.px[i] then return false, i end
  end
  return true
end

local function animate(ts, slots, value)
  for _, slot in ipairs(slots) do
    local x0, y0 = (slot % COLS) * 16, math.floor(slot / COLS) * 16
    for y = 0, 15 do
      for x = 0, 15 do ts.imageData.px[(y0 + y) * W + x0 + x] = value end
    end
    NativeTileset.markDirty(ts, false, slot)
  end
end

local water = {}
for slot = 0, ROWS * COLS - 1, 6 do
  if slot < 55 * COLS then water[#water + 1] = slot end
end

test("a scattered anim frame uploads in a few row bands, not one per metatile", function()
  local ts = atlas()
  uploads = 0
  animate(ts, water, 100)
  NativeTileset.flush(ts, true, false)
  assert(#water > 140, "fixture has " .. #water .. " animated metatiles")
  assert(uploads <= 16, "uploads per flush: " .. uploads)
end)

test("the drawn atlas matches the CPU atlas after every flush, both buffers", function()
  local ts = atlas()
  local a, b = {}, {}
  for i, slot in ipairs(water) do
    if i % 2 == 0 then a[#a + 1] = slot else b[#b + 1] = slot end
  end
  for frame = 1, 6 do
    animate(ts, frame % 2 == 0 and a or b, 100 + frame)
    NativeTileset.flush(ts, true, false)
    local ok, at = same(ts.image, ts.imageData)
    assert(ok, "frame " .. frame .. " drawn atlas differs at pixel " .. tostring(at))
  end
  animate(ts, { 3 }, 200)
  NativeTileset.flush(ts, true, false)
  animate(ts, { 3 }, 201)
  NativeTileset.flush(ts, true, false)
  assert(same(ts.image, ts.imageData), "drawn atlas after single-slot frames")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
