local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_ss_tidal_porthole", "/tmp/em_ss_tidal_porthole")

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    local Rse = require("src.core.game3.rse.init")
    local Constants = require("src.core.game3.constants").active(session)
    local Natives = require("src.core.game3.scripting.natives")
    local Player = require("src.core.game3.player")
    local Map = require("src.core.game3.map")
    local Scene = require("src.core.game3.special_scene_rse")

    d.check(M.goTo(game, "EM_SSTIDAL_CORRIDOR", 5, 7, "up"), "S.S. Tidal corridor loaded")
    Rse.setFlag("FLAG_SYS_CRUISE_MODE", true, session)
    Rse.setVar("VAR_CRUISE_STEP_COUNT", 0, session)
    local Space = require("src.core.game3.scripting.space")
    local startScript = Space.startScript
    local reachedCruiseLimit = false
    Space.startScript = function(key, ...)
      if key == Space.scriptKey("SSTidalCorridor_EventScript_ReachedStepCount") then
        reachedCruiseLimit = true
        return true
      end
      return startScript(key, ...)
    end
    local StepEvents = require("src.core.game3.step_events")
    for _ = 1, 3 do StepEvents.onStepTaken(session, game) end
    d.check(Rse.var("VAR_CRUISE_STEP_COUNT", session) == 3,
      "three ordinary cabin walking steps increment the cruise count by three")
    Rse.setVar("VAR_CRUISE_STEP_COUNT", 204, session)
    StepEvents.onStepTaken(session, game)
    d.check(Rse.var("VAR_CRUISE_STEP_COUNT", session) == 205 and reachedCruiseLimit,
      "the 205th ordinary cabin step fires the reached-step script")
    Space.startScript = startScript
    Rse.setFlag("FLAG_SYS_CRUISE_MODE", false, session)
    Rse.setVar("VAR_SS_TIDAL_STATE", 2, session)
    Rse.setVar("VAR_CRUISE_STEP_COUNT", 0, session)
    local ctx = { session = session, specialVars = {} }
    local yielding, _, known = Natives.special(ctx, Constants:special("LookThroughPorthole"), {
      log = function(msg) d.note(msg) end,
    })
    d.check(known and yielding, "LookThroughPorthole yielded while the sailing scene runs")

    local entered = false
    for _ = 1, 900 do
      if Scene.portholeActive() then entered = true break end
      U.wait(1)
    end
    d.check(entered, "Emerald warped to the currents and opened the porthole view")
    if entered then
      d.check(Map.current == "EM_ROUTE134", "Slateport sailing begins over Route 134")
      d.check(not Player.isVisible(), "player sprite stays hidden behind the ship scene")
      d.check(require("src.core.game3.virtual_objects").get(0x7FEF) ~= nil,
        "S.S. Tidal artwork follows the invisible player")
      U.wait(24)
      d.check(Rse.var("VAR_CRUISE_STEP_COUNT", session) > 0, "scripted sailing advances the cruise step counter")
      d.shot(game, "01_route134_porthole_view")
      U.tap(game, "a")
      for _ = 1, 900 do
        if not Scene.portholeActive() then break end
        U.wait(1)
      end
      d.check(not Scene.portholeActive(), "A exits the porthole and completes the warp")
      d.check(Map.current == "EM_SSTIDAL_CORRIDOR", "the dynamic warp returns to the ship corridor")
      d.check(Player.isVisible(), "player visibility is restored after returning aboard")
      d.check(Rse.var("VAR_SS_TIDAL_STATE", session) == 9,
        "eastbound porthole exit sets the pret exit-currents state")

      Rse.setVar("VAR_SS_TIDAL_STATE", 2, session)
      Rse.setVar("VAR_CRUISE_STEP_COUNT", 204, session)
      local autoCtx = { session = session, specialVars = {} }
      local autoYield, _, autoKnown = Natives.special(autoCtx, Constants:special("LookThroughPorthole"), {
        log = function(msg) d.note(msg) end,
      })
      d.check(autoKnown and autoYield, "205-step cruise uses the same asynchronous porthole scene")
      local autoEntered = false
      for _ = 1, 900 do
        if Scene.portholeActive() then autoEntered = true break end
        U.wait(1)
      end
      d.check(autoEntered, "near-limit cruise opened the route scene")
      local autoReturned = false
      for _ = 1, 900 do
        if not Scene.portholeActive() then autoReturned = true break end
        U.wait(1)
      end
      d.check(autoReturned and Map.current == "EM_SSTIDAL_CORRIDOR",
        "the 205th sailing step automatically returns to the ship")
      d.check(Rse.var("VAR_CRUISE_STEP_COUNT", session) == 205
        and Rse.var("VAR_SS_TIDAL_STATE", session) == 9,
        "the automatic exit preserves Emerald's cruise count and eastbound exit state")
    end
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
