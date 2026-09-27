local U = require("tests.drivers.util")

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_map_music failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Party = require("src.core.game3.party")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Collision = require("src.core.game3.collision")
  local Field = require("src.core.game3.field")
  local Audio = require("src.core.game3.audio")
  local Song = require("src.core.game3.song_ids")
  local C = require("src.core.game3.constants").of("emerald")
  local EM = Song.forVersion("emerald")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field session exists") then return finish() end
  check(Audio.mapMusicPolicy() == "rse", "Emerald session runs the RSE map music policy")
  local T = Flags.forVersion("emerald")
  local function setVar(n, v) Flags.setVar(Space.store, nil, assert(T.VAR_IDS[n], n), v) end
  local function setFlag(n, on) Flags.setFlag(Space.store, nil, assert(T.IDS[n], n), on ~= false) end

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_SWAMPERT, 50, "SWAMPERT")
  session.party[1].moves = { C.moves.byName.MOVE_SURF, C.moves.byName.MOVE_DIVE, 0, 0 }
  setVar("VAR_REPEL_STEP_COUNT", 5000)
  setVar("VAR_LITTLEROOT_TOWN_STATE", 4)
  setVar("VAR_ROUTE101_STATE", 3)
  setVar("VAR_OLDALE_TOWN_STATE", 1)
  setVar("VAR_OLDALE_RIVAL_STATE", 2)
  setVar("VAR_ROUTE118_STATE", 1)
  setVar("VAR_WEATHER_INSTITUTE_STATE", 1)
  setFlag("FLAG_RESCUED_BIRCH", true)
  setFlag("FLAG_BADGE05_GET", true)

  local function name(id) return tostring(Song.nameOf(id, "emerald") or id) end
  local function playing() return Audio._currentSong and Audio._currentSong.id or 0 end
  local function mapNow() local s = Runtime.getSession() return s and s.map end
  local function header(mapId)
    local idx = Audio._pack and Audio._pack.index and Audio._pack.index.mapSongs
    return idx and idx[mapId]
  end

  local function idle()
    return not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() and not Field.locked
      and not Warp.isBusy() and not (Choice.isOpen and Choice.isOpen())
  end

  local function pump(pred, frames)
    for _ = 1, frames or 600 do
      if pred() then return true end
      if (Choice.isOpen and Choice.isOpen()) or Message._choice then
        U.tap(game, "a")
      elseif Message.isOpen and Message.isOpen() then
        U.tap(game, "a")
        U.wait(3)
      else
        U.wait(1)
      end
    end
    return pred()
  end

  local function place(mapId, x, y, facing)
    pump(idle, 300)
    local ok, err = pcall(Map.load, nil, game, mapId, { x = x, y = y, facing = facing })
    if not ok then print("[driver] Map.load " .. mapId .. " error: " .. tostring(err)) end
    local s = Runtime.getSession()
    s.x, s.y, s.facing = x, y, facing
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    Field.unlock()
    U.wait(20)
    pump(idle, 300)
    return ok
  end

  local function expectSong(want, label)
    local target = Audio.currentMapMusic()
    for _ = 1, 40000 do
      if playing() == want then break end
      U.wait(1)
    end
    local got = playing()
    print(string.format("[driver] %s: target %s (%s) playing %s (%s) map %s x=%s",
      label, tostring(target), name(target), tostring(got), name(got), tostring(mapNow()), tostring(Player.cellX)))
    return check(got == want, string.format("%s plays %s (%s)", label, name(want), name(got)))
  end

  local function walkUntil(dir, pred, steps)
    for _ = 1, steps or 8 do
      U.hold(game, dir, 16)
      pump(function() return not Warp.isBusy() end, 400)
      if pred() then return true end
    end
    return pred()
  end

  place("EM_LITTLEROOT_TOWN", 10, 3, "up")
  expectSong(EM.MUS_LITTLEROOT, "Littleroot Town")

  check(walkUntil("up", function() return mapNow() == "EM_ROUTE101" end, 6),
    "walking north crosses into Route 101 (" .. tostring(mapNow()) .. ")")
  expectSong(EM.MUS_ROUTE101, "Route 101 via the connection")

  place("EM_ROUTE101", 10, 2, "up")
  check(walkUntil("up", function() return mapNow() == "EM_OLDALE_TOWN" end, 6),
    "Route 101 north crosses into Oldale Town (" .. tostring(mapNow()) .. ")")
  expectSong(EM.MUS_OLDALE, "Oldale Town via the connection")

  place("EM_ROUTE118", 10, 8, "right")
  expectSong(EM.MUS_ROUTE110, "Route 118 west half (x 10) on a warp load")
  place("EM_ROUTE118", 60, 8, "right")
  expectSong(EM.MUS_ROUTE119, "Route 118 east half (x 60) on a warp load")

  local my = nil
  place("EM_MAUVILLE_CITY", 30, 10, "right")
  for y = 0, 19 do
    if not my and Collision.isWalkable(39, y) and Collision.isWalkable(38, y) then my = y end
  end
  check(my ~= nil, "Mauville has a walkable east edge row (" .. tostring(my) .. ")")
  if my then
    place("EM_MAUVILLE_CITY", 38, my, "right")
    expectSong(header("EM_MAUVILLE_CITY"), "Mauville City")
    check(walkUntil("right", function() return mapNow() == "EM_ROUTE118" end, 4),
      "walking east from Mauville reaches Route 118 (" .. tostring(mapNow()) .. ")")
    expectSong(EM.MUS_ROUTE110, "Route 118 entered from Mauville (x " .. tostring(Player.cellX) .. ")")
  end

  local sx, sy, dir, back = nil, nil, nil, nil
  place("EM_ROUTE118", 20, 8, "right")
  local DIRS = { { "right", 1, 0, "left" }, { "left", -1, 0, "right" }, { "up", 0, -1, "down" }, { "down", 0, 1, "up" } }
  for y = 1, 18 do
    for x = 1, 78 do
      if not sx and Collision.isWalkable(x, y) and not Collision.isWater(x, y) then
        for _, d in ipairs(DIRS) do
          local wx, wy = x + d[2], y + d[3]
          if not sx and Collision.isWater(wx, wy) and Collision.isSurfable(Collision.behavior(wx, wy)) then
            sx, sy, dir, back = x, y, d[1], d[4]
          end
        end
      end
    end
  end
  check(sx ~= nil, "Route 118 has a shore cell facing surfable water (" .. tostring(sx) .. "," .. tostring(sy) .. " " .. tostring(dir) .. ")")
  if sx then
    place("EM_ROUTE118", sx, sy, dir)
    local landSong = (sx < 24) and EM.MUS_ROUTE110 or EM.MUS_ROUTE119
    expectSong(landSong, "Route 118 shore (x " .. sx .. ")")
    U.tap(game, "a")
    local surfed = pump(function() return Player.surfing and idle() end, 1200)
    check(surfed, "surf prompt YES puts the player on the water")
    expectSong(EM.MUS_SURF, "surfing on Route 118")
    for _ = 1, 3 do
      if not Player.surfing then break end
      U.hold(game, back, 16)
      pump(function() return idle() and not Player.moving end, 400)
    end
    check(not Player.surfing, "walking back onto the shore dismounts")
    local def = (Player.cellX < 24) and EM.MUS_ROUTE110 or EM.MUS_ROUTE119
    expectSong(def, "dismounted on Route 118 (x " .. tostring(Player.cellX) .. ")")
  end

  setFlag("FLAG_SYS_WEATHER_CTRL", true)
  place("EM_LILYCOVE_CITY", 20, 20, "down")
  expectSong(EM.MUS_ABNORMAL_WEATHER, "Lilycove under FLAG_SYS_WEATHER_CTRL")
  setFlag("FLAG_SYS_WEATHER_CTRL", false)
  place("EM_LILYCOVE_CITY", 20, 20, "down")
  expectSong(header("EM_LILYCOVE_CITY"), "Lilycove after the weather clears")

  setVar("VAR_WEATHER_INSTITUTE_STATE", 0)
  place("EM_ROUTE119_WEATHER_INSTITUTE_1F", 5, 5, "up")
  expectSong(EM.MUS_MT_CHIMNEY, "infiltrated Weather Institute 1F")
  setVar("VAR_WEATHER_INSTITUTE_STATE", 1)

  setVar("VAR_MOSSDEEP_CITY_STATE", 1)
  place("EM_MOSSDEEP_CITY_SPACE_CENTER_1F", 5, 5, "up")
  expectSong(EM.MUS_ENCOUNTER_MAGMA, "infiltrated Space Center 1F")
  setVar("VAR_MOSSDEEP_CITY_STATE", 3)

  place("EM_UNDERWATER_ROUTE124", 10, 10, "up")
  expectSong(EM.MUS_UNDERWATER, "underwater Route 124")

  setVar("VAR_SKY_PILLAR_STATE", 1)
  place("EM_SOOTOPOLIS_CITY", 31, 32, "down")
  local target = Audio.currentMapMusic()
  print(string.format("[driver] Sootopolis with legendaries: target %s playing %s", tostring(target), tostring(playing())))
  check(playing() == 0, "Sootopolis is silent while Sky Pillar state is 1")
  setVar("VAR_SKY_PILLAR_STATE", 2)

  finish()
end
