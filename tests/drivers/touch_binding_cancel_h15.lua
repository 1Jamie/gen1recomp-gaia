local U = require("tests.drivers.util")
local Touch = require("src.core.TouchControls")
local Input = require("src.core.Input")
local Screens = require("src.ui.Screens")
local SaveData = require("src.core.SaveData")

return function(game)
  local deadline = love.timer.getTime() + 25
  local oldWrite, oldPersist = rawget(game, "writeOptions"), rawget(game, "persistOptions")
  local ok, err = xpcall(function()
    local identity = os.getenv("POKEPORT_IDENTITY") or ""
    assert(identity ~= "" and identity ~= "pokemon-love2d", "isolated READY identity required")
    local out = assert(os.getenv("POKEPORT_SHOT_DIR"), "shot directory required")
    local function wait(n)
      for _ = 1, n do
        assert(love.timer.getTime() < deadline, "driver deadline")
        U.wait(1)
      end
    end
    local function ready()
      if game.world then
        return game.world.map and not game.stack:top() and game.world:acceptsMenuInput()
      end
      return game.overworld and game.stack:top() == game.overworld and not game.overworld.transitioning
    end
    if require("src.core.GameVersion").generation() == 1 then
      U.teleport(game,"PALLET_TOWN",10,8,"down")
    end
    for _ = 1, 1200 do if ready() then break end; wait(1) end
    assert(ready(), "READY world did not settle")
    assert(Touch:visible(), "run with POKEPORT_TOUCH=1")
    local bindings = SaveData.encode({ bindings = game.save.options.bindings })
    game.writeOptions = function() error("unexpected options write") end
    game.persistOptions = game.writeOptions
    local base = game.stack:top()
    local menu = Screens.push(game, "BindingsMenu")
    wait(4)
    local function contact(btn, id, down)
      local z = Touch:layout()[btn]
      if down then game:touchpressed(id, z.cx, z.cy, 0, 0, 1)
      else game:touchreleased(id, z.cx, z.cy, 0, 0, 0) end
    end
    local function shot(name)
      assert(game.stack:top() == menu, "intended Controls screen missing")
      wait(4)
      assert(U.still(game, out .. "/" .. name .. ".png"), "screenshot failed")
      assert(love.timer.getTime() < deadline, "capture deadline")
    end
    contact("a", "arm", true); wait(1)
    assert(menu.capture == menu.items[1], "touch A did not arm capture")
    contact("a", "arm", false); wait(1)
    assert(menu.capture and not menu.pending, "initiating release changed capture")
    shot("01-armed-touch-cancel-prompt")
    contact("b", "cancel", true); wait(1)
    assert(not menu.capture and game.stack:top() == menu, "touch B did not cancel only capture")
    contact("b", "cancel", false); wait(1)
    shot("02-cancelled-controls")
    contact("a", "arm2", true); wait(1)
    contact("a", "arm2", false); wait(1)
    contact("b", "fast", true); contact("b", "fast", false); wait(1)
    assert(not menu.capture and game.stack:top() == menu and not Input:isDown("b"), "same-step B tap failed")
    contact("a", "arm3", true); wait(1)
    contact("a", "arm3", false); wait(1)
    game:keypressed("z"); wait(1)
    assert(menu.pending and menu.pending.value == "z", "physical candidate not pending")
    contact("b", "candidate", true); wait(1)
    game:keyreleased("z"); contact("b", "candidate", false); wait(1)
    assert(not menu.capture and not menu.pending, "held candidate cancellation failed")
    assert(SaveData.encode({ bindings = game.save.options.bindings }) == bindings, "touch cancellation changed bindings")
    shot("03-late-release-no-binding")
    contact("b", "close", true); wait(1)
    contact("b", "close", false); wait(1)
    assert(game.stack:top() == base, "next B did not close Controls")
    print("PASS H15 actual touch route, same-step tap, held candidate/late release, no writes, next B close")
  end, debug.traceback)
  game.writeOptions, game.persistOptions = oldWrite, oldPersist
  if not ok then print("FAIL H15 " .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
