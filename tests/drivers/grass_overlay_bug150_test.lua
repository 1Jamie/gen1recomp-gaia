-- Visual + render-decision regression for #150 ("Grass transparency is off").
--
-- The reporter's should_be.png shows Red standing in Route 1 tall grass with a
-- GREEN cap that blends into the grass.  The default SGB color mode instead
-- region-tints the player with the per-map SGB BG palette: Red's dark-gray cap
-- (DMG shade 2) maps to the ROUTE palette's shade-2 = light-blue (165,214,255)
-- (data/generated/palettes.lua ROUTE), so the character clashes with the grass.
-- On real GBC/SGB an OBJ carries its own object palette; OG RED already bakes
-- PaletteFX.ogObj() (green over Red, pink over Blue -- color/sprites.asm
-- ColorOverworldSprite) onto overworld characters.  The fix makes SGB mode do
-- the same while leaving terrain on its per-map SGB palette.
--
-- Gate (fails before the fix, passes after):
--   * PaletteFX.usesSpriteObp("gbc") == true
--   * the player SpriteRenderer bakes a distinct OBJ image in SGB mode
--     (resolveImage() ~= the raw grayscale sheet) -- the pixel path that
--     recolors the cap green
--   * that baked OBJ palette's shade-2 (the cap) is green, not ROUTE light-blue
-- Regression guard (must hold before AND after -- terrain is untouched):
--   * the ROUTE terrain palette still carries BOTH grass green (173,230,90) and
--     light-blue (165,214,255), so the grass field keeps its green+blue dither.
--
-- Screenshots (SHOT_DIR): grass_bug150_sgb.png (the reported view) and
-- grass_bug150_ogred.png (OG RED reference -- green character, red terrain).
--
-- Run: POKEPORT_DRIVER=tests/drivers/grass_overlay_bug150_test.lua \
--      POKEPORT_IDENTITY=bug150 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local DIR = os.getenv("SHOT_DIR") or "."

  local fails = 0
  local function check(cond, msg)
    if cond then U.log("ok:   " .. msg)
    else fails = fails + 1; U.log("FAIL: " .. msg) end
  end
  local function hasColor(pal, r, g, b)
    if not pal then return false end
    for i = 1, #pal do
      if pal[i][1] == r and pal[i][2] == g and pal[i][3] == b then return true end
    end
    return false
  end

  -- a party + starter flag so the overworld is fully usable
  game.save.flags.EVENT_GOT_STARTER = true
  local Pokemon = require("src.pokemon.Pokemon")
  table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 5))

  -- default SGB color mode.  Set the SAVED option too: Game:applyOptions
  -- re-reads save.options.colors, so a bare setMode() would get reverted.
  game.save.options = game.save.options or {}
  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")

  U.teleport(game, "ROUTE_1", 10, 6, "down")
  local ow = game.overworld
  local p = ow.player
  check(ow.map.id == "ROUTE_1", "on ROUTE_1")
  check(ow.map:isGrassCell(p.cellX, p.cellY),
        "player stands on a tall-grass cell (" .. p.cellX .. "," .. p.cellY .. ")")

  U.wait(40) -- let the grass/flower tile animation cycle
  U.shot(game, DIR .. "/grass_bug150_sgb.png")

  -- === render-decision gate: fails before the fix, passes after =========
  check(PaletteFX.usesSpriteObp("gbc") == true,
        "SGB mode bakes an OBJ palette onto overworld characters")

  -- the player's sprite must resolve to a baked OBJ image (not the raw
  -- grayscale sheet) in SGB mode -- this is the exact path that colors the cap
  local spr = p.sprite
  check(spr and spr.image and spr:resolveImage() ~= spr.image,
        "player sprite bakes a distinct OBJ image in SGB mode")

  -- the baked object palette's shade-2 (the cap) is a green, and specifically
  -- NOT the ROUTE light-blue the region shader used to hand it
  local obj = PaletteFX.ogObj()   -- {white, brightgreen, darkgreen, black}
  local cap = obj and obj[3]      -- DMG shade 2 -> 3rd palette entry
  check(cap and cap[2] > cap[1] and cap[2] > cap[3],
        "OBJ cap color is green-dominant (g>r and g>b)")
  check(cap and not (cap[1] == 165 and cap[2] == 214 and cap[3] == 255),
        "OBJ cap color is NOT ROUTE light-blue (165,214,255)")

  -- === regression guard: terrain palette untouched =====================
  local terrain = PaletteFX.pal(game.data, ow:paletteNameFor(ow.map))
  check(hasColor(terrain, 173, 230, 90),
        "ROUTE terrain palette still contains grass green (173,230,90)")
  check(hasColor(terrain, 165, 214, 255),
        "ROUTE terrain palette still contains light-blue (grass keeps its blue dither)")

  -- OG RED reference for the human diff (green character over red terrain)
  game.save.options.colors = "ogred"
  PaletteFX.setMode("ogred")
  U.wait(20)
  U.shot(game, DIR .. "/grass_bug150_ogred.png")
  -- restore the default so the run doesn't end in a non-default mode
  game.save.options.colors = "gbc"
  PaletteFX.setMode("gbc")
  U.wait(2)

  if fails > 0 then error(fails .. " check(s) failed for #150") end
  U.log("all #150 checks passed")
end
