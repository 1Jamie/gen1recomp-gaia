--   luajit tests/engine/save_editor_portmaster_pad_2829.lua

package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua"
  .. ";./tools/save-editor/panels/?.lua"

love = require("tests.love_stub")
love.mouse = love.mouse or {}
love.mouse.getPosition = function() return -1, -1 end
love.mouse.isDown = function() return false end

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. msg)
  end
end
local function eq(a, b, msg)
  check(a == b, msg .. string.format(" (got %s, want %s)", tostring(a), tostring(b)))
end

local ffi = require("ffi")
local setVar
if ffi.os == "Windows" then
  ffi.cdef([[ int _putenv(const char *envstring); ]])
  setVar = function(name, value) ffi.C._putenv(name .. "=" .. value) end
else
  ffi.cdef([[
  int setenv(const char *name, const char *value, int overwrite);
  int unsetenv(const char *name);
  ]])
  setVar = function(name, value)
    if value == "" then ffi.C.unsetenv(name) else ffi.C.setenv(name, value, 1) end
  end
end
local originalDataDir = os.getenv("POKEPORT_DATA_DIR")
local originalHandheld = os.getenv("POKEPORT_HANDHELD")
setVar("POKEPORT_DATA_DIR", "tests/fixture_data")

local PadInput = require("PadInput")

PadInput.reset()
PadInput.gamepadaxis(nil, "triggerright", 1)
PadInput.update(0.016)
eq(PadInput.takeWheel(), -3, "R2 axis scrolls down a page of notches")
PadInput.update(0.016)
eq(PadInput.takeWheel(), 0, "a held R2 does not repeat before the delay")
PadInput.update(0.5)
check(PadInput.takeWheel() < 0, "a held R2 keeps scrolling down")
PadInput.gamepadaxis(nil, "triggerright", 0)
PadInput.update(0.5)
eq(PadInput.takeWheel(), 0, "releasing R2 stops the scroll")

PadInput.gamepadaxis(nil, "triggerleft", 0.9)
PadInput.gamepadaxis(nil, "triggerleft", 0.95)
PadInput.update(0.016)
eq(PadInput.takeWheel(), 3, "L2 axis scrolls up once per press")
PadInput.gamepadaxis(nil, "triggerleft", 0)
check(PadInput.isActive(), "a trigger raises the pad pointer so the wheel lands in the content")

PadInput.reset()
eq(PadInput.gamepadpressed(nil, "triggerright"), nil, "trigger button press is not a host action")
PadInput.update(0.016)
eq(PadInput.takeWheel(), -3, "digital R2 button scrolls down")
PadInput.gamepadreleased(nil, "triggerright")

PadInput.reset()
local rawJoy = { isGamepad = function() return false end }
PadInput.joystickaxis(rawJoy, 4, 1)
PadInput.update(0.016)
eq(PadInput.takeWheel(), -3, "raw R2 axis scrolls down like the launcher")
PadInput.joystickaxis(rawJoy, 4, -1)
PadInput.joystickaxis(rawJoy, 3, 1)
PadInput.update(0.016)
eq(PadInput.takeWheel(), 3, "raw L2 axis scrolls up like the launcher")
PadInput.reset()

local Kit = require("Kit")
local Ops = require("Ops")
local App = require("App")
local VirtualKeyboard = require("src.ui.kit.VirtualKeyboard")

local tmpPath = os.tmpname() .. "-pad-2829.lua"
os.remove(tmpPath)
App.load(tmpPath)
local S = App.getState()
check(S ~= nil, "the editor opens")

local wheel = {}
local realWheel = App.wheelmoved
App.wheelmoved = function(x, y)
  wheel[#wheel + 1] = y
  return realWheel(x, y)
end

App.gamepadaxis(nil, "triggerright", 1)
App.update(0.016)
eq(wheel[#wheel], -3, "R2 reaches the editor wheel")
App.gamepadaxis(nil, "triggerright", 0)
App.gamepadaxis(nil, "triggerleft", 1)
App.update(0.016)
eq(wheel[#wheel], 3, "L2 reaches the editor wheel")
App.gamepadaxis(nil, "triggerleft", 0)

S.tab = "items"
local n = #wheel
App.keypressed("pagedown")
eq(wheel[n + 1], -3, "Page Down scrolls")
App.keypressed("pageup")
eq(wheel[n + 2], 3, "Page Up scrolls")
App.keypressed("down")
eq(wheel[n + 3], -1, "Down arrow scrolls")
S.tab = "map"
n = #wheel
App.keypressed("down")
eq(#wheel, n, "arrows still pan the map instead of scrolling")
S.tab = "items"
App.wheelmoved = realWheel

Ops.openItemPicker(S, Kit, "bag")
check(S.itemPicker ~= nil, "the add-item picker opens")
App.gamepadpressed(nil, "b")
check(S.itemPicker == nil, "B closes the picker")
check(not S._closeRequested and not S._quitArmed, "B on a picker does not close the editor")

setVar("POKEPORT_HANDHELD", "1")
Kit.blur()
Kit.beginFrame(20, 20, true, 0)
Kit.textfield("pm-field", 0, 0, 100, 40, "", "Name")
Kit.endFrame()
check(VirtualKeyboard.active, "pressing a field on a handheld opens the on-screen keyboard")
eq(VirtualKeyboard.targetId, "pm-field", "the keyboard targets the pressed field")
eq(Kit.focus, "pm-field", "the field keeps focus while the keyboard is up")

App.gamepadpressed(nil, "a")
App.gamepadpressed(nil, "dpright")
App.gamepadpressed(nil, "a")
eq(VirtualKeyboard.text, "12", "pad presses type through the keyboard, not the pad pointer")
App.gamepadpressed(nil, "start")
check(not VirtualKeyboard.active, "Start confirms the keyboard")

local submitted
Kit.beginFrame(-1, -1, false, 0)
local value = Kit.textfield("pm-field", 0, 0, 100, 40, "", "Name", {
  onSubmit = function(v) submitted = v end,
})
Kit.endFrame()
eq(value, "12", "the field takes the typed text")
eq(submitted, "12", "confirming submits the field")
eq(Kit.focus, nil, "confirming blurs the field")

Kit.requestKeyboard("pm-num")
Kit.beginFrame(-1, -1, false, 0)
Kit.textfield("pm-num", 0, 0, 100, 40, "5", "")
Kit.endFrame()
check(VirtualKeyboard.active, "a value field focused by its button opens the keyboard")
App.gamepadpressed(nil, "b")
check(not VirtualKeyboard.active, "B cancels the keyboard")
Kit.beginFrame(-1, -1, false, 0)
value = Kit.textfield("pm-num", 0, 0, 100, 40, "5", "")
Kit.endFrame()
eq(value, "5", "cancelling keeps the old value")
eq(Kit.focus, nil, "cancelling blurs the field")

Kit.focus = "pm-auto"
Kit.beginFrame(-1, -1, false, 0)
Kit.textfield("pm-auto", 0, 0, 100, 40, "", "")
Kit.endFrame()
check(not VirtualKeyboard.active, "an auto-focused search field waits for a press")
Kit.blur()

setVar("POKEPORT_HANDHELD", "")
Kit.beginFrame(20, 20, true, 0)
Kit.textfield("pm-desk", 0, 0, 100, 40, "", "")
Kit.endFrame()
check(not VirtualKeyboard.active, "desktop fields keep the physical keyboard")
Kit.blur()

App.unload()
os.remove(tmpPath)
setVar("POKEPORT_HANDHELD", originalHandheld or "")
setVar("POKEPORT_DATA_DIR", originalDataDir or "")

print(string.format("save_editor_portmaster_pad_2829: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
