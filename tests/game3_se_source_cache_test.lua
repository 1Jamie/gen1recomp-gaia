#!/usr/bin/env luajit
-- Gen 3 Audio.playSe caches the static Source per (id, pan, gain, mono,
-- loop): a repeat SE neither re-bakes nor rebuilds SoundData / Source, the
-- player-slot bookkeeping (_seSources/_seByPlayer/_seMeta) behaves as with a
-- fresh Source, and anything baked into the PCM (pan, volume) still misses.
--   luajit tests/game3_se_source_cache_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("game3 se source cache")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local built, sources = 0, 0
local Source = {}
Source.__index = Source
function Source:play() self.playing = true; self.plays = self.plays + 1 end
function Source:stop() self.playing = false; self.stops = self.stops + 1 end
function Source:isPlaying() return self.playing end
function Source:setVolume(v) self.volume = v end
function Source:getVolume() return self.volume or 1 end
function Source:setLooping(v) self.looping = v end
function Source:clone()
  sources = sources + 1
  return setmetatable({ sd = self.sd, plays = 0, stops = 0, clone = true },
    Source)
end
love.audio = love.audio or {}
love.audio.newSource = function(sd)
  sources = sources + 1
  return setmetatable({ sd = sd, plays = 0, stops = 0 }, Source)
end
local realNewSoundData = love.sound.newSoundData
love.sound.newSoundData = function(...)
  built = built + 1
  return realNewSoundData(...)
end

local Player = require("src.core.game3.m4a_player")
local bakes = 0
Player.songInfo = function(_, id)
  return { kind = "se", player = (id == 7) and 2 or 1 }
end
Player.start = function() return true end
Player.bakeSlot = function()
  bakes = bakes + 1
  local L, R = {}, {}
  for i = 1, 64 do L[i] = math.sin(i) * 0.5; R[i] = math.cos(i) * 0.5 end
  return L, R
end

local Audio = require("src.core.game3.audio")
Audio._ready = true
Audio._pack = {}
Audio._cache = {}
Audio._seRawClear()

local function live(id)
  local n = 0
  for _, src in ipairs(Audio._seSources) do
    local meta = Audio._seMeta[src]
    if meta and meta.id == id then n = n + 1 end
  end
  return n
end

check(Audio.playSe(5), "first play")
local first = Audio._seByPlayer[1]
eq(bakes, 1, "first play bakes")
eq(sources, 1, "first play builds one Source")
check(first and first.playing, "first play is sounding")

check(Audio.playSe(5), "repeat play")
eq(bakes, 1, "repeat does not re-bake")
eq(sources, 1, "repeat reuses the cached Source")
check(Audio._seByPlayer[1] == first, "same Source on its player slot")
check(first.playing and first.plays == 2, "cached Source restarted")
eq(live(5), 1, "one live entry for the SE (the previous play was replaced)")
check(Audio._seMeta[first] and Audio._seMeta[first].id == 5
  and Audio._seMeta[first].player == 1, "meta rebuilt for the replay")

-- a different SE on the same player replaces it, then the first comes back
local builtBefore = built
Audio.playSe(6)
check(not first.playing, "player 1 SE replaced stops the cached Source")
check(Audio._seMeta[first] == nil, "replaced Source forgotten")
Audio.playSe(5)
check(Audio._seByPlayer[1] == first and first.playing,
  "cached Source reused after being replaced")
eq(built - builtBefore, 1, "only the new SE built SoundData")

-- PCM-baked parameters miss the cache
local n = sources
Audio.playSe(5, { pan = 63 })
eq(sources, n + 1, "a different pan builds its own Source")
Audio.playSe(5, { pan = 63 })
eq(sources, n + 1, "and that one is cached too")
Audio.playSe(5, { volume = 0.5 })
eq(sources, n + 2, "a different volume builds its own Source")

-- stopSe still stops and forgets it
Audio.playSe(5)
local cached = Audio._seByPlayer[1]
Audio.stopSe(5)
check(not cached.playing and Audio._seMeta[cached] == nil
  and Audio._seByPlayer[1] == nil, "stopSe stops and forgets a cached Source")

-- a cached Source still tracked live (not replaced) is cloned, not cut off
Audio._seSources[#Audio._seSources + 1] = cached
Audio._seMeta[cached] = { id = 5, player = 3 }
cached.playing = true
Audio.playSe(5)
local now = Audio._seByPlayer[1]
check(now ~= cached and now.clone and now.playing,
  "live cached Source is cloned for the new play")
check(cached.playing, "the live one keeps playing")
Audio.stopSe()

-- a re-install / session end drops the cache with the raw memo
Audio._seRawClear()
n = sources
Audio.playSe(5)
eq(sources, n + 1, "cache cleared with the raw memo")
eq(bakes, 3, "and the SE is baked again (5 and 6 before)")

-- non-memoable plays (explicit loop/maxSec) never touch the cache
n = sources
Audio.playSe(5, { maxSec = 1 })
Audio.playSe(5, { maxSec = 1 })
eq(sources, n + 2, "maxSec plays build fresh Sources")

S.finish()
