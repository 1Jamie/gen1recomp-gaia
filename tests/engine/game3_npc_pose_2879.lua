-- pokeemerald/src/event_object_movement.c:5101 InitMovementNormal
-- pokeemerald/src/event_object_movement.c:4582 SetStepAnimHandleAlternation
-- pokeemerald/src/data/object_events/object_event_anims.h:202 sAnim_GoSouth
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local eq = T.eq
local GameVersion = require("src.core.GameVersion")
local Player = require("src.core.game3.player")
local Objects = require("src.core.game3.objects")
local Runtime = require("src.core.game3.runtime")
local Field = require("src.core.game3.field")

local game = { data = {}, session = { version = "emerald", flags = {}, vars = {}, party = {} } }
Runtime.session = game.session
Field.locked = true

local function fixture(version)
  GameVersion.set(version)
  game.session.version = version
  Player.reset(1, 1, "down")
  local eo = { localId = 1, cellX = 5, cellY = 5, px = 80, py = 80, facing = "down",
    animClock = 0, progress = 0, stepFlip = false, visible = true, frozen = true, scriptBusy = true }
  Objects._byId, Objects._order, Objects._tracks = { [1] = eo }, { 1 }, {}
  return eo
end

local function pose(eo)
  if Objects.walkPhase(eo) ~= 1 then return "." end
  return eo.stepFlip and "A" or "B"
end

local function rep(c, n) return string.rep(c, n) end

local function play(eo, frames, before, after)
  local out = {}
  for i = 1, frames do
    if before then before(i) end
    Objects.update(game)
    if after then after(i) end
    out[i] = pose(eo)
  end
  return table.concat(out)
end

local function queue(eo, jobs)
  local jobsLeft = { unpack(jobs) }
  return function()
    if eo.moving or not jobsLeft[1] then return end
    local job = table.remove(jobsLeft, 1)
    Objects.scriptStep(eo, job.dir, job.run, job.slow, job.fast, job.frames)
  end
end

for _, v in ipairs({ "emerald", "firered" }) do
  local eo = fixture(v)
  eq(play(eo, 32, queue(eo, { { dir = "down" }, { dir = "up" } })),
    rep("B", 8) .. rep(".", 8) .. rep("A", 8) .. rep(".", 8),
    v .. " NPC scripted walk x2 begun before the tick")

  eo = fixture(v)
  eq(play(eo, 16, queue(eo, { { dir = "down", fast = true }, { dir = "up", fast = true } })),
    rep("B", 4) .. rep(".", 4) .. rep("A", 4) .. rep(".", 4),
    v .. " NPC scripted walk_fast x2 begun before the tick")

  eo = fixture(v)
  eq(play(eo, 48, queue(eo, { { dir = "down", frames = 32 }, { dir = "up" } })),
    rep("B", 8) .. rep(".", 8) .. rep("A", 8) .. rep(".", 8) .. rep("B", 8) .. rep(".", 8),
    v .. " NPC 32-frame slow step strides on both feet, then the next step on the first foot")

  eo = fixture(v)
  local pushes = 0
  eq(play(eo, 34, nil, function()
    if not eo.moving and pushes < 2 then
      pushes = pushes + 1
      Objects.pushStep(eo, pushes == 1 and "down" or "up", 16)
    end
  end), rep("B", 8) .. rep(".", 8) .. rep("A", 8) .. rep(".", 8) .. "..",
    v .. " NPC step begun after the tick (wander order) x2")
end

T.finish("game3_npc_pose_2879")
