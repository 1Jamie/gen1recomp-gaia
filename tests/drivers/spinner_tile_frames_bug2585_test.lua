-- home/overworld.asm:268-273, engine/overworld/spinners.asm:23-49, home/copy2.asm:62-91
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local ok = true
  local function expect(cond, label)
    U.log((cond and "PASS " or "FAIL ") .. label)
    if not cond then ok = false end
  end

  U.teleport(game, "ROCKET_HIDEOUT_B2F", 13, 9, "left")
  U.wait(10)
  local ow = game.overworld
  local p = ow.player
  U.hold(game, "left", 20)
  for _ = 1, 30 do
    if p.spinning then break end
    U.wait(1)
  end
  expect(p.spinning, "stepping on the arrow starts the spin")
  local firstLen = p.stepFramesCur
  expect(firstLen == 48, ("first spinner tile step length is 48 (got %s)"):format(tostring(firstLen)))

  local tiles, steps, lastX, lastY = {}, 0, p.cellX, p.cellY
  for _ = 1, 3000 do
    if not p.spinning then break end
    U.wait(1)
    steps = steps + 1
    if p.cellX ~= lastX or p.cellY ~= lastY then
      tiles[#tiles + 1] = steps
      steps = 0
      lastX, lastY = p.cellX, p.cellY
    end
  end
  local good, bad = 0, 0
  for i = 2, #tiles do
    if tiles[i] == 48 then good = good + 1 else bad = bad + 1 end
  end
  U.log("fixed steps per tile:", table.concat(tiles, ","))
  expect(#tiles >= 8, ("the ride covered %d tiles (want >= 8)"):format(#tiles))
  expect(good >= 7 and bad == 0,
    ("every whole spinner tile takes 48 fixed steps (%d of 48, %d other)"):format(good, bad))
  expect(not p.spinning, "the slide ends")
  love.event.quit(ok and 0 or 1)
end
