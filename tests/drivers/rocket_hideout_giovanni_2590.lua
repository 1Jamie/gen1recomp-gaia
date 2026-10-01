-- scripts/RocketHideoutB4F.asm:99-121; home/trainers.asm:339,399
-- engine/battle/battle_transitions.asm:11-46,96-121,174-185
-- engine/battle/read_trainer_party.asm:69-80
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Music = require("src.core.Music")
  local TextBox = require("src.render.TextBox")
  local BattleTransition = require("src.render.BattleTransition")

  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
                   or "/tmp/shots"
  local failed = false
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failed = true end
    return ok
  end
  local function quit()
    U.wait(2)
    love.event.quit(failed and 1 or 0)
    while true do coroutine.yield() end
  end

  local MAP = "ROCKET_HIDEOUT_B4F"
  game.save.party = { Pokemon.new(game.data, "WARTORTLE", 25) }
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI = nil
  game.save.defeatedTrainers = game.save.defeatedTrainers or {}

  U.teleport(game, MAP, 24, 3, "right")
  U.wait(20)
  local ow = game.overworld
  if not check("Rocket Hideout B4F loaded", ow and ow.map and ow.map.id == MAP) then
    quit()
  end

  local giovanni
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.def and npc.def.name == "ROCKETHIDEOUTB4F_GIOVANNI" then giovanni = npc end
  end
  if not check("Giovanni stands at (25,3)", giovanni ~= nil
               and giovanni.cellX == 25 and giovanni.cellY == 3) then
    quit()
  end
  local mapSong = Music.current()
  local origFacing = giovanni.facing

  U.tap(game, "a")
  U.wait(10)
  local box = game.stack:top()
  if not check("talking to him opens the impressed box",
               getmetatable(box) == TextBox) then
    quit()
  end

  local typed = false
  for _ = 1, 600 do
    if game.stack:top() ~= box then break end
    if box.done then typed = true break end
    if box.waiting then
      U.tap(game, "a")
      U.wait(4)
    end
    U.wait(1)
  end
  if not check("the impressed text finishes typing with the box still open", typed) then
    quit()
  end
  U.wait(6)
  check("Music_MeetEvilTrainer plays while the typed box waits for A (RocketHideoutB4F.asm:113)",
        Music.current() == "Music_MeetEvilTrainer" and mapSong ~= "Music_MeetEvilTrainer")
  check("the box is still waiting for A", game.stack:top() == box)
  U.still(game, SHOT_DIR .. "/2590_01_box_open_meet_evil_trainer_sting.png")

  U.tap(game, "a")
  local closed = false
  for _ = 1, 60 do
    if game.stack:top() ~= box then closed = true break end
    U.wait(1)
  end
  if not check("A closes the impressed box", closed) then quit() end

  local stingFrames, toWipe, tr = 0, nil, nil
  for i = 1, 120 do
    local top = game.stack:top()
    if getmetatable(top) == BattleTransition then tr = top toWipe = i break end
    if Music.current() == "Music_MeetEvilTrainer" then stingFrames = stingFrames + 1 end
    U.wait(1)
  end
  if not check("the battle transition starts", tr ~= nil) then quit() end
  U.log("frames from close to the wipe:", toWipe, "sting frames after the close:", stingFrames)
  check("the battle starts right after the close (home/overworld.asm:127-130, :321)", toWipe <= 4)
  check("the battle theme replaces the sting within 4 frames (play_battle_music.asm:7-8)",
        stingFrames <= 4)
  check("Giovanni faces his pre-talk way again (text_script.asm:112-120)",
        giovanni.facing == origFacing)
  check("Giovanni's OAM is kept for the wipe", ow.battleOamKeep == giovanni)
  check("Giovanni is not culled", not ow:oamCulled(giovanni))
  check("L29 last mon vs L25 lead picks the outward spiral (%011)",
        tr.style == "spiralout")

  local half = math.floor((tr.wipeLen or 40) / 2)
  for _ = 1, half do
    if game.stack:top() ~= tr then break end
    U.wait(1)
  end
  check("still mid-wipe", game.stack:top() == tr)
  check("Giovanni is still kept mid-wipe", ow.battleOamKeep == giovanni)
  U.still(game, SHOT_DIR .. "/2590_02_mid_wipe_spiral_out_giovanni_visible.png")

  quit()
end
