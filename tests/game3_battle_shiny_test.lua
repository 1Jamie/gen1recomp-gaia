#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local Anim = require("src.core.game3.battle.anim")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
local Audio = require("src.core.game3.audio")
local SE = require("src.core.game3.se_ids")
local ShinySeq = require("src.core.game3.battle.shiny_seq")

local shinySound = 0
local starsSeen = false
local orbitSeen = false
local diagonalSeen = false
local done = 0
local doneFrame = nil
local frame = 0
local created = {}
local oldAcquire = AnimSprites.acquire
AnimSprites.acquire = function(opts)
  local sprite = oldAcquire(opts)
  if sprite and opts and opts.tag == "GOLD_STARS" then
    created[#created + 1] = {
      frame = frame,
      template = opts.template,
      callback = opts.callback,
      w = opts.w,
      h = opts.h,
      hostId = sprite.hostId,
    }
  end
  return sprite
end
local oldPlaySe = Audio.playSe
Audio.playSe = function(id, ...)
  if id == SE.SE_SHINY then shinySound = shinySound + 1 end
  return oldPlaySe(id, ...)
end

Anim.reset({ headless = false })
assert(ShinySeq.start({ mon = { isShiny = true } }, "player", function()
  done = done + 1
  doneFrame = doneFrame or frame
end))
for _ = 1, 30 do
  frame = frame + 1
  Anim.update(1 / 60)
  if AnimSprites.activeCount() > 0 then starsSeen = true end
  AnimSprites.forEachActive(function(sprite)
    if sprite.callback == AnimCallbacks.ShinySparkleOrbit then orbitSeen = true end
    if sprite.callback == AnimCallbacks.ShinySparkle then diagonalSeen = true end
  end)
end
assert(shinySound == 0, "shiny send-out waits before starting the sparkle phase")
for _ = 1, 240 do
  frame = frame + 1
  Anim.update(1 / 60)
  if AnimSprites.activeCount() > 0 then starsSeen = true end
  AnimSprites.forEachActive(function(sprite)
    if sprite.callback == AnimCallbacks.ShinySparkleOrbit then orbitSeen = true end
    if sprite.callback == AnimCallbacks.ShinySparkle then diagonalSeen = true end
  end)
end
Audio.playSe = oldPlaySe

assert(shinySound == 1, "shiny send-out plays the shiny sound once")
assert(starsSeen, "shiny send-out creates sparkle sprites")
assert(orbitSeen and diagonalSeen, "shiny send-out uses both sparkle trajectories")
assert(#created == 10, "shiny send-out creates two five-sprite FireRed bursts")
assert(created[1].template == "gWishStarSpriteTemplate"
  and created[2].template == "gWishStarSpriteTemplate",
  "both FireRed sparkle tasks start with wish stars")
assert(created[1].callback == AnimCallbacks.ShinySparkleOrbit
  and created[2].callback == AnimCallbacks.ShinySparkle,
  "FireRed sparkle tasks use orbit and diagonal callbacks")
for i = 3, #created do
  assert(created[i].template == "gMiniTwinklingStarSpriteTemplate",
    "FireRed sparkle tails use mini-star sprites")
end
for i = 3, #created, 2 do
  assert(created[i].frame == created[i + 1].frame,
    "paired sparkle tasks emit on the same frame")
  if i > 3 then
    assert(created[i].frame - created[i - 2].frame == 4,
      "paired sparkle tasks emit every four frames")
  end
end
assert(done == 1 and not Anim._vm:busy(), "shiny send-out completes")
assert(doneFrame and doneFrame > 60, "shiny send-out waits for the sparkle sprites")

-- FireRed's double-battle intro starts one sparkle task pair per shiny mon
-- through the same animation lifetime rather than serializing the two mons.
created = {}
frame = 0
local doubleDone = 0
Anim.reset({ headless = false, double = true })
assert(ShinySeq.startMany(
  { { mon = { isShiny = true } }, { mon = { isShiny = true } } },
  { 0, 2 },
  function() doubleDone = doubleDone + 1 end
), "double shiny send-out starts when both mons are shiny")
for _ = 1, 300 do
  frame = frame + 1
  Anim.update(1 / 60)
end
local byHost = {}
for _, event in ipairs(created) do
  byHost[event.hostId] = (byHost[event.hostId] or 0) + 1
end
assert(byHost[0] == 10 and byHost[2] == 10,
  "double shiny send-out gives each mon two five-sprite FireRed bursts")
assert(doubleDone == 1 and not Anim._vm:busy(),
  "double shiny send-out shares one completion lifecycle")

AnimSprites.acquire = oldAcquire
Anim.reset({ headless = false })
assert(not ShinySeq.start({ mon = { isShiny = false } }, "player", function()
  done = done + 1
end), "normal send-out skips the shiny phase")
assert(not Anim._vm:busy(), "normal send-out leaves the animation VM idle")
print("[ok] shiny send-out sound, stars, and completion")
