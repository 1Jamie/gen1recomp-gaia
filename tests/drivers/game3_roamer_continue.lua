local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_roamer_continue", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_roamer_continue")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Roamer = require("src.core.game3.roamer")
  local Rng = require("src.core.game3.rng")
  local session = Runtime.getSession()
  local version = session.version
  local frlg = version == "firered" or version == "leafgreen"
  local C = require("src.core.game3.constants").of(version)
  local mapId, sx, sy, roamFrom
  if frlg then
    mapId, sx, sy, roamFrom = "FR_ROUTE_1", 10, 10, "FR_ROUTE_3"
  else
    mapId, sx, sy, roamFrom = "EM_ROUTE110", 27, 20, "EM_ROUTE119"
  end
  Party.giveMon(session, C:require("species", frlg and "SPECIES_CHARIZARD" or "SPECIES_SCEPTILE"), 60)
  require("src.core.game3.encounters").onStep = function() return nil end
  F.noTrainerSight()
  if not S.check(F.goTo(game, mapId, sx, sy, "down"), "save spot " .. mapId .. " loaded") then return S.finish() end
  local okInit = frlg and Roamer.init(session, 1) or (not frlg and Roamer.initRse(session, false))
  if not S.check(okInit, "roamer created") then return S.finish() end
  session.roamer.active = true
  local sets = Roamer.locationSets(Roamer.config(session))
  S.check(#sets == (frlg and 25 or 20), "roamer location sets from the cache (" .. #sets .. ")")

  local seen = {}
  local realOnContinue = Roamer.onContinue
  local entry
  Roamer.onContinue = function(s, m)
    entry = { rng = Rng.getState(), map = s.roamer and s.roamer.map }
    return realOnContinue(s, m)
  end

  local function continueFrom(tag, how)
    local s = Runtime.getSession()
    s.roamer.map = roamFrom
    s.roamer.history = { roamFrom, roamFrom, roamFrom }
    S.check(game:saveGame() ~= false, tag .. " saved on " .. mapId .. " with the roamer on " .. roamFrom)
    entry = nil
    if how == "f2" then
      game:keypressed("f2")
      game:keyreleased("f2")
    else
      game.softResetRequested = true
      U.wait(2)
      for _ = 1, 900 do
        if game.phase == "boot" and game.boot then break end
        U.wait(1)
      end
      S.check(game.phase == "boot", tag .. " back on the title")
      game:_handleBootAction({ action = "continue" })
    end
    for _ = 1, 3000 do
      if game.phase == "field" and Runtime.isActive() then break end
      if game.phase == "quest_log" and game.questPlayback then game.questPlayback.done = true end
      U.wait(1)
    end
    U.wait(60)
    s = Runtime.getSession()
    local r = s and s.roamer
    if not S.check(r and entry, tag .. " continue reached the field and re-rolled the roamer") then return end
    S.check(entry.map == roamFrom, tag .. " roamer was on " .. roamFrom .. " when the save loaded")
    local cur = Rng.getState()
    Rng.setState(entry.rng)
    local want = sets[(Rng.Random() % #sets) + 1][1]
    Rng.setState(cur)
    S.check(r.map == want, tag .. " roamer on set head " .. tostring(r.map) .. " = Random() % " .. #sets
      .. " head " .. tostring(want))
    S.check(r.history[1] == mapId and r.history[2] == false and r.history[3] == false,
      tag .. " history reset to the saved map (" .. tostring(r.history[1]) .. ","
      .. tostring(r.history[2]) .. "," .. tostring(r.history[3]) .. ")")
    S.check(s.map == mapId, tag .. " player back on " .. tostring(s.map))
    seen[r.map] = true
  end

  for i = 1, 4 do
    continueFrom("continue " .. i, "title")
  end
  S.still(game, "roamer_01_" .. version .. "_field_after_continue.png")
  continueFrom("f2 load", "f2")
  local n = 0
  for _ in pairs(seen) do n = n + 1 end
  S.note("roamer heads after continue: " .. n .. " distinct")
  Roamer.onContinue = realOnContinue
  return S.finish()
end
