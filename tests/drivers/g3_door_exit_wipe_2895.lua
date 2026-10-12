local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("g3_door_exit_wipe_2895", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3_door_exit_wipe_2895")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Player = require("src.core.game3.player")
  local Fade = require("src.ui.game3.fade")
  local Doors = require("src.core.game3.doors")
  local Warp = require("src.core.game3.warp")
  local session = Runtime.getSession()
  local frlg = session.version == "firered" or session.version == "leafgreen"
  local inside, outside = "EM_OLDALE_TOWN_HOUSE1", "EM_OLDALE_TOWN"
  if frlg then inside, outside = "FR_VIRIDIAN_CITY_HOUSE", "FR_VIRIDIAN_CITY" end
  local matY = frlg and 7 or 8
  S.check(F.goTo(game, inside, 4, matY - 1, "down"), "inside " .. inside)

  F.holdKeys(game, { "down" }, 120, function() return Warp.isBusy() end)
  local sawWarp, arrived, wipeStart, maxW, sawHold, sawOpenAnim = false, false, nil, -1, false, false
  local shots = {}
  local function shoot(key, file)
    if shots[key] then return end
    shots[key] = true
    S.check(S.still(game, file), "shot " .. file)
  end
  for _ = 1, 900 do
    U.wait(1)
    if Warp.isBusy() then sawWarp = true end
    if sawWarp and session.map == outside then
      if not arrived then
        arrived = true
        local w = Fade._wipe
        wipeStart = w and { lhs = w.lhs, rhs = w.rhs } or false
      end
      local w = Fade._wipe
      if w then
        maxW = math.max(maxW, w.rhs - w.lhs)
        if frlg and w.rhs - w.lhs >= 40 then shoot("w1", "2895_01_wipe_narrow.png") end
        if frlg and w.rhs - w.lhs >= 150 then shoot("w2", "2895_02_wipe_wide.png") end
      end
      local a = Doors._activeAnim
      if a and a.mode == "hold" and not Player.visible then sawHold = true end
      if a and a.mode == "open" then sawOpenAnim = true end
      if not frlg and a and a.mode == "hold" and Fade.active and (Fade.t or 0) <= 10 then
        shoot("h", "2895_01_rse_door_open_fading_in.png")
      end
      if Player.visible and Player.moving then
        U.wait(6)
        shoot("step", "2895_03_step_out.png")
      end
      if not Warp.isBusy() then break end
    end
  end
  U.wait(4)
  shoot("done", "2895_04_door_closed.png")
  S.check(arrived, "arrived in " .. outside)
  S.check(not Warp.isBusy(), "warp finished")
  if frlg then
    S.check(wipeStart and wipeStart.lhs == 120 and wipeStart.rhs == 120, "FRLG wipe starts fully masked")
    S.check(maxW >= 150 and Fade._wipe == nil, "FRLG wipe widened (" .. maxW .. ") and ended")
    S.check(sawOpenAnim, "FRLG door animates open")
  else
    S.check(wipeStart == false, "RSE has no barn door wipe")
    S.check(sawHold, "RSE door shown open while fading in")
    S.check(not sawOpenAnim, "RSE door does not animate open")
  end
  S.check(Fade._wipe == nil and not Fade.active, "no wipe or fade left running")
  S.check(Player.facing == "down" and Player.visible, "player stepped out facing down")

  F.holdKeys(game, { "up" }, 120, function() return Warp.isBusy() end)
  local sawDelay, sawClose, closeHidden, enteredBack = false, false, false, false
  for _ = 1, 900 do
    local a = Doors._activeAnim
    if a and a.mode == "delay_close" then sawDelay = true end
    if a and a.mode == "close" and not sawClose then
      sawClose = true
      closeHidden = not Player.visible
      shoot("entry", "2895_05_entry_door_closing.png")
    end
    if session.map == inside then enteredBack = true end
    if enteredBack and not Warp.isBusy() then break end
    U.wait(1)
  end
  S.check(enteredBack, "entered " .. inside .. " again")
  S.check(sawClose and closeHidden, "entry door closes with the player hidden")
  S.check(not sawDelay, "entry door closes as soon as the player stops")
  S.finish()
end
