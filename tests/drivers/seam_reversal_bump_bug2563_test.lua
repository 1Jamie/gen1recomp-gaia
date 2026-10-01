-- home/overworld.asm:236, home/overworld.asm:1219
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Sound = require("src.core.Sound")
  local sounds = {}
  local origPlay = Sound.play
  Sound.play = function(data, key, ...)
    sounds[#sounds + 1] = key
    return origPlay(data, key, ...)
  end
  local ok = true
  local function expect(cond, label)
    U.log((cond and "PASS " or "FAIL ") .. label)
    if not cond then ok = false end
  end
  local function setDir(d)
    for _, k in ipairs({ "up", "down", "left", "right" }) do
      game.input.state[k] = (k == d)
    end
    if d then table.insert(game.input.pressQueue, d) end
  end
  local function p() return game.overworld.player end
  local function clear() for i = #sounds, 1, -1 do sounds[i] = nil end end
  local function has(key)
    for _, v in ipairs(sounds) do if v == key then return true end end
    return false
  end
  local function where()
    local pl = p()
    return ("%s (%d,%d) facing=%s"):format(game.overworld.map.id,
      pl.cellX, pl.cellY, pl.facing)
  end

  local function seam(label, bike)
    U.teleport(game, "VIRIDIAN_CITY", 20, 33, "up")
    game.save.inventory.BICYCLE = 1
    game.save.onBike = bike
    U.wait(30)
    local wasMoving = false
    for _ = 1, 300 do
      setDir("down")
      coroutine.yield()
      local m = p().moving
      if wasMoving and not m and game.overworld.map.id ~= "VIRIDIAN_CITY" then break end
      wasMoving = m
    end
    U.log(label, "after down:", where(), "armed=", tostring(p().turnArmed))
    clear()
    for _ = 1, 3 do setDir("up"); coroutine.yield() end
    setDir(nil)
    U.wait(40)
    U.log(label, "after up:", where(), "sounds=", table.concat(sounds, ","))
    expect(not has("Collision"), label .. " gapless reversal at the seam is silent")
    expect(game.overworld.map.id == "VIRIDIAN_CITY", label .. " and crosses back north")
  end

  local function findLedge(map)
    local data = game.data
    for y = 0, map.heightCells - 3 do
      for x = 1, map.widthCells - 1 do
        for _, l in ipairs(data.field.ledges) do
          if l.input == "down" and l.facing == "down"
             and (l.tileset or "OVERWORLD") == map.def.tileset
             and map:cellTile(x, y) == l.standingTile
             and map:cellTile(x, y + 1) == l.ledgeTile
             and map:isWalkableCell(x, y + 2)
             and map:isWalkableCell(x - 1, y) and map:isWalkableCell(x, y) then
            return x, y
          end
        end
      end
    end
  end

  seam("seam-bike", true)
  seam("seam-walk", false)

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  game.save.onBike = false
  local lx, ly = findLedge(game.overworld.map)
  expect(lx ~= nil, "found a down ledge on ROUTE_1")
  if lx then
    U.teleport(game, "ROUTE_1", lx - 1, ly, "left")
    game.save.onBike = false
    U.wait(10)
    local startX = p().cellX
    for _ = 1, 120 do
      setDir("right")
      coroutine.yield()
      if not p().moving and p().cellX ~= startX then break end
    end
    U.log("ledge after right:", where(), "armed=", tostring(p().turnArmed))
    clear()
    for _ = 1, 3 do setDir("down"); coroutine.yield() end
    setDir(nil)
    U.wait(60)
    U.log("ledge after down:", where(), "sounds=", table.concat(sounds, ","))
    expect(not has("Collision"), "gapless turn onto a ledge is silent")
    expect(has("Ledge") and p().cellY == ly + 2, "and hops the ledge")
  end

  Sound.play = origPlay
  love.event.quit(ok and 0 or 1)
end
