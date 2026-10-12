local Chrome = require("src.ui.gen2.Chrome")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local List = {}
List.__index = List
List.isOpaque = false

List.X, List.Y, List.W, List.H = 0, 0, 20, 12
List.ITEM_X, List.ITEM_Y = 2, 3
List.VISIBLE = 4

function List.scrollFor(index, count, scroll)
  scroll = scroll or 0
  if index - 1 < scroll then scroll = index - 1 end
  if index > scroll + List.VISIBLE then scroll = index - List.VISIBLE end
  return math.max(0, math.min(scroll, math.max(0, count - List.VISIBLE)))
end

function List.new(game, title, items, onDone)
  return setmetatable({
    game = game, data = (game and game.data) or {}, title = title,
    items = items or {}, onDone = onDone, index = 1, scroll = 0, done = false,
  }, List)
end

function List:wantsFillScale() return true end

function List:playSfx(name)
  local sfx = self.data.audio and self.data.audio.sfx
  if sfx and sfx[Sound.resolve(self.data, name)] then Sound.play(self.data, name) end
end

function List:finish(item)
  if self.done then return end
  self.done = true
  local stack = self.game and self.game.stack
  if stack and stack:top() == self then stack:pop() end
  if self.onDone then self.onDone(item) end
end

function List:update(_dt)
  if self.done then return end
  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("up") and self.index > 1 then
    self.index = self.index - 1
  elseif input:wasPressed("down") and self.index < #self.items then
    self.index = self.index + 1
  elseif input:wasPressed("b") then
    self:playSfx("Sfx_ReadText2")
    return self:finish(nil)
  elseif input:wasPressed("a") then
    self:playSfx("Sfx_ReadText2")
    return self:finish(self.items[self.index])
  end
  self.scroll = List.scrollFor(self.index, #self.items, self.scroll)
end

function List:draw()
  Chrome.box(List.X, List.Y, List.W, List.H)
  if self.title then Chrome.print(Strings(self.title), 1, 1) end
  for slot = 1, math.min(List.VISIBLE, #self.items) do
    local it = self.items[self.scroll + slot]
    if it then
      local y = List.ITEM_Y + (slot - 1) * 2
      Chrome.print(it.label, List.ITEM_X, y)
      if it.right then Chrome.printRight(it.right, List.W - 2, y) end
    end
  end
  Chrome.cursor(List.ITEM_X - 1, List.ITEM_Y + (self.index - self.scroll - 1) * 2)
  love.graphics.setColor(1, 1, 1, 1)
end

return List
