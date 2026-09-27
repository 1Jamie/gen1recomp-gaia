local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_hof_credits"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_hof_credits failures=" .. failures)
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
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Space = require("src.core.game3.scripting.space")
  local Party = require("src.core.game3.party")
  local Dex = require("src.core.game3.dex")
  local Rse = require("src.core.game3.rse.init")
  local HallOfFame = require("src.ui.game3.hall_of_fame")
  local Credits = require("src.ui.game3.rse.credits")
  local Audio = require("src.core.game3.audio")
  local Song = require("src.core.game3.song_ids")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session and session.version == "emerald", "emerald session") then return finish() end
  for _, name in ipairs({ "SPECIES_BLAZIKEN", "SPECIES_GARDEVOIR", "SPECIES_MANECTRIC", "SPECIES_SWELLOW" }) do
    local sp = C:require("species", name)
    Party.giveMonToPlayer(session, sp, 50)
    Dex.setCaught(session.dex, sp)
  end
  Rse.setVar("VAR_STARTER_MON", 1, session)

  local songs = {}
  local playSong = Audio.playSong
  Audio.playSong = function(id, opts)
    songs[#songs + 1] = id
    return playSong(id, opts)
  end
  local function sawSong(id)
    for _, s in ipairs(songs) do if s == id then return true end end
    return false
  end

  try("Map.load", function()
    Map.load(nil, game, "EM_EVER_GRANDE_CITY_HALL_OF_FAME", { x = 11, y = 5, facing = "up" })
  end)
  Player.cellX, Player.cellY, Player.facing = 11, 5, "up"
  U.wait(40)
  local labels = Space.bundle and Space.bundle.labels or {}
  local key = labels["EverGrandeCity_HallOfFame_EventScript_GameClearMale"]
  check(key ~= nil, "GameClearMale script label in the bundle")
  try("start GameClear", function() Space.vm:startTalk(key, nil, 2) end)
  local opened = false
  for _ = 1, 600 do
    if HallOfFame.isOpen() then opened = true break end
    U.wait(1)
  end
  check(opened, "special GameClear opens the Hall of Fame")
  check(Rse.flag("FLAG_SYS_GAME_CLEAR", session), "FLAG_SYS_GAME_CLEAR set")
  local shots = { hold = "01_hof_mon", applause = "02_hof_welcome", exitwait = "03_hof_player" }
  local taken = {}
  for _ = 1, 6000 do
    local ph = HallOfFame.phase()
    if shots[ph] and not taken[ph] then
      taken[ph] = true
      U.wait(ph == "applause" and 200 or 20)
      U.still(game, DIR .. "/" .. shots[ph] .. ".png")
    end
    if ph == "exitwait" then U.tap(game, "a") end
    if not HallOfFame.isOpen() then break end
    U.wait(1)
  end
  check(sawSong(Song.MUS_HALL_OF_FAME), "MUS_HALL_OF_FAME (" .. Song.MUS_HALL_OF_FAME .. ")")
  check(not HallOfFame.isOpen(), "A leaves the Hall of Fame")
  check(Credits.isOpen(), "Hall of Fame exit starts the Emerald credits (StartCredits)")
  check(sawSong(Song.MUS_CREDITS), "MUS_CREDITS (" .. Song.MUS_CREDITS .. ")")
  local st = Credits.state
  if not st then return finish() end
  local seenModes, seenScenes, maxPage = {}, {}, 0
  local pageTask = st.m.tasks:get(st.m.tasks:get(st.mainId).data[15]).data
  local modeShots = {}
  local sceneNames = { [0] = "ocean_morning", "ocean_sunset", "forest_rival_arrive", "forest_catch_rival", "city_night" }
  local theEnd = false
  local shotN = 0
  for _ = 1, 40000 do
    if not Credits.isOpen() then break end
    local d = st.m.tasks:get(st.mainId).data
    maxPage = math.max(maxPage, pageTask[2] or 0)
    if st.mainFunc == "main" and st.text and not st.m.ppu.palette:fadeActive() then
      local tag = st.showMons and "mons" or sceneNames[d[7]]
      seenModes[st.showMons and "mons" or "bike"] = true
      if not st.showMons then seenScenes[d[7]] = true end
      if tag and not modeShots[tag] and (not st.showMons or #st.mons > 0) then
        modeShots[tag] = true
        U.wait(30)
        shotN = shotN + 1
        U.still(game, string.format("%s/1%d_credits_%s.png", DIR, shotN, tag))
      end
    end
    if st.theEnd == "theEnd" and not theEnd then
      theEnd = true
      U.wait(10)
      U.still(game, DIR .. "/20_the_end.png")
      U.wait(60)
      U.tap(game, "a")
    end
    U.wait(1)
  end
  check(maxPage == 57, "all 57 credits pages printed (" .. maxPage .. ")")
  check(seenModes.bike and seenModes.mons, "bike scenes and Pokemon interludes both ran")
  local n = 0
  for _ in pairs(seenScenes) do n = n + 1 end
  check(n == 5, "five bike scenes (" .. n .. ")")
  check(theEnd, "THE END screen")
  check(not Credits.isOpen(), "credits close after THE END")
  local reset = false
  for _ = 1, 300 do
    if game.phase == "boot" then reset = true break end
    U.wait(1)
  end
  check(reset, "credits end in a soft reset")
  Audio.playSong = playSong
  finish()
end
