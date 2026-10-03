package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness").suite("Resolved shoulder input H17")
if os.getenv("H17_CANDIDATE") then
  local root = os.getenv("H17_CANDIDATE")
  for _, name in ipairs({"Input", "Game", "Game2", "Game3"}) do
    package.preload["src.core." .. name] = assert(loadfile(root .. "/src/core/" .. name .. ".lua"))
  end
end
do
local Input = require("src.core.Input")
local Controls = require("src.ui.game3.controls_menu")
local Stack = require("src.ui.game3.stack")
local Game = require("src.core.Game")
local Game2 = require("src.core.Game2")
local Game3 = require("src.core.Game3")
local Bag = require("src.core.game3.bag")
local BagMenu = require("src.ui.game3.bag_menu")
local Items = require("src.core.game3.items_data")
local Options = require("src.core.game3.options")
local Map = require("src.core.GamepadMap")
local safe = true
local pass, fail = 0, 0
local function check(ok, label)
  T.check(ok, label)
end
local function newGame(class, options)
  local g = setmetatable({input = Input, options = options or {}, save = {options = options or {}}, stack = {top = function() return nil end}, speeds = 0,
    writeOptions = function(self) self.writes = (self.writes or 0) + 1 end,
    _cycleSpeed = function(self, n) self.speeds = self.speeds + n end}, {__index = class})
  return g
end
local function bindAtoLB()
  Input:init(); Stack.clear()
  local beforeLB = Input.padBindings.leftshoulder
  local g = newGame(Game3)
  Controls.show({game = g})
  local menu = assert(Controls._bm)
  for i, item in ipairs(menu.items) do if item.button.id == "a" then menu.index = i end end
  Input:overlayPressed("a"); Input:step(); Controls.handleInput(Input)
  Input:overlayReleased("a"); Input:step(); Controls.handleInput(Input)
  g:gamepadpressed(nil, "leftshoulder"); Input:step(); Controls.handleInput(Input)
  g:gamepadreleased(nil, "leftshoulder"); Input:step(); Controls.handleInput(Input)
  check(g.options.bindings.a.pad == "leftshoulder" and g.options.bindings.l.pad == "a", "actual Controls A←LB/L←oldA swap")
  check(g.writes == 1 and Input.padBindings.leftshoulder == beforeLB, "one detached write and delayed apply")
  Input:overlayPressed("b"); Input:step(); Controls.handleInput(Input)
  Input:overlayReleased("b"); Input:step()
  check(not Controls.open and not Stack.has("controls"), "real menu closes and applies")
  return g
end
local g3 = bindAtoLB()
Items.installPack({items = {
  [13] = {name = "POTION", pocket = "ITEMS", description = "Fixture potion"},
  [360] = {name = "BICYCLE", pocket = "KEY_ITEMS", description = "Fixture bike", registrability = 1},
  [4] = {name = "POKE BALL", pocket = "POKE_BALLS", description = "Fixture ball"},
}})
for _, lr in ipairs({true, false}) do
  local session = {version = "firered", options = {buttonMode = lr and 1 or 0}, bag = Bag.new(), party = {}}
  session.bag.pockets.KEY_ITEMS = {{id = 360, qty = 1}}
  BagMenu.show(session, {pocketIdx = 2})
  BagMenu.settle()
  check(Options.lrMode(session) == lr and BagMenu.currentPocket() == "KEY_ITEMS", "actual LR option and settled KEY pocket")
  g3:gamepadpressed(nil, "leftshoulder"); Input:step()
  check(Input:wasPressed("a"), "configured A reaches actual Bag input")
  BagMenu.handleInput(Input)
  if lr then
    check(BagMenu.pocketIdx == (safe and 2 or 1) and BagMenu.mode == (safe and "action" or "list"), "LR mode: A must open KEY action instead of paging left")
    print("OBS bag LR=true pocket=" .. BagMenu.currentPocket() .. " mode=" .. BagMenu.mode .. " extraL=" .. tostring(Input:wasPressed("l")))
  else
    check(BagMenu.pocketIdx == 2 and BagMenu.mode == "action", "LR off: actual A action consumer positive control")
  end
  g3:gamepadreleased(nil, "leftshoulder"); Input:step(); BagMenu.close()
end
for _, row in ipairs({{Game, "Gen1"}, {Game2, "Gen2"}}) do
  Input:reset(); Input:applyBindings(g3.options.bindings)
  local g = newGame(row[1], g3.options)
  g:gamepadpressed(nil, "leftshoulder"); Input:step()
  check(g.speeds == (safe and 0 or -1) and Input:wasPressed("a") == safe, row[2] .. " plain assigned LB must defeat inherited default speed")
  g:gamepadreleased(nil, "leftshoulder"); Input:step()
end
local physical = {}
local pad = {isGamepad = function() return true end, isGamepadDown = function(_, b) return physical[b] == true end,
  getGamepadAxis = function() return 0 end, isConnected = function() return true end, getName = function() return "Xbox Controller" end}
love.joystick = {getJoystickCount = function() return 1 end, getJoysticks = function() return {pad} end}
Input:reset(); Input:applyBindings(g3.options.bindings); Input:step()
physical.leftshoulder = true
g3:gamepadpressed(pad, "leftshoulder"); Input:step()
physical.leftshoulder = false
Input:step()
check(not Input:isDown("a"), "poll repair releases configured A when release event is lost")
check(Input:isDown("l") == not safe, "poll repair must also avoid stranded hardwired extra L")
print("OBS missed release: A=" .. tostring(Input:isDown("a")) .. " L=" .. tostring(Input:isDown("l")))
Input:init(); Input:step(); physical.leftshoulder = true; Input:step()
check(Input:isDown("l") == safe, "default first-class L must use same pollable map on lost press")
physical.leftshoulder = false; Input:step()
Input:reset(); physical.leftshoulder = true; Input:reconcile(); Input:step()
check(Input:isDown("l") == safe, "default first-class L must use same map during reconcile")
physical.leftshoulder = false; Input:step()
love.joystick = nil
for _, button in ipairs({"leftshoulder", "rightshoulder"}) do
  Input:init(); Input:applyBindings({speedUp = {pad = button}})
  local g = newGame(Game3)
  g:gamepadpressed(nil, button); Input:step()
  check(g.speeds == (safe and 1 or 0), "explicit Gen3 SPEED+ on " .. button .. " must execute")
  check(Input:wasPressed(button == "leftshoulder" and "l" or "r") == not safe, "explicit speed action must not emit shoulder gameplay")
  g:gamepadreleased(nil, button); Input:step()
end
for _, row in ipairs({{Game, "Gen1"}, {Game2, "Gen2"}, {Game3, "Gen3"}}) do
  Input:init(); Input:applyBindings({a = {pad = "lefttrigger"}})
  check(Input.padBindings.triggerleft == "a", "legacy trigger alias canonicalizes")
  local g = newGame(row[1]); g:gamepadaxis(nil, "triggerleft", 1); Input:step()
  check(g.speeds == (safe and 0 or -1) and Input:wasPressed("a") == safe, row[2] .. " plain trigger binding must defeat inherited default action")
  g:gamepadaxis(nil, "triggerleft", 0); Input:step()
end
for _, row in ipairs({{Game, "Gen1"}, {Game2, "Gen2"}, {Game3, "Gen3"}}) do
  Input:init(); Input:applyBindings({a = {pad = "joy5"}, speedUp = {pad = "joy6"}})
  local g = newGame(row[1])
  g:joystickpressed(nil, 5); Input:step()
  check(Input:wasPressed("a") and g.speeds == 0, row[2] .. " unrecognized raw JOY5 plain binding positive")
  g:joystickreleased(nil, 5); Input:step()
  g:joystickpressed(nil, 6); Input:step()
  check(g.speeds == 1, row[2] .. " unrecognized raw JOY6 explicit speed positive")
  g:joystickreleased(nil, 6); Input:step()
end
check(Map.DEFAULT_GAMEPAD_BINDINGS.leftshoulder == nil and Map.DEFAULT_PAD_ACTIONS.leftshoulder == "speedDown", "launcher/shared defaults unchanged during read-only probe")
end
do
local Input = require("src.core.Input")
local Game = require("src.core.Game")
local Game3 = require("src.core.Game3")
local Controls = require("src.ui.game3.controls_menu")
local Stack = require("src.ui.game3.stack")
local safe = true
local pass, fail = 0, 0
local function check(ok, label)
  T.check(ok, label)
end
local function newGame(class)
  return setmetatable({input = Input, options = {}, save = {options = {}}, stack = {top = function() return nil end}, speeds = 0,
    writeOptions = function(self) self.writes = (self.writes or 0) + 1 end,
    _cycleSpeed = function(self, n) self.speeds = self.speeds + n end}, {__index = class})
end
Input:init(); Stack.clear()
local g3 = newGame(Game3)
Controls.show({game = g3})
for i, item in ipairs(Controls._bm.items) do if item.button.id == "speedUp" then Controls._bm.index = i end end
Input:overlayPressed("a"); Input:step(); Controls.handleInput(Input)
Input:overlayReleased("a"); Input:step(); Controls.handleInput(Input)
g3:gamepadpressed(nil, "leftshoulder"); Input:step(); Controls.handleInput(Input)
g3:gamepadreleased(nil, "leftshoulder"); Input:step(); Controls.handleInput(Input)
check(g3.options.bindings.speedUp.pad == "leftshoulder" and g3.options.bindings.l.pad == "triggerright", "actual SPEED+←LB/L←oldR2 swap")
check(g3.writes == 1, "one actual detached configuration write")
Input:overlayPressed("b"); Input:step(); Controls.handleInput(Input)
Input:overlayReleased("b"); Input:step()
g3:gamepadpressed(nil, "leftshoulder"); Input:step()
check(g3.speeds == (safe and 1 or 0) and Input:wasPressed("l") == not safe, "actual speed-row shoulder binding must execute exclusively")
g3:gamepadreleased(nil, "leftshoulder"); Input:step()
g3:gamepadaxis(nil, "triggerright", 1); Input:step()
check(Input:wasPressed("l"), "actual moved L on old R2 remains usable")
g3:gamepadaxis(nil, "triggerright", 0); Input:step()
Input:init(); Input:applyBindings({speedDown = false, a = {pad = "leftshoulder"}})
local g1 = newGame(Game)
g1:gamepadpressed(nil, "leftshoulder"); Input:step()
check(g1.speeds == 0 and Input:wasPressed("a"), "explicit OFF defeats both inherited speedDown aliases")
g1:gamepadreleased(nil, "leftshoulder"); Input:step()
check(Input:padAction("triggerleft") == nil, "explicit OFF disables the trigger alias as today")
Input:init(); Input:applyBindings({a = {pad = "lefttrigger"}, speedUp = {pad = "triggerleft"}})
g1:gamepadaxis(nil, "triggerleft", 1); Input:step()
check(g1.speeds == 1 and not Input:wasPressed("a"), "explicit speed action wins a canonicalized conflicting plain binding")
g1:gamepadaxis(nil, "triggerleft", 0); Input:step()
Input:init(); Input:applyBindings({speedUp = {pad = "joy1"}})
local raw = {isGamepad = function() return false end, isDown = function(_, b) return b == 1 end,
  getAxis = function() return 0 end, getHatCount = function() return 0 end, getName = function() return "Generic Controller" end}
love.joystick = {getJoysticks = function() return {raw} end, getJoystickCount = function() return 1 end}
Input:reconcile(); Input:step()
check(Input:isDown("a") == not safe, "explicit raw action must not rehydrate a shadow default A during reconcile")
Input:reset(); love.joystick = nil
end
do
local Input = require("src.core.Input")
local classes = {{require("src.core.Game"), "Gen1"}, {require("src.core.Game2"), "Gen2"}, {require("src.core.Game3"), "Gen3"}}
local expected = true
local pass, fail = 0, 0
for _, row in ipairs(classes) do
  Input:init(); Input:applyBindings({speedUp = {pad = "joy1"}})
  local g = setmetatable({input = Input, options = {}, save = {options = {}}, stack = {top = function() return nil end}, speeds = 0,
    _cycleSpeed = function(self, n) self.speeds = self.speeds + n end}, {__index = row[1]})
  local pad = {isGamepad = function() return true end, getName = function() return "Xbox Controller" end}
  g:joystickpressed(pad, 1)
  Input:step()
  local ok = g.speeds == (expected and 0 or 1) and not Input:wasPressed("a")
  T.check(ok, row[2] .. " recognized raw event cannot dispatch actions")
  print((ok and "PASS " or "FAIL ") .. row[2] .. " recognized pad raw event must be ignored before action lookup; speed=" .. g.speeds)
  g:joystickreleased(pad, 1); Input:step()
end
end
do
local Input = require("src.core.Input")
local Map = require("src.core.GamepadMap")
local classes = {require("src.core.Game"), require("src.core.Game2"), require("src.core.Game3")}
local physical = {}
local pad = {isGamepad = function() return true end, getName = function() return "Xbox" end,
  isGamepadDown = function(_, b) return physical[b] == true end,
  getGamepadAxis = function() return 0 end, isConnected = function() return true end}
love.joystick = {getJoysticks = function() return {pad} end, getJoystickCount = function() return 1 end}
local function fixture(i, bindings)
  physical = {}
  Input:init(i == 3); Input:applyBindings(bindings); Input:step()
  return setmetatable({input = Input, stack = {top = function() return nil end}, speeds = 0,
    _cycleSpeed = function(self, n) self.speeds = self.speeds + n end}, {__index = classes[i]})
end
for i = 1, 3 do
  local g = fixture(i)
  physical.leftshoulder = true; g:gamepadpressed(pad, "leftshoulder"); Input:step()
  T.eq(g.speeds, i == 3 and 0 or -1, "generation " .. i .. " default shoulder action")
  T.eq(Input:isDown("l"), i == 3, "generation " .. i .. " default shoulder gameplay")
  physical.leftshoulder = false; Input:step()
  T.check(not Input:isDown("l"), "lost shoulder release clears generation " .. i)
  g = fixture(i); physical.rightshoulder = true; Input:step()
  T.eq(Input:isDown("r"), i == 3, "lost default press follows generation policy " .. i)
  Input:reset(); Input:reconcile(); Input:step()
  T.eq(Input:isDown("r"), i == 3, "reconcile follows generation policy " .. i)
  g = fixture(i, {a = {pad = "rightshoulder"}})
  physical.rightshoulder = true; Input:step()
  T.check(Input:isDown("a") and not Input:isDown("r"), "poll resolves configured A exclusively " .. i)
  Input:reset(); Input:reconcile(); Input:step()
  T.check(Input:isDown("a") and not Input:isDown("r"), "reconcile resolves configured A exclusively " .. i)
  g = fixture(i, {speedUp = {pad = "a"}})
  physical.a = true; Input:step(); Input:reset(); Input:reconcile(); Input:step()
  T.check(not Input:isDown("a"), "explicit face action never rehydrates inherited A " .. i)
  g:gamepadpressed(pad, "a"); Input:step()
  T.eq(g.speeds, 1, "explicit face speed callback executes " .. i)
  g = fixture(i, {speedDown = false})
  T.eq(Input:padAction("leftshoulder"), nil, "OFF removes default shoulder action " .. i)
  T.eq(Input:padAction("triggerleft"), nil, "OFF removes default trigger action " .. i)
end
local g = fixture(3, {a = {pad = "leftshoulder"}})
Input:keypressed("z"); Input:overlayPressed("a"); Input:sourcePress("a", "mod:test:1")
physical.leftshoulder = true; g:gamepadpressed(pad, "leftshoulder"); Input:step()
T.check(Input.sources.a["pad:leftshoulder"] and not Input.sources.l, "configured source uses physical pad tag only")
physical.leftshoulder = false; Input:step()
T.check(Input:isDown("a") and not Input.sources.a["pad:leftshoulder"], "poll releases only its source while keyboard/touch/mod cohold")
Input:keyreleased("z"); Input:overlayReleased("a"); Input:sourceRelease("a", "mod:test:1"); Input:step()
T.check(not Input:isDown("a"), "last independent cohold clears")
g = fixture(3)
g:gamepadpressed(nil, "leftshoulder"); g:gamepadreleased(nil, "leftshoulder"); Input:step()
T.check(Input:wasPressed("l") and not Input:isDown("l"), "same-frame shoulder tap preserves edge without hold")
g = fixture(3); physical.leftshoulder = true; Input:reset(); Input:step()
T.check(not Input:isDown("l"), "soft reset suppresses physically held shoulder")
physical.leftshoulder = false; Input:step(); physical.leftshoulder = true; Input:step()
T.check(Input:isDown("l"), "physical neutral rearms shoulder poll")
g = fixture(3); Input.captureArmed = true; physical.leftshoulder = true; Input:step()
T.check(not Input:isDown("l"), "poll cannot synthesize during raw capture")
g:gamepadpressed(pad, "leftshoulder"); Input:step()
T.check(Input.captureEvents and Input.captureEvents[1].value == "leftshoulder", "actual capture event keeps shoulder candidate")
g:gamepadreleased(pad, "leftshoulder"); Input.captureArmed = false; physical.leftshoulder = false; Input:step()
local Runtime = require("src.mods.Runtime"); local wants = Runtime.wantsHook
g = fixture(3); Runtime.wantsHook = function(hook) return hook == "input.gamepad" end
physical.leftshoulder = true; Input:step()
T.check(not Input:isDown("l"), "mod pad owner suppresses watchdog press")
Runtime.wantsHook = wants
local Hints = require("src.core.PadHints"); local minimized = Hints.windowMinimized
g = fixture(3); Hints.windowMinimized = function() return true end
physical.leftshoulder = true; Input:step()
T.check(not Input:isDown("l"), "minimized window suppresses watchdog press")
Hints.windowMinimized = minimized
love.joystick = nil
for i = 1, 3 do
  g = fixture(i, {speedUp = {pad = "joy1"}}); love.joystick = nil
  local sensor = {isGamepad = function() return false end, getName = function() return "Phone Accelerometer" end}
  g:joystickpressed(sensor, 1); Input:step()
  T.check(g.speeds == 0 and not Input:isDown("a"), "sensor raw callback ignored before action lookup " .. i)
end
Map._setForceNXForTests(true)
Input:init(); Input:applyBindings({a = {pad = "leftshoulder"}})
Input:gamepadpressed(pad, "leftshoulder"); Input:step()
T.check(Input:isDown("a") and not Input:isDown("l"), "NX explicit shoulder resolves exclusively")
T.eq(Input.padBindings.b, "a", "NX face default remains Nintendo A")
T.eq(#Input.padPoll, 0, "NX still excludes unsupported polling")
Map._setForceNXForTests(false)
Input:init(); love.joystick = nil
end
T.finish()
