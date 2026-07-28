-- Driver: manual look at the Pokedex entry pic (#307).
--
-- DexEntryMenu loaded its front pic through
--     local ok, img = path and pcall(love.graphics.newImage, path)
-- which reads as a guarded pcall but is not one: `path and pcall(...)` is an
-- expression, so Lua adjusts it to a single value, `img` is always nil, and
-- every dex page drew with an empty pic box.  Both callers were hit -- the
-- starter previews on Oak's lab balls (StarterDex, engine/events/
-- starter_dex.asm, which forces the owned bit so the page fills in) and
-- every entry opened from the Pokedex list.
--
-- tests/parity_dex_pic.lua asserts the page now holds an image.  What it
-- cannot judge is placement: pokedex.asm draws the pic at the top-left of
-- the page and DexEntryMenu bottom-aligns it against y=60, so a wrong-sized
-- or wrong-anchored sprite still "loads" while looking broken.
--
-- Screenshots land in the scratch path given below; the run also parks a
-- live Pokedex so the pages can be paged through by hand.
--
--   POKEPORT_DRIVER=tests/drivers/dex_pic_bug307_test.lua \
--     POKEPORT_IDENTITY=bug307 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Screens = require("src.ui.Screens")
  local Sprites = require("src.pokemon.Sprites")

  -- the three starters are the reported case (Oak's lab preview), plus one
  -- ordinary list entry as the control
  local CASES = { "BULBASAUR", "CHARMANDER", "SQUIRTLE", "PIDGEY" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions the eye cannot check --------------------------------
  -- A path that does not resolve, a PNG that is missing from the cache, and
  -- the truncation bug all render as the same empty box.
  local DexEntryMenu = require("src.ui.DexEntryMenu")
  for _, species in ipairs(CASES) do
    local path = Sprites.path(game.data, species, "front", { kind = "dex" })
    check(species .. " resolves a dex front-pic path",
          type(path) == "string" and path ~= "")
    local page = DexEntryMenu.new(game, { species = species, forceOwned = true })
    local held = page.sprite ~= nil
    check(species .. " dex page holds its pic", held)
    if held and page.sprite.getDimensions then
      local w, h = page.sprite:getDimensions()
      U.log("   " .. species .. " pic is", w .. "x" .. h,
            "drawn at x=8, y=" .. math.max(0, 60 - h))
    end
  end

  -- ---- mark the cases seen so the list can reach them ---------------------
  local dex = game.save.pokedex
  if dex then
    for _, species in ipairs(CASES) do
      dex.seen[species] = true
      dex.owned[species] = true
    end
    U.log("flagged", #CASES, "species as seen+owned so the list can open them")
  end

  -- ---- screenshots, one page at a time ------------------------------------
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  for _, species in ipairs(CASES) do
    while game.stack:top() do game.stack:pop() end
    Screens.push(game, "DexEntryMenu", { species = species, forceOwned = true })
    U.wait(30)
    U.shot(game, SHOT_DIR .. "/dex_" .. species:lower() .. ".png")
    U.log("captured", SHOT_DIR .. "/dex_" .. species:lower() .. ".png")
  end

  -- ---- hand off on a live page, then stay out of the way -------------------
  while game.stack:top() do game.stack:pop() end
  Screens.push(game, "DexEntryMenu", { species = "BULBASAUR", forceOwned = true })
  U.wait(10)

  U.log("........................................................")
  U.log("LOOK NOW: a BULBASAUR Pokedex entry is open on screen.")
  U.log("  RIGHT: the BULBASAUR front sprite sits in the top-left of the")
  U.log("         page, sitting on the line above HT/WT, with the name,")
  U.log("         SEED POKeMON, No.001, height, weight and description")
  U.log("         filled in down the right and bottom.")
  U.log("  BUG #307 looks like: the whole left side is blank white where")
  U.log("         the sprite belongs, everything else drawn normally.")
  U.log("  ALSO WRONG: the sprite is there but floats too high or too low,")
  U.log("         overlaps the text, or is the wrong species entirely.")
  U.log("Screenshots of all four cases were written to " .. SHOT_DIR)
  U.log("Press A or B to close the page; input is yours from here on.")
  U.log("........................................................")

  while true do
    coroutine.yield()
  end
end
