local ScriptMenu = require("src.ui.gen2.ScriptMenu")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")

local Dialog = {}

-- constants/menu_constants.asm:21
local STATICMENU_CURSOR = 0x80

Dialog.MENU_LEFT, Dialog.MENU_RIGHT = 11, 19
Dialog.MENU_BOTTOM = 11

local function popIf(stack, state)
  if state and stack:top() == state then
    stack:pop()
    return true
  end
  return false
end

function Dialog.sfx(game, name)
  local data = game and game.data
  local sfx = data and data.audio and data.audio.sfx
  if sfx and sfx[Sound.resolve(data, name)] then Sound.play(data, name) end
end

function Dialog.say(game, text, onDone)
  local box = TextBox.new(game, text, onDone)
  game.stack:push(box)
  return box
end

function Dialog.ask(game, text, onAnswer, opts)
  opts = opts or {}
  local box = TextBox.new(game, text, nil, {
    choice = function(yes) onAnswer(yes and true or false) end,
    defaultNo = opts.defaultNo,
  })
  game.stack:push(box)
  return box
end

function Dialog.menuHeader(labels)
  local items = {}
  local widest = 0
  for i, label in ipairs(labels) do
    items[i] = Strings(label)
    widest = math.max(widest, require("src.render.Font").width(items[i]) / 8)
  end
  local top = Dialog.MENU_BOTTOM - (#items * 2 + 1)
  local left = math.min(Dialog.MENU_LEFT, Dialog.MENU_RIGHT - 2 - math.ceil(widest))
  return {
    left = left, right = Dialog.MENU_RIGHT,
    top = top, bottom = Dialog.MENU_BOTTOM,
    items = items, dataFlags = STATICMENU_CURSOR, cursor = 1,
  }
end

function Dialog.menu(game, text, labels, onChoose)
  local stack = game.stack
  local box, menu
  box = TextBox.new(game, text, nil, { stay = { onShown = function()
    menu = ScriptMenu.new(game, {
      header = Dialog.menuHeader(labels), kind = "union_talk",
      onChoose = function(index)
        popIf(stack, menu)
        popIf(stack, box)
        onChoose(index)
      end,
    })
    stack:push(menu)
  end } })
  stack:push(box)
  return box
end

local Waiter = {}
Waiter.__index = Waiter
Waiter.isOpaque = false

function Waiter:update()
  if self.closed then return end
  self.tick(self, self.game and self.game.input)
end

function Waiter:draw() end

function Waiter:close()
  if self.closed then return end
  self.closed = true
  local stack = self.game.stack
  popIf(stack, self)
  popIf(stack, self.box)
end

function Waiter:shown()
  return self.game.stack:top() == self
end

function Dialog.hold(game, text, tick)
  local stack = game.stack
  local waiter = setmetatable({ game = game, tick = tick, closed = false }, Waiter)
  waiter.box = TextBox.new(game, text, nil, { stay = { onShown = function()
    if not waiter.closed then stack:push(waiter) end
  end } })
  stack:push(waiter.box)
  return waiter
end

function Dialog.pressed(input, key)
  return input and input.wasPressed and input:wasPressed(key) and true or false
end

return Dialog
