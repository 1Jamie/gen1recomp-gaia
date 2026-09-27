local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_evolution"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_evolution failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Evolution = require("src.core.game3.evolution")
  local Pokemon = require("src.core.game3.pokemon")
  local EvolutionScene = require("src.ui.game3.evolution_scene")
  local Audio = require("src.core.game3.audio")
  local Song = require("src.core.game3.song_ids")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session and session.version == "emerald", "emerald session") then return finish() end
  local torchic = C:require("species", "SPECIES_TORCHIC")
  local combusken = C:require("species", "SPECIES_COMBUSKEN")
  Party.giveMonToPlayer(session, torchic, 16)
  local mon = session.party[1]
  mon.moves[4] = C:require("moves", "MOVE_DOUBLE_KICK")
  local pending = Evolution.pending(session.party, { [1] = true, 1 }, session)
  local entry = pending and pending[1]
  local target = entry and (entry.toSpecies or entry.target)
  check(target == combusken, "Torchic lv16 is due to evolve into Combusken (" .. tostring(target) .. ")")
  if not target then return finish() end

  local songs = {}
  local playSong = Audio.playSong
  Audio.playSong = function(id, opts)
    songs[#songs + 1] = id
    return playSong(id, opts)
  end
  local fanfares = {}
  local playFanfare = Audio.playFanfare
  Audio.playFanfare = function(id, ...)
    fanfares[#fanfares + 1] = id
    return playFanfare(id, ...)
  end

  local result
  try("start", function()
    EvolutionScene.start(mon, target, { session = session, canStop = true, onDone = function(r) result = r end })
  end)
  check(EvolutionScene.isOpen(), "evolution scene opens")
  local shots = { intro_msg = "01_is_evolving", cycle = "02_cycle", flash_reveal = "03_flash", congrats = "04_congrats" }
  local taken = {}
  for _ = 1, 4000 do
    local st = EvolutionScene._state
    if shots[st] and not taken[st] then
      taken[st] = true
      U.wait(st == "cycle" and 60 or 6)
      U.still(game, DIR .. "/" .. shots[st] .. ".png")
    end
    if not EvolutionScene.isOpen() then break end
    if st == "congrats" or st == "done" or st == "learn" then U.tap(game, "a") else U.wait(1) end
  end
  check(not EvolutionScene.isOpen(), "evolution scene closes")
  check(Pokemon.speciesOf(mon) == combusken, "party mon is now Combusken (" .. tostring(Pokemon.speciesOf(mon)) .. ")")
  local sawIntro, sawEvo = false, false
  for _, id in ipairs(songs) do
    if id == Song.MUS_EVOLUTION_INTRO then sawIntro = true end
    if id == Song.MUS_EVOLUTION then sawEvo = true end
  end
  check(sawIntro and sawEvo, "Emerald MUS_EVOLUTION_INTRO (" .. Song.MUS_EVOLUTION_INTRO .. ") and MUS_EVOLUTION ("
    .. Song.MUS_EVOLUTION .. ") played")
  check(fanfares[1] == Song.MUS_EVOLVED, "MUS_EVOLVED fanfare (" .. tostring(fanfares[1]) .. ")")
  check(result ~= nil, "scene reported " .. tostring(result))
  Audio.playSong, Audio.playFanfare = playSong, playFanfare
  finish()
end
