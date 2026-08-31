local U = require("tests.drivers.util")

-- ../pokecrystal/engine/events/map_name_sign.asm:41-44
local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0

  local function say(line) print("[mapsign1994] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map) then
    say("FAIL the crystal world did not boot")
    love.event.quit(1)
    return
  end

  local DESTS = {
    { "ROUTE_29", 10, 8, "left" },
    { "NEW_BARK_TOWN", 5, 6, "down" },
  }
  local nextDest = 1

  local function raise()
    local d = DESTS[nextDest]
    nextDest = nextDest % #DESTS + 1
    world:warpToMapId(d[1], d[2], d[3], d[4])
    for _ = 1, 240 do
      if world.mapSign then return true end
      U.wait(1)
    end
    return false
  end

  local function measure(speed)
    game.speedOverride = speed
    if not raise() then
      ok(false, speed .. "X: no sign came up to time")
      return nil
    end
    say(("%dX: game:logicSpeed() reports %s")
      :format(speed, tostring(game:logicSpeed())))
    local frames, t0 = 0, love.timer.getTime()
    for _ = 1, 60 * 60 do
      if not world.mapSign then break end
      U.wait(1)
      frames = frames + 1
    end
    local elapsed = love.timer.getTime() - t0
    say(("%dX: %d rendered frames (%d logic steps), %.3f real seconds")
      :format(speed, frames, frames * speed, elapsed))
    ok(world.mapSign == nil, speed .. "X: the sign expired")
    return frames, elapsed
  end

  for _, speed in ipairs({ 1, 4, 10 }) do
    local frames, elapsed = measure(speed)
    if frames then
      ok(math.abs(frames - 60) <= 15,
        ("%dX: %d rendered frames is within 15 of 60"):format(speed, frames))
      ok(elapsed >= 0.75 and elapsed <= 1.5,
        ("%dX: %.3fs of wall clock is the one-second hold"):format(speed, elapsed))
    end
  end

  game.speedOverride = 10
  if raise() then
    U.wait(30)
    ok(world.mapSign ~= nil,
      "10X: the banner is still up half a real second in")
    U.shot(game, SHOT_DIR .. "/mapsign1994_10x_halfsecond.png")
  else
    ok(false, "10X: no sign came up for the screenshot")
  end
  game.speedOverride = nil

  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
