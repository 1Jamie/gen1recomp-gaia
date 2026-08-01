-- Shared gamepad + raw joystick button tables for launcher and gameplay.
-- Hardware-measured NX overrides live in NX_* tables (see docs/switch-development.md).

local GamepadMap = {}

-- LÖVE SDL game-controller mapping (D-pad / face / menu).
GamepadMap.DEFAULT_GAMEPAD_BINDINGS = {
  dpup = "up", dpdown = "down", dpleft = "left", dpright = "right",
  a = "a", b = "b",
  start = "start", back = "select",
}

-- Generic SDL joysticks without a game-controller DB entry (Linux handhelds).
GamepadMap.RAW_BUTTON_BINDINGS = {
  [1] = "a", [2] = "b",
  [7] = "select", [8] = "start", [9] = "select", [10] = "start",
}

-- Raw index -> gamepad button name for RomImporter routing.
GamepadMap.RAW_TO_GAMEPAD_BUTTON = {
  [1] = "a", [2] = "b",
  [7] = "back", [8] = "start", [9] = "back", [10] = "start",
}

-- Test hook: force NX raw tables without stubbing love.
GamepadMap._forceNXForTests = false
GamepadMap.NX_RAW_BUTTON_BINDINGS = nil
GamepadMap.NX_RAW_TO_GAMEPAD_BUTTON = nil

function GamepadMap._setForceNXForTests(v)
  GamepadMap._forceNXForTests = not not v
end

local function nxActive()
  if GamepadMap._forceNXForTests then return true end
  if love and love._os == "NX" then return true end
  if love and love.system and love.system.getOS() == "NX" then return true end
  return false
end

function GamepadMap.mapGamepadButton(button)
  return GamepadMap.DEFAULT_GAMEPAD_BINDINGS[button]
end

function GamepadMap.mapRawButton(index)
  if nxActive() and GamepadMap.NX_RAW_BUTTON_BINDINGS then
    local nx = GamepadMap.NX_RAW_BUTTON_BINDINGS[index]
    if nx then return nx end
  end
  return GamepadMap.RAW_BUTTON_BINDINGS[index]
end

function GamepadMap.mapRawToGamepadButton(index)
  if nxActive() and GamepadMap.NX_RAW_TO_GAMEPAD_BUTTON then
    local nx = GamepadMap.NX_RAW_TO_GAMEPAD_BUTTON[index]
    if nx then return nx end
  end
  return GamepadMap.RAW_TO_GAMEPAD_BUTTON[index]
end

return GamepadMap
