-- pokeemerald/src/event_object_movement.c:5724 MovementAction_WalkInPlaceSlow_Step1
-- pokeemerald/src/event_object_movement.c:4582 SetStepAnimHandleAlternation
local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_bump_release_2879", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_bump_release_2879")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local session = Runtime.getSession()
  local version = session.version
  S.note("version " .. tostring(version))
  if version ~= "emerald" then U.wait(240) end
  F.noTrainerSight()
  F.setFlag("FLAG_SYS_B_DASH", true)

  local mapId, sx, sy = "EM_ROUTE116", 21, 7
  if version == "ruby" then mapId = "RU_ROUTE116"
  elseif version == "sapphire" then mapId = "SA_ROUTE116"
  elseif version ~= "emerald" then mapId, sx, sy = "FR_PALLET_TOWN", 12, 16 end
  S.check(F.goTo(game, mapId, sx, sy, "up"), mapId .. " reached")
  local function open(x, y, fx, fy, dir)
    return Collision.canEnter(game, x, y, { fromX = fx, fromY = fy, dir = dir }) == true
      and not Collision.warpAt(x, y)
  end
  local spot
  for y = 2, 60 do
    for x = 2, 60 do
      if not spot and open(x, y + 2, x, y + 3, "up") and open(x, y + 1, x, y + 2, "up")
          and open(x, y, x, y + 1, "up") and open(x - 1, y, x, y, "left")
          and Collision.arrowWarpDir(Collision.behavior(x, y)) ~= "up"
          and not Collision.canEnter(game, x, y - 1, { fromX = x, fromY = y, dir = "up" }) then
        spot = { x = x, y = y }
      end
    end
  end
  if not S.check(spot ~= nil, "found a run-up into a wall") then return S.finish() end
  S.note(("run from (%d,%d) up into (%d,%d)"):format(spot.x, spot.y + 2, spot.x, spot.y - 1))

  local function stride() return Player.walkPhase() == 1 and "1" or "0" end

  local function runUpToWall()
    F.goTo(game, mapId, spot.x, spot.y + 2, "up")
    F.holdKeys(game, {}, 2)
    local bumped
    F.holdKeys(game, { "up", "b" }, 80, function()
      if Player.walkInPlace and Player.action then bumped = true return true end
    end)
    return bumped
  end

  local function bumpTimeline(holdFrames, total, onFrame)
    local out, flips = {}, {}
    out[1], flips[1] = stride(), Player.drawFlip()
    if onFrame then onFrame(1) end
    local i = 1
    local function each()
      i = i + 1
      out[i], flips[i] = stride(), Player.drawFlip()
      if onFrame then onFrame(i) end
      return i >= total
    end
    if holdFrames > 1 then F.holdKeys(game, { "up", "b" }, holdFrames - 1, each) end
    if i < total then F.holdKeys(game, {}, total - i, each) end
    return table.concat(out), flips
  end

  local function rep(c, n) return string.rep(c, n) end

  S.check(runUpToWall(), "A: run bumps the wall")
  local a, aFlips = bumpTimeline(70, 70, function(i)
    if i == 8 then S.still(game, "2879_01_bump_stride.png") end
    if i == 24 then S.still(game, "2879_02_bump_standing_half.png") end
    if i == 40 then S.still(game, "2879_03_second_bump_other_foot.png") end
  end)
  S.note("A " .. a)
  S.check(a == rep("1", 16) .. rep("0", 16) .. rep("1", 16) .. rep("0", 16) .. rep("1", 6),
    "A: held bump draws stride 16 then stand 16 per bump")
  S.check(aFlips[1] ~= aFlips[33], "A: the next bump strides on the other foot")

  S.check(runUpToWall(), "B: run bumps the wall")
  local actionAt28, actionAt29
  local b = bumpTimeline(4, 49, function(i)
    if i == 12 then S.still(game, "2879_04_release_at_4_stride_runs_out.png") end
    if i == 24 then S.still(game, "2879_05_release_at_4_standing.png") end
    if i == 32 then actionAt28 = Player.action ~= nil end
    if i == 33 then actionAt29 = Player.action ~= nil end
  end)
  S.note("B " .. b)
  S.check(b == rep("1", 16) .. rep("0", 33), "B: release at bump frame 4 strides out the first half then stands")
  S.check(actionAt28 and not actionAt29, "B: the bump runs its 32 frames after the release")

  S.check(runUpToWall(), "C: run bumps the wall")
  local c = bumpTimeline(16, 46, function(i)
    if i == 26 then S.still(game, "2879_06_release_at_16_no_second_stride.png") end
  end)
  S.note("C " .. c)
  S.check(c == rep("1", 16) .. rep("0", 30), "C: no stride frame after a release at bump frame 16")

  F.goTo(game, mapId, spot.x, spot.y + 2, "up")
  F.holdKeys(game, {}, 2)
  local turn = {}
  F.holdKeys(game, { "left" }, 1, function() turn[#turn + 1] = stride() end)
  F.holdKeys(game, {}, 15, function(i)
    turn[#turn + 1] = stride()
    if i == 5 then S.still(game, "2879_07_turn_stand_half.png") end
  end)
  local t = table.concat(turn)
  S.note("D " .. t)
  S.check(t == "1111" .. rep("0", 12) and Player.facing == "left",
    "D: standstill turn draws stride 4 then stand 4")
  S.finish()
end
