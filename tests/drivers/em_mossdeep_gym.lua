local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("em_mossdeep_gym")

local ARROW = { [0] = { 1, 0 }, [1] = { 0, 1 }, [2] = { -1, 0 }, [3] = { 0, -1 } }
local CCW = { right = "up", down = "right", left = "down", up = "left" }

return function(game)
  if not F.boot(game) then return F.finish() end
  F.givePartyAndRepel()
  local Objects = require("src.core.game3.objects")
  local RTP = require("src.core.game3.rotating_tile_puzzle")
  local TrainerSight = require("src.core.game3.trainer_sight")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local Player = require("src.core.game3.player")
  local C = require("src.core.game3.constants").of("emerald")

  F.check(F.goTo(game, "EM_MOSSDEEP_CITY_GYM", 3, 31, "up"), "Mossdeep Gym loads")
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    local tid = eo and TrainerSight.getTrainerId(eo)
    if tid and TrainerSight.isTrainerType(eo) then Flags.setFlag(Space.store, nil, Flags.trainerFlagId(tid), true) end
  end
  local start = C:require("metatile_labels", "METATILE_MossdeepGym_YellowArrow_Right")
  local onYellow = {}
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if eo and not eo.hidden then
      local mt = RTP.metatileAt(eo.cellX, eo.cellY)
      local row, tile = math.floor((mt - start) / 8), (mt - start) % 8
      if mt >= start and row == 0 and tile < 4 then
        onYellow[#onYellow + 1] = { eo = eo, x = eo.cellX, y = eo.cellY, tile = tile, facing = eo.facing }
      end
    end
  end
  F.check(#onYellow >= 3, "objects stand on yellow arrow tiles (" .. #onYellow .. ")")
  F.shot(game, "01_before_yellow_switch.png", true)

  Player.facing = "up"
  for _ = 1, 20 do
    if Player.moving then break end
    U.hold(game, "up", 1)
  end
  local ran = false
  for _ = 1, 120 do
    if Space.vm and Space.vm:isRunning() then ran = true break end
    U.wait(1)
  end
  F.check(ran, "stepping on the yellow floor switch runs MossdeepCity_Gym_EventScript_YellowFloorSwitch")
  local midShot = false
  for _ = 1, 3000 do
    if not (Space.vm and Space.vm:isRunning()) then break end
    if not midShot then
      for _, o in ipairs(onYellow) do
        if o.eo.moving and o.eo.progress == 8 then
          F.shot(game, "02_tiles_shifting.png", true)
          midShot = true
          break
        end
      end
    end
    U.wait(1)
  end
  if Space.vm and Space.vm:isRunning() then
    local pc = Space.vm.ctx.pc
    local list = pc and Space.vm.scripts[pc.listKey]
    local row = list and list[pc.index]
    print(string.format("[driver] INFO vm at %s#%s op=%s status=%s", tostring(pc and pc.listKey), tostring(pc and pc.index),
      tostring(row and row.op), tostring(Space.vm.ctx.status)))
  end
  F.check(not (Space.vm and Space.vm:isRunning()), "switch script finishes (waitmovement on the shifted objects)")
  local moved, turned, fixed = 0, 0, 0
  for _, o in ipairs(onYellow) do
    local d = ARROW[o.tile]
    if o.eo.cellX == o.x + d[1] and o.eo.cellY == o.y + d[2] then moved = moved + 1 end
    if o.eo.movement ~= "LOOK" and o.eo.movement ~= "LOOK_AROUND" then
      fixed = fixed + 1
      if o.eo.facing == CCW[o.facing] then turned = turned + 1 end
    end
  end
  F.check(moved == #onYellow, string.format("every yellow-tile object moved one step along its arrow (%d/%d)", moved, #onYellow))
  F.check(turned == fixed, string.format("fixed-facing objects turned counterclockwise (%d/%d)", turned, fixed))
  F.check(RTP._p == nil, "freerotatingtilepuzzle frees the puzzle state")
  F.shot(game, "03_after_yellow_switch.png", true)
  F.finish()
end
