local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_oldale_blocker_savestate_2913"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end
  local function finish()
    print(string.format("[driver] em_oldale_blocker_savestate_2913: %d failure(s)", fails))
    love.event.quit(fails == 0 and 0 or 1)
    U.wait(10)
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Field = require("src.core.game3.field")
  local VARS = Flags.forVersion("emerald").VAR_IDS
  local IDS = Flags.forVersion("emerald").IDS
  result(Runtime.getSession() ~= nil, "field session exists")
  if not Runtime.getSession() then return finish() end

  local function goTo(x, y)
    Map.load(nil, game, "EM_OLDALE_TOWN", { x = x, y = y, facing = "left" })
    local s = Runtime.getSession()
    s.x, s.y, s.facing = x, y, "left"
    Player.cellX, Player.cellY, Player.px, Player.py = x, y, x * 16, y * 16
    Player.targetX, Player.targetY, Player.facing = x, y, "left"
    U.wait(40)
  end
  -- data/maps/OldaleTown/map.json:72
  local blocked = Space.scriptKey("OldaleTown_EventScript_BlockedPath")
  local function blockedRunning()
    return Space.vm and Space.vm:isRunning() and Space.vm._scriptKey == blocked
  end
  local function holdLeft(n)
    local fired = false
    for _ = 1, n do
      table.insert(game.input.pressQueue, "left")
      game.input.state.left = true
      coroutine.yield()
      game.input.state.left = false
      if blockedRunning() then fired = true end
    end
    return fired
  end
  local function settle()
    for _ = 1, 600 do
      if not (Space.vm and Space.vm:isRunning()) and not Field.isLocked() and not Player.moving then return end
      local Message = require("src.ui.game3.message")
      if Message.isOpen and Message.isOpen() then table.insert(game.input.pressQueue, "a") end
      U.wait(1)
    end
  end
  local function cell() return Player.cellX .. "," .. Player.cellY end

  -- data/maps/OldaleTown/scripts.inc:8
  Flags.setVar(Space.store, nil, VARS.VAR_OLDALE_TOWN_STATE, 0)
  Flags.setFlag(Space.store, nil, IDS.FLAG_ADVENTURE_STARTED, false)
  goTo(1, 10)
  result(game:quickSaveAllowed(), "quick save allowed at rest on (1,10)")
  game:_hotkey("f1")
  U.wait(5)

  local SaveData = require("src.core.SaveData")
  for _, run in ipairs({ false, true }) do
    local label = run and "running" or "walking"
    goTo(2, 10)
    Flags.setVar(Space.store, nil, VARS.VAR_OLDALE_TOWN_STATE, 0)
    Flags.setFlag(Space.store, nil, IDS.FLAG_SYS_B_DASH, run)
    game:_hotkey("f1")
    U.wait(3)
    local pressed = false
    for _ = 1, 120 do
      table.insert(game.input.pressQueue, "left")
      game.input.state.left = true
      game.input.state.b = run
      coroutine.yield()
      if not pressed and Player.moving and Player.cellX == 1 and Player.targetX == 0 and Player.px < 12 then
        U.still(game, DIR .. "/2913_01_" .. label .. "_into_trigger.png")
        result(Runtime.getSession().x == 1, label .. ": session stays on (1,10) mid-step after a draw (" .. tostring(Runtime.getSession().x) .. ")")
        love.keypressed("f1", "f1", false)
        love.keyreleased("f1", "f1")
        pressed = true
      end
      if blockedRunning() then break end
    end
    game.input.state.left = false
    game.input.state.b = false
    result(pressed, label .. ": F1 pressed mid-step into (0,10)")
    settle()
    local sv = SaveData.load()
    result(sv and sv.x == 1 and sv.y == 10, label .. ": quick save mid-step holds (1,10) (" .. tostring(sv and sv.x) .. "," .. tostring(sv and sv.y) .. ")")
    love.keypressed("f2", "f2", false)
    love.keyreleased("f2", "f2")
    U.wait(80)
    settle()
    result(cell() == "1,10", label .. ": reload lands on (1,10) (" .. cell() .. ")")
    local fired = holdLeft(100)
    result(fired, label .. ": walking west after the reload fires BlockedPath")
    settle()
    result(Runtime.getSession().map == "EM_OLDALE_TOWN", label .. ": Route 102 stays closed (" .. tostring(Runtime.getSession().map) .. ")")
    if run then U.still(game, DIR .. "/2913_02_pushed_back.png") end
  end
  return finish()
end
