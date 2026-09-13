#!/usr/bin/env luajit
-- pokefirered/src/sound.c:190 PlayFanfareByFanfareNum, src/m4a.c:668 m4aMPlayStop, src/m4a.c:186 m4aMPlayContinue

package.path = "./?.lua;./?/init.lua;" .. package.path

local Mix = require("src.core.game3.m4a_mix")
local Seq = require("src.core.game3.m4a_seq")
local Player = require("src.core.game3.m4a_player")

local pass, fail = 0, 0
local function check(name, cond)
  if cond then
    pass = pass + 1
    print("ok   " .. name)
  else
    fail = fail + 1
    print("FAIL " .. name)
  end
end

local function block(f)
  local ok, err = pcall(f)
  if not ok then
    fail = fail + 1
    print("FAIL block raised: " .. tostring(err))
  end
end

local function held_song()
  return {
    tracks = 2,
    trackData = {
      string.char(0xBB, 75, 0xBD, 0, 0xBE, 100, 0xBF, 0x20, 0xFF, 60, 100, 0xB0, 0xFF, 64, 100, 0xB0, 0xB2, 0, 0, 0, 0),
      string.char(0xBD, 0, 0xBE, 90, 0xBF, 0x60, 0xFF, 55, 100, 0xB0, 0xB0, 0xB2, 0, 0, 0, 0),
    },
  }
end

local function held_slot()
  local slot = { voices = {}, done = false }
  slot.seq = Seq.newPlayer(held_song(), {
    voiceResolver = function(_, key, _, _, volL, volR)
      return Mix.newCgbPulse({
        key = key, volL = volL, volR = volR, cgbChan = key == 55 and 2 or 1,
        tone = { attack = 0, decay = 0, sustain = 15, release = 0 },
      })
    end,
  })
  return slot
end

local function peak(L, R, a, b)
  local p = 0
  for i = a, b do
    p = math.max(p, math.abs(L[i] or 0), math.abs(R[i] or 0))
  end
  return p
end

block(function()
  local BUF = 1024
  local a, ref = held_slot(), held_slot()
  local snaps, abs = {}, 0
  Mix._hpfCapL, Mix._hpfCapR = 0, 0
  for _ = 1, 8 do
    snaps[#snaps + 1] = Player.snapshotSlot(a, abs)
    Player.renderBuffered(a, BUF, { raw = true })
    abs = abs + BUF
  end
  check("worker is rendering ahead with voices sounding", #a.voices > 0)
  local P = 3000
  Mix._hpfCapL, Mix._hpfCapR = 0, 0
  Player.renderBuffered(ref, BUF, { raw = true })
  Player.renderBuffered(ref, BUF, { raw = true })
  Player.renderBuffered(ref, P - 2 * BUF, { raw = true })
  local newAbs = Player.stopAt(a, snaps, P, abs)
  check("stopAt rewinds render position to the heard sample", newAbs == P)
  check("stopAt releases every channel (TrackStop)", #a.voices == 0 and #a.seq.voices == 0)
  local same = a.seq.tempoC == ref.seq.tempoC and a.seq.tempo == ref.seq.tempo
  for i, tr in ipairs(ref.seq.tracks) do
    local t = a.seq.tracks[i]
    same = same and t.pc == tr.pc and t.wait == tr.wait and t.volume == tr.volume and t.pan == tr.pan
  end
  check("resume sequencer state equals a straight render to the heard sample", same)
  check("snapshots after the heard sample are dropped", snaps[#snaps].at <= P)
  Mix._hpfCapL, Mix._hpfCapR = 0, 0
  local aL, aR = Player.renderBuffered(a, BUF, { raw = true })
  local rL, rR = Player.renderBuffered(ref, BUF, { raw = true })
  check("old continue path would still sound held notes", peak(rL, rR, 1, BUF) > 0.01)
  check("continued BGM starts silent until the next note-on", peak(aL, aR, 1, BUF) < 1e-6)
  check("seq position keeps advancing after continue", a.seq.tracks[1].wait == ref.seq.tracks[1].wait)
end)

block(function()
  local snapA = held_slot()
  Seq.update(snapA.seq, 5)
  local s = Seq.snapshot(snapA.seq)
  local wait5 = snapA.seq.tracks[1].wait
  Seq.update(snapA.seq, 40)
  snapA.seq.tracks[1]._pitchDirty = true
  Seq.restore(snapA.seq, s)
  check("Seq.restore puts wait back", snapA.seq.tracks[1].wait == wait5)
  check("Seq.restore clears fields absent from the snapshot", snapA.seq.tracks[1]._pitchDirty == false or snapA.seq.tracks[1]._pitchDirty == nil)
end)

block(function()
  local realStart = Player.start
  Player.start = function(_, _, slot)
    local fresh = held_slot()
    slot.seq, slot.voices, slot.done = fresh.seq, {}, false
    return true
  end
  Mix._hpfCapL, Mix._hpfCapR = 0.25, -0.25
  local bL, bR = Player.bakeSong({}, nil, 258, { raw = true, maxSec = 0.1 })
  check("bakeSong restores the BGM HPF capacitor state", Mix._hpfCapL == 0.25 and Mix._hpfCapR == -0.25)
  Mix._hpfCapL, Mix._hpfCapR = 0, 0
  local ref = held_slot()
  local q = Player.mixQuantum()
  local L, R, n = {}, {}, #bL
  local done = 0
  while done < n do
    local c = math.min(q, n - done)
    local l, r = Player.renderBuffered(ref, c, { raw = true, master = 1, quantum = q })
    for i = 1, c do L[#L + 1] = l[i]; R[#R + 1] = r[i] end
    done = done + c
  end
  local maxd = 0
  for i = 1, n do
    maxd = math.max(maxd, math.abs(bL[i] - L[i]), math.abs(bR[i] - R[i]))
  end
  check("fanfare bake is sample-identical to the BGM worker mix path (gain parity)", n > 0 and maxd == 0)
  local stereo = false
  for i = 1, n do
    if math.abs(bL[i] - bR[i]) > 1e-4 then stereo = true; break end
  end
  check("fanfare bake keeps stereo like BGM", stereo)
  Player.start = realStart
end)

local function fake_channel()
  local ch = { items = {} }
  function ch:push(v) self.items[#self.items + 1] = v end
  function ch:pop() return table.remove(self.items, 1) end
  function ch:clear() self.items = {} end
  function ch:getCount() return #self.items end
  return ch
end

local function fake_source(kind)
  local s = { kind = kind, playing = false, volume = 1, queued = {}, calls = {}, free = 30, pos = 1000 }
  local function note(name) s.calls[#s.calls + 1] = name end
  function s:play() note("play"); self.playing = true; return true end
  function s:stop() note("stop"); self.playing = false; self.queued = {}; self.free = 32 end
  function s:pause() note("pause"); self.playing = false end
  function s:setVolume(v) self.volume = v end
  function s:getVolume() return self.volume end
  function s:isPlaying() return self.playing end
  function s:setLooping() end
  function s:tell() return self.pos end
  function s:getFreeBufferCount() return self.free end
  function s:queue(sd) self.queued[#self.queued + 1] = sd; self.free = self.free - 1; return true end
  return s
end

block(function()
  local made = {}
  love = {
    audio = {
      newSource = function(sd, kind)
        local s = fake_source(kind)
        s.sd = sd
        made[#made + 1] = s
        return s
      end,
    },
  }
  package.loaded["src.core.game3.se_ids"] = { resolve = function(v) return tonumber(v) end }
  local Audio = require("src.core.game3.audio")

  local renders = 0
  local realBakeSlot, realBakeSong, realRender, realStart = Player.bakeSlot, Player.bakeSong, Player.renderBuffered, Player.start
  Player.bakeSlot = function(...) renders = renders + 1; return realBakeSlot(...) end
  Player.bakeSong = function(...) renders = renders + 1; return realBakeSong(...) end
  Player.renderBuffered = function(...) renders = renders + 1; return realRender(...) end
  Player.start = function(...) renders = renders + 1; return false end

  local cmd, out, ffc = fake_channel(), fake_channel(), fake_channel()
  local bgm = fake_source("queue")
  Audio._pack = {
    index = {
      fanfares = { [257] = { frames = 80 }, [258] = { frames = 160 } },
      songs = {
        [257] = { id = 257, kind = "fanfare", fanfareFrames = 80, player = 2 },
        [258] = { id = 258, kind = "fanfare", fanfareFrames = 160, player = 2 },
        [300] = { id = 300, kind = "bgm", player = 0 },
        [301] = { id = 301, kind = "bgm", player = 0 },
      },
    },
  }
  Audio._ready = true
  Audio._root = "data/generated/gba/audio"
  Audio._worker = {}
  Audio._cmdCh, Audio._outCh, Audio._fanfareCh = cmd, out, ffc
  Audio._bgmSource = bgm
  Audio._bgmGen = 300
  Audio._currentSong = { id = 300 }
  Audio._mapSong = 300
  Audio._savedSong = 999
  Audio._bgmEpoch = 4
  Audio._bgmQueuedAt = { { at = 0, n = 8192 }, { at = 8192, n = 8192 }, { at = 16384, n = 8192 } }
  bgm.free, bgm.pos, bgm.playing = 30, 1000, true

  local function cmds(name)
    local r = {}
    for _, c in ipairs(cmd.items) do
      if c.cmd == name then r[#r + 1] = c end
    end
    return r
  end

  Audio.playFanfare(258)
  local stops = cmds("stopAt")
  check("fanfare stops BGM at the heard sample (8192 + tell)", #stops == 1 and stops[1].at == 9192)
  check("BGM queued-ahead PCM is flushed, not paused", bgm.calls[#bgm.calls] == "stop" and #bgm.queued == 0)
  check("uncached fanfare asks the worker to bake it", #cmds("bakeFanfare") == 1 and cmds("bakeFanfare")[1].id == 258)
  check("no fanfare/BGM synthesis on the main thread", renders == 0)
  check("fanfare countdown per sFanfares", Audio._fanfareFrames == 160)

  local sd258 = { tag = "sd258" }
  ffc:push({ id = 258, root = Audio._root, data = sd258 })
  Audio.update(1 / 60)
  local fsrc = made[#made]
  check("worker-baked fanfare starts when it arrives", fsrc and fsrc.sd == sd258 and fsrc.playing)
  check("fanfare plays at the BGM bus level, not the SE bake gain", fsrc and fsrc.volume == 1 and fsrc.volume ~= Audio._seBakeGain)
  check("still no main-thread render after arrival", renders == 0)

  out:push({ gen = 300, epoch = 4, at = 50000, n = 8192, data = { tag = "stale" } })
  out:push({ gen = 300, epoch = Audio._bgmEpoch, at = 9192, n = 8192, data = { tag = "resume" } })
  cmd:clear()
  for _ = 1, 170 do
    if not Audio._fanfareActive then break end
    Audio.update(1 / 60)
  end
  check("fanfare countdown ended", not Audio._fanfareActive)
  check("countdown end continues BGM (m4aMPlayContinue)", #cmds("resume") == 1 and not Audio._bgmPaused)
  check("stale savebgm value is not restarted", #cmds("play") == 0)
  check("stale pre-stop buffers are rejected", bgm.queued[1] and bgm.queued[1].tag == "resume")
  check("BGM resumes from the stop sample", Audio._bgmQueuedAt[1] and Audio._bgmQueuedAt[1].at == 9192)

  Audio._fanfareSd[257] = { tag = "sd257" }
  cmd:clear()
  local before = #made
  Audio.playFanfare(257)
  local src257 = made[#made]
  check("cached fanfare starts in the same call as the BGM stop", #made == before + 1 and src257.playing and #cmds("stopAt") == 1)
  Audio.playFanfare(258)
  check("nested fanfare does not stop BGM twice", #cmds("stopAt") == 1)
  check("nested fanfare replaces the SE2 song", not src257.playing)
  check("nested fanfare keeps the first restore target", Audio._fanfareRestore == 300)
  Audio.playMapSong(301)
  for _ = 1, 200 do
    if not Audio._fanfareActive then break end
    Audio.update(1 / 60)
  end
  local plays = cmds("play")
  check("map song changed during a fanfare plays at countdown end", #plays == 1 and plays[1].id == 301)

  cmd:clear()
  Audio.playFanfare(5)
  check("unknown fanfare falls back to sFanfares[0] (80 frames)", Audio._fanfareFrames == 80)

  Player.bakeSlot, Player.bakeSong, Player.renderBuffered, Player.start = realBakeSlot, realBakeSong, realRender, realStart
  check("fanfare path never touched synthesis", renders == 0)
end)

block(function()
  local Audio = require("src.core.game3.audio")
  local bgm = fake_source("queue")
  Audio._bgmSource = bgm
  Audio._bgmPaused = false
  Audio._fanfareActive = false
  Audio._bgmGen = 300
  Audio._bgmEpoch = 10
  Audio._bgmQueuedAt = { { at = 0, n = 8192 }, { at = 8192, n = 8192 }, { at = 16384, n = 8192 } }
  bgm.free, bgm.pos, bgm.playing = 30, 9000, true
  check("heard position spans a processed buffer not yet unqueued (no clamp)", Audio.bgmHeardPosition() == 8192 + 9000)
  bgm.pos = 100
  check("heard position inside the head buffer", Audio.bgmHeardPosition() == 8292)

  love.audio.newQueueableSource = function() return fake_source("queue") end
  Audio._bgmQueuedAt = { { at = 40000, n = 8192 } }
  bgm.free, bgm.pos = 31, 100
  check("rebuildPlayback succeeds", Audio.rebuildPlayback() == true)
  check("rebuildPlayback keeps the last heard sample", Audio._bgmBaseAt == 40100)
  Audio._cmdCh:clear()
  Audio.pauseBgm()
  local stops = {}
  for _, c in ipairs(Audio._cmdCh.items) do
    if c.cmd == "stopAt" then stops[#stops + 1] = c end
  end
  check("pause before the first pump after a rebuild rewinds to the heard sample", #stops == 1 and stops[1].at == 40100)
  Audio.resumeBgm()
end)

block(function()
  local Audio = require("src.core.game3.audio")
  local songs = Audio._pack.index.songs
  for i = 1, 9 do
    songs[1000 + i] = { id = 1000 + i, kind = "se", player = 10 + i }
  end
  Audio._seSources, Audio._seByPlayer, Audio._seMeta = {}, {}, {}
  Audio._fanfareActive = false
  Audio._bgmPaused = false
  Audio._bgmQueuedAt = {}
  Audio._fanfareSd[257] = { tag = "sd257" }
  Audio._fanfareSrc = {}
  Audio.playFanfare(257)
  local ff = Audio._fanfareSource
  check("fanfare source is live", ff and ff.playing and Audio._seSources[1] == ff)
  local realStart, realBakeSlot = Player.start, Player.bakeSlot
  Player.start = function(_, _, slot) slot.seq = nil; return true end
  Player.bakeSlot = function() return { tag = "se" } end
  for i = 1, 9 do Audio.playSe(1000 + i) end
  Player.start, Player.bakeSlot = realStart, realBakeSlot
  local kept = false
  for _, s in ipairs(Audio._seSources) do
    if s == ff then kept = true end
  end
  check("SE pressure trims to 8 sources", #Audio._seSources == 8)
  check("SE pressure never stops the fanfare", ff.playing and kept and Audio._fanfareSource == ff)
  Audio.stopSe()
  Audio._fanfareActive = false
  Audio._bgmPaused = false
end)

block(function()
  local Audio = require("src.core.game3.audio")
  local cmd = Audio._cmdCh
  Audio._bgmGen = 300
  Audio._currentSong = { id = 300 }
  Audio._mapSong = 300
  Audio.setSavedSong(0)
  check("savebgm MUS_DUMMY clears the saved song", Audio._savedSong == nil)
  Audio.setSavedSong(999)
  cmd:clear()
  Audio.restoreMapSong()
  local plays = {}
  for _, c in ipairs(cmd.items) do
    if c.cmd == "play" then plays[#plays + 1] = c.id end
  end
  check("map music after a battle prefers the saved song", plays[1] == 999)
  check("only a warp clears the saved song", Audio._savedSong == 999)
  Audio.setSavedSong(999)
  Audio._currentSong = { id = 999 }
  cmd:clear()
  Audio.fadeDefaultBgm(4)
  plays = {}
  for _, c in ipairs(cmd.items) do
    if c.cmd == "play" then plays[#plays + 1] = c.id end
  end
  check("fadedefaultbgm goes to the map default, not the saved song", plays[1] == 300)
  Audio.setSavedSong(999)
  Audio.playMapSong(999, { mapSong = 300 })
  check("playing the saved song keeps the map default", Audio._mapSong == 300)
  Audio._fadeOut = nil
end)

block(function()
  local channels = {}
  local function chan(name)
    if not channels[name] then channels[name] = fake_channel() end
    return channels[name]
  end
  local calls, sleeps, injected = {}, 0, false
  package.preload["love.thread"] = function() return true end
  package.preload["love.sound"] = function() return true end
  package.preload["love.timer"] = function() return true end
  package.preload["love.filesystem"] = function() return true end
  love.thread = { getChannel = chan }
  love.sound = { newSoundData = function() return newproxy(false) end }
  love.timer = {
    sleep = function()
      sleeps = sleeps + 1
      if sleeps == 1 then
        chan("game3_m4a_cmd"):push({ cmd = "bakeFanfare", id = 257 })
      else
        chan("game3_m4a_cmd"):push({ cmd = "quit" })
      end
    end,
  }
  love.filesystem = {
    read = function() return nil end,
    load = function(rel)
      local chunk = assert(loadfile(rel))
      if not rel:find("m4a_player.lua", 1, true) then return chunk end
      return function()
        local P = chunk()
        P.loadPack = function()
          return { index = { fanfares = { [257] = { frames = 80 }, [258] = { frames = 160 } } } }
        end
        P.bakeSong = function(_, _, id, opts)
          calls[#calls + 1] = id
          if opts.yieldEvery and not injected then
            injected = true
            chan("game3_m4a_cmd"):push({ cmd = "bakeFanfare", id = id })
            coroutine.yield()
          end
          return newproxy(false)
        end
        return P
      end
    end,
  }
  chan("game3_m4a_cmd"):push({ cmd = "install", root = "r", sampleRate = 32768 })
  dofile("src/core/game3/m4a_worker.lua")
  local n258, n257 = 0, 0
  for _, id in ipairs(calls) do
    if id == 258 then n258 = n258 + 1 end
    if id == 257 then n257 = n257 + 1 end
  end
  check("priority bake of an in-progress prebake finishes it instead of baking twice", n258 == 1)
  check("a request for a fanfare the main thread dropped is baked again", n257 == 2)
  check("every bake is pushed exactly once", chan("game3_m4a_fanfare"):getCount() == #calls)
end)

print(string.format("game3_fanfare_bgm_test: ok=%d fail=%d", pass, fail))
if fail > 0 then os.exit(1) end
