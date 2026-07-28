-- Driver: manual audio check for the wild battle intro cry (#303).
--
-- pokered engine/battle/core.asm:9-100, SlidePlayerAndEnemySilhouettesOnScreen,
-- ends with `jpfar PrintBeginningBattleText`, and that routine
-- (engine/battle/common_text.asm:10-19) is:
--     ld a, [wEnemyMonSpecies2]
--     call PlayCry
--     ld hl, WildMonAppearedText
--     ...
--     call PrintText
-- so the cry sounds at the instant the silhouettes finish sliding in and the
-- "Wild X appeared!" box opens, not before and not after.  The enemy HP bar
-- comes later still: _InitBattleCommon only reaches DrawEnemyHUDAndHPBar
-- (core.asm:6762) once that text has been dismissed.
--
-- Two wrong versions of this have shipped.  First the cry was queued behind
-- the intro text, so it waited on the player's A press.  Then it was queued
-- ahead of the text but the message queue was never held for the slide, so
-- it fired on the slide's first frame, a full 40 frames early.  The queue
-- hold is asserted in tests/parity_battle_intro_cry.lua; the thing no test
-- can judge is whether the cry and the box land together to an ear.
--
-- Do NOT add POKEPORT_SPEED to this run.  Fast-forward scales only the logic
-- clock, while audio runs on its own real-time 60 Hz accumulator in
-- Game:update (src/core/Game.lua) -- so the two halves of the exact
-- coincidence under test would drift apart and the run would prove nothing.
--
--   POKEPORT_DRIVER=tests/drivers/wild_cry_bug303_test.lua \
--     POKEPORT_IDENTITY=bug303 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")

  -- Route 1 is the shortest walk to a wild encounter from a fresh start and
  -- its table is all PIDGEY and RATTATA, whose cries are short and distinct.
  -- (10, 6) is the west end of the northern grass patch -- taken from
  -- data/generated/maps.lua, not guessed, and re-derived below if a map edit
  -- ever moves it.
  local MAP = "ROUTE_1"
  local GRASS = { x = 10, y = 6 }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions the ear cannot check --------------------------------
  -- Sound.playCry reads data.audio.cries[species]; a missing key is a silent
  -- no-op with no error, which sounds exactly like the bug.
  local cries = game.data.audio and game.data.audio.cries
  check("data.audio.cries resolves", cries ~= nil)
  local encounters = game.data.encounters and game.data.encounters[MAP]
  local slots = encounters and encounters.grass and encounters.grass.slots
  local species = {}
  for _, slot in ipairs(slots or {}) do
    local id = slot.species
    if type(id) == "string" and not species[id] then
      species[id] = true
      species[#species + 1] = id
    end
  end
  check(MAP .. " has a wild encounter table", #species > 0)
  local missing = {}
  for _, id in ipairs(species) do
    if not (cries and cries[id]) then missing[#missing + 1] = id end
  end
  check("every " .. MAP .. " species has a cry sample", #missing == 0)
  if #missing > 0 then
    U.log("  species with no cry:", table.concat(missing, ", "))
  end
  U.log("  " .. MAP .. " wild species:", table.concat(species, ", "))

  local vol = game.save.options and game.save.options.sfxVol
  U.log("audio device present:", love.audio ~= nil,
        "  SFX VOL (0-7):", tostring(vol))
  if not love.audio or vol == 0 then
    U.log("WARNING: sound output is off, so nothing below will be audible;",
          "raise SFX VOL in OPTION first")
  end

  -- ---- give the player something to fight with ---------------------------
  if #game.save.party == 0 then
    table.insert(game.save.party, Pokemon.new(game.data, "SQUIRTLE", 12))
    U.log("party was empty; added a level 12 SQUIRTLE")
  end

  -- ---- park the player in the grass --------------------------------------
  U.teleport(game, MAP, GRASS.x, GRASS.y, "up")
  U.wait(10)

  -- the hard-coded cell stopping being grass (map edit, or a mod) would park
  -- the player on stone where no encounter can ever roll, which looks exactly
  -- like a broken fix; sweep for a real one instead
  local function firstGrassCell(map)
    for y = 0, (map.heightCells or 0) - 1 do
      for x = 0, (map.widthCells or 0) - 1 do
        if map:isGrassCell(x, y) and map:isWalkableCell(x, y) then
          return x, y
        end
      end
    end
  end

  local ow = game.overworld
  if ow and not ow.map:isGrassCell(ow.player.cellX, ow.player.cellY) then
    local gx, gy = firstGrassCell(ow.map)
    if gx then
      U.log(("(%d, %d) is not grass; standing on"):format(GRASS.x, GRASS.y),
            gx, gy)
      U.teleport(game, MAP, gx, gy, "up")
      U.wait(10)
    else
      U.log("FAIL no walkable grass cell found on " .. MAP)
    end
  end
  U.log("standing on", MAP, "at",
        game.overworld and game.overworld.player.cellX,
        game.overworld and game.overworld.player.cellY)

  -- ---- say what to listen for, THEN trigger it ----------------------------
  -- The moment under test is about a second long and cannot be replayed
  -- once it has passed, so the ear has to be ready before the encounter
  -- rolls.  Print first, pause, then walk.
  U.log("........................................................")
  U.log("LISTEN NOW: a wild encounter is about to be walked into for you.")
  U.log("  RIGHT: the two silhouettes slide in, and the moment they land")
  U.log("         the cry sounds AT THE SAME TIME as the \"Wild X")
  U.log("         appeared!\" box opens.  The HP bar only shows up after")
  U.log("         you dismiss that box -- that is correct, not a bug.")
  U.log("  BUG #303 sounds like: the cry fires while the silhouettes are")
  U.log("         still sliding, well before any text -- or (the older")
  U.log("         form) not until after you press A to clear the box.")
  U.log("  ALSO WRONG: the cry sounds twice, or a trainer battle now cries")
  U.log("         at the wrong moment too -- trainers should stay silent")
  U.log("         until the foe's first mon is actually sent out.")
  U.log("........................................................")
  U.log("walking into the grass in 3 seconds -- ears up")
  U.wait(180)

  -- ---- walk until the encounter rolls ------------------------------------
  local BattleState = require("src.battle.BattleState")
  local function liveBattle()
    for _, s in ipairs(game.stack.states or {}) do
      if getmetatable(s) == BattleState then return s end
    end
    return nil
  end

  -- pace back and forth over the grass; each step gets its own encounter
  -- roll, and the transition wipe puts the battle on the stack under us
  local DIRS = { "up", "down", "left", "right" }
  local battle
  for i = 1, 400 do
    U.hold(game, DIRS[(i - 1) % #DIRS + 1], 10)
    battle = liveBattle()
    if battle then break end
  end

  check("a wild battle started", battle ~= nil)
  if battle then
    U.log("   encounter:", battle.enemy and battle.enemy.mon
          and battle.enemy.mon.species, "at level",
          battle.enemy and battle.enemy.mon and battle.enemy.mon.level)
    check("it is a wild battle (trainers cry at a different point)",
          battle.kind ~= "trainer")
  else
    U.log("no encounter after 400 steps -- walk into the grass yourself")
  end

  -- ---- hand off, then stay out of the way --------------------------------
  U.log("........................................................")
  U.log("Input is yours from here on -- run from the battle and walk back")
  U.log("into the grass to hear it as many times as you want.")
  U.log("........................................................")

  while true do
    coroutine.yield()
  end
end
