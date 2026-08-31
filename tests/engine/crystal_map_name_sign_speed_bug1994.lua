-- ../pokecrystal/engine/events/map_name_sign.asm:41-44
-- ../pokecrystal/engine/events/map_name_sign.asm:99-107

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.GameVersion"] = {
  engine = function() return "crystal" end,
}
package.loaded["src.render.Assets"] = {
  register = function() end,
  resolve = function(path) return path end,
  exists = function() return false end,
  image = function() error("no sheet in the fixture cache") end,
}
package.loaded["src.render.GbcPalette"] = {
  available = function() return false end,
  with = function(_, body) body() end,
}
package.loaded["src.render.Font"] = {
  ttfActive = function() return false end,
  encode = function(text)
    local out = {}
    for i = 1, #tostring(text) do out[i] = string.byte(text, i) end
    return out
  end,
  width = function(text) return #tostring(text) * 8 end,
  draw = function() end,
}
package.loaded["src.world.gen2.MapNameSign"] = nil
local Sign = require("src.world.gen2.MapNameSign")

local World = {}
World.__index = World

function World.new(game)
  return setmetatable({
    game = game,
    map = { id = "ROUTE_29",
      def = { landmark = "LANDMARK_ROUTE_29", environment = "ROUTE" } },
    mapSignState = { prev = "LANDMARK_NEW_BARK_TOWN" },
  }, World)
end

function World:currentLandmarkId() return "LANDMARK_ROUTE_29" end
function World:landmarkName() return "ROUTE 29" end

local function raise(game)
  local w = World.new(game)
  Sign.init(w)
  return w
end

local function ticksToClear(w, limit)
  for i = 1, limit do
    Sign.tick(w)
    if w.mapSign == nil then return i end
  end
  return nil
end

local function gameAt(speed)
  return { logicSpeed = function() return speed end }
end

local one = raise(gameAt(1))
if check(one.mapSign ~= nil, "the sign comes up at 1X") then
  eq(one.mapSign.timer, 60, "wLandmarkSignTimer starts at 60")
  for _ = 1, 10 do Sign.tick(one) end
  eq(one.mapSign.timer, 50, "ten frames burn ten frames of the timer at 1X")
end
eq(ticksToClear(raise(gameAt(1)), 200), 60, "60 logic frames clear it at 1X")

local four = raise(gameAt(4))
for _ = 1, 60 do Sign.tick(four) end
if check(four.mapSign ~= nil, "60 logic frames at 4X is a quarter second, so "
    .. "the sign is still up") then
  eq(four.mapSign.timer, 45, "and 60 logic frames at 4X have burned 15 of them")
end

local four2 = raise(gameAt(4))
for _ = 1, 3 do Sign.tick(four2) end
if check(four2.mapSign ~= nil, "the sign is up three logic frames into 4X") then
  eq(four2.mapSign.timer, 60, "three logic frames at 4X burn none of the timer")
  Sign.tick(four2)
  eq(four2.mapSign.timer, 59, "the fourth burns exactly one")
end
eq(ticksToClear(raise(gameAt(4)), 400), 240,
  "4 x 60 logic frames is one real second at 4X")

eq(ticksToClear(raise(gameAt(10)), 900), 600, "and 600 of them at 10X")

local half = raise({ logicSpeed = function() return 1.5 end })
for _ = 1, 3 do Sign.tick(half) end
if check(half.mapSign ~= nil, "1.5X keeps the sign up past three ticks") then
  eq(half.mapSign.timer, 58, "1.5X burns two frames in three ticks")
end

local bare = raise(nil)
eq(ticksToClear(bare, 200), 60, "no game object means the plain 60-frame life")

local broken = raise({ logicSpeed = function() error("no speed for you") end })
eq(ticksToClear(broken, 200), 60, "a throwing logicSpeed falls back to 1X")

local numberless = raise({ logicSpeed = function() return "fast" end })
eq(ticksToClear(numberless, 200), 60, "a non-numeric logicSpeed falls back too")

local zero = raise({ logicSpeed = function() return 0 end })
eq(ticksToClear(zero, 200), 60, "and so does a zero, rather than freezing it")

-- ../pokecrystal/home/window.asm:42
for _, speed in ipairs({ 1, 4, 10 }) do
  local talked = raise(gameAt(speed))
  talked.textbox = true
  Sign.tick(talked)
  eq(talked.mapSign, nil,
    "a text box takes the sign down on the first tick at " .. speed .. "X")
end

-- ../pokecrystal/engine/overworld/events.asm:284-285
local pushed = raise(gameAt(10))
for _ = 1, 30 do Sign.tick(pushed) end
check(pushed.mapSign ~= nil, "the sign survives 30 logic frames at 10X")
Sign.cancel(pushed)
eq(pushed.mapSign, nil, "and a player event still clears it outright")

local stateful = raise(gameAt(4))
Sign.tick(stateful)
eq(Sign.state(stateful).accum, nil,
  "the accumulator does not reach the saved crystal state")
check(stateful.mapSign and stateful.mapSign.accum ~= nil,
  "it lives on world.mapSign")

T.finish("crystal map name sign speed bug 1994")
