-- scripts/VermilionDock.asm:79, scripts/VermilionDock.asm:142, home/oam.asm:6
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TileRenderer = require("src.render.TileRenderer")
  local Pokemon = require("src.pokemon.Pokemon")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local ok = true
  local function expect(cond, label)
    U.log((cond and "PASS " or "FAIL ") .. label)
    if not cond then ok = false end
  end

  local function frozen(fn)
    local update = rawget(game, "update")
    game.update = function() end
    local r = fn()
    game.update = update
    return r
  end

  local function waterPair(tag)
    return frozen(function()
      local a = U.shot(game, DIR .. "/2560_" .. tag .. "_water_a.png")
      local start = TileRenderer.animClock()
      for _ = 1, 20000 do
        if TileRenderer.animClock() - start >= 25 then break end
        coroutine.yield()
      end
      local b = U.shot(game, DIR .. "/2560_" .. tag .. "_water_b.png")
      local fa = io.open(DIR .. "/2560_" .. tag .. "_water_a.png", "rb")
      local fb = io.open(DIR .. "/2560_" .. tag .. "_water_b.png", "rb")
      local da = fa and fa:read("*a") or ""
      local db = fb and fb:read("*a") or ""
      if fa then fa:close() end
      if fb then fb:close() end
      return a and b and da ~= db
    end)
  end

  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.flags.EVENT_GOT_POKEDEX = true
  game.save.flags.EVENT_GOT_HM01 = true
  game.save.flags.EVENT_SS_ANNE_LEFT = nil
  U.teleport(game, "VERMILION_DOCK", 14, 2, "up")
  local ow = game.overworld

  local sa
  for _ = 1, 600 do
    sa = ow.shipAnim
    if sa then break end
    U.wait(1)
  end
  expect(sa ~= nil, "the departure starts on entering the dock")
  if not sa then love.event.quit(1) return end

  local maxLive, seen, emitted = 0, {}, 0
  local shots = { [24] = "01_sailing", [56] = "02_puff_mid", [104] = "03_puff_left_edge" }
  local tookWater = false
  for _ = 1, 3000 do
    if sa.gone then break end
    local live = (sa.puff and 1 or 0) + #(sa.puffs or {})
    if live > maxLive then maxLive = live end
    if sa.puff and not seen[sa.puff] then seen[sa.puff] = true; emitted = emitted + 1 end
    for _, p in ipairs(sa.puffs or {}) do
      if not seen[p] then seen[p] = true; emitted = emitted + 1 end
    end
    local tag = shots[sa.off]
    if tag and sa.frames == 4 then
      shots[sa.off] = nil
      if not tookWater then
        tookWater = true
        expect(waterPair(tag), "water tiles in the ship overlay change across a frozen 25-frame span")
      else
        local realDraw = love.graphics.draw
        local puffDraws = 0
        love.graphics.draw = function(d, ...)
          if d == ow.smokeImg then puffDraws = puffDraws + 1 end
          return realDraw(d, ...)
        end
        frozen(function() return U.shot(game, DIR .. "/2560_" .. tag .. ".png") end)
        love.graphics.draw = realDraw
        U.log(tag, "puff at", sa.puff and sa.puff.x, sa.puff and sa.puff.y,
              "cam", ow.camera and ow.camera.x, ow.camera and ow.camera.y)
        expect(puffDraws > 0 and puffDraws % 4 == 0,
               ("%s draws the puff as one 2x2 block per frame (%d tiles)"):format(tag, puffDraws))
      end
    end
    U.wait(1)
  end
  expect(sa.gone, "she sails off")
  expect(emitted == 8, ("eight smoke puffs are emitted (got %d)"):format(emitted))
  expect(maxLive <= 1, ("at most one puff is live at a time (saw %d)"):format(maxLive))
  U.wait(30)
  expect(waterPair("04_gone"), "gangway-row water keeps animating after she is gone")
  love.event.quit(ok and 0 or 1)
end
