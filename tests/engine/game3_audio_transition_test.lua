package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local check, eq = T.check, T.eq
love = require("tests.love_stub")
local Version = require("src.core.GameVersion")
local Audio = require("src.core.game3.audio")
local Song = require("src.core.game3.song_ids")
local Player = require("src.core.game3.m4a_player")
local Adapters = require("src.core.game3.scripting.adapters")

local function channel()
  local ch = { items = {} }
  function ch:push(v) self.items[#self.items + 1] = v end
  function ch:pop() return table.remove(self.items, 1) end
  function ch:clear() self.items = {} end
  return ch
end

local function source()
  local src = { playing = true, volume = 1, queued = {}, stops = 0 }
  function src:stop() self.playing = false; self.stops = self.stops + 1; self.queued = {} end
  function src:play() self.playing = true end
  function src:isPlaying() return self.playing end
  function src:setVolume(v) self.volume = v end
  function src:getFreeBufferCount() return Player.BUFFER_COUNT end
  function src:queue(data) self.queued[#self.queued + 1] = data; return true end
  return src
end

local function setup(version)
  Version.set(version)
  local songs = Song.forVersion(version)
  local a = songs.MUS_LITTLEROOT or songs.MUS_PALLET
  local b = songs.MUS_OLDALE or songs.MUS_VIRIDIAN_FOREST
  assert(type(a) == "number" and type(b) == "number" and a ~= b)
  Audio._ready, Audio._worker = true, true
  Audio._pack = { index = { songs = {} } }
  Audio._meta, Audio._fanfareCh, Audio._statusCh = nil, nil, nil
  Audio._cmdCh, Audio._outCh = channel(), channel()
  Audio._bgmSource, Audio._fanfareSource = source(), source()
  Audio._currentSong, Audio._bgmGen = { id = a }, a
  Audio._bgmEpoch, Audio._bgmQueuedAt, Audio._bgmBaseAt = 3, {}, 0
  Audio._bgmLocal, Audio._pendingBgm, Audio._bgmPaused = nil, nil, false
  Audio._fadeOut, Audio._fadeIn = nil, nil
  Audio._fanfareActive, Audio._fanfareFrames = false, 0
  Audio._fanfareRestore, Audio._fanfareDeferred, Audio._fanfarePending = nil, nil, nil
  Audio._waitFanfareCb, Audio._suspended, Audio._mapSong = nil, false, a
  return a, b
end

local function fanfare(a)
  Audio.pauseBgm()
  Audio._fanfareActive, Audio._fanfareFrames, Audio._fanfareRestore = true, 1, a
end

local function lastPlay()
  for i = #Audio._cmdCh.items, 1, -1 do
    local m = Audio._cmdCh.items[i]
    if m.cmd == "play" then return m end
  end
end

for _, version in ipairs({ "emerald", "firered", "leafgreen" }) do
  local a, b = setup(version)
  Audio.playSong(a)
  eq(Audio._bgmEpoch, 3, version .. " stable same-song keeps epoch")
  eq(#Audio._cmdCh.items, 0, version .. " stable same-song sends no restart")
  eq(Audio._bgmSource.stops, 0, version .. " stable same-song preserves source")

  a, b = setup(version)
  fanfare(a)
  local adapter = Adapters.host(nil, { data = { maps = {} } }, nil)
  local epoch, count, callback = Audio._bgmEpoch, #Audio._cmdCh.items, 0
  local sourceStops = Audio._bgmSource.stops
  Audio._waitFanfareCb = function() callback = callback + 1 end
  adapter.playBgm(a)
  eq(Audio._bgmEpoch, epoch, version .. " stable script same-A during fanfare preserves epoch")
  eq(#Audio._cmdCh.items, count, version .. " stable script same-A during fanfare sends no restart")
  Audio.fadeOutAndPlay(b, 1)
  eq(Audio.currentMapMusic(), b, version .. " actual script fixture has fanfare-deferred B")
  adapter.playBgm(a)
  eq(Audio.currentMapMusic(), a, version .. " actual script playBgm(A) supersedes fanfare-deferred B")
  check(Audio._fanfareDeferred == nil, version .. " actual script A clears obsolete deferred B")
  check(Audio._fanfareActive and Audio._bgmPaused and Audio._fanfareSource:isPlaying(),
    version .. " actual script same-A preserves fanfare lifetime and BGM pause")
  eq(Audio._bgmEpoch, epoch, version .. " actual script same-A preserves physical epoch")
  eq(#Audio._cmdCh.items, count, version .. " actual script same-A sends no restart")
  eq(Audio._bgmSource.stops, sourceStops, version .. " actual script same-A preserves physical source")
  Audio.update(1)
  eq(Audio.currentMapMusic(), a, version .. " actual script fanfare resumes latest A")
  eq(lastPlay(), nil, version .. " actual script fanfare never starts obsolete B")
  check(Audio._bgmSource:isPlaying() and not Audio._bgmPaused,
    version .. " actual script fanfare resumes audible A")
  eq(callback, 1, version .. " actual script same-A completes fanfare wait once")

  a, b = setup(version)
  Audio.fadeOutAndPlay(b, 1)
  Audio.playSong(a)
  Audio.update(1)
  eq(Audio._currentSong and Audio._currentSong.id, a, version .. " newer A cancels pending B")
  eq(lastPlay() and lastPlay().id, a, version .. " worker plays latest A")
  check(Audio._fadeOut == nil, version .. " interrupted fade removed")
  local stops = Audio._bgmSource.stops
  Audio._outCh:push({ gen = a, epoch = Audio._bgmEpoch, data = "A PCM", at = 0, n = 16 })
  Audio.update(1)
  check(Audio._bgmSource:isPlaying() and Audio._bgmSource.volume > 0, version .. " replacement source remains audible")
  eq(Audio._bgmSource.stops, stops, version .. " old fade cannot stop replacement")

  a, b = setup(version)
  Audio.fadeOutBgm(1)
  eq(Audio.currentMapMusic(), 0, version .. " fade-to-stop reports logical silence")
  Audio.playSong(a)
  Audio.update(1)
  eq(Audio._currentSong and Audio._currentSong.id, a, version .. " explicit same A cancels standalone fade")
  Audio._outCh:push({ gen = a, epoch = Audio._bgmEpoch, data = "resumed PCM", at = 0, n = 16 })
  Audio.update(1)
  check(Audio._bgmSource:isPlaying() and Audio._bgmSource.volume > 0, version .. " standalone fade replacement is audible")

  a, b = setup(version)
  fanfare(a)
  local callback = 0
  Audio._waitFanfareCb = function() callback = callback + 1 end
  Audio._fanfareDeferred = b
  Audio.playSong(0)
  check(Audio._fanfareActive and Audio._fanfareSource:isPlaying(), version .. " BGM stop preserves fanfare lifetime")
  Audio.update(1)
  eq(Audio._currentSong, nil, version .. " stop during fanfare stays silent")
  eq(Audio._bgmGen, nil, version .. " stop during fanfare clears generation")
  check(not Audio._bgmSource:isPlaying(), version .. " stop during fanfare stops source")
  eq(lastPlay(), nil, version .. " fanfare completion sends no revived play")
  eq(callback, 1, version .. " stopped BGM still completes fanfare wait")

  a, b = setup(version)
  Audio.fadeOutAndPlay(b, 1)
  Audio.playSong(0)
  Audio._outCh:push({ gen = a, epoch = Audio._bgmEpoch, data = "stale PCM", at = 0, n = 16 })
  Audio.update(1)
  eq(Audio._currentSong, nil, version .. " stop during fade stays silent")
  check(not Audio._bgmSource:isPlaying() and #Audio._bgmSource.queued == 0, version .. " explicit stop rejects old queued PCM")

  a, b = setup(version)
  Audio._outCh:push({ gen = a, epoch = 2, data = "old epoch", at = 0, n = 16 })
  Audio._outCh:push({ gen = b, epoch = 3, data = "old song", at = 0, n = 16 })
  Audio._outCh:push({ gen = a, epoch = 3, data = "current PCM", at = 16, n = 16 })
  Audio.pumpBgm()
  eq(#Audio._bgmSource.queued, 1, version .. " pump rejects stale generation and epoch")
  eq(Audio._bgmSource.queued[1], "current PCM", version .. " pump queues current PCM")
  if version ~= "emerald" then
    a, b = setup(version)
    fanfare(a)
    Audio.changeMusicTo(b)
    Audio.changeMusicTo(a)
    eq(Audio._fanfareDeferred, a, version .. " changeMusicTo replaces deferred B with A")
    Audio.update(1)
    eq(Audio._currentSong and Audio._currentSong.id, a, version .. " changeMusicTo fanfare resumes latest A")

    a, b = setup(version)
    fanfare(a)
    Audio.bikeMusic(true, true)
    Audio.bikeMusic(false)
    eq(Audio._fanfareDeferred, a, version .. " bike dismount replaces deferred cycling with A")
    Audio.update(1)
    eq(Audio._currentSong and Audio._currentSong.id, a, version .. " dismount fanfare resumes map A")

    a, b = setup(version)
    Audio.fadeOutAndPlay(b, 1)
    Audio.fadeDefaultBgm(1)
    Audio.update(1)
    eq(Audio._currentSong and Audio._currentSong.id, a, version .. " fadeDefaultBgm replaces pending B with map A")

    a, b = setup(version)
    fanfare(a)
    Audio.changeMusicTo(b)
    Audio.fadeDefaultBgm(1)
    eq(Audio._fanfareDeferred, a, version .. " fadeDefaultBgm replaces fanfare-deferred B with map A")
    check(Audio._fanfareActive and Audio._bgmPaused, version .. " default map request preserves active fanfare pause")
    Audio.update(1)
    eq(Audio._currentSong and Audio._currentSong.id, a, version .. " default map request fanfare resumes A")
  end
end

do
  local a, b = setup("emerald")
  local session = { version = "emerald", map = "EM_LITTLEROOT_TOWN", x = 5, y = 5 }
  package.loaded["src.core.game3.runtime"] = { getSession = function() return session end,
    _game = { data = { maps = { EM_LITTLEROOT_TOWN = { music = a }, EM_OLDALE_TOWN = { music = b } } } } }
  Audio.fadeOutAndPlay(b, 1)
  Audio.mapLoadMusic({ mapId = session.map })
  Audio.update(1)
  eq(Audio._currentSong and Audio._currentSong.id, a, "Emerald actual map policy replaces pending fade B with A")
  a, b = setup("emerald")
  fanfare(a)
  session.map = "EM_OLDALE_TOWN"
  Audio.mapLoadMusic({ mapId = session.map })
  eq(Audio.currentMapMusic(), b, "Emerald logical music reflects fanfare-deferred B")
  session.map = "EM_LITTLEROOT_TOWN"
  Audio.mapLoadMusic({ mapId = session.map })
  eq(Audio._fanfareDeferred, a, "Emerald return map replaces deferred B with A")
  Audio.update(1)
  eq(Audio._currentSong and Audio._currentSong.id, a, "Emerald fanfare resumes latest map A")
  check(Audio._bgmSource:isPlaying() and not Audio._bgmPaused, "Emerald fanfare restores audible A")
end

T.finish("game3_audio_transition_test")
