local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_f2_load_teardown_2873", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_f2_load_teardown_2873")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Battle = require("src.core.game3.battle")
  local Bridge = require("src.core.game3.battle_bridge")
  local Party = require("src.core.game3.party")
  local Player = require("src.core.game3.player")
  local Audio = require("src.core.game3.audio")
  local Space = require("src.core.game3.scripting.space")
  local Stack = require("src.ui.game3.stack")
  local Message = require("src.ui.game3.message")
  local session = Runtime.getSession()
  local version = session.version
  local C = require("src.core.game3.constants").of(version)
  local rse = version == "emerald" or version == "ruby" or version == "sapphire"

  Party.giveMon(session, C:require("species", rse and "SPECIES_TREECKO" or "SPECIES_CHARMANDER"), 12)
  local mapId, sx, sy, song, scene, sceneSong, sceneAt
  if rse then
    if version == "emerald" then
      F.setVar("VAR_LITTLEROOT_INTRO_STATE", 7)
      F.setVar("VAR_LITTLEROOT_TOWN_STATE", 4)
    end
    F.setVar("VAR_ROUTE101_STATE", 1)
    local prefix = ({ emerald = "EM", ruby = "RU", sapphire = "SA" })[version]
    mapId, sx, sy = prefix .. "_ROUTE101", 10, 12
    scene, sceneAt = "Route101_EventScript_StartBirchRescue", { 10, 19 }
  else
    mapId, sx, sy = "FR_PALLET_TOWN", 12, 8
    scene, sceneAt = "PalletTown_EventScript_OakTriggerLeft", { 12, 1 }
  end
  if version == "emerald" then song, sceneSong = "MUS_ROUTE101", "MUS_HELP"
  elseif not rse then song, sceneSong = "MUS_PALLET", "MUS_OAK" end
  require("src.core.game3.encounters").onStep = function() return nil end
  F.noTrainerSight()

  if not S.check(F.goTo(game, mapId, sx, sy, "down"), "save spot " .. mapId .. " loaded") then return S.finish() end
  U.wait(60)
  local songId = song and Audio.resolveSong(song) or Audio.currentMapMusic()
  song = song or "map music"
  S.check(songId and songId ~= 0 and Audio.currentMapMusic() == songId,
    "map song " .. song .. "=" .. tostring(songId) .. " before save")
  S.check(game:saveGame() ~= false, "saved at " .. mapId .. " " .. sx .. "," .. sy)

  local function settledField(tag)
    for _ = 1, 600 do
      if Runtime.isActive() and not (Space.vm and Space.vm:isRunning()) then break end
      U.wait(1)
    end
    U.wait(90)
    local s = Runtime.getSession()
    S.check(game.phase == "field" and Runtime.isActive(), tag .. " field runtime active")
    S.check(not Battle.isActive(), tag .. " no battle running")
    S.check(Stack.top() == nil, tag .. " ui stack empty")
    S.check(not (Space.vm and Space.vm:isRunning()), tag .. " no script running")
    S.check(not (Message.isOpen and Message.isOpen()), tag .. " no message box open")
    S.check(s and s.map == mapId, tag .. " back on " .. mapId .. " (" .. tostring(s and s.map) .. ")")
    S.check(Player.cellX == sx and Player.cellY == sy,
      tag .. " player at saved cell (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
    S.check(F.songId() == songId and Audio.currentMapMusic() == songId,
      tag .. " map song " .. song .. "=" .. tostring(songId) .. " (" .. tostring(F.songId()) .. ")")
    S.check(Audio._savedSong == nil, tag .. " no saved song carried over (" .. tostring(Audio._savedSong) .. ")")
    U.hold(game, "up", 20)
    U.wait(30)
    S.check(Player.cellY == sy - 1, tag .. " player walks after load (" .. tostring(Player.cellY) .. ")")
    F.release(game)
    U.wait(10)
  end

  if scene then
    for _ = 1, 3 do
      local key = Space.scriptKey(scene)
      local ev = game.data and game.data.maps and game.data.maps[mapId]
      for _, c in ipairs(not key and ev and ev.coordEvents or {}) do
        if c.x == sceneAt[1] and c.y == sceneAt[2] then key = c.scriptKey or c.script end
      end
      local started = key and Space.startScript(key)
      if started then break end
      U.wait(30)
    end
    local heard = false
    for _ = 1, 240 do
      local id = F.songId()
      if (sceneSong and id == Audio.resolveSong(sceneSong)) or (not sceneSong and id and id ~= songId) then
        heard = true
      end
      U.wait(1)
    end
    S.check(Space.vm and Space.vm:isRunning(), "cutscene " .. scene .. " running")
    S.check(heard, "cutscene song " .. tostring(sceneSong or F.songId()) .. " playing")
    S.still(game, "2873_01_" .. version .. "_cutscene_before_f2.png")
    game:keypressed("f2")
    game:keyreleased("f2")
    settledField("cutscene")
    S.still(game, "2873_02_" .. version .. "_field_after_cutscene_f2.png")
  end

  local wild = C:require("species", rse and "SPECIES_WURMPLE" or "SPECIES_PIDGEY")
  if not S.check(Bridge.startWild(Runtime._mod, game, { species = wild, level = 3 }, { fade = false }) == true,
      "wild battle started") then return S.finish() end
  for _ = 1, 3000 do
    if Battle.isActive() and Battle._phase == "command" then break end
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(1)
  end
  S.check(Battle.isActive() and Battle._phase == "command", "battle reached the command menu")
  S.still(game, "2873_03_" .. version .. "_battle_before_f2.png")
  game:keypressed("f2")
  game:keyreleased("f2")
  settledField("battle")
  S.still(game, "2873_04_" .. version .. "_field_after_battle_f2.png")

  return S.finish()
end
