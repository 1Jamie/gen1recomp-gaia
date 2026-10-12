-- Screenshots the RS PokeNav main menu and condition headers for visual comparison.
local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/rs_pokenav_header"
local TAG = os.getenv("POKENAV_SHOT_TAG") or "after"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " rs_pokenav_header failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function until_(n, fn)
  for _ = 1, n do
    if fn() then return true end
    U.wait(1)
  end
  return fn()
end

local function shot(game, name)
  U.wait(3)
  local path = DIR .. "/" .. name .. "-" .. TAG .. ".png"
  U.shot(game, path)
  U.wait(2)
  return path
end

local function enterWorld(game)
  local Message = require("src.ui.game3.message")
  local Warp = require("src.core.game3.warp")
  local Runtime = require("src.core.game3.runtime")
  pcall(function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(60)
  until_(600, function()
    if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
    return not (Warp.isBusy() or (Message.isOpen and Message.isOpen()))
  end)
  return Runtime.getSession()
end

return function(g)
  local Runtime = require("src.core.game3.runtime")
  local session = enterWorld(g)
  session = session or Runtime.getSession()
  check(session ~= nil, "new game has a session")
  local Nav = require("src.ui.game3.rs.pokenav.init")
  local ok, s = pcall(Nav.show, { session = session, game = g })
  check(ok and s ~= nil, "pokenav opens" .. (ok and "" or (": " .. tostring(s))))
  if ok and s then
    check(until_(300, function() return s.phase == "active" end), "phase reaches active")
    U.wait(10)
    shot(g, "main-menu")
    print("cursor=" .. tostring(s.cursor))
    U.tap(g, "down"); U.wait(8) -- cursor 0 (MAP) -> 1 (CONDITION)
    check(s.cursor == 1, "cursor on CONDITION (cursor=" .. tostring(s.cursor) .. ")")
    U.tap(g, "a")
    U.wait(60)
    shot(g, "condition")
    check(Nav.isOpen(), "pokenav still open after A")
  end
  finish()
end
