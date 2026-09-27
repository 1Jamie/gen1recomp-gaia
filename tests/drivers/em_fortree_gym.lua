local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("em_fortree_gym")

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local DIRS = { "up", "left", "right", "down" }

return function(game)
  if not F.boot(game) then return F.finish() end
  F.givePartyAndRepel()
  local Objects = require("src.core.game3.objects")
  local Collision = require("src.core.game3.collision")
  local Player = require("src.core.game3.player")
  local RG = require("src.core.game3.rotating_gate")
  local TrainerSight = require("src.core.game3.trainer_sight")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")

  F.check(F.goTo(game, "EM_FORTREE_CITY_GYM", 15, 23, "up", { keepScripts = true, wait = 60 }), "Fortree Gym loads")
  F.settle(game)
  F.check(RG.active(), "map scripts run RotatingGate_InitPuzzle / InitPuzzleAndGraphics")
  if not RG.active() then return F.finish() end
  local p = RG._p
  F.check(#p.gates == 8, "eight Fortree gates from sRotatingGate_FortreePuzzleConfig")
  local o0 = {}
  for i = 0, #p.gates - 1 do o0[i + 1] = RG.getOrientation(i) end
  F.check(o0[1] == p.gates[1].orientation and o0[8] == p.gates[8].orientation, "gate orientations live in VAR_TEMP_0..3")
  F.shot(game, "01_fortree_gates.png", true)

  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    local tid = eo and TrainerSight.getTrainerId(eo)
    if tid and TrainerSight.isTrainerType(eo) then Flags.setFlag(Space.store, nil, Flags.trainerFlagId(tid), true) end
  end

  local goalX, goalY = 15, 3
  local n = #p.gates
  local function blockedCell(x, y)
    return not (Collision.inBounds(x, y) and Collision.isWalkable(x, y))
  end
  local cur
  RG.setStore(function(id)
    local base = require("src.core.game3.constants").of("emerald"):require("vars", "VAR_TEMP_0")
    local k = id - base
    return (cur[2 * k + 1] or 0) + (cur[2 * k + 2] or 0) * 256
  end, function(id, v)
    local base = require("src.core.game3.constants").of("emerald"):require("vars", "VAR_TEMP_0")
    local k = id - base
    cur[2 * k + 1], cur[2 * k + 2] = v % 256, math.floor(v / 256) % 256
  end)
  local function key(x, y, o) return x .. "," .. y .. ":" .. table.concat(o, "") end
  local start = { x = 15, y = 23, o = o0 }
  local seen = { [key(15, 23, o0)] = true }
  local queue, head = { start }, 1
  local found
  local expanded = 0
  while head <= #queue and expanded < 200000 do
    local st = queue[head]
    head = head + 1
    expanded = expanded + 1
    if st.x == goalX and st.y == goalY then found = st break end
    for _, dir in ipairs(DIRS) do
      local d = DELTA[dir]
      local tx, ty = st.x + d[1], st.y + d[2]
      if not blockedCell(tx, ty) and not Objects.blocks(tx, ty, nil, nil) then
        cur = {}
        for i = 1, n do cur[i] = st.o[i] end
        local gateBlocked = RG.checkCollision(dir, tx, ty, false, blockedCell, true)
        if not gateBlocked then
          local k = key(tx, ty, cur)
          if not seen[k] then
            seen[k] = true
            queue[#queue + 1] = { x = tx, y = ty, o = cur, prev = st, dir = dir }
          end
        end
      end
    end
  end
  RG.setStore(nil, nil)
  local path = {}
  local s = found
  while s and s.prev do
    table.insert(path, 1, s.dir)
    s = s.prev
  end
  F.check(found ~= nil, string.format("a gate solution reaches Winona (%d steps, %d states)", #path, expanded))
  for i = 0, n - 1 do RG.setOrientation(i, o0[i + 1]) end
  if not found then return F.finish() end

  local src = love.filesystem.read("src/core/game3/player.lua") or ""
  local hooked = src:find("rotating_gate", 1, true) ~= nil
  print("[driver] INFO player.lua rotating gate hook " .. (hooked and "present" or "missing: driver applies the gate collision"))
  local rotations = 0
  local shotTaken = false
  for i, dir in ipairs(path) do
    local d = DELTA[dir]
    local tx, ty = Player.cellX + d[1], Player.cellY + d[2]
    local before = {}
    for g = 0, n - 1 do before[g] = RG.getOrientation(g) end
    if not hooked then RG.checkCollision(dir, tx, ty) end
    Player.facing = dir
    for _ = 1, 20 do
      if Player.moving then break end
      U.hold(game, dir, 1)
    end
    for _ = 1, 40 do
      if not Player.moving then break end
      U.wait(1)
      if next(RG._p.anims) and not shotTaken then
        U.wait(6)
        F.shot(game, "02_gate_turning.png", true)
        shotTaken = true
      end
    end
    for g = 0, n - 1 do if RG.getOrientation(g) ~= before[g] then rotations = rotations + 1 end end
    if Player.cellX ~= tx or Player.cellY ~= ty then
      print(string.format("[driver] step %d %s stopped at %d,%d want %d,%d", i, dir, Player.cellX, Player.cellY, tx, ty))
      break
    end
  end
  F.check(rotations > 0, "walking the solution turns gates (" .. rotations .. " rotations)")
  F.check(Player.cellX == goalX and Player.cellY == goalY,
    string.format("player reaches Winona (%d,%d)", Player.cellX, Player.cellY))
  F.shot(game, "03_fortree_solved.png", true)
  F.finish()
end
