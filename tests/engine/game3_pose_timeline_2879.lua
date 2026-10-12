-- pokeemerald/src/event_object_movement.c:4582 SetStepAnimHandleAlternation
-- pokeemerald/src/event_object_movement.c:5724 MovementAction_WalkInPlaceSlow_Step1
-- pokeemerald/src/data/object_events/object_event_anims.h:202 sAnim_GoSouth
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local check, eq = T.check, T.eq
local GameVersion = require("src.core.GameVersion")
local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")

local W, H = 16, 16
local grid = {}

local function setup(version, facing)
  GameVersion.set(version)
  for i = 1, W * H do grid[i] = 0x00 end
  grid[2 * W + 5 + 1] = 0xff
  Collision._grid, Collision._widthCells, Collision._heightCells = grid, W, H
  Player.reset(5, 6, facing)
  Player.biking = false
  Player.surfing = false
  Player.canDash = function() return true end
end

local function input(held, b)
  return {
    isDown = function(_, k) return k == held or (b and k == "b") end,
    wasPressed = function() return false end,
  }
end

local function pose()
  local run = Player.runPose()
  local even
  if run ~= nil then even = run == 0 else even = Player.walkPhase() == 1 end
  if not even then return "." end
  return Player.drawFlip() and "A" or "B"
end

local function rep(c, n) return string.rep(c, n) end

local RUN3 = "BBBBB...AAAAA...BBBBB..."

local function play(script, frames, onFrame, before, after)
  local out = {}
  for i = 1, frames do
    local held, b = script(i)
    if before then before(i) end
    Player.update(nil, input(held, b))
    if after then after(i) end
    out[i] = pose()
    if onFrame then onFrame(i) end
  end
  return table.concat(out)
end

local rows = {
  {
    name = "hold into wall",
    facing = "up",
    frames = 94,
    script = function() return "up", true end,
    want = RUN3 .. rep("A", 16) .. rep(".", 16) .. rep("B", 16) .. rep(".", 16) .. rep("A", 6),
  },
  {
    name = "release at bump frame 4",
    facing = "up",
    frames = 73,
    script = function(i) if i <= 28 then return "up", true end end,
    want = RUN3 .. rep("A", 16) .. rep(".", 33),
    onFrame = function(i, v)
      if i == 56 then check(Player.action ~= nil, v .. " bump still runs 28 frames after the release") end
      if i == 57 then
        check(Player.action == nil and not Player.walkInPlace, v .. " bump ends 29 frames after the release")
      end
      if i == 73 then check(Player.turnArmed, v .. " release after the bump re-arms the turn") end
    end,
  },
  {
    name = "release at bump frame 16",
    facing = "up",
    frames = 70,
    script = function(i) if i <= 40 then return "up", true end end,
    want = RUN3 .. rep("A", 16) .. rep(".", 30),
  },
  {
    name = "new direction during bump",
    facing = "up",
    frames = 44,
    script = function(i) if i <= 28 then return "up", true end return "left", true end,
    want = RUN3 .. "AAAA" .. "AAAAA..." .. "BBBBB...",
    onFrame = function(i, v)
      if i == 29 then
        check(Player.moving and Player.facing == "left" and Player.turnTimer == 0,
          v .. " the new direction steps on its first frame")
      end
    end,
  },
  {
    name = "same direction still blocked",
    facing = "up",
    frames = 84,
    script = function(i) if i <= 28 or i >= 45 then return "up", true end end,
    want = RUN3 .. rep("A", 16) .. rep(".", 16) .. rep("B", 16) .. rep(".", 12),
  },
  {
    name = "opposite direction during bump",
    facing = "up",
    frames = 44,
    script = function(i) if i <= 28 then return "up", true end return "down", true end,
    want = RUN3 .. "AAAA" .. "AAAAA..." .. "BBBBB...",
    onFrame = function(i, v)
      if i == 29 then
        check(Player.moving and Player.facing == "down" and Player.turnTimer == 0,
          v .. " the opposite direction steps on its first frame")
      end
    end,
  },
  {
    name = "release mid walk step",
    facing = "up",
    frames = 33,
    script = function(i) if i <= 3 then return "up", false end end,
    want = rep("B", 8) .. rep(".", 25),
    onFrame = function(i, v)
      if i == 33 then check(not Player.moving and Player.cellY == 5, v .. " the walk step completes") end
    end,
  },
  {
    name = "release mid run step",
    facing = "up",
    frames = 23,
    script = function(i) if i <= 3 then return "up", true end end,
    want = "BBBBB" .. rep(".", 18),
    onFrame = function(i, v)
      if i == 23 then check(not Player.moving and Player.cellY == 5, v .. " the run step completes") end
    end,
  },
  {
    name = "standstill turn",
    facing = "up",
    frames = 16,
    script = function(i) if i == 1 then return "left", false end end,
    want = "BBBB" .. rep(".", 12),
  },
  {
    name = "standstill turn then hold",
    facing = "up",
    frames = 24,
    script = function() return "left", false end,
    want = "BBBB....AAAAAAAA........",
    onFrame = function(i, v)
      if i == 1 then eq(Player.turnTimer, 8, v .. " turn-in-place timer") end
      if i == 8 then check(not Player.moving and Player.facing == "left", v .. " input ignored for the 8 turn frames") end
      if i == 9 then check(Player.moving, v .. " step begins the frame the turn ends") end
    end,
  },
  {
    name = "stick jitter into wall",
    facing = "up",
    frames = 98,
    script = function(i)
      if i <= 28 or (i - 29) % 2 == 1 then return "up", true end
    end,
    want = RUN3 .. rep("A", 16) .. rep(".", 16) .. "." .. rep("B", 16) .. rep(".", 16) .. rep("A", 9),
  },
  {
    name = "stick jitter at standstill",
    facing = "up",
    frames = 40,
    script = function(i) if (i - 1) % 2 == 0 then return "left", false end end,
    want = "BBBB....AAAAAAAA........BBBBBBBB........",
  },
  {
    name = "scripted walk begun before the tick",
    facing = "up",
    frames = 32,
    script = function() return nil end,
    before = function() if not Player.moving then Player.scriptStep("up") end end,
    want = rep("B", 8) .. rep(".", 8) .. rep("A", 8) .. rep(".", 8),
  },
  {
    name = "scripted walk_fast begun before the tick",
    facing = "up",
    frames = 16,
    script = function() return nil end,
    before = function() if not Player.moving then Player.scriptStep("up", false, false, true) end end,
    want = rep("B", 4) .. rep(".", 4) .. rep("A", 4) .. rep(".", 4),
  },
  {
    name = "scripted 2-frame step begun before the tick",
    facing = "up",
    frames = 6,
    script = function() return nil end,
    before = function(i) if i == 1 then Player.scriptStep("up", false, false, false, 2) end end,
    want = rep(".", 6),
    onFrame = function(i, v)
      if i == 6 then check(not Player.moving and Player.cellY == 5, v .. " the 2-frame step completes") end
    end,
  },
  {
    name = "scripted walk begun after the tick",
    facing = "up",
    frames = 33,
    script = function() return nil end,
    after = function(i) if i == 1 or i == 17 then Player.scriptStep("up") end end,
    want = rep("B", 8) .. rep(".", 8) .. rep("A", 8) .. rep(".", 9),
  },
}

for _, v in ipairs({ "emerald", "firered", "ruby" }) do
  for _, row in ipairs(rows) do
    setup(v, row.facing)
    Player.update(nil, input(nil))
    local tag = v .. " " .. row.name
    local got = play(row.script, row.frames, row.onFrame and function(i) row.onFrame(i, tag) end,
      row.before, row.after)
    eq(got, row.want, tag .. " pose timeline")
  end
end

T.finish("game3_pose_timeline_2879")
