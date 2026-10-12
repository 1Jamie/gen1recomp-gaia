local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("game3_frlg_trainer_approach_facing")

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPP = { up = "down", down = "up", left = "right", right = "left" }
local PERP = { up = { "left", "right" }, down = { "left", "right" }, left = { "up", "down" }, right = { "up", "down" } }
local FOREST = { firered = "FR_VIRIDIAN_FOREST", leafgreen = "LG_VIRIDIAN_FOREST", emerald = "EM_ROUTE_104",
  ruby = "RU_ROUTE_104", sapphire = "SA_ROUTE_104" }

return function(game)
  if not F.boot(game) then return F.finish() end
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  local version = session.version
  local label = "approach_facing " .. version
  local Objects = require("src.core.game3.objects")
  local TrainerSight = require("src.core.game3.trainer_sight")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Message = require("src.ui.game3.message")
  local Collision = require("src.core.game3.collision")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of(version)
  if #(session.party or {}) == 0 then Party.giveMonToPlayer(session, C:require("species", "SPECIES_PIKACHU"), 100) end
  local vars = Flags.forVersion(version).VAR_IDS
  Flags.setVar(Space.store, nil, assert(vars.VAR_REPEL_STEP_COUNT), 250)
  require("src.core.game3.battle_bridge").start = function() return true end

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

  local function clear(x, y)
    return Collision.inBounds(x, y) and Collision.isWalkable(x, y) and not Objects.at(x, y)
  end

  local function crossing(eo)
    local d = DELTA[eo.facing]
    if not d or (eo.sight or 0) < 2 then return nil end
    for dist = 2, math.min(eo.sight or 0, 3) do
      local tx, ty = eo.cellX + d[1] * dist, eo.cellY + d[2] * dist
      local ok = true
      for k = 1, dist - 1 do
        if not clear(eo.cellX + d[1] * k, eo.cellY + d[2] * k) then ok = false end
      end
      if ok and clear(tx, ty) then
        for _, side in ipairs(PERP[eo.facing]) do
          local p = DELTA[side]
          local sx, sy = tx + p[1], ty + p[2]
          if clear(sx, sy) then return sx, sy, OPP[side], tx, ty, dist end
        end
      end
    end
    return nil
  end

  local Field = require("src.core.game3.field")
  local MapPreview = require("src.ui.game3.map_preview_screen")
  local function settled()
    waitFor(function() return not MapPreview.isActive() and not Field.locked end, 900)
    U.wait(10)
  end

  local mapId = FOREST[version]
  if not F.check(mapId and F.goTo(game, mapId, 5, 5, "down"), label .. " map_loaded") then return F.finish() end
  settled()
  local eo, sx, sy, walkDir, tx, ty, dist
  for _, lid in ipairs(Objects._order) do
    local o = Objects._byId[lid]
    if o and tonumber(o.trainerType) == 1 then
      sx, sy, walkDir, tx, ty, dist = crossing(o)
      if sx then eo = o break end
    end
  end
  if not F.check(eo ~= nil, label .. " trainer_with_crossing_cell") then return F.finish() end
  for _, lid in ipairs(Objects._order) do
    local o = Objects._byId[lid]
    local tid = o and o ~= eo and TrainerSight.getTrainerId(o)
    if tid then Flags.setFlag(Space.store, nil, Flags.trainerFlagId(tid), true) end
  end
  print(string.format("[driver] trainer lid=%d at %d,%d facing %s sight %d; player %d,%d walks %s to %d,%d (dist %d)",
    eo.localId, eo.cellX, eo.cellY, eo.facing, eo.sight or 0, sx, sy, walkDir, tx, ty, dist))
  local lid = eo.localId
  F.goTo(game, mapId, sx, sy, walkDir, { wait = 20 })
  settled()
  eo = Objects.find(lid)
  local trainerFacing = eo.facing
  F.check(F.shot(game, "2876_" .. version .. "_approach_01_before.png", true), label .. " before_capture")
  U.hold(game, walkDir, 16)
  waitFor(function() return not Player.moving end, 60)
  local engaged = waitFor(function() return eo.frozen or eo.scriptBusy end, 30)
  F.check(engaged and Player.cellX == tx and Player.cellY == ty, label .. " spotted_on_crossing")
  F.check(waitFor(function() return scriptStarted(eo) end, 600), label .. " battle_script_started")
  F.check(math.abs(eo.cellX - tx) + math.abs(eo.cellY - ty) == 1, label .. " trainer_arrived_adjacent")
  F.check(eo.facing == trainerFacing, label .. " trainer_faces_player")
  -- pokefirered/src/trainer_see.c:359, pokeruby/src/trainer_see.c:327
  local want = Objects.isRse() and OPP[trainerFacing] or walkDir
  F.check(Player.facing == want, label .. " player_facing (want " .. want .. ", got " .. tostring(Player.facing) .. ")")
  F.check(F.shot(game, "2876_" .. version .. "_approach_02_arrived.png", true), label .. " arrived_capture")
  F.finish()
end
