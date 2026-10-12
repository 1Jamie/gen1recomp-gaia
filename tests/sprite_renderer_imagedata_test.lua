-- Sprite defs whose `image` is an in-memory love.image.ImageData (mods build
-- these at runtime) must construct a SpriteRenderer; only string images have
-- a path to prefetch.
--
--   luajit tests/sprite_renderer_imagedata_test.lua   (ROM-free)
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("sprite renderer imagedata")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

-- Real LOVE rejects newImage(nil); the stub accepts it, which would hide the
-- regression.
local stubNewImage = love.graphics.newImage
love.graphics.newImage = function(arg)
  if arg == nil then
    error("bad argument #1 to 'newImage' (ImageData expected, got nil)", 2)
  end
  return stubNewImage(arg)
end

local NPC = require("src.world.gen2.Npc")
local SpriteRenderer = require("src.render.SpriteRenderer")

local function modDef()
  return {
    image = love.image.newImageData(16, 96), frames = 6, walker = true,
    spriteType = "WALKING_SPRITE", trueColor = true,
  }
end

do
  local def = modDef()
  local ok, r = pcall(SpriteRenderer.new, def, "seed")
  check(ok, "SpriteRenderer.new accepts an ImageData image: " .. tostring(r))
  if ok then
    check(r.image ~= nil, "renderer has an image for an ImageData def")
    eq(r.frameCount, 6, "frame count carried over")
  end
end

eq(SpriteRenderer.imagePath(modDef()), nil,
  "imagePath is nil for an ImageData image (nothing to prefetch)")
eq(SpriteRenderer.imagePath({ image = "assets/generated/sprites/fairy.png" }),
  "assets/generated/sprites/fairy.png", "imagePath returns a string image")

do
  local ok, npc = pcall(NPC.new, "TEST_MAP",
    { index = 1, movement = 0x01, x = 4, y = 4 }, modDef())
  check(ok, "gen2 NPC.new accepts an ImageData sprite def: " .. tostring(npc))
end

S.finish()
