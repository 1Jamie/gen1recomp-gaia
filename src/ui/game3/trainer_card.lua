-- FRLG Trainer Card front (pret trainer_card.c).
-- Displays player name, 5-digit IDNo, money, Pokédex count, playtime,
-- 64×64 trainer front pic (Red/Leaf), and 8 Kanto gym badges.

local Stack = require("src.ui.game3.stack")
local FrlgFont = require("src.ui.game3.frlg_font")

local TrainerCard = {}

TrainerCard.open = false
TrainerCard._session = nil
TrainerCard._onClose = nil

-- Cached images
local _bgMale = nil
local _bgFemale = nil
local _badgesImg = nil
local _badgeQuads = nil
local _picRed = nil
local _picLeaf = nil
local _assetsTried = false

local function read_cache_file(path)
  local ok, CacheFs = pcall(require, "src.util.CacheFs")
  if ok and CacheFs and CacheFs.read then
    local data = CacheFs.read(path)
    if data and #data > 0 then return data end
  end
  local f = io.open(path, "rb")
  if f then
    local d = f:read("*a")
    f:close()
    if d and #d > 0 then return d end
  end
  return nil
end

local function load_rgba_image(candidates, w, h)
  if not (love and love.graphics) then return nil end
  for _, p in ipairs(candidates) do
    if p:sub(-5) == ".rgba" then
      local raw = read_cache_file(p)
      if raw and #raw >= w * h * 4 and love.image and love.image.newImageData then
        local ok, imgData = pcall(love.image.newImageData, w, h, "rgba8", raw)
        if ok and imgData then
          local img = love.graphics.newImage(imgData)
          if img.setFilter then img:setFilter("nearest", "nearest") end
          return img
        end
      end
    else
      local bytes = read_cache_file(p)
      if bytes and #bytes > 0 and love.image and love.filesystem then
        local ok, img = pcall(function()
          local fd = love.filesystem.newFileData(bytes, p:match("[^/]+$") or "img.png")
          local id = love.image.newImageData(fd)
          local image = love.graphics.newImage(id)
          if image.setFilter then image:setFilter("nearest", "nearest") end
          return image
        end)
        if ok and img then return img end
      end
      local ok, img = pcall(love.graphics.newImage, p)
      if ok and img then
        if img.setFilter then img:setFilter("nearest", "nearest") end
        return img
      end
    end
  end
  return nil
end

local function ensureAssets()
  if _assetsTried then return end
  _assetsTried = true

  _bgMale = load_rgba_image({
    "trainer_card/bg.rgba",
    "data/generated/gba/trainer_card/bg.rgba",
    "trainer_card/bg.png",
    "data/generated/gba/trainer_card/bg.png",
  }, 240, 160)

  _bgFemale = load_rgba_image({
    "trainer_card/bg_female.rgba",
    "data/generated/gba/trainer_card/bg_female.rgba",
    "trainer_card/bg_female.png",
    "data/generated/gba/trainer_card/bg_female.png",
  }, 240, 160)

  _badgesImg = load_rgba_image({
    "trainer_card/badges.rgba",
    "data/generated/gba/trainer_card/badges.rgba",
    "trainer_card/badges.png",
    "data/generated/gba/trainer_card/badges.png",
  }, 128, 16)

  if _badgesImg and love and love.graphics and love.graphics.newQuad then
    _badgeQuads = {}
    local iw, ih = _badgesImg:getDimensions()
    for i = 0, 7 do
      _badgeQuads[i + 1] = love.graphics.newQuad(i * 16, 0, 16, 16, iw, ih)
    end
  end

  _picRed = load_rgba_image({
    "trainers/front/0.rgba",
    "data/generated/gba/trainers/front/0.rgba",
    "trainer_card/red.png",
    "data/generated/gba/trainer_card/red.png",
    "data/generated/gba/trainers/front/0.png",
  }, 64, 64)

  _picLeaf = load_rgba_image({
    "trainers/front/1.rgba",
    "data/generated/gba/trainers/front/1.rgba",
    "trainer_card/leaf.png",
    "data/generated/gba/trainer_card/leaf.png",
    "data/generated/gba/trainers/front/1.png",
  }, 64, 64)
end

local function count_caught(dex)
  if not dex then return 0 end
  local n = 0
  for sp, on in pairs(dex.caught or {}) do
    if on then n = n + 1 end
  end
  return n
end

local function is_badge_unlocked(session, badgeIndex)
  if not session then return false end
  if session.badges then
    if type(session.badges) == "table" then
      if session.badges[badgeIndex] == true or (tonumber(session.badges[badgeIndex]) or 0) > 0 then
        return true
      end
    elseif type(session.badges) == "number" then
      local mask = bit and bit.lshift(1, badgeIndex - 1) or math.pow(2, badgeIndex - 1)
      if bit and bit.band(session.badges, mask) ~= 0 then return true end
    end
  end
  if session["badge" .. badgeIndex] == true then return true end
  if session.flags then
    local flagId = 0x820 + (badgeIndex - 1) -- FLAG_BADGE01_GET
    if session.flags[flagId] == true then return true end
  end
  return false
end

function TrainerCard.show(opts)
  opts = opts or {}
  TrainerCard.open = true
  TrainerCard._session = opts.session
  TrainerCard._onClose = opts.onClose
  ensureAssets()
  Stack.push("trainer", TrainerCard, { hideBelow = true })
end

function TrainerCard.close()
  TrainerCard.open = false
  Stack.pop("trainer")
  local cb = TrainerCard._onClose
  TrainerCard._onClose = nil
  if cb then cb() end
end

function TrainerCard.isOpen()
  return TrainerCard.open
end

function TrainerCard.draw()
  if not TrainerCard.open then return end
  ensureAssets()
  local session = TrainerCard._session or {}
  local isFemale = (session.gender == "female" or session.gender == 1 or session.playerGender == "female")

  -- 1. Card Background
  local bg = isFemale and (_bgFemale or _bgMale) or (_bgMale or _bgFemale)
  love.graphics.setColor(1, 1, 1, 1)
  if bg then
    love.graphics.draw(bg, 0, 0)
  else
    -- Fallback panel
    love.graphics.setColor(0.85, 0.55, 0.35, 1)
    love.graphics.rectangle("fill", 16, 8, 208, 144)
    love.graphics.setColor(0.98, 0.92, 0.78, 1)
    love.graphics.rectangle("fill", 24, 16, 192, 128)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- 2. Trainer Portrait (pret sTrainerPicOffsets: (19, 5) tiles -> (152, 40))
  local pic = isFemale and (_picLeaf or _picRed) or (_picRed or _picLeaf)
  if pic then
    love.graphics.draw(pic, 152, 40)
  end

  -- 3. Card Labels & Values (pret trainer_card.c relative to window (8, 8))
  -- NAME: (pret x=20, y=29 in window -> (28, 37))
  local name = tostring(session.name or session.playerName or "RED")
  FrlgFont.draw("NAME:", 28, 37, { colors = FrlgFont.COLOR.NORMAL })
  FrlgFont.draw(name, 68, 37, { colors = FrlgFont.COLOR.NORMAL })

  -- IDNo. (pret x=142, y=10 in window -> (150, 18) inside top-right oval pill)
  local rawId = tonumber(session.trainerId or session.id or session.playerTrainerId) or 0
  local idStr = string.format("%05d", rawId % 65536)
  FrlgFont.draw("IDNo. " .. idStr, 150, 18, { colors = FrlgFont.COLOR.NORMAL })

  -- MONEY (pret x=20, y=56 in window -> (28, 64))
  local money = tonumber(session.money) or 0
  FrlgFont.draw("MONEY", 28, 64, { colors = FrlgFont.COLOR.NORMAL })
  local moneyStr = string.format("$%d", money)
  local moneyW = FrlgFont.measure(moneyStr)
  FrlgFont.draw(moneyStr, math.max(68, 126 - moneyW), 64, { colors = FrlgFont.COLOR.NORMAL })

  -- POKéDEX (pret x=20, y=72 in window -> (28, 80))
  local caught = count_caught(session.dex) or tonumber(session.caughtMonsCount) or 0
  FrlgFont.draw("POKéDEX", 28, 80, { colors = FrlgFont.COLOR.NORMAL })
  local dexStr = string.format("%d", caught)
  local dexW = FrlgFont.measure(dexStr)
  FrlgFont.draw(dexStr, math.max(68, 126 - dexW), 80, { colors = FrlgFont.COLOR.NORMAL })

  -- TIME (pret x=20, y=88 in window -> (28, 96))
  local hours = tonumber(session.playTimeHours or session.hours) or 0
  local mins = tonumber(session.playTimeMinutes or session.minutes) or 0
  FrlgFont.draw("TIME", 28, 96, { colors = FrlgFont.COLOR.NORMAL })
  local timeStr = string.format("%d:%02d", hours, mins)
  FrlgFont.draw(timeStr, 88, 96, { colors = FrlgFont.COLOR.NORMAL })

  -- 4. Badges (pret tile 16 -> y = 128, x = 32, 56, 80, 104, 128, 152, 176, 200)
  if _badgesImg and _badgeQuads then
    for i = 1, 8 do
      local bx = 32 + (i - 1) * 24
      local by = 128
      if is_badge_unlocked(session, i) then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(_badgesImg, _badgeQuads[i], bx, by)
      end
    end
  end
end

return TrainerCard
