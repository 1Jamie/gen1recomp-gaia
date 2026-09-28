local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/cut_tree_input_lock_2515"
local failed = false
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failed = true end
  return ok
end
local function finish()
  love.event.quit(failed and 1 or 0)
end
return function(game)
  local ready = false
  for _ = 1, 600 do
    if game.data and game.stack and game.input then ready = true break end
    U.wait(1)
  end
  if not check(ready, "game_ready") then return finish() end
  U.teleport(game, "PALLET_TOWN", 4, 13, "down")
  local ow = game.overworld
  if not check(ow ~= nil, "overworld_ready") then return finish() end
  local x, y = ow.player.cellX, ow.player.cellY
  ow:startCutTreeAnim(4, 12, nil)
  if not check(ow.cutAnim ~= nil, "cut_animation_started") then return finish() end
  check(U.still(game, DIR .. "/2515_cut_split_active.png"), "active_animation_shot")
  U.hold(game, "right", 3)
  check(ow.player.cellX == x and ow.player.cellY == y and not ow.player.moving,
        "held_direction_blocked_during_cut_split")
  while ow.cutAnim do U.wait(1) end
  finish()
end
