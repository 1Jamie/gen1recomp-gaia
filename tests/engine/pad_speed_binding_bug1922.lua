
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Input = require("src.core.Input")
local Strings = require("src.core.Strings")
local BindingsMenu = require("src.ui.BindingsMenu")

local function newGame()
  local game = { save = { options = {} }, data = {}, wroteOptions = 0 }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = {
    queue = {},
    wasPressed = function(self, btn) return self.queue[btn] or false end,
    isDown = function() return false end,
  }
  function game:writeOptions() self.wroteOptions = self.wroteOptions + 1 end
  return game
end

local function press(state, btn)
  state.game.input.queue = { [btn] = true }
  state:update(1 / 60)
  state.game.input.queue = {}
end

local ROW_A, ROW_SPEED_DOWN, ROW_SPEED_UP = 5, 9, 10


Input:init()
eq(Input:padAction("rightshoulder"), "speedUp", "R1 speeds up by default")
eq(Input:padAction("leftshoulder"), "speedDown", "L1 slows down by default")
eq(Input:padAction("righttrigger"), "speedUp", "R2 alongside it")
eq(Input:padAction("lefttrigger"), "speedDown", "L2 alongside it")
eq(Input:padAction("a"), nil, "a face button is not a pad action")
check(Input.padBindings["rightshoulder"] == nil,
      "a pad action never enters the Game Boy button map")
eq(Input.padBindings["a"], "a", "which is otherwise untouched")

Input:gamepadpressed(nil, "rightshoulder")
Input:step()
local held = 0
for _ in pairs(Input.state) do held = held + 1 end
eq(held, 0, "pressing R1 presses no Game Boy button")


Input:applyBindings({ speedUp = { pad = "y" } })
eq(Input:padAction("y"), "speedUp", "the overlay moves SPEED + to Y")
eq(Input:padAction("rightshoulder"), nil, "and leaves R1 inert")
eq(Input:padAction("righttrigger"), nil, "including its trigger alias")
eq(Input:padAction("leftshoulder"), "speedDown", "SPEED - keeps its default")
check(Input.padBindings["y"] == nil,
      "the moved action does not press a Game Boy button either")


Input:applyBindings({ speedUp = false, speedDown = false, a = { pad = "y" } })
eq(Input:padAction("rightshoulder"), nil, "unbound: R1 does nothing")
eq(Input:padAction("leftshoulder"), nil, "unbound: L1 does nothing")
eq(Input:padAction("righttrigger"), nil, "unbound: R2 does nothing")
eq(Input.padBindings["y"], "a", "a GB rebind in the same overlay still lands")
Input:init()


local game = newGame()
local bm = BindingsMenu.new(game)
game.stack:push(bm)
eq(#bm.items, 10, "CONTROLS grew two rows")
eq(bm.items[ROW_SPEED_UP].right, "RB", "SPEED + shows its default shoulder")
eq(bm.items[ROW_SPEED_DOWN].right, "LB", "SPEED - shows its own")

bm.index = ROW_SPEED_UP
press(bm, "a")
eq(bm.capture, bm.items[ROW_SPEED_UP], "A arms the SPEED + row")
bm:onGamepadPressed("y")
bm:onGamepadReleased("y")
eq(game.save.options.bindings.speedUp.pad, "y", "the release stores pad Y")
eq(bm.items[ROW_SPEED_UP].right, "Y", "and the row redraws")


local writes = game.wroteOptions
press(bm, "select")
eq(game.save.options.bindings.speedUp, false, "SELECT unbinds the action")
eq(bm.items[ROW_SPEED_UP].right, Strings("OFF"), "the row reads OFF")
eq(game.wroteOptions, writes + 1, "clearing writes once")
press(bm, "select")
eq(game.wroteOptions, writes + 1, "SELECT on an already-OFF row writes nothing")

bm:commitBindings()
eq(Input:padAction("rightshoulder"), nil, "closing applies the OFF state")
eq(Input:padAction("y"), nil, "the moved button is inert too")


bm.index = ROW_SPEED_DOWN
press(bm, "a")
bm:onGamepadPressed("leftshoulder")
bm:onGamepadReleased("leftshoulder")
eq(bm.items[ROW_SPEED_DOWN].right, "LB", "SPEED - is back on L1")

bm.index = ROW_A
press(bm, "a")
bm:onGamepadPressed("leftshoulder")
bm:onGamepadReleased("leftshoulder")
eq(game.save.options.bindings.a.pad, "leftshoulder", "GB A takes L1")
eq(game.save.options.bindings.speedDown, false,
   "and the speed action yields rather than trading for a face button")
eq(bm.items[ROW_SPEED_DOWN].right, Strings("OFF"), "the row shows it")

bm:commitBindings()
eq(Input.padBindings["leftshoulder"], "a", "applied: L1 is Game Boy A")
eq(Input:padAction("leftshoulder"), nil, "and no longer a speed shortcut")


bm.index = ROW_SPEED_UP
press(bm, "a")
bm:onKeyPressed("q")
check(bm.capture == nil, "a key cancels an armed pad-action row")
if bm.onKeyReleased then bm:onKeyReleased("q") end
eq(game.save.options.bindings.speedUp, false, "and stores nothing")


game.save.options.bindings = nil
for _, it in ipairs(bm.items) do it.right = nil end
local fresh = BindingsMenu.new(game)
eq(fresh.items[ROW_SPEED_UP].right, "RB", "a cleared overlay restores SPEED +")
Input:applyBindings(nil)
eq(Input:padAction("rightshoulder"), "speedUp", "and the live map with it")


local SaveData = require("src.core.SaveData")
local files = {}
local fs = {
  write = function(path, content) files[path] = content return true end,
  read = function(path) return files[path] end,
  remove = function(path) files[path] = nil return true end,
  getInfo = function(path)
    if files[path] ~= nil then return { type = "file" } end
    return nil
  end,
}
local full = SaveData.defaultOptions()
full.bindings = { speedUp = false, a = { pad = "y" } }
check(SaveData.saveOptions(full, fs) ~= nil, "options with an OFF row write")
local reloaded = SaveData.loadOptions(fs)
eq(reloaded.bindings.speedUp, false, "false round-trips as false, not nil")
eq(reloaded.bindings.a.pad, "y", "beside an ordinary GB rebind")
Input:applyBindings(reloaded.bindings)
eq(Input:padAction("rightshoulder"), nil, "a reloaded OFF row stays off")

Input:init()
T.finish("pad_speed_binding_bug1922")
