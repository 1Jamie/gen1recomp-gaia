package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local eq = T.eq

local battleResets = 0
local battleActive = true
package.loaded["src.core.game3.battle.init"] = {
  isActive = function() return battleActive end,
  reset = function() battleResets = battleResets + 1; battleActive = false end,
}
package.loaded["src.core.game3.battle"] = package.loaded["src.core.game3.battle.init"]

local Input = require("src.core.Input")
local SaveData = require("src.core.SaveData")
local Game3 = require("src.core.Game3")
local Runtime = require("src.core.game3.runtime")
local Audio = require("src.core.game3.audio")
local Stack = require("src.ui.game3.stack")
local StartMenu = require("src.ui.game3.start_menu")

local realLoad = SaveData.load
SaveData.load = function() return { engine = "game3", map = "EM_ROUTE101" } end
local realStop = Runtime.stop
local stops = 0
Runtime.stop = function() stops = stops + 1; Runtime.active = false end

Input:init()
Input:applyBindings(nil)

local actions = {}
local g = setmetatable({
  phase = "field",
  options = {},
  input = Input,
  writeOptions = function() end,
  _handleBootAction = function(_, a)
    actions[#actions + 1] = { action = a.action, battle = battleActive, top = Stack.top(),
      runtime = Runtime.active, saved = Audio._savedSong }
  end,
}, { __index = Game3 })

Runtime.active = true
Stack.clear()
Stack.push("start", StartMenu)
Audio._savedSong = 1
g:keypressed("f2")

eq(#actions, 1, "f2 in the field reloads the save")
local a = actions[1] or {}
eq(a.action, "continue", "f2 continues from the save")
eq(battleResets, 1, "f2 tears down the running battle")
eq(a.battle, false, "battle is gone before the save is entered")
eq(stops, 1, "f2 stops the field runtime")
eq(a.runtime, false, "runtime is stopped before the save is entered")
eq(a.top, nil, "ui stack is cleared before the save is entered")
eq(a.saved, nil, "saved map song is cleared before the save is entered")

SaveData.load = realLoad
Runtime.stop = realStop
Runtime.active = false
Stack.clear()
T.finish("game3 f2 load teardown")
