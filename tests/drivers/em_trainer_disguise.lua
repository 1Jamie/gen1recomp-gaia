local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("em_trainer_disguise")

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPP = { up = "down", down = "up", left = "right", right = "left" }

return function(game)
  if not F.boot(game) then return F.finish() end
  F.givePartyAndRepel()
  local Objects = require("src.core.game3.objects")
  local TrainerSight = require("src.core.game3.trainer_sight")
  local FieldEffects = require("src.core.game3.field_effects")
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")
  local Collision = require("src.core.game3.collision")

  local BattleBridge = require("src.core.game3.battle_bridge")
  local battles = {}
  BattleBridge.start = function(_, _, _, opts)
    battles[#battles + 1] = opts and opts.trainerId
    return true
  end
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

  local function spot(tag, mapId, lid, kind)
    F.check(F.goTo(game, mapId, 5, 5, "down"), mapId .. " loads")
    local Flags = require("src.core.game3.scripting.flags")
    for _, other in ipairs(Objects._order) do
      local o = Objects._byId[other]
      local tid = o and other ~= lid and TrainerSight.getTrainerId(o)
      if tid then Flags.setFlag(Space.store, nil, Flags.trainerFlagId(tid), true) end
    end
    local eo = Objects.find(lid)
    if not F.check(eo ~= nil and eo ~= require("src.core.game3.player"), tag .. " trainer localId " .. lid .. " spawned") then return end
    if kind == "buried" then
      F.check(eo.buried == true and eo.invisible == true, tag .. " trainer starts buried and hidden")
    else
      F.check(eo.disguise ~= nil and eo.disguise.sheet == kind, tag .. " trainer wears the " .. kind .. " sprite")
    end
    local facing = eo.facing or "down"
    local reach = kind == "buried" and 1 or math.max(1, tonumber(eo.sight) or 1)
    local d = DELTA[facing]
    local tx, ty
    for r = reach, 1, -1 do
      local cx, cy = eo.cellX + d[1] * r, eo.cellY + d[2] * r
      if Collision.inBounds(cx, cy) and Collision.isWalkable(cx, cy) then tx, ty = cx, cy break end
    end
    if not F.check(tx ~= nil, tag .. " has a walkable cell in sight (" .. tostring(tx) .. "," .. tostring(ty) .. ")") then return end
    F.goTo(game, mapId, eo.cellX + d[1] * (reach + 3), eo.cellY + d[2] * (reach + 3), OPP[facing], { wait = 20 })
    eo = Objects.find(lid)
    F.shot(game, tag .. "_1_hidden.png", true)
    F.goTo(game, mapId, tx, ty, OPP[facing], { wait = 2 })
    eo = Objects.find(lid)
    local P = require("src.core.game3.player")
    local spotted, dist = TrainerSight.checkLineOfSight(eo, P, game)
    local Field = require("src.core.game3.field")
    local Battle = package.loaded["src.core.game3.battle"]
    print(string.format("[driver] INFO %s hud=%s battle=%s disguise=%s buried=%s mt=%s frozen=%s", tag,
      tostring(require("src.ui.game3.hud").busy()), tostring(Battle and Battle.isActive and Battle.isActive()),
      tostring(eo.disguise and eo.disguise.sheet), tostring(eo.buried), tostring(eo.movementType), tostring(eo.frozen)))
    print(string.format("[driver] INFO %s los=%s dist=%s locked=%s vm=%s msg=%s eo=%d,%d facing=%s sight=%s tt=%s P=%d,%d elev=%s/%s",
      tag, tostring(spotted), tostring(dist), tostring(Field.locked), tostring(Space.vm and Space.vm:isRunning()),
      tostring(Message.isOpen and Message.isOpen()), eo.cellX, eo.cellY, tostring(eo.facing), tostring(eo.sight),
      tostring(eo.trainerType), P.cellX, P.cellY, tostring(eo.currentElevation), tostring(P.currentElevation)))
    local engaged = TrainerSight.check(game) or eo.frozen or eo.scriptBusy
    if not engaged then engaged = waitFor(function() return eo.frozen or eo.scriptBusy end, 30) end
    for _, other in ipairs(Objects._order) do
      local o = Objects._byId[other]
      if o and o ~= eo and (o.frozen or o.scriptBusy) then
        print(string.format("[driver] INFO %s: another object engaged lid=%s tid=%s", tag, tostring(other),
          tostring(TrainerSight.getTrainerId(o))))
      end
    end
    F.check(engaged, tag .. " trainer spots the player")
    if kind == "buried" then
      local puffed = waitFor(function() return FieldEffects.rse().count("ash_puff") > 0 end, 200)
      F.check(puffed, tag .. " trainer pops out of the ash (FLDEFF_ASH_PUFF)")
      waitFor(function() return not eo.invisible end, 60)
      U.wait(3)
      F.check(not eo.invisible and eo.jumpArc ~= nil, tag .. " trainer jumps up as the ash settles")
      F.shot(game, tag .. "_2_pop_out.png", true)
    else
      local revealing = waitFor(function() return eo.disguise and eo.disguise.revealing end, 200)
      F.check(revealing, tag .. " disguise starts its reveal anim after the ! icon")
      U.wait(10)
      F.shot(game, tag .. "_2_reveal.png", true)
    end
    local started = waitFor(function() return scriptStarted(eo) end, 400)
    F.check(started, tag .. " trainer walks up and starts its battle script")
    F.check(eo.disguise == nil and not eo.buried, tag .. " trainer is revealed for good")
    F.shot(game, tag .. "_3_revealed.png", true)
    F.haltVm()
    local BT = require("src.core.game3.battle_transition")
    if BT.isActive() then BT.abort() end
    local Hud = require("src.ui.game3.hud")
    if Hud.clearWaitButton then Hud.clearWaitButton() end
    pcall(function() require("src.ui.game3.fade").clear() end)
    if Message.close then pcall(Message.close) end
    U.wait(5)
    local Battle = package.loaded["src.core.game3.battle"]
    print(string.format("[driver] INFO after %s: hud=%s battle=%s msg=%s", tag, tostring(Hud.busy()),
      tostring(Battle and Battle.isActive and Battle.isActive()), tostring(Message.isOpen())))
  end

  spot("route119_tree", "EM_ROUTE119", 12, "tree_disguise")
  spot("route120_mountain", "EM_ROUTE120", 34, "mountain_disguise")
  spot("route113_buried", "EM_ROUTE113", 8, "buried")

  F.finish()
end
