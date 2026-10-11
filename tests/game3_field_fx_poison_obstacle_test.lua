package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local played = {}
package.loaded["src.core.game3.audio"] = { playSe = function(id) played[#played + 1] = id end }

local StepEvents = require("src.core.game3.step_events")
local SE = require("src.core.game3.se_ids")

local function run(isRse)
  played = {}
  StepEvents.flush()
  StepEvents.startPoisonEffect(isRse)
  local seq = {}
  for _ = 1, 20 do
    StepEvents.update(1 / 60, nil)
    if not StepEvents.poisonEffectActive() then break end
    seq[#seq + 1] = StepEvents.bgMosaic()
  end
  return table.concat(seq, ","), played
end

-- pokeemerald/src/fldeff_misc.c:1206
local seq, se = run(true)
T.eq(seq, "2,4,6,8,10,8,6,4,2,0", "RSE poison mosaic climbs by 2 past 8 and back to 0")
T.eq(se[1], SE.SE_FIELD_POISON, "RSE poison effect plays SE_FIELD_POISON")
T.check(not StepEvents.busy(), "the mosaic does not hold the player")
-- pokefirered/src/fldeff_poison.c:6
seq = run(false)
T.eq(seq, "1,2,3,4,5,4,3,2,1,0", "FRLG poison mosaic climbs by 1 past 4 and back to 0")
T.eq(StepEvents.bgMosaic(), 0, "no mosaic once the task ends")

local Movement = require("src.core.game3.scripting.movement")
-- pokefirered/src/data/object_events/object_event_anims.h:861
T.eq(Movement.decodeAction(0x68).animFrames, 8, "rock smash break steps the rock anim every 8 frames")
-- pokefirered/src/data/object_events/object_event_anims.h:869
T.eq(Movement.decodeAction(0x69).animFrames, 6, "cut tree steps the tree anim every 6 frames")

local Objects = require("src.core.game3.objects")
local eo = { customFrame = nil, invisible = false }
Objects.removeObstacle(eo, 6)
local frames, toggles, last, calls = { tostring(eo.customFrame) }, 0, false, 0
repeat
  calls = calls + 1
  local done = eo.trackWait(eo)
  if frames[#frames] ~= tostring(eo.customFrame) then frames[#frames + 1] = tostring(eo.customFrame) end
  if eo.invisible ~= last then toggles, last = toggles + 1, eo.invisible end
until done or calls > 200
T.eq(table.concat(frames, ","), "0,1,2,3", "the obstacle sprite steps frames 0..3")
T.eq(calls, 56, "cut tree anim plus flicker lasts 56 frames")
T.check(toggles >= 30, "the obstacle flickers before it is removed (" .. toggles .. ")")
T.eq(eo.invisible, true, "the obstacle ends invisible")

T.finish()
