package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
love = love or require("tests.love_stub")

local Game3 = require("src.core.Game3")
local Hud = require("src.ui.game3.hud")

local SPACE = "src.core.game3.scripting.space"
local FIELD = "src.core.game3.field"
local savedSpace, savedField = package.loaded[SPACE], package.loaded[FIELD]

local state = { running = false, locked = false, pending = false }
local space = { vm = { isRunning = function() return state.running end } }
local field = {}
package.loaded[SPACE] = space
package.loaded[FIELD] = field

local function sync()
  space._pendingOnFrame = state.pending
  field.locked = state.locked
end

local function game(opts)
  opts = opts or {}
  local g = { phase = opts.phase or "field", writes = 0 }
  g.saveOffered = function() return opts.offered ~= false end
  g.saveGame = function(self) self.writes = self.writes + 1; return true end
  return setmetatable(g, { __index = Game3 })
end

local function allowed(g)
  sync()
  if type(Game3.quickSaveAllowed) ~= "function" then return nil end
  return g:quickSaveAllowed()
end

local function f1(g)
  sync()
  local before = g.writes
  local swallowed = g:_hotkey("f1")
  return swallowed, g.writes - before
end

local function reset()
  state.running, state.locked, state.pending = false, false, false
  Hud._waitButton = nil
end

check(type(Game3.quickSaveAllowed) == "function", "Game3 exposes quickSaveAllowed")
check(type(Hud.startButtonAllowed) == "function", "hud exports the START gate it already uses")

reset()
check(allowed(game()) == true, "idle field: quick save allowed")
local sw, wrote = f1(game())
check(sw == true and wrote == 1, "idle field: F1 writes one save")

reset()
state.running = true
check(allowed(game()) == false, "script running: quick save refused")
sw, wrote = f1(game())
check(sw == true and wrote == 0, "script running: F1 swallowed, nothing written")

reset()
state.locked = true
check(allowed(game()) == false, "field controls locked: refused")
sw, wrote = f1(game())
check(wrote == 0, "field controls locked: F1 writes nothing")

reset()
state.pending = true
check(allowed(game()) == false, "ON_FRAME script pending: refused")
sw, wrote = f1(game())
check(wrote == 0, "ON_FRAME script pending: F1 writes nothing")

reset()
Hud._waitButton = function() end
check(allowed(game()) == false, "HUD busy: refused")
sw, wrote = f1(game())
check(wrote == 0, "HUD busy: F1 writes nothing")

reset()
check(allowed(game({ offered = false })) == false, "START menu would not list SAVE: still refused")
sw, wrote = f1(game({ offered = false }))
check(wrote == 0, "no SAVE entry: F1 writes nothing")

reset()
check(allowed(game({ phase = "boot" })) == false, "outside the field: refused")

local function quit(g)
  sync()
  g:quit()
  return g.writes
end

reset()
check(quit(game()) == 1, "quit on an idle field autosaves")
reset()
state.running = true
check(quit(game()) == 0, "quit while a script runs writes nothing")
reset()
state.locked = true
check(quit(game()) == 0, "quit with field controls locked writes nothing")
reset()
state.pending = true
check(quit(game()) == 0, "quit with an ON_FRAME script pending writes nothing")
reset()
Hud._waitButton = function() end
check(quit(game()) == 0, "quit while the HUD is busy writes nothing")
reset()
check(quit(game({ offered = false })) == 0, "quit where START lists no SAVE writes nothing")
reset()
check(quit(game({ phase = "boot" })) == 0, "quit outside the field writes nothing")

local function startSample()
  sync()
  local input = { wasPressed = function(_, b) return b == "start" end }
  Hud.sampleFieldInput({ input = input })
  local s = Hud._fieldInput and Hud._fieldInput.start
  Hud.clearFieldInput()
  return s
end
reset()
check(startSample() == true, "START menu path: idle field opens START")
state.running = true
check(startSample() == false, "START menu path: script running blocks START as before")
reset()

package.loaded[SPACE] = savedSpace
package.loaded[FIELD] = savedField

if T.finish then T.finish() end
