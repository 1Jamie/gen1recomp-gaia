-- Gold #DEX AREA page drew no nest markers or landmark name because
-- PokedexMenu:drawArea read the non-existent self.data.landmarks instead of
-- the gen2Landmarks table Nests already resolves through (#1267).
-- engine/pokegear/pokegear.asm:2427
--   luajit tests/engine/gen2_pokedex_area_landmark_bug1267.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local PokedexMenu = require("src.ui.gen2.PokedexMenu")
local Nests = require("src.core.gen2.Nests")

-- one Johto landmark (index 5), one species that nests there
local data = {
  gen2Encounters = {
    grass = {
      ROUTE_30 = { slots = { day = { { species = "RATTATA" } } } },
    },
  },
  gen2Maps = {
    ROUTE_30 = { landmark = 5 },
  },
  gen2Landmarks = {
    landmarks = {
      LANDMARK_ROUTE_30 = { index = 5, x = 40, y = 60, name = "ROUTE 30" },
    },
  },
}

-- sanity: Nests.landmark itself resolves the index (never broken, per the
-- verifier) so a failure below is isolated to drawArea's own lookup
eq(Nests.landmark(data, 5) and Nests.landmark(data, 5).name, "ROUTE 30",
  "Nests.landmark resolves index 5 to the ROUTE 30 record")

-- capture what drawArea actually paints, without needing a real tile sheet
-- or font: fill/blank/current/monName are stubbed on the instance, which
-- Lua resolves before the PokedexMenu metatable's own methods.
local function newSelf()
  local texts = {}
  local rects = {}
  local self = setmetatable({
    game = { save = {} },
    data = data,
    mapGfx = { maps = { johto = { 1 } } }, -- non-nil `cells`, no real sheet
    areaRegion = "johto",
    areaBlink = 0, -- (0 % 32) < 20, so markers are in their "on" phase
    current = function() return { species = "RATTATA" } end,
    monName = function() return "RATTATA" end,
    fill = function() end,
    blank = function() end,
    text = function(_, str, tx, ty)
      texts[#texts + 1] = { str = str, tx = tx, ty = ty }
    end,
  }, { __index = PokedexMenu })
  return self, texts, rects
end

local realRect = love.graphics.rectangle
local self, texts, rects
do
  self, texts, rects = newSelf()
  love.graphics.rectangle = function(mode, x, y, w, h)
    rects[#rects + 1] = { mode = mode, x = x, y = y, w = w, h = h }
  end
  self:drawArea()
  love.graphics.rectangle = realRect
end

local function hasRect(x, y)
  for _, r in ipairs(rects) do
    if r.x == x and r.y == y then return true end
  end
  return false
end
check(hasRect(40 - 2, 60 - 2), "the nest marker is drawn at the landmark's x-2,y-2")

local function hasText(str)
  for _, t in ipairs(texts) do
    if t.str == str then return true end
  end
  return false
end
check(hasText("ROUTE 30"), "the landmark name is printed on row 16")

T.finish("gen2 pokedex area landmark bug 1267")
