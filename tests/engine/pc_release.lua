-- Headless regression: two Bill's PC releases in one list session (#171).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local Data = require("src.core.Data")
if not (Data.pokemon and Data.pokemon.RATTATA) then Data:load() end
require("src.render.Font").load(Data)

local Pokemon = require("src.pokemon.Pokemon")
local Boxes = require("src.pokemon.Boxes")
local BoxMenu = require("src.ui.BoxMenu")
local ListMenu = require("src.ui.ListMenu")
local ChoiceBox = require("src.ui.ChoiceBox")
local SaveData = require("src.core.SaveData")
local Sound = require("src.core.Sound")

local realCry, realPlay = Sound.playCry, Sound.play
Sound.playCry = function() end
Sound.play = function() end

local stack = { states = {} }
function stack:push(s) self.states[#self.states + 1] = s end
function stack:pop()
  local t = self.states[#self.states]
  self.states[#self.states] = nil
  return t
end
function stack:top() return self.states[#self.states] end
function stack:update(dt)
  local t = self:top()
  if t and t.update then t:update(dt) end
end

local pressed = {}
local game = {
  data = Data,
  save = SaveData.newGame(),
  stack = stack,
  input = {
    wasPressed = function(_, key) return pressed[key] or false end,
    isDown = function() return false end,
  },
}
game.save.options = game.save.options or {}
game.save.options.textSpeed = 1

local box = Boxes.active(game.save)
box[1] = Pokemon.new(Data, "RATTATA", 5)
box[2] = Pokemon.new(Data, "PIDGEY", 6)
box[3] = Pokemon.new(Data, "CATERPIE", 4)

local function press(btn)
  pressed = { [btn] = true }
  stack:update(1 / 60)
  pressed = {}
end

local function topMt() return getmetatable(stack:top()) end
local function mash(btn, cond, n)
  for _ = 1, (n or 400) do
    if cond() then return true end
    press(btn)
  end
  return false
end

stack:push(BoxMenu.new(game))
press("down"); press("down"); press("a")
T.check(topMt() == ListMenu, "RELEASE opens the box list")
T.eq(#box, 3, "box still has 3 before releases")

local function releaseCurrent()
  local before = #box
  press("a")
  T.check(mash("a", function() return topMt() == ChoiceBox end),
          "confirm choice opens")
  press("up") -- defaultNo -> YES
  press("a")
  T.check(mash("a", function() return topMt() == ListMenu end),
          "returns to RELEASE list")
  T.eq(#box, before - 1, "one mon removed from the box")
end

releaseCurrent()
releaseCurrent()
T.eq(#box, 1, "two releases leave one mon")
T.check(topMt() == ListMenu, "still on RELEASE list after the second")
T.eq(box[1].species, "CATERPIE", "remaining mon is the third seeded one")

Sound.playCry, Sound.play = realCry, realPlay
T.finish("pc_release")
