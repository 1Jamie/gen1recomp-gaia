-- engine/gfx/screen_effects.asm:1-12 (#1872)

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.modkit")
local check, eq = T.check, T.eq

local Data = T.fixtures.fresh()

local SaveData = require("src.core.SaveData")
local Pokemon  = require("src.pokemon.Pokemon")
local PaletteFX = require("src.render.PaletteFX")
local OW = require("src.world.OverworldController")

local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end

do
  local bgp = 0xE4
  local want = {}
  for i = 0, 3 do
    local shade = math.floor(bgp / (4 ^ i)) % 4
    want[i] = (i == 0) and (shade % 4 >= 2 and shade or shade + 2) or shade
  end
  for i = 0, 3 do
    eq(PaletteFX.POISON_BGP[i], want[i],
       ("POISON_BGP color %d matches `or $2` on rBGP"):format(i))
  end

  local colors = { { 1, 1, 1 }, { 2, 2, 2 }, { 3, 3, 3 }, { 4, 4, 4 } }
  local out = PaletteFX.permute(colors, PaletteFX.POISON_BGP)
  eq(out[1][1], 3, "poison shows DMG white as shade 2")
  eq(out[2][1], 2, "poison leaves shade 1 alone")
  eq(out[4][1], 4, "poison leaves shade 3 alone")
end

do
  local realSound = package.loaded["src.core.Sound"]
  package.loaded["src.core.Sound"] = { play = function() end, playCry = function() end }
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
  save.party[1].status = "PSN"
  save.party[1].hp = 20
  save.poisonSteps = 3
  local game = { data = Data, save = save, stack = { push = function() end } }
  setUpvalue(OW.applyFieldPoison, "Game", game)
  local self_ = setmetatable({}, { __index = OW })
  self_:applyFieldPoison()
  eq(self_.poisonFlash, 4, "a poison tick arms four frames of flicker")
  package.loaded["src.core.Sound"] = realSound
end

do
  local rects = {}
  local savedRect = love.graphics.rectangle
  love.graphics.rectangle = function(mode, x, y, w, h)
    rects[#rects + 1] = { mode = mode, x = x, y = y, w = w, h = h }
  end
  local savedShader = PaletteFX.shader
  PaletteFX.shader = function() return { send = function() end } end

  local renderer = {}
  setUpvalue(OW.drawUI, "Game", { renderer = renderer })
  local self_ = setmetatable({ poisonFlash = 4 }, { __index = OW })

  PaletteFX.setShadeMap(nil)
  self_:drawUI()
  eq(#rects, 0, "the poison flicker paints no rect on the UI canvas")
  check(PaletteFX.shadeMap() == PaletteFX.POISON_BGP,
        "the flicker arms the poison BGP map, which the world and UI blits both read")
  eq(self_.poisonFlash, 3, "and ticks the counter down")

  for _ = 1, 3 do
    PaletteFX.setShadeMap(nil)
    self_:drawUI()
  end
  eq(self_.poisonFlash, 0, "four draws spend the flicker")
  PaletteFX.setShadeMap(nil)
  self_:drawUI()
  check(PaletteFX.shadeMap() == nil, "a spent flicker arms nothing")

  -- home/fade.asm:66
  self_.poisonFlash = 4
  PaletteFX.setShadeMap(PaletteFX.DARK_BGP)
  self_:drawUI()
  check(PaletteFX.shadeMap() == PaletteFX.DARK_BGP,
        "the flicker leaves a dark map's shade map in place")
  eq(#rects, 0, "and still paints no rect")

  PaletteFX.shader = function() return nil end
  PaletteFX.setShadeMap(nil)
  self_.poisonFlash = 4
  renderer.screenVeil = nil
  self_:drawUI()
  check(renderer.screenVeil ~= nil and renderer.screenVeil[1] == 0
        and renderer.screenVeil[2] > 0,
        "with no shader the flicker becomes a screen-space veil")
  eq(#rects, 0, "and still not a 160x144 fill")

  PaletteFX.setShadeMap(nil)
  PaletteFX.shader = savedShader
  love.graphics.rectangle = savedRect
end
