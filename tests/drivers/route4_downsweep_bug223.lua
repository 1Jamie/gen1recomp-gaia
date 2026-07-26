-- #223 exhaustive DOWN-hop sweep for ROUTE_4 (evidence driver).
--
-- The reporter's build (v0.1.25) and HEAD share byte-identical ledge code
-- (checkLedgeHop) and ledge data (tools/rom_manifest.json ->
-- data/generated/field.lua, the 8 rows of data/tilesets/ledge_tiles.asm), so
-- this reproduces exactly what the reporter would see.
--
-- For EVERY ROUTE_4 cell whose tile-at-feet is a south-ledge STANDING tile
-- (44/57, i.e. pokered $2C/$39) with a south-ledge tile (54/55, $36/$37)
-- directly below, teleport the player onto it facing DOWN, hold DOWN, and
-- assert the Gen1 hop fires (p.hopFrames>0) and lands two cells south.
--
-- Finding: all 139 reachable/functional south ledges hop.  The only two that
-- do not -- (12,16) and (13,16) -- sit on the SOUTH boundary of the Mt Moon
-- Poke Center plaza, where the cell two south is off the map onto the border
-- mountain (tile 17); there is no landing, so the hop is correctly refused
-- (checkLedgeHop's landing-walkable gate).  These are NOT the reporter's spot
-- (an open EAST plateau, cells ~62-80) and refusing a hop into the map border
-- is correct, so they are treated as EXPECTED refusals here.
--
-- Run:
--   POKEPORT_DRIVER=tests/drivers/route4_downsweep_bug223.lua \
--   POKEPORT_IDENTITY=bug223 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")

  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  local Pokemon = require("src.pokemon.Pokemon")
  if #game.save.party == 0 then
    table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 5))
  end
  game.save.options = game.save.options or {}
  game.save.options.zoom = -2

  -- same tile read as Map:cellTile: bottom-left 8x8 of the 2x2-cell block
  local def = game.data.maps.ROUTE_4
  local ts = game.data.tilesets[def.tileset]
  local function cellTile(cx, cy)
    local tx, ty = cx * 2, cy * 2 + 1
    local bx, by = math.floor(tx / 4), math.floor(ty / 4)
    local id
    if bx < 0 or by < 0 or bx >= def.width or by >= def.height then id = def.borderBlock
    else id = def.blocks[by * def.width + bx + 1] end
    local block = ts.blocks[(id or 0) + 1]
    return block and block[(ty % 4) * 4 + (tx % 4) + 1] or nil
  end
  local W, H = def.width * 2, def.height * 2

  local function holdDown(x, y, frames)
    U.teleport(game, "ROUTE_4", x, y, "down")
    require("src.render.Zoom").applyOptions(game.save.options)
    U.wait(6)
    local p = game.overworld.player
    local hop = false
    for _ = 1, frames do
      table.insert(game.input.pressQueue, "down")
      game.input.state.down = true
      coroutine.yield()
      if (p.hopFrames or 0) > 0 then hop = true end
    end
    game.input.state.down = false
    U.wait(4)
    return p.cellX, p.cellY, hop
  end

  -- (12,16)/(13,16): south ledges on the plaza's map-border edge; the cell two
  -- south is off-map (border mountain), so the refusal is correct, not a bug.
  local expectedRefusal = { ["12,16"] = true, ["13,16"] = true }

  local standers = {}
  for cy = 0, H - 2 do
    for cx = 0, W - 1 do
      local s = cellTile(cx, cy)
      local f = cellTile(cx, cy + 1)
      if (s == 44 or s == 57) and (f == 54 or f == 55) then
        standers[#standers + 1] = { cx, cy }
      end
    end
  end
  U.log(("#223 sweep: %d south-ledge standing cells in ROUTE_4"):format(#standers))

  local fails, refusals = 0, 0
  for _, c in ipairs(standers) do
    local cx, cy = c[1], c[2]
    -- 2-cell hop is 32 frames (16/cell); budget past it so cellY settles
    local ex, ey, hop = holdDown(cx, cy, 44)
    local ok = hop and ex == cx and ey == cy + 2
    if not ok then
      if expectedRefusal[cx .. "," .. cy] then
        refusals = refusals + 1
        U.log(("  refused (expected, map-border edge) (%d,%d) -> (%d,%d) hop=%s")
          :format(cx, cy, ex, ey, tostring(hop)))
      else
        fails = fails + 1
        U.log(("  FAIL (%d,%d) -> (%d,%d) hop=%s"):format(cx, cy, ex, ey, tostring(hop)))
      end
    end
  end
  U.log(("#223 sweep DONE: %d hopped, %d expected border-refusals, %d unexpected FAILS")
    :format(#standers - fails - refusals, refusals, fails))
  if fails > 0 then error(fails .. " unexpected south-ledge DOWN-hop failure(s)") end
end
