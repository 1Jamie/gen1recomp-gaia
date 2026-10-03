package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
love.system.getOS = function() return "Android" end

local T = require("tests.harness")
local Input = require("src.core.Input")
local Touch = require("src.core.TouchControls")
local Bindings = require("src.ui.BindingsMenu")
local routes = { { "Gen1", require("src.core.Game") }, { "Gen2", require("src.core.Game2") } }

local function fixture()
  Input:init()
  Touch:init()
  local game = { input = Input, save = { options = {} }, writes = 0 }
  game.stack = { states = {} }
  function game.stack:push(s) self.states[#self.states + 1] = s end
  function game.stack:pop() return table.remove(self.states) end
  function game.stack:top() return self.states[#self.states] end
  function game:writeOptions() self.writes = self.writes + 1 end
  local menu = Bindings.new(game)
  game.stack:push(menu)
  return game, menu
end

local function tick(menu)
  Input:step()
  menu:update(1 / 60)
end

local function contact(route, game, btn, id, down)
  local z = Touch:layout()[btn]
  if down then route.touchpressed(game, id, z.cx, z.cy, 0, 0, 1)
  else route.touchreleased(game, id, z.cx, z.cy, 0, 0, 0) end
end

for _, pair in ipairs(routes) do
  local label, route = pair[1], pair[2]
  local function check(v, s) T.check(v, label .. ": " .. s) end
  local function arm()
    local game, menu = fixture()
    contact(route, game, "a", 1, true)
    tick(menu)
    check(menu.capture == menu.items[1], "touch A arms capture")
    contact(route, game, "a", 1, false)
    tick(menu)
    check(menu.capture ~= nil and menu.pending == nil, "initiating A release is ignored")
    return game, menu
  end

  local game, menu = arm()
  contact(route, game, "b", 2, true)
  tick(menu)
  check(menu.capture == nil and not Input.captureArmed, "touch B cancels capture")
  check(game.stack:top() == menu, "cancel stays on Controls")
  check(game.writes == 0 and game.save.options.bindings == nil, "touch cancellation stores no binding")
  contact(route, game, "b", 2, false)
  tick(menu)
  check(game.stack:top() == menu, "cancel release does not close Controls")
  contact(route, game, "b", 3, true)
  tick(menu)
  check(game.stack:top() == nil, "next touch B closes normally")

  game, menu = arm()
  contact(route, game, "b", 2, true)
  contact(route, game, "b", 2, false)
  tick(menu)
  check(menu.capture == nil and game.stack:top() == menu, "same-step B press and release cancels only capture")
  check(not Input:isDown("b"), "same-step tap does not strand B held")

  game, menu = fixture()
  contact(route, game, "b", 2, true)
  menu:beginCapture(menu.items[1])
  tick(menu)
  check(menu.capture ~= nil, "pre-capture held B edge cannot cancel")
  contact(route, game, "b", 2, false)
  tick(menu)
  check(menu.capture ~= nil, "stale B release cannot cancel")
  contact(route, game, "b", 3, true)
  tick(menu)
  check(menu.capture == nil, "new B after stale contact cancels")

  game, menu = fixture()
  contact(route, game, "a", 1, true)
  tick(menu)
  contact(route, game, "b", 2, true)
  tick(menu)
  check(menu.capture == nil and game.stack:top() == menu, "B cancels while initiating A remains held")
  contact(route, game, "a", 1, false)
  contact(route, game, "b", 2, false)
  tick(menu)
  check(game.writes == 0 and game.stack:top() == menu, "initiating late releases cannot bind or close")

  game, menu = arm()
  Input:keypressed("z")
  tick(menu)
  check(menu.pending and menu.pending.value == "z", "physical candidate waits for release")
  contact(route, game, "b", 2, true)
  tick(menu)
  Input:keyreleased("z")
  contact(route, game, "b", 2, false)
  tick(menu)
  check(menu.capture == nil and menu.pending == nil and game.writes == 0, "touch B cancels held candidate; late release cannot store")

  game, menu = arm()
  Input:keypressed("x")
  tick(menu)
  check(menu.capture ~= nil and menu.pending and menu.pending.value == "x", "physical mapped B remains bindable")
  Input:keyreleased("x")
  tick(menu)
  check(menu.capture == nil and game.save.options.bindings.up.key == "x", "physical B release stores capture")

  game, menu = arm()
  contact(route, game, "b", 2, true)
  contact(route, game, "b", 3, true)
  tick(menu)
  check(menu.capture == nil and game.stack:top() == menu, "two fingers cancel once")
  contact(route, game, "b", 2, false)
  tick(menu)
  check(Input:isDown("b") and game.stack:top() == menu, "one finger release retains other hold without closing")
  contact(route, game, "b", 3, false)
  tick(menu)
  check(not Input:isDown("b") and game.stack:top() == menu, "final finger release clears hold without closing")

  game, menu = arm()
  Input:keypressed("escape")
  tick(menu)
  check(menu.capture == nil and game.writes == 0, "Escape still cancels")
  menu:beginCapture(menu.items[5])
  Input:gamepadpressed(nil, "x")
  tick(menu)
  Input:gamepadpressed(nil, "b")
  tick(menu)
  check(menu.capture == nil and game.writes == 0, "second physical pad press still cancels")
  Input:gamepadreleased(nil, "x")
  Input:gamepadreleased(nil, "b")
  tick(menu)

  menu:beginCapture(menu.items[6])
  Input:keypressed("z")
  tick(menu)
  check(game.writes == 0, "swap waits for release")
  Input:keyreleased("z")
  tick(menu)
  check(game.save.options.bindings.b.key == "z" and game.save.options.bindings.a.key == "x", "release stores exact A/B swap")
  check(Input.keyBindings.z == "a" and Input.keyBindings.x == "b", "live mappings remain deferred")
  contact(route, game, "b", 4, true)
  tick(menu)
  check(game.stack:top() == nil and Input.keyBindings.z == "b" and Input.keyBindings.x == "a", "closing applies both mappings")

  game, menu = arm()
  Input:sourcePress("b", "mod:h15-control")
  tick(menu)
  check(menu.capture ~= nil and menu.pending == nil, "logical mod B cannot impersonate touch cancellation")
  Input:sourceRelease("b", "mod:h15-control")
  Input:overlayPressed("left")
  Input:overlayReleased("left")
  tick(menu)
  check(menu.capture ~= nil and menu.pending == nil, "touch direction cannot become a binding")
end

Input:init()
Input:overlayPressed("b")
Input:overlayReleased("b")
T.check(Input.captureEvents == nil and not Input.captureArmed, "unarmed overlay events allocate no raw capture queue")
Input:step()
T.check(Input:wasPressed("b") and not Input:isDown("b"), "unarmed touch tap preserves logical edge and released state")
Input:init()
T.finish("touch_binding_cancel_h15")
