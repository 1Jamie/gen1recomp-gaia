local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_ambient_cry", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_ambient_cry")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Audio = require("src.core.game3.audio")
  local AmbientCry = require("src.core.game3.ambient_cry")
  local Encounters = require("src.core.game3.encounters")
  local session = Runtime.getSession()
  local version = session.version
  local frlg = version == "firered" or version == "leafgreen"
  local mapId, sx, sy
  if frlg then
    mapId, sx, sy = "FR_ROUTE_1", 10, 10
  else
    mapId, sx, sy = session.map:match("^(%u+)_") .. "_ROUTE110", 27, 20
  end
  Encounters.onStep = function() return nil end
  F.noTrainerSight()

  local cries = {}
  local realPlayCry = Audio.playCry
  Audio.playCry = function(species, mode, pan)
    if type(mode) == "table" and mode.noDuck then
      cries[#cries + 1] = { species = species, pan = mode.pan, volume = mode.volume, mode = mode.mode }
    end
    return realPlayCry(species, mode, pan)
  end

  if not S.check(F.goTo(game, mapId, sx, sy, "down"), version .. " on " .. mapId) then return S.finish() end
  local t = Encounters.tableFor(mapId)
  local allowed = {}
  for _, kind in ipairs({ "land", "grass", "water" }) do
    local area = t and t[kind]
    local slots = area and (area.slots or area.mons or area)
    if type(slots) == "table" then
      for _, e in ipairs(slots) do allowed[tonumber(e.species or e[1]) or -1] = true end
    end
  end
  S.check(AmbientCry.species ~= 0 and allowed[AmbientCry.species],
    version .. " ambient species " .. tostring(AmbientCry.species) .. " comes from " .. mapId .. "'s land/water table")

  local function waitCry(limit)
    local n0 = #cries
    for i = 1, limit do
      if #cries > n0 then return i, cries[#cries] end
      U.wait(1)
    end
    return nil
  end

  if AmbientCry.isWaterMon then
    local cycled = false
    for _ = 1, 3700 do
      if AmbientCry.state == AmbientCry.RESET then cycled = true break end
      U.wait(1)
    end
    S.check(cycled and #cries == 0, version .. " water mon on land: timer cycles with no cry")
    for _ = 1, 20 do
      if not AmbientCry.isWaterMon then break end
      F.goTo(game, mapId, sx, sy, "down")
    end
    S.check(not AmbientCry.isWaterMon, version .. " re-entering picked a land mon (" .. tostring(AmbientCry.species) .. ")")
  end

  local frames, c = waitCry(3700)
  if S.check(c ~= nil, version .. " first ambient cry played (" .. tostring(frames) .. " frames)") then
    S.check(frames <= 3602, version .. " first cry inside the 1200-3599 frame window")
    S.check(c.species == AmbientCry.species, version .. " cry species matches the map pick")
    S.check(c.mode == 0, version .. " cry mode normal, no duck")
    S.check(c.pan >= -44 and c.pan <= 43, version .. " pan " .. tostring(c.pan) .. " in -44..43")
    S.check(c.volume >= 50 and c.volume <= 79, version .. " volume " .. tostring(c.volume) .. " in 50..79")
  end
  frames, c = waitCry(2500)
  S.check(c ~= nil and frames >= 1199 and frames <= 2402,
    version .. " repeat cry inside the 1200-2399 frame window (" .. tostring(frames) .. ")")

  U.wait(5)
  local before = AmbientCry.delay
  U.tap(game, "start")
  U.wait(120)
  S.check(Runtime.uiBusy(), version .. " start menu open")
  S.check(before - AmbientCry.delay <= 3, version .. " start menu freezes the countdown ("
    .. tostring(before) .. " -> " .. tostring(AmbientCry.delay) .. ")")
  U.tap(game, "b")
  U.wait(30)
  local Field = require("src.core.game3.field")
  Field.lock("driver")
  before = AmbientCry.delay
  U.wait(60)
  S.check(AmbientCry.delay == before, version .. " locked field controls freeze the countdown")
  Field.unlock("driver")
  U.wait(10)
  S.check(AmbientCry.delay < before, version .. " countdown resumes after unlock")

  Audio.playCry = realPlayCry
  return S.finish()
end
