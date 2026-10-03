package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local candidate = os.getenv("H17_HELP_GAME3")
if candidate and candidate ~= "" then
  package.preload["src.core.Game3"] = assert(loadfile(candidate))
end
local T = require("tests.harness")
local Input = require("src.core.Input")
local Game3 = require("src.core.Game3")
local Runtime = require("src.core.game3.runtime")
local Help = require("src.ui.game3.help_system")
local Controls = require("src.ui.game3.controls_menu")
local Stack = require("src.ui.game3.stack")
local Fade = require("src.ui.game3.fade")
local Battle = require("src.core.game3.battle")
local Task = require("src.core.game3.task")
local Rng = require("src.core.game3.rng")
local pack = {version = 1, contexts = {}, topics = {}, entries = {}, basic = {}, cancel = "CANCEL"}
for i = 1, 35 do pack.contexts[i] = {} end
for i = 1, 6 do pack.topics[i] = "TOPIC " .. i; pack.entries[i] = {} end
local function reset()
  Controls.close(); Stack.clear(); Help.reset(); Help.installPack(pack)
  Fade.clear(); Input:init(); Task.clear()
  Runtime.active = false; Runtime.session = nil; Runtime._game = nil
  Runtime._deferred = nil; Runtime._menuFocus = false
  Battle._active = false; Battle._st = nil; Battle._phase = nil
end
local function game(version, mode)
  reset()
  local options = {buttonMode = mode}
  local session = {version = version, map = "FR_PLAYERS_HOUSE_2F", options = options, flags = {}}
  local g = setmetatable({generation = 3, input = Input, options = options, session = session,
    save = {options = options}, phase = "field", writes = 0,
    writeOptions = function(self) self.writes = self.writes + 1 end}, Game3)
  Runtime.active = true; Runtime.session = session; Runtime._game = g
  return g
end
local function tick(g) g:fixedUpdate(1 / 60) end
local function arm(g)
  Controls.show({game = g})
  local bm = assert(Controls._bm)
  for i, item in ipairs(bm.items) do if item.button.id == "a" then bm.index = i end end
  Input:overlayPressed("a"); tick(g)
  Input:overlayReleased("a"); tick(g)
  T.check(bm.capture and Input.captureArmed and not bm.pending, "actual Runtime/Hud A arms capture")
  return bm
end
for _, version in ipairs({"firered", "leafgreen"}) do
  for _, mode in ipairs({0, 1, 2}) do
    for _, button in ipairs({"leftshoulder", "rightshoulder"}) do
      local g = game(version, mode)
      local bm = arm(g)
      g:gamepadpressed(nil, button)
      T.check(Input.captureEvents[1].kind == "pad" and Input.captureEvents[1].value == button,
        "actual Game3 dispatch queues raw " .. button)
      tick(g)
      T.check(not Help.isOpen(), version .. " mode " .. mode .. " capture excludes Help")
      T.check(bm.pending and bm.pending.slot == "pad" and bm.pending.value == button,
        version .. " mode " .. mode .. " shoulder reaches pending in same full frame")
      T.check(g.writes == 0, "captured press waits for matching release")
      g:gamepadreleased(nil, button); tick(g)
      T.check(not bm.capture and not Input.captureArmed, "matching release completes capture")
      T.check(g.writes == 1 and g.options.bindings and g.options.bindings.a
        and g.options.bindings.a.pad == button, "matching release writes raw binding once")
      T.check(not Input:isDown("l") and not Input:isDown("r"), "release clears both logical shoulders")
      tick(g)
      T.check(g.writes == 1 and not Help.isOpen(), "settled frame does not replay release or Help")
    end
  end
end
for _, kind in ipairs({"key", "joy", "trigger"}) do
  local g = game("firered", 0)
  local binding = kind == "key" and {l = {key = "f1"}}
    or kind == "joy" and {l = {pad = "joy5"}} or {l = {pad = "triggerleft"}}
  Input:applyBindings(binding)
  local bm = arm(g)
  local value, slot
  if kind == "key" then value, slot = "f1", "key"; g:keypressed("f1")
  elseif kind == "joy" then value, slot = "joy5", "pad"; g:joystickpressed(nil, 5)
  else value, slot = "triggerleft", "pad"; g:gamepadaxis(nil, "triggerleft", 1) end
  tick(g)
  T.check(not Help.isOpen() and bm.pending and bm.pending.value == value and bm.pending.slot == slot,
    "raw " .. kind .. " mapped to L is captured before Help")
  if kind == "key" then g:keyreleased("f1")
  elseif kind == "joy" then g:joystickreleased(nil, 5)
  else g:gamepadaxis(nil, "triggerleft", 0) end
  tick(g)
  T.check(g.writes == 1 and not bm.capture and g.options.bindings.a[slot] == value,
    "raw " .. kind .. " matching release preserves raw identity and stores once")
  T.check(not Input:isDown("l"), "raw " .. kind .. " matching release clears logical L")
end
for _, cancel in ipairs({"second-pad", "touch-b", "escape", "physical-b"}) do
  local g = game("firered", 0)
  local bm = arm(g)
  g:gamepadpressed(nil, "leftshoulder"); tick(g)
  if cancel == "second-pad" then g:gamepadpressed(nil, "rightshoulder")
  elseif cancel == "touch-b" then Input:overlayPressed("b")
  elseif cancel == "escape" then g:keypressed("escape")
  else g:gamepadpressed(nil, "b") end
  tick(g)
  T.check(not Help.isOpen() and not bm.capture and not Input.captureArmed,
    cancel .. " cancels through full frame without Help intercept")
  T.check(g.writes == 0, cancel .. " cancellation does not persist")
end
for _, version in ipairs({"firered", "leafgreen"}) do
  for _, id in ipairs({"party", "bag", "summary"}) do
    local g = game(version, 0)
    local dispatches = 0
    Stack.push(id, {isMenu = true, handleInput = function() dispatches = dispatches + 1 end, _page = 0})
    local context = ({party = 5, bag = 9, summary = 6})[id]
    g:gamepadpressed(nil, "leftshoulder"); tick(g)
    T.check(Help.isOpen() and Help.contextId == context, version .. " ordinary " .. id .. " Help preserved")
    T.check(dispatches == 0, "ordinary Help remains modal above menu")
    g:gamepadreleased(nil, "leftshoulder"); tick(g)
    Input:overlayPressed("a"); tick(g)
    T.check(Help.level == "main" and dispatches == 0, "Help welcome/main flow remains modal")
    Input:overlayReleased("a"); tick(g)
    g:gamepadpressed(nil, "rightshoulder"); tick(g)
    T.check(not Help.isOpen() and dispatches == 0, "ordinary shoulder closes Help without leaking closing press")
    g:gamepadreleased(nil, "rightshoulder"); tick(g)
    T.check(dispatches == 1, "ordinary menu resumes on subsequent frame")
  end
end
for _, row in ipairs({
  {wild = true, context = 23}, {wild = false, context = 24},
  {wild = false, double = true, context = 25}, {safari = true, context = 26},
}) do
  local g = game("firered", 0)
  Stack.push("party", {isMenu = true, handleInput = function() error("Help must own battle input") end})
  Battle._active = true; Battle._st = row; Battle._phase = "command"
  local rng = Rng._value
  g:gamepadpressed(nil, "leftshoulder"); tick(g)
  T.check(Help.isOpen() and Help.contextId == row.context, "ordinary battle Help context " .. row.context .. " preserved")
  T.check(Battle.getState() == row and Battle._phase == "command" and Rng._value == rng,
    "ordinary Help still freezes battle dispatch and frame RNG")
  g:gamepadreleased(nil, "leftshoulder"); tick(g)
  g:gamepadpressed(nil, "rightshoulder"); tick(g)
  T.check(not Help.isOpen() and Battle._phase == "command" and Rng._value == rng,
    "closing Help retains battle state and does not leak input")
end
for _, mode in ipairs({1, 2}) do
  local g = game("firered", mode)
  local dispatches = 0
  Stack.push("party", {isMenu = true, handleInput = function() dispatches = dispatches + 1 end})
  g:gamepadpressed(nil, "leftshoulder"); tick(g)
  T.check(not Help.isOpen() and dispatches == 1, "ordinary non-HELP button mode remains unblocked")
end
for _, unavailable in ipairs({"disabled", "missing-pack", "fade"}) do
  local g = game("firered", 0)
  local dispatches = 0
  Stack.push("party", {isMenu = true, handleInput = function() dispatches = dispatches + 1 end})
  if unavailable == "disabled" then Help.enabled = false
  elseif unavailable == "missing-pack" then Help.installPack(nil)
  else Fade.begin(Fade.MODE.FROM_BLACK, 1) end
  g:gamepadpressed(nil, "leftshoulder"); tick(g)
  T.check(not Help.isOpen(), unavailable .. " guard still prevents opening Help")
end
reset()
T.finish("H17 actual fixedUpdate/Runtime/Hud Help capture")
