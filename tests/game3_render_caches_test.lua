-- tests/game3_render_caches_test.lua
-- Per-frame render caches in the Gen 3 battle system and UI: each one must
-- stay correct when what it caches changes.
--   * anim_vm: the anim bg and sprites share one blend shader; a sprite drawn
--     after the bg must re-send its own tint (the uniform cache used to miss
--     the bg's send, so the sprite drew with the bg's tint).
--   * anim_vm: band draws inside a frame bracket reuse one sorted list.
--   * pokemon.lua: a missing pic file is probed once, not every frame.
--   * trainer_card RSE: the front pic and badge quads are built once.
--   * rom_text: plain() memoises pure IRs and follows overrides.
--   * bag: listPocket rows are reused until the pocket changes.

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
local function eq(a, b, msg)
  if a ~= b then
    error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
  end
end

-- Minimal love.graphics that records shader uniforms and draws.
local counts = { newImageData = 0, newImage = 0, newQuad = 0, draws = 0, fsRead = 0 }
local Image = {}
Image.__index = Image
function Image:getDimensions() return self.w, self.h end
function Image:setFilter() end
function Image:setWrap() end
local Quad = {}
Quad.__index = Quad
function Quad:setViewport(x, y, w, h) self.x, self.y, self.w, self.h = x, y, w, h end
function Quad:getViewport() return self.x, self.y, self.w, self.h end
local shaders = {}
local drawLog = {}
local currentShader = nil
love = {
  graphics = {
    newImage = function(data)
      counts.newImage = counts.newImage + 1
      return setmetatable({ w = data and data.w or 64, h = data and data.h or 64 }, Image)
    end,
    newQuad = function(x, y, w, h)
      counts.newQuad = counts.newQuad + 1
      return setmetatable({ x = x, y = y, w = w, h = h }, Quad)
    end,
    newShader = function()
      local sh = { uniforms = {}, sends = 0 }
      function sh:send(name, v)
        self.sends = self.sends + 1
        if type(v) == "table" then v = { v[1], v[2], v[3] } end
        self.uniforms[name] = v
      end
      shaders[#shaders + 1] = sh
      return sh
    end,
    setShader = function(sh) currentShader = sh end,
    getShader = function() return currentShader end,
    draw = function(img)
      counts.draws = counts.draws + 1
      local sh = currentShader
      drawLog[#drawLog + 1] = { img = img, coeff = sh and sh.uniforms.coeff,
        target = sh and sh.uniforms.target and table.concat(sh.uniforms.target, ",") }
    end,
    setColor = function() end,
    getColor = function() return 1, 1, 1, 1 end,
    setBlendMode = function() end,
    rectangle = function() end,
    push = function() end,
    pop = function() end,
    translate = function() end,
    scale = function() end,
  },
  image = {
    newImageData = function(w, h)
      counts.newImageData = counts.newImageData + 1
      return { w = w, h = h }
    end,
  },
  filesystem = {
    read = function(path)
      counts.fsRead = counts.fsRead + 1
      if path:find("trainers/front/", 1, true) then return string.rep("\0", 64 * 64 * 4) end
      return nil
    end,
  },
  timer = { getTime = function() return 0 end },
}

-- anim_vm -----------------------------------------------------------------
local AnimVm = require("src.core.game3.battle.anim_vm")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
local AnimPal = require("src.core.game3.battle.anim_pal")

local function reset_anim()
  AnimSprites.reset()
  AnimTasks.reset()
  for i = #drawLog, 1, -1 do drawLog[i] = nil end
end

test("sprite drawn after a tinted anim bg re-sends its own blend", function()
  reset_anim()
  local vm = AnimVm.new()
  local bgImg = setmetatable({ w = 256, h = 256, name = "bg" }, Image)
  local spriteImg = setmetatable({ w = 32, h = 32, name = "sprite" }, Image)
  local realBgImage, realBgColors = AnimVm.animBgImage, AnimPal.bgColors
  AnimVm.animBgImage = function() return bgImg end
  AnimPal.bgColors = function() return nil end
  local ok, err = pcall(function()
    vm._animBgId = 1
    vm._animBgBlend = { coeff = 12, color = 0x001F } -- red, from the bg
    local s = AnimSprites._pool[1]
    s.active, s.visible, s.image = true, true, spriteImg
    s.x, s.y, s.z = 100, 50, 150
    s.palBlend = { coeff = 6, color = 0x7C00 } -- blue, the sprite's own
    for _ = 1, 3 do vm:draw(0, 999) end
    local sprites = 0
    for _, d in ipairs(drawLog) do
      if d.img == spriteImg then
        sprites = sprites + 1
        eq(d.coeff, 6, "sprite coeff")
        eq(d.target, "0,0,31", "sprite target")
      elseif d.img == bgImg then
        eq(d.coeff, 12, "bg coeff")
        eq(d.target, "31,0,0", "bg target")
      end
    end
    eq(sprites, 3, "sprite draws")
  end)
  AnimVm.animBgImage, AnimPal.bgColors = realBgImage, realBgColors
  vm._animBgId = nil
  if not ok then error(err, 0) end
end)

test("band draws in a frame bracket slice one sorted list", function()
  reset_anim()
  local vm = AnimVm.new()
  local imgs = {}
  local zs = { 150, 50, 250, 120, 50 }
  for i, z in ipairs(zs) do
    local s = AnimSprites._pool[i]
    imgs[i] = setmetatable({ w = 8, h = 8, id = i }, Image)
    s.active, s.visible, s.image, s.x, s.y, s.z = true, true, imgs[i], 0, 0, z
  end
  local function order(bracket)
    for i = #drawLog, 1, -1 do drawLog[i] = nil end
    if bracket then vm:beginDrawFrame() end
    vm:draw(0, 99)
    vm:draw(101, 199)
    vm:draw(201, 999)
    if bracket then vm:endDrawFrame() end
    local out = {}
    for _, d in ipairs(drawLog) do out[#out + 1] = d.img.id end
    return table.concat(out, ",")
  end
  local plain = order(false)
  -- z ascending, ties by higher pool index first (battle_anim.c:630 order)
  eq(plain, "5,2,4,1,3", "unbracketed order")
  eq(order(true), plain, "bracketed order")
  -- a change between frames is picked up by the next bracket
  AnimSprites._pool[3].z = 10
  eq(order(true), "3,5,2,4,1", "next frame sees the new z")
  -- z 100 / 200 stay outside every band, as before
  AnimSprites._pool[1].z = 100
  eq(order(true), "3,5,2,4", "z=100 is still not drawn by the bands")
end)

-- pokemon pics --------------------------------------------------------------
local Pokemon = require("src.core.game3.pokemon")

test("missing pic is probed once and re-probed after invalidate", function()
  local reads = 0
  local savedCache = Pokemon._cache
  Pokemon._cache = { read = function() reads = reads + 1 return nil end }
  Pokemon._back = {}
  Pokemon._front = {}
  eq(Pokemon.backPic(25), nil, "missing back pic")
  eq(Pokemon.backPic(25), nil, "missing back pic again")
  eq(Pokemon.frontPic(25), nil, "missing front pic")
  eq(Pokemon.frontPic(25), nil, "missing front pic again")
  eq(reads, 2, "one read per missing pic")
  Pokemon._front = {}
  Pokemon._back = nil
  eq(Pokemon.backPic(25), nil, "after reset")
  eq(reads, 3, "a cache reset probes again")
  Pokemon._cache = savedCache
  Pokemon._front = {}
  Pokemon._back = nil
end)

test("present pic is still loaded and cached", function()
  local reads = 0
  local savedCache = Pokemon._cache
  Pokemon._cache = { read = function() reads = reads + 1 return string.rep("\0", 64 * 64 * 4) end }
  Pokemon._front = {}
  local a = Pokemon.frontPic(4)
  local b = Pokemon.frontPic(4)
  if not a then error("expected a pic entry", 0) end
  eq(a, b, "same entry")
  eq(reads, 1, "one read")
  Pokemon._cache = savedCache
  Pokemon._front = {}
end)

-- trainer card (RSE) ----------------------------------------------------------
test("RSE trainer card builds its pic and badge quads once", function()
  local realKit = package.loaded["src.ui.game3.rse.scene_kit"]
  local badgeImg = setmetatable({ w = 128, h = 16 }, Image)
  package.loaded["src.ui.game3.rse.scene_kit"] = {
    manifest = function()
      return { layers = {}, pics = { male = 71, female = 72 }, picOffset = { 0, 0 },
        star = { png = "star" }, badges = { png = "badges" } }
    end,
    image = function(name) return name == "badges" and badgeImg or nil end,
  }
  local TrainerCard = require("src.ui.game3.trainer_card")
  local realFront = TrainerCard.frontTextsRse
  TrainerCard.frontTextsRse = function() return {} end
  local ok, err = pcall(function()
    TrainerCard.open, TrainerCard._rse, TrainerCard.side, TrainerCard._flip = true, true, "front", nil
    TrainerCard._card = { female = false, stars = 0,
      badges = { true, false, true, true, false, false, false, true } }
    local before = { img = counts.newImageData, quad = counts.newQuad }
    for _ = 1, 5 do TrainerCard.draw() end
    eq(counts.newImageData - before.img, 1, "pic decoded once")
    eq(counts.newQuad - before.quad, 8, "badge quads built once")
    TrainerCard._card.female = true
    TrainerCard.draw()
    TrainerCard.draw()
    eq(counts.newImageData - before.img, 2, "the other pic decoded once")
  end)
  TrainerCard.frontTextsRse = realFront
  TrainerCard.open, TrainerCard._rse, TrainerCard._card = false, nil, nil
  package.loaded["src.ui.game3.rse.scene_kit"] = realKit
  if not ok then error(err, 0) end
end)

-- rom_text ------------------------------------------------------------------
local RomText = require("src.core.game3.rom_text")
local TextIR = require("src.core.game3.scripting.text_ir")

test("plain() follows overrides and ignores cached text for impure IRs", function()
  RomText.overrides.TEST_CACHE_KEY = TextIR.fromAscii("HELLO")
  eq(RomText.plain("TEST_CACHE_KEY"), "HELLO", "first")
  eq(RomText.plain("TEST_CACHE_KEY"), "HELLO", "memoised")
  RomText.overrides.TEST_CACHE_KEY = TextIR.fromAscii("WORLD")
  eq(RomText.plain("TEST_CACHE_KEY"), "WORLD", "override replaced")
  local ir = { { t = "text", s = "A " }, { t = "strvar", n = 1 }, { t = "eos" } }
  RomText.overrides.TEST_CACHE_KEY = ir
  eq(RomText.plain("TEST_CACHE_KEY", { stringVars = { "X" } }), "A X", "with ctx")
  eq(RomText.plain("TEST_CACHE_KEY", { stringVars = { "Y" } }), "A Y", "ctx still honoured")
  RomText.overrides.TEST_CACHE_KEY = nil
end)

-- bag rows --------------------------------------------------------------------
local okData = pcall(function()
  require("tests.game3_cache").root("items/pack.lua")
end)
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local haveItems = okData and pcall(ItemsData.ensureLoaded)
if haveItems then
  test("listPocket reuses rows until the pocket changes", function()
    local bag = Bag.new and Bag.new() or {}
    Bag.add(bag, 13, 3) -- POTION
    local a = Bag.listPocket(bag, "ITEMS")
    local b = Bag.listPocket(bag, "ITEMS")
    eq(a, b, "same rows while unchanged")
    eq(#a, 1, "one row")
    eq(a[1].qty, 3, "qty")
    Bag.add(bag, 13, 2)
    local c = Bag.listPocket(bag, "ITEMS")
    if c == a then error("rows not rebuilt after add", 0) end
    eq(c[1].qty, 5, "qty after add")
    eq(a[1].qty, 3, "old rows untouched")
    bag.pockets.ITEMS[1].qty = 7 -- direct slot edit (save load, scripts)
    eq(Bag.listPocket(bag, "ITEMS")[1].qty, 7, "direct edit seen")
    Bag.remove(bag, 13, 7)
    eq(#Bag.listPocket(bag, "ITEMS"), 0, "empty after remove")
  end)
else
  print("  SKIP: listPocket (items pack not in the cache)")
end

print(string.format("game3_render_caches_test: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
