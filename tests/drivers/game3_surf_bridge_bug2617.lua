local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or ".bazinga/BSA/10-02-26-00-userreported/shots/2617"

return function(game)
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    print("RESULT route110_surf_bridge failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
  end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.phase == "boot" and game.boot, "boot_ready") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "NICK", gender = 0 })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Field = require("src.core.game3.field")
  local Space = require("src.core.game3.scripting.space")
  if not check(Runtime.getSession() ~= nil, "session_ready") then return finish() end
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").check = function() return false end
  Map.load(Runtime._mod, game, "EM_ROUTE110", { x = 15, y = 29, facing = "down" })
  U.wait(90)
  if Space.vm and Space.vm.stop then Space.vm:stop() end
  Field.unlock()
  Player.surfing, Player.dismounting, Player.surfHopping = true, false, false
  Player.elevation, Player.currentElevation = 1, 1
  Player.facing, Player.turnArmed, Player.turnTimer = "down", true, 0
  if not check(Map.current == "EM_ROUTE110" and Player.cellX == 15 and Player.cellY == 29
      and Collision.isWater(15, 29), "normal_water_setup") then return finish() end

  local function state(label)
    print(string.format("STATE %s x=%d y=%d surfing=%s dismounting=%s elevation=%s current=%s behavior=%s coll=%s moving=%s locked=%s",
      label, Player.cellX, Player.cellY, tostring(Player.surfing), tostring(Player.dismounting),
      tostring(Player.elevation), tostring(Player.currentElevation),
      tostring(Collision.behavior(Player.cellX, Player.cellY)), tostring(Collision.cell(Player.cellX, Player.cellY)),
      tostring(Player.moving), tostring(Field.locked)))
  end
  local function step(dir)
    local x, y = Player.cellX, Player.cellY
    for _ = 1, 24 do
      U.hold(game, dir, 1)
      if Player.moving then break end
    end
    for _ = 1, 80 do
      if not Player.moving then break end
      U.wait(1)
    end
    state(dir)
    return x ~= Player.cellX or y ~= Player.cellY
  end

  local Popup = require("src.ui.game3.map_name_popup")
  for _ = 1, 360 do
    if not Popup.isActive() then break end
    U.wait(1)
  end
  if not check(not Popup.isActive(), "map_popup_finished") then return finish() end
  if not check(step("up") and Map.current == "EM_ROUTE110" and Player.cellX == 15
      and Player.cellY == 28 and Player.surfing and not Player.dismounting
      and Player.elevation == 1 and Player.currentElevation == 1 and Collision.isWater(15, 28),
      "before_bridge_clear_water_by_input") then return finish() end
  state("before_bridge_clear_water")
  check(U.still(game, DIR .. "/2617_before_bridge_on_water.png"), "shot_before")
  if not check(step("down") and Map.current == "EM_ROUTE110" and Player.cellX == 15
      and Player.cellY == 29 and Player.surfing and not Player.dismounting
      and Player.elevation == 1 and Player.currentElevation == 1 and Collision.isWater(15, 29),
      "returned_to_causal_setup_by_input") then return finish() end
  state("before_bridge")
  if not check(step("down") and Player.cellY == 30, "entered_bridge_by_input") then return finish() end
  if not check(Player.surfing and not Player.dismounting and Player.elevation == 1,
      "retain_surf_under_bridge") then return finish() end
  check(U.still(game, DIR .. "/2617_under_bridge_after_entry.png"), "shot_under_bridge")
  check(step("down") and Player.cellY == 31 and Player.surfing, "bridge_second_row")
  check(step("down") and Player.cellY == 32 and Player.surfing, "bridge_third_row")
  if not check(step("down") and Map.current == "EM_ROUTE110" and Player.cellX == 15
      and Player.cellY == 33 and Player.surfing and not Player.dismounting
      and Player.elevation == 1 and Player.currentElevation == 1 and Collision.isWater(15, 33),
      "exit_bridge_to_south_water") then return finish() end
  for _, y in ipairs({ 34, 35 }) do
    if not check(step("down") and Map.current == "EM_ROUTE110" and Player.cellX == 15
        and Player.cellY == y and Player.surfing and not Player.dismounting
        and Player.elevation == 1 and Player.currentElevation == 1 and Collision.isWater(15, y),
        "south_water_row" .. y .. "_retains_surf") then return finish() end
  end
  state("south_water_clear_of_bridge")
  check(U.still(game, DIR .. "/2617_south_water_clear_of_bridge.png"), "shot_exit")
  finish()
end
