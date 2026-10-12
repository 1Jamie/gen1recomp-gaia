-- F3 toggles the frame overlay only when nothing else wants the key.
--   luajit tests/engine/frame_profiler_f3_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local P = require("src.core.FrameProfiler")

-- Mirrors Game:keypressed's vanilla path: a top state with onKeyPressed owns the key.
local function fakeGame(top)
  local g = { delivered = {} }
  g.stack = { top = function() return top end }
  function g:keypressed(key)
    local t = self.stack:top()
    if t and t.onKeyPressed then return t:onKeyPressed(key) end
    self.delivered[#self.delivered + 1] = key
  end
  return g
end

local function fresh() P.init(function() return nil end); P.setEnabled(false) end

-- normal play: toggles on, and again off
do
  fresh()
  local g = fakeGame({})
  local input = { keyBindings = { z = "a" } }
  T.eq(P.keypressed("f3", g, input), true, "reports the toggle")
  T.check(P.enabled, "F3 enables the overlay")
  P.keypressed("f3", g, input)
  T.check(not P.enabled, "second F3 disables it")
  T.eq(#g.delivered, 2, "F3 still reaches the game's key handler")
end

-- capturing state on top: delivered, no toggle
do
  fresh()
  local got = {}
  local top = { onKeyPressed = function(_, key) got[#got + 1] = key end }
  local g = fakeGame(top)
  T.eq(P.keypressed("f3", g, { keyBindings = {} }), false, "no toggle")
  T.check(not P.enabled, "overlay stays off while a state captures keys")
  T.eq(got[1], "f3", "onKeyPressed received f3")
end

-- bound to an action: no toggle
do
  fresh()
  local g = fakeGame({})
  P.keypressed("f3", g, { keyBindings = { f3 = "start" } })
  T.check(not P.enabled, "a player binding of F3 wins")
  T.eq(g.delivered[1], "f3", "bound F3 is delivered to the game")
end

-- robustness: no stack / no input (Gen 2/3 shapes) still toggles
do
  fresh()
  local g = { keypressed = function() end }
  P.keypressed("f3", g, nil)
  T.check(P.enabled, "missing stack/input counts as free")
  fresh()
  local bad = { keypressed = function() end, stack = { top = function() error("boom") end } }
  P.keypressed("f3", bad, {})
  T.check(P.enabled, "a throwing top() is guarded")
end

T.finish("frame profiler f3")
