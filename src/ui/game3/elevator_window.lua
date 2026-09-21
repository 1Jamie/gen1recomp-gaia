-- pokefirered/src/field_specials.c:1094

local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local Strings = require("src.core.Strings")

local ElevatorWindow = {}

-- pokefirered/src/field_specials.c:727
ElevatorWindow.LEFT = 22
ElevatorWindow.TOP = 1
ElevatorWindow.WIDTH = 7
ElevatorWindow.HEIGHT = 4

-- pokefirered/src/field_specials.c:1108
ElevatorWindow.LABEL_RIGHT = 56

ElevatorWindow.visible = false
ElevatorWindow._label = nil

-- pokefirered/src/field_specials.c:1102
function ElevatorWindow.show(floorLabel)
  ElevatorWindow.visible = true
  ElevatorWindow._label = floorLabel and tostring(floorLabel) or nil
  return true
end

-- pokefirered/src/field_specials.c:1113
function ElevatorWindow.hide()
  ElevatorWindow.visible = false
  ElevatorWindow._label = nil
  return true
end

function ElevatorWindow.isVisible()
  return ElevatorWindow.visible
end

function ElevatorWindow.label()
  return ElevatorWindow._label
end

-- pokefirered/src/field_specials.c:1107
function ElevatorWindow.labelX()
  local label = ElevatorWindow._label
  if not label then return ElevatorWindow.LEFT * 8 end
  local w = (FrlgFont.measure and FrlgFont.measure(label)) or (6 * #label)
  return ElevatorWindow.LEFT * 8 + ElevatorWindow.LABEL_RIGHT - w
end

function ElevatorWindow.draw()
  if not ElevatorWindow.visible then return end
  local left, top = ElevatorWindow.LEFT, ElevatorWindow.TOP
  Window.stdFrame(Window.template(left, top, ElevatorWindow.WIDTH, ElevatorWindow.HEIGHT))
  -- pokefirered/src/field_specials.c:1105
  Window.printPx(Strings("Now on:"), left * 8, top * 8 + 2)
  local label = ElevatorWindow._label
  if label then
    -- pokefirered/src/field_specials.c:1108
    Window.printPx(label, ElevatorWindow.labelX(), top * 8 + 16)
  end
end

return ElevatorWindow
