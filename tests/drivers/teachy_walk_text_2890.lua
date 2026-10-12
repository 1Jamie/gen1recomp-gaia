local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/teachy_walk_text_2890"

-- pokefirered/include/constants/items.h:438
local ITEM_TEACHY_TV = 366

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS teachy_walk_text_2890")
    love.event.quit(0)
  else
    print("FAIL teachy_walk_text_2890 failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Bag = require("src.core.game3.bag")
  local TeachyTv = require("src.core.game3.teachy_tv")
  local TvUi = require("src.ui.game3.teachy_tv")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_TEACHY_TV, 1)
  session.registeredItem = ITEM_TEACHY_TV

  U.tap(game, "select")
  for _ = 1, 60 do
    U.wait(1)
    if TvUi.isOpen() and TvUi.fadeLevel() == 0 then break end
  end
  if not result(TvUi.isOpen(), "SELECT opened the TEACHY TV") then return finish() end
  U.wait(10)
  U.tap(game, "a")

  local poses, frames = {}, 0
  local sawStand, sawStep = false, false
  for _ = 1, 400 do
    U.wait(1)
    if TvUi.stepName() == "npc_move_and_setup_text_printer"
        and (TvUi.hostX or 0) > TeachyTv.TIMING.DUDE_X_START then
      frames = frames + 1
      local walk, stepA = TvUi.hostPose()
      poses[#poses + 1] = walk == 1 and (stepA and "A" or "B") or "S"
      if walk == 0 and not sawStand and (TvUi.hostX or 0) >= 40 and (TvUi.hostAnim or 0) % 8 == 4 then
        sawStand = true
        U.still(game, DIR .. "/2890_01_dude_walk_stand_frame.png")
      elseif walk == 1 and not stepA and not sawStep and (TvUi.hostX or 0) >= 40 and (TvUi.hostAnim or 0) % 8 == 4 then
        sawStep = true
        U.still(game, DIR .. "/2890_02_dude_walk_step_frame.png")
      end
    elseif TvUi.phase == "hello" then
      break
    end
  end
  local seq = table.concat(poses)
  print("INFO walk poses " .. seq)
  -- pokefirered/src/data/object_events/object_event_anims.h:201
  result(frames > 32, "the dude walked across the screen")
  result(seq:find("SSSSSSSS", 1, true) ~= nil, "the walk cycle includes the 8-frame standing cel")
  result(seq:find("AAAAAAAA", 1, true) ~= nil and seq:find("BBBBBBBB", 1, true) ~= nil,
    "both step cels show for 8 frames each")

  local revealSeen = {}
  local shotTyping = false
  for _ = 1, 200 do
    if TvUi.phase == "hello" and TvUi.typing() then
      revealSeen[TvUi._revealed] = true
      if not shotTyping and (TvUi._revealed or 0) >= 8 then
        shotTyping = true
        U.still(game, DIR .. "/2890_03_hello_typing.png")
      end
    end
    if TvUi.phase == "hello" and not TvUi.typing() then break end
    U.wait(1)
  end
  local distinct = 0
  for _ in pairs(revealSeen) do distinct = distinct + 1 end
  -- pokefirered/src/teachy_tv.c:679
  result(distinct >= 8, "the hello text types out one character at a time, saw " .. distinct .. " steps")
  result(TvUi.waitingForKey(), "the prompt arrow shows once the page is done")
  U.still(game, DIR .. "/2890_04_hello_done.png")

  finish()
end
