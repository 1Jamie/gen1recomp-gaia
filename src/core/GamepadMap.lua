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

-- Switch OLED: love.joystickpressed indices (1-based). Used only when the
-- device is NOT a gamepad — love-nx also emits gamepadpressed for Joy-Con,
-- and applying both face paths in one frame breaks NamingScreen (a+b).
-- Y→a / X→b matches operator OLED naming diagnosis (2026-08-01).
GamepadMap.NX_RAW_BUTTON_BINDINGS = {
  [1] = "a", [2] = "b",
  [3] = "a", [4] = "b",
  [9] = "select", [10] = "start",
}

-- Raw index -> gamepad button name for RomImporter routing.
GamepadMap.RAW_TO_GAMEPAD_BUTTON = {
  [1] = "a", [2] = "b",
  [7] = "back", [8] = "start", [9] = "back", [10] = "start",
}

GamepadMap.NX_RAW_TO_GAMEPAD_BUTTON = {
  [1] = "a", [2] = "b",
  [3] = "a", [4] = "b",
  [9] = "back", [10] = "start",
}

-- Test hook: force NX raw tables without stubbing love.
GamepadMap._forceNXForTests = false

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

-- love-nx / SDL: when isGamepad(), face+menu already arrive via gamepad*.
-- Applying joystickpressed raw on top double-fires GB A/B in one frame.
function GamepadMap.ignoreRawForJoystick(joystick)
  if not joystick then return false end
  local ok, isPad = pcall(function()
    return joystick.isGamepad and joystick:isGamepad()
  end)
  return ok and isPad == true
end

function GamepadMap.mapRawButton(index)
  if nxActive() then
    local nx = GamepadMap.NX_RAW_BUTTON_BINDINGS[index]
    if nx then return nx end
  end
  return GamepadMap.RAW_BUTTON_BINDINGS[index]
end

function GamepadMap.mapRawToGamepadButton(index)
  if nxActive() then
    local nx = GamepadMap.NX_RAW_TO_GAMEPAD_BUTTON[index]
    if nx then return nx end
  end
  return GamepadMap.RAW_TO_GAMEPAD_BUTTON[index]
end

return GamepadMap
