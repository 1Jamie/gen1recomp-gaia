-- home/vblank.asm:58-72
-- home/delay.asm:14

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check, eq = T.check, T.eq
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)

local Sound = require("src.core.Sound")
local BattleState = require("src.battle.BattleState")


eq(Sound.rate(), 1, "the rate starts at 1")
Sound.setRate(2)
eq(Sound.rate(), 2, "2X sets the one-shot playback rate to 2")
Sound.setRate(100)
eq(Sound.rate(), 4, "a huge speed clamps to FF_PITCH_MAX")
Sound.setRate(nil)
eq(Sound.rate(), 1, "nil falls back to 1")
Sound.setRate(-1)
eq(Sound.rate(), 1, "a negative speed falls back to 1")
Sound.setRate(0)
eq(Sound.rate(), 1, "zero falls back to 1")
Sound.setRate(0 / 0)
eq(Sound.rate(), 1, "NaN falls back to 1")
Sound.setRate(1)


local function stub(dur, pitch, playing)
  return {
    playing = playing ~= false,
    getDuration = function() return dur end,
    getPitch = function() return pitch end,
    isPlaying = function(self) return self.playing end,
    stop = function(self) self.playing = false end,
  }
end

eq(Sound.waitFrames(nil), 0, "no source is no wait")
eq(Sound.waitFrames(stub(2, 1)), 122, "a 2s sfx at pitch 1 is 120 frames plus margin")
eq(Sound.waitFrames(stub(2, 2)), 62, "pitched to 2X it takes half as many frames")
eq(Sound.waitFrames(stub(2, 4)), 32, "and a quarter at the 4X clamp")

Sound.setRate(4)
eq(Sound.waitFrames(stub(2, 4)), 122,
  "at 4X a 4X-pitched jingle still spans the same 120 logic frames")
eq(Sound.waitFrames(stub(2, 1)), 482,
  "a source fast-forward could not pitch costs proportionally more frames")
Sound.setRate(1)

local broken = { getDuration = function() error("no duration") end }
eq(Sound.waitFrames(broken), 180, "a source with no usable duration gets the fallback")
eq(Sound.waitFrames(broken, 90), 90, "and the caller may pick the fallback")
eq(Sound.waitFrames({}), 180, "so does a source with no getDuration at all")


local function gate(src)
  local st = setmetatable({
    waitingSound = src,
    queue = {},
    game = { stack = { top = function() return nil end } },
  }, BattleState)
  return st
end

local stuck = stub(1, 1)
local st = gate(stuck)
local budget = Sound.waitFrames(stuck)
local held = 0
for _ = 1, budget + 200 do
  if not st:updateQueue() then break end
  held = held + 1
end
check(stuck.playing == false, "the budget stops a source that never ends on its own")
eq(st.waitingSound, nil, "and releases the queue")
eq(held, budget - 1, "after exactly the frame budget, not forever")

local short = stub(1, 1)
local st2 = gate(short)
check(st2:updateQueue(), "the gate holds while the sfx sounds")
short.playing = false
check(st2:updateQueue() == false, "and releases the frame the sfx goes quiet")
eq(st2.waitSoundLeft, nil, "the budget is cleared with the source")


local Game2 = require("src.core.Game2")
require("src.core.FixedStep"):init(function() end)

local function gen2(speed)
  return setmetatable({
    phase = "boot",
    speedOverride = speed,
    audioAccum = 0,
    data = {},
    stack = { top = function() return nil end },
  }, { __index = Game2 })
end

Sound.setRate(1)
gen2(4):update(0)
eq(Sound.rate(), 4, "a Gen 2 frame drives the one-shot rate off its own speed")
gen2(2):update(0)
eq(Sound.rate(), 2, "and follows it down")
gen2(100):update(0)
eq(Sound.rate(), 4, "the Gen 2 path clamps through the same setRate")
gen2(1):update(0)
eq(Sound.rate(), 1, "1X is rate 1 in Gen 2 too")

Sound.setRate(4)
require("src.core.SessionLifecycle").endGameSession(nil)
eq(Sound.rate(), 1, "session teardown resets the rate for the next boot")

T.finish("fanfare_speed_bug1952")
