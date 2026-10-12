package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local check, eq = T.check, T.eq
if not _G.love then _G.love = require("tests.love_stub") end

local Audio = require("src.core.game3.audio")

local function source(seconds)
  local src = { playing = true }
  function src:isPlaying() return self.playing end
  function src:getDuration() return seconds end
  function src:stop() self.playing = false end
  function src:setVolume() end
  function src:getFreeBufferCount() return 0 end
  return src
end

local INTRO = 319
local intro = source(274 / 60)
Audio._suspended = false
Audio._seSources = { intro }
Audio._seMeta = { [intro] = { id = INTRO, player = 1 } }
Audio._waitSe = nil

eq(Audio.seDurationFrames(INTRO), 274, "MUS_CAUGHT_INTRO source is 274 frames long")
eq(Audio.seDurationFrames(12345), nil, "unknown SE has no duration")

local fired = nil
Audio.waitSe(INTRO, function() fired = true end)
check(Audio._waitSe[1].frames > 274, "the wait cap covers the whole jingle")

local function tick(n)
  for _ = 1, n do Audio.update(1 / 60) end
end

tick(180)
check(fired == nil, "still waiting at frame 180 ({WAIT_SE} outlives the old 180-frame cap)")
tick(93)
check(fired == nil, "still waiting at frame 273")
intro.playing = false
tick(1)
check(fired == true, "released when MUS_CAUGHT_INTRO stops")

Audio._waitSe = nil
Audio.waitSe(INTRO, function() end, { frames = 180 })
eq(Audio._waitSe[1].frames, 180, "an explicit per-call cap is kept")

Audio._seSources = {}
Audio._seMeta = {}
Audio._waitSe = nil
Audio.waitSe(INTRO, function() end)
eq(Audio._waitSe[1].frames, 180, "no known source keeps the 180-frame cap")

T.finish()
