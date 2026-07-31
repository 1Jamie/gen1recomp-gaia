-- Rebinding over the logical Game Boy buttons (gap C2's file-12 half,
-- 12-ui-extensibility 4.4): one row per button, A arms a "PRESS A BUTTON"
-- capture and the captured key or pad button lands in
-- save.options.bindings, which Input:applyBindings layers over its fixed
-- default map (see src/core/Input.lua and Game:applyOptions).

local Font = require("src.render.Font")
local ListMenu = require("src.ui.ListMenu")
local Input = require("src.core.Input")
local Strings = require("src.core.Strings")

local BindingsMenu = setmetatable({}, { __index = ListMenu })
BindingsMenu.__index = BindingsMenu

-- Input.lua's map, primary key first where several keys share a button.
-- `pad` is the default SDL gamecontroller button (see Input.lua); shown
-- on the SELECT row so controller Back/View is discoverable (#73).
local BUTTONS = {
  { id = "up", label = "UP", key = "up" },
  { id = "down", label = "DOWN", key = "down" },
  { id = "left", label = "LEFT", key = "left" },
  { id = "right", label = "RIGHT", key = "right" },
  { id = "a", label = "A", key = "z" },
  { id = "b", label = "B", key = "x" },
  { id = "start", label = "START", key = "escape" },
  { id = "select", label = "SELECT", key = "tab", pad = "back" },
}

-- a binding is a plain key string or { key, pad }; absent = the fixed
-- map, so a vanilla save renders today's keys byte-identically
local function boundKey(overlay, def)
  local b = overlay and overlay[def.id]
  if type(b) == "table" then return b.key or def.key end
  if type(b) == "string" then return b end
  return def.key
end

local function boundPad(overlay, def)
  local b = overlay and overlay[def.id]
  if type(b) == "table" and b.pad then return b.pad end
  return def.pad
end

-- Key column for every row. SELECT also appends "/PAD" (default BACK)
-- so controller Select/View is visible without opening a second legend.
local function boundRight(overlay, def)
  local key = boundKey(overlay, def)
  if def.id ~= "select" then return key:upper() end
  local pad = boundPad(overlay, def)
  if pad then return (key .. "/" .. pad):upper() end
  return key:upper()
end

function BindingsMenu.new(game)
  local overlay = game.save and game.save.options
                  and game.save.options.bindings
  local items = {}
  for i, def in ipairs(BUTTONS) do
    -- translated here, not in ROWS: that table is built at require
    -- time, before Strings.load has a catalog to look in
    items[i] = { label = Strings(def.label),
                 right = boundRight(overlay, def), button = def }
  end
  local self = setmetatable(ListMenu.new(game, "CONTROLS", items, {}),
                            BindingsMenu)
  self.onChoose = function(item) self:beginCapture(item) end
  -- A rebind reaches Input only when this screen closes (#510).  The menu
  -- steers by the live map, so applying "B = Z" the instant it was captured
  -- turned the player's next confirm press into a cancel and shut the
  -- screen mid-swap.  options.bindings is still written immediately, and
  -- Game:applyOptions re-applies it on load, so a close that skips this
  -- hook still ends up with the saved map.
  self.onCancel = function() self:commitBindings() end
  return self
end

-- Cross-file contract with src/core/Input.lua: the saved overlay reaches
-- the live map here, on close, and nowhere else in this screen.
function BindingsMenu:commitBindings()
  local game = self.game
  local opts = game and game.save and game.save.options
  if opts then Input:applyBindings(opts.bindings) end
end

-- the capture handlers are per-instance slots, so Game's raw-input
-- routing only ever sees this screen while a capture is armed
function BindingsMenu:beginCapture(item)
  self.capture = item
  self.onKeyPressed = BindingsMenu.captureKey
  self.onGamepadPressed = BindingsMenu.capturePad
end

-- Escape is the capture's way out, so it is never captured: every other
-- key is bindable, which otherwise leaves an armed row with no exit but
-- to bind something (#510).  Escape stays START in Input's default map,
-- which no rebind removes, so reserving it costs the player nothing.
function BindingsMenu:captureKey(key)
  if key == "escape" then return self:storeBinding("key", nil) end
  self:storeBinding("key", key)
end

function BindingsMenu:capturePad(button)
  self:storeBinding("pad", button)
end

function BindingsMenu:storeBinding(slot, value)
  local item = self.capture
  self.capture = nil
  self.onKeyPressed = nil
  self.onGamepadPressed = nil
  local game = self.game
  if not (item and value and game.save and game.save.options) then return end
  local opts = game.save.options
  opts.bindings = opts.bindings or {}
  local b = opts.bindings[item.button.id]
  if type(b) ~= "table" then
    -- keep a direct-edited plain key string when only the pad changes
    b = { key = type(b) == "string" and b or nil }
  end
  b[slot] = value
  opts.bindings[item.button.id] = b
  item.right = boundRight(opts.bindings, item.button)
  if game.writeOptions then game:writeOptions() end
end

function BindingsMenu:update(dt)
  if self.capture then return end -- the raw capture owns the input
  ListMenu.update(self, dt)
end

function BindingsMenu:draw()
  ListMenu.draw(self)
  if self.capture then
    Font.drawBox(1, 6, 18, 5)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(Strings("PRESS A BUTTON"), 24, 60)
    Font.draw(Strings("ESC TO CANCEL"), 24, 72)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return BindingsMenu
