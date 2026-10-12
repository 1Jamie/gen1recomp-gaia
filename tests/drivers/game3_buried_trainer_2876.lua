local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("game3_buried_trainer_2876")

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPP = { up = "down", down = "up", left = "right", right = "left" }

return function(game)
  if not F.boot(game) then return F.finish() end
  F.givePartyAndRepel()
  local Runtime = require("src.core.game3.runtime")
  local version = Runtime.getSession().version
  local prefix = ({ emerald = "EM", ruby = "RU", sapphire = "SA" })[version]
  if not F.check(prefix ~= nil, "buried2876 RSE version") then return F.finish() end
  local Objects = require("src.core.game3.objects")
  local TrainerSight = require("src.core.game3.trainer_sight")
  local FxRse = require("src.core.game3.field_effects_rse")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Message = require("src.ui.game3.message")
  local Collision = require("src.core.game3.collision")
  local Player = require("src.core.game3.player")

  local BattleBridge = require("src.core.game3.battle_bridge")
  BattleBridge.start = function() return true end

  local function waitFor(pred, frames)
    for _ = 1, frames or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end

  local function scriptStarted(eo)
    local key = eo.scriptKey or (eo.def and eo.def.scriptKey)
    return (Space.vm and Space.vm:isRunning() and Space.vm._scriptKey == key) or (Message.isOpen and Message.isOpen())
  end

  local function drawn(eo)
    for _, obj in ipairs(Objects.forDraw()) do if obj == eo then return true end end
    return false
  end

  local function approachCell(eo)
    for _, dir in ipairs({ "right", "left", "down", "up" }) do
      local d = DELTA[dir]
      local nx, ny = eo.cellX + d[1], eo.cellY + d[2]
      local sx, sy = eo.cellX + d[1] * 2, eo.cellY + d[2] * 2
      if Collision.inBounds(sx, sy) and Collision.isWalkable(sx, sy) and Collision.isWalkable(nx, ny)
        and not Objects.at(sx, sy) and not Objects.at(nx, ny) then
        return sx, sy, OPP[dir]
      end
    end
    return nil
  end

  local function cleanup(eo)
    local tid = TrainerSight.getTrainerId(eo)
    if tid then Flags.setFlag(Space.store, nil, Flags.trainerFlagId(tid), true) end
    F.haltVm()
    local BT = require("src.core.game3.battle_transition")
    if BT.isActive() then BT.abort() end
    local Hud = require("src.ui.game3.hud")
    if Hud.clearWaitButton then Hud.clearWaitButton() end
    pcall(function() require("src.ui.game3.fade").clear() end)
    if Message.close then pcall(Message.close) end
    U.wait(5)
  end

  local function scene(tag, mapId, pick, buried)
    local label = "buried2876 " .. version .. " " .. tag
    if not F.check(F.goTo(game, mapId, 5, 5, "down"), label .. " map_loaded") then return end
    local eo
    for _, lid in ipairs(Objects._order) do
      local o = Objects._byId[lid]
      if o and tonumber(o.trainerType) == 3 and pick(o) and approachCell(o) then eo = o break end
    end
    if not F.check(eo ~= nil, label .. " trainer_with_approach_cell") then return end
    for _, lid in ipairs(Objects._order) do
      local o = Objects._byId[lid]
      local tid = o and o ~= eo and TrainerSight.getTrainerId(o)
      if tid then Flags.setFlag(Space.store, nil, Flags.trainerFlagId(tid), true) end
    end
    local lid = eo.localId
    local sx, sy, walkDir = approachCell(eo)
    F.goTo(game, mapId, sx, sy, walkDir, { wait = 20 })
    eo = Objects.find(lid)
    if buried then
      F.check(eo.buried == true and eo.invisible == true and not drawn(eo), label .. " hidden_before_approach")
    else
      F.check(not eo.invisible and drawn(eo), label .. " visible_before_approach")
    end
    F.check(F.shot(game, "2876_" .. version .. "_" .. tag .. "_01_before.png", true), label .. " before_capture")
    local startFacing = eo.facing
    U.hold(game, walkDir, 16)
    waitFor(function() return not Player.moving end, 60)
    local engaged = waitFor(function() return eo.frozen or eo.scriptBusy end, 30)
    F.check(engaged and Player.cellX == sx + DELTA[walkDir][1] and Player.cellY == sy + DELTA[walkDir][2],
      label .. " spotted_after_one_step")
    if buried then
      local puffed = waitFor(function() return FxRse.isActive("FLDEFF_ASH_PUFF") end, 300)
      F.check(puffed and eo.invisible == true, label .. " ash_puff_starts_hidden")
      waitFor(function() return not eo.invisible end, 60)
      U.wait(3)
      F.check(not eo.invisible and eo.jumpArc ~= nil and FxRse.isActive("FLDEFF_ASH_PUFF"), label .. " pops_out_of_ash")
      F.check(F.shot(game, "2876_" .. version .. "_" .. tag .. "_02_popout.png", true), label .. " popout_capture")
    end
    local started = waitFor(function() return scriptStarted(eo) end, 400)
    F.check(started, label .. " battle_script_started")
    F.check(eo.facing == OPP[walkDir], label .. " trainer_faces_player (was " .. tostring(startFacing) .. ")")
    F.check(Player.facing == walkDir, label .. " player_faces_trainer")
    F.check(not eo.buried and not eo.invisible and drawn(eo), label .. " trainer_stays_revealed")
    F.check(F.shot(game, "2876_" .. version .. "_" .. tag .. "_03_facing.png", true), label .. " facing_capture")
    cleanup(eo)
  end

  scene("route113", prefix .. "_ROUTE113", function(o) return o.cellX == 29 and o.cellY == 6 end, true)
  scene("lavaridge_gym", prefix .. "_LAVARIDGE_TOWN_GYM_1F", function() return true end, true)
  F.finish()
end
