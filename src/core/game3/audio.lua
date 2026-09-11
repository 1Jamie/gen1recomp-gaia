-- Game3 audio façade: numeric pret song/SE/cry IDs → in-process M4A / DirectSound.

local Sample = require("src.core.game3.m4a_sample")
local Mix = require("src.core.game3.m4a_mix")
local Player = require("src.core.game3.m4a_player")

local Audio = {}

Audio._pack = nil
Audio._cache = nil
Audio._root = "data/generated/gba/audio"
Audio._meta = nil
Audio._currentSong = nil
Audio._mapSong = nil
Audio._savedSong = nil
Audio._log = false
Audio._ready = false
Audio._seSources = {}
Audio._seByPlayer = {} -- pret m4a: one active song per MusicPlayer (SE1/SE2/SE3)
Audio._seMeta = {} -- src → { id, player }
Audio._crySlot = nil
Audio._cryClock = 0
Audio._cryUntil = nil
Audio._fanfareFrames = 0
Audio._fanfareActive = false
Audio._bgmPaused = false
Audio._bgmVolume = 1
Audio._sfxVolume = 1
-- Baked SE/fanfare sit under BGM: CGB voice scales are conservative for the
-- shared mix bus, but doors/UI play as separate sources and need to cut through.
-- SE bake is quieter than hardware/mGBA mix under battle BGM; 3.5 keeps
-- move hits readable without hard-clipping typical effectiveness/move SE.
Audio._seBakeGain = 3.5
Audio._duck = 1
Audio._duckHold = 0
Audio._mono = false
Audio._warned = {}

-- Threaded BGM
Audio._worker = nil
Audio._cmdCh = nil
Audio._outCh = nil
Audio._bgmSource = nil
Audio._bgmGen = nil
Audio._bgmLocal = nil -- sync fallback slot

local function log(msg)
  if Audio._log then
    print("[game3.audio] " .. tostring(msg))
  end
end

local function warn_once(id, msg)
  if Audio._warned[id] then return end
  Audio._warned[id] = true
  print("[game3.audio] " .. msg)
end

local function filesystem_cache()
  return {
    read = function(_, rel)
      if love and love.filesystem then return love.filesystem.read(rel) end
      return nil
    end,
    write = function(_, rel, data)
      if love and love.filesystem then return love.filesystem.write(rel, data) end
      return false
    end,
    exists = function(_, rel)
      if love and love.filesystem and love.filesystem.getInfo then
        return love.filesystem.getInfo(rel) ~= nil
      end
      return false
    end,
  }
end

local function ensure_worker()
  if Audio._worker ~= nil then return Audio._worker end
  if not (love and love.thread and love.thread.newThread) then
    Audio._worker = false
    return false
  end
  local ok, thread = pcall(love.thread.newThread, "src/core/game3/m4a_worker.lua")
  if not ok or not thread then
    Audio._worker = false
    return false
  end
  Audio._cmdCh = love.thread.getChannel("game3_m4a_cmd")
  Audio._outCh = love.thread.getChannel("game3_m4a_out")
  Audio._cmdCh:clear()
  Audio._outCh:clear()
  local started = pcall(function() thread:start() end)
  if not started then
    Audio._worker = false
    return false
  end
  Audio._worker = thread
  Audio._cmdCh:push({
    cmd = "install",
    root = Audio._root,
    sampleRate = Mix.SAMPLE_RATE,
  })
  return true
end

local function ensure_bgm_source()
  if Audio._bgmSource then return Audio._bgmSource end
  if not (love and love.audio and love.audio.newQueueableSource) then return nil end
  Audio._bgmRate = Mix.SAMPLE_RATE
  Audio._bgmSource = love.audio.newQueueableSource(Audio._bgmRate, 16, 2, Player.BUFFER_COUNT)
  return Audio._bgmSource
end

--- Install pack from explicit root (never Sevii Extract.CACHE_ROOT default).
function Audio.install(cache, opts)
  opts = opts or {}
  Audio._root = opts.root or "data/generated/gba/audio"
  Audio._cache = cache or filesystem_cache()
  local pack, err = Player.loadPack(Audio._cache, Audio._root)
  if not pack then
    Audio._ready = false
    Audio._pack = nil
    warn_once("install", "audio pack unavailable: " .. tostring(err))
    return false, err
  end
  Audio._pack = pack
  Audio._meta = pack.index
  Audio._ready = true
  if ensure_worker() then
    Audio._cmdCh:push({
      cmd = "install",
      root = Audio._root,
      sampleRate = Mix.SAMPLE_RATE,
    })
  end
  log("installed root=" .. Audio._root)
  return true
end

function Audio.isReady()
  return Audio._ready and Audio._pack ~= nil
end

function Audio.loadMeta(meta)
  -- Legacy shim: merge song table into meta without full pack.
  Audio._meta = type(meta) == "table" and meta or {}
end

function Audio.songInfo(id)
  id = tonumber(id) or id
  if Audio._pack then
    return Player.songInfo(Audio._pack, id)
  end
  local meta = Audio._meta or {}
  local songs = meta.songs or meta
  if type(songs) == "table" then
    return songs[id] or songs[tostring(id)]
  end
  return nil
end

function Audio.role(name)
  local roles = Audio._pack and Audio._pack.index and Audio._pack.index.roles
  if roles and roles[name] then return roles[name] end
  return nil
end

function Audio.applyOptions(session)
  local Options = require("src.core.game3.options")
  local o = Options.ensure(session)
  Audio._mono = (tonumber(o.sound) or 0) == 0
  -- volumes reserved for future option fields
end

local function bgm_gain()
  return (Audio._bgmVolume or 1) * (Audio._duck or 1)
end

local function stop_bgm_source()
  if Audio._bgmSource then
    pcall(function() Audio._bgmSource:stop() end)
  end
  if Audio._cmdCh then
    Audio._cmdCh:push({ cmd = "stop" })
  end
  Audio._bgmLocal = nil
  Audio._bgmGen = nil
  Audio._pendingBgm = nil
end

function Audio.playSong(id, opts)
  opts = opts or {}
  id = tonumber(id) or id
  if id == nil or id == 0 or id == 0xFFFF then
    stop_bgm_source()
    Audio._currentSong = nil
    return true
  end
  if not opts.restart and Audio._currentSong and Audio._currentSong.id == id then
    return true
  end
  local info = Audio.songInfo(id) or {}
  Audio._currentSong = {
    id = id,
    duration = info.duration,
    loop = info.loop ~= false,
    startedAt = os.clock(),
  }
  Audio._mapSong = Audio._mapSong or id

  -- A new song owns the bus — cancel stale fades and fanfares (oak exit fade was killing lab BGM).
  Audio._fadeOut = nil
  Audio._fadeIn = nil
  Audio._fanfareActive = false
  Audio._fanfareFrames = 0
  Audio._bgmPaused = false

  if not Audio.isReady() then
    log(string.format("playsong id=%s (no pack)", tostring(id)))
    return true
  end

  if ensure_worker() then
    Audio._pendingBgm = nil
    if Audio._outCh then Audio._outCh:clear() end
    Audio._cmdCh:push({ cmd = "play", id = id })
    Audio._cmdCh:push({ cmd = "volume", volume = bgm_gain() })
    Audio._bgmGen = id
    local src = ensure_bgm_source()
    if src then
      pcall(function()
        src:stop()
        src:setVolume(bgm_gain())
      end)
    end
  else
    -- Sync fallback
    Audio._bgmLocal = { voices = {}, songId = id }
    Player.start(Audio._pack, Audio._cache, Audio._bgmLocal, id, { forceSeq = true })
  end
  log(string.format("playsong id=%s", tostring(id)))
  return true
end

function Audio.playMapSong(id, opts)
  opts = opts or {}
  id = tonumber(id) or id
  if id == nil or id == 0xFFFF then return true end
  Audio._mapSong = id
  if Audio._fanfareActive then return true end
  if opts.fadeOut then
    Audio.fadeOutBgm(opts.fadeOut)
  end
  return Audio.playSong(id, opts)
end

function Audio.setMapSong(id)
  Audio._mapSong = tonumber(id) or id
end

function Audio.restoreMapSong(opts)
  local id = Audio._savedSong or Audio._mapSong
  Audio._savedSong = nil
  if id then return Audio.playSong(id, opts) end
  return true
end

function Audio.fadeDefaultBgm(speed)
  Audio.fadeOutBgm(speed)
  return Audio.restoreMapSong()
end

function Audio.fadeOutBgm(speed)
  speed = tonumber(speed) or 4
  -- pret: seconds = 16 * speed / 60
  local seconds = 16 * speed / 60
  local songId = Audio._currentSong and Audio._currentSong.id
  if Audio._bgmSource and songId then
    -- Immediate approximate fade via volume step in update
    Audio._fadeOut = {
      t = 0,
      dur = seconds,
      start = bgm_gain(),
      songId = songId,
      gen = Audio._bgmGen,
    }
  else
    stop_bgm_source()
    Audio._currentSong = nil
  end
  log(string.format("fadeOutBgm speed=%s", tostring(speed)))
  return true
end

function Audio.fadeInBgm(id, speed)
  Audio.playSong(id)
  speed = tonumber(speed) or 4
  local seconds = 16 * speed / 60
  Audio._fadeIn = { t = 0, dur = seconds }
  if Audio._bgmSource then Audio._bgmSource:setVolume(0) end
  return true
end

function Audio.pauseBgm()
  Audio._bgmPaused = true
  if Audio._cmdCh then Audio._cmdCh:push({ cmd = "pause" }) end
  if Audio._bgmSource then pcall(function() Audio._bgmSource:pause() end) end
end

function Audio.resumeBgm()
  Audio._bgmPaused = false
  if Audio._cmdCh then Audio._cmdCh:push({ cmd = "resume" }) end
  if Audio._bgmSource then
    pcall(function()
      Audio._bgmSource:setVolume(bgm_gain())
      Audio._bgmSource:play()
    end)
  end
end

function Audio.isBgmStopped()
  if Audio._bgmPaused then return true end
  if Audio._bgmSource then
    return not Audio._bgmSource:isPlaying()
  end
  return Audio._currentSong == nil
end

function Audio.playSe(id, opts)
  opts = opts or {}
  local SE = require("src.core.game3.se_ids")
  id = SE.resolve(id)
  if id == nil then
    return false
  end
  if opts.fanfare or (Audio.songInfo(id) and Audio.songInfo(id).kind == "fanfare") then
    return Audio.playFanfare(id)
  end
  if not Audio.isReady() then
    log(string.format("playse id=%s (no pack)", tostring(id)))
    return true
  end
  local info = Audio.songInfo(id) or {}
  -- pret m4aSongNumStart: starting a song on a player replaces that player's song.
  local mplay = tonumber(info.player) or 1
  Audio._stopSePlayer(mplay)

  local slot = { voices = {} }
  -- SE must run the M4A sequencer (SE_SELECT is CGB pulse, not voice0 PCM).
  local ok = Player.start(Audio._pack, Audio._cache, slot, id, { forceSeq = true })
  if not ok then
    warn_once("se:" .. tostring(id), "SE " .. tostring(id) .. " missing")
    return false
  end

  local loop = opts.loop
  if loop == nil then
    -- SE_LOW_HEALTH and any track with GOTO before FINE are hardware loops.
    loop = (id == SE.SE_LOW_HEALTH) or Audio._songHasGoto(slot)
  end

  local pan = Audio.normalizePan(opts.pan)
  local sd = Player.bakeSlot(slot, {
    master = (Audio._sfxVolume or 1) * (opts.volume or 1) * (Audio._seBakeGain or 3.5),
    mono = Audio._mono,
    maxSec = opts.maxSec or (loop and 2.5 or 2.0),
    stopOnGoto = loop and true or false,
    pan = pan,
  })
  if sd and love and love.audio and love.audio.newSource then
    local src = love.audio.newSource(sd, "static")
    src:setVolume(1)
    if loop then
      pcall(function() src:setLooping(true) end)
    end
    src:play()
    Audio._seSources[#Audio._seSources + 1] = src
    Audio._seByPlayer[mplay] = src
    Audio._seMeta[src] = { id = id, player = mplay }
    while #Audio._seSources > 8 do
      local old = table.remove(Audio._seSources, 1)
      Audio._forgetSeSource(old)
      pcall(function() old:stop() end)
    end
    log(string.format("playse id=%s player=%s pan=%s loop=%s", tostring(id), tostring(mplay), tostring(pan), tostring(loop)))
    return true
  end
  -- Headless / no device: still count as handled.
  log(string.format("playse id=%s (baked, no device)", tostring(id)))
  return true
end

function Audio.normalizePan(pan)
  if pan == nil then return 0 end
  if type(pan) == "number" then
    if pan > 63 then return 63 end
    if pan < -64 then return -64 end
    return pan
  end
  local s = tostring(pan)
  if s == "SOUND_PAN_TARGET" or s == "TARGET" then return 63 end
  if s == "SOUND_PAN_ATTACKER" or s == "ATTACKER" then return -64 end
  local n = tonumber(s)
  if n then return Audio.normalizePan(n) end
  return 0
end

function Audio._songHasGoto(slot)
  local seq = slot and slot.seq
  if not seq or not seq.tracks then return false end
  for _, tr in ipairs(seq.tracks) do
    local data = tr.data
    if type(data) == "string" and data:find(string.char(0xB2), 1, true) then
      return true
    end
  end
  return false
end

function Audio._forgetSeSource(src)
  if not src then return end
  local meta = Audio._seMeta[src]
  if meta and Audio._seByPlayer[meta.player] == src then
    Audio._seByPlayer[meta.player] = nil
  end
  Audio._seMeta[src] = nil
end

function Audio._stopSePlayer(mplay)
  mplay = tonumber(mplay)
  if not mplay then return end
  local src = Audio._seByPlayer[mplay]
  if not src then return end
  pcall(function() src:stop() end)
  Audio._forgetSeSource(src)
  for i = #Audio._seSources, 1, -1 do
    if Audio._seSources[i] == src then
      table.remove(Audio._seSources, i)
    end
  end
end

function Audio.stopSe(id)
  if id == nil then
    for _, src in ipairs(Audio._seSources) do
      pcall(function() src:stop() end)
      Audio._forgetSeSource(src)
    end
    Audio._seSources = {}
    Audio._seByPlayer = {}
    return
  end
  local SE = require("src.core.game3.se_ids")
  id = SE.resolve(id)
  for i = #Audio._seSources, 1, -1 do
    local src = Audio._seSources[i]
    local meta = Audio._seMeta[src]
    if meta and meta.id == id then
      pcall(function() src:stop() end)
      Audio._forgetSeSource(src)
      table.remove(Audio._seSources, i)
    end
  end
end

function Audio.isSePlaying(id)
  if id == nil then
    for _, src in ipairs(Audio._seSources) do
      if src:isPlaying() then return true end
    end
    return false
  end
  local SE = require("src.core.game3.se_ids")
  id = SE.resolve(id)
  for _, src in ipairs(Audio._seSources) do
    local meta = Audio._seMeta[src]
    if meta and meta.id == id and src:isPlaying() then return true end
  end
  return false
end

function Audio.waitSe(id, cb)
  -- Poll in update via callback list
  Audio._waitSe = Audio._waitSe or {}
  Audio._waitSe[#Audio._waitSe + 1] = { id = id, cb = cb }
end

function Audio.playFanfare(id)
  local SE = require("src.core.game3.se_ids")
  id = SE.resolve(id)
  if id == nil then return false end
  local info = Audio.songInfo(id) or {}
  local frames = info.fanfareFrames
  if not frames then
    local ff = Audio._pack and Audio._pack.index and Audio._pack.index.fanfares
    frames = ff and ff[id] and ff[id].frames or 160
  end
  -- Remember what to restore; fade/stop may have cleared the worker mid-fanfare.
  Audio._savedSong = Audio._savedSong
    or (Audio._currentSong and Audio._currentSong.id)
    or Audio._mapSong
  Audio.pauseBgm()
  Audio._fanfareActive = true
  Audio._fanfareFrames = frames
  -- Fanfares are sequenced songs (not a single voice0 sample).
  local slot = { voices = {} }
  if Audio.isReady() then
    if Player.start(Audio._pack, Audio._cache, slot, id, { forceSeq = true }) then
      local sd = Player.bakeSlot(slot, {
        master = (Audio._sfxVolume or 1) * (Audio._seBakeGain or 3.5),
        mono = Audio._mono,
        maxSec = math.max(1.5, (frames or 160) / 60 + 0.75),
      })
      if sd and love and love.audio and love.audio.newSource then
        local src = love.audio.newSource(sd, "static")
        src:setVolume(1)
        src:play()
        Audio._seSources[#Audio._seSources + 1] = src
      end
    end
  end
  log(string.format("playFanfare id=%s frames=%s", tostring(id), tostring(frames)))
  return true
end

function Audio.isFanfareFinished()
  return not Audio._fanfareActive
end

function Audio.waitFanfare(cb)
  Audio._waitFanfareCb = cb
  if not Audio._fanfareActive and cb then cb() end
end

function Audio.playCry(species, mode)
  species = tonumber(species) or species
  log(string.format("playCry species=%s", tostring(species)))
  if not Audio.isReady() then
    Audio._cryUntil = (Audio._cryClock or 0) + 64
    return true
  end
  local slot = Player.startCry(Audio._pack, species, { pitch = 1.0 })
  if not slot then
    Audio._cryUntil = (Audio._cryClock or 0) + 64
    return false
  end
  Audio._crySlot = slot
  local cry = slot.info
  local meta = nil
  if cry and cry.cryIndex ~= nil then
    local c = Audio._pack.index.cries[cry.cryIndex]
    if c then meta = Audio._pack.samples[c.sampleId] end
  end
  if meta then
    local src = Sample.makeSource(Audio._pack.samplesBin, meta, {
      volume = (Audio._sfxVolume or 1) * 0.9,
      rate = Mix.waveRate(meta.freq),
    })
    if src then
      src:play()
      Audio._crySource = src
      local dur = (meta.size or 4000) / Mix.waveRate(meta.freq)
      Audio._cryUntil = (Audio._cryClock or 0) + math.max(16, dur * 60)
    end
  end
  -- Duck BGM to 85/256
  Audio._duck = 85 / 256
  Audio._duckHold = 2
  if Audio._cmdCh then Audio._cmdCh:push({ cmd = "volume", volume = bgm_gain() }) end
  if Audio._bgmSource then Audio._bgmSource:setVolume(bgm_gain()) end
  return true
end

function Audio.tickCry(dt)
  Audio._cryClock = (Audio._cryClock or 0) + (dt or 1 / 60) * 60
end

function Audio.isCryFinished()
  -- Timer is authoritative once expired (love Source:isPlaying can stick in tests).
  if Audio._cryUntil and (Audio._cryClock or 0) >= Audio._cryUntil then
    return true
  end
  if Audio._crySource and Audio._crySource:isPlaying() then return false end
  if not Audio._cryUntil then return true end
  return (Audio._cryClock or 0) >= Audio._cryUntil
end

function Audio.stopCry()
  if Audio._crySource then pcall(function() Audio._crySource:stop() end) end
  Audio._crySource = nil
  Audio._cryUntil = nil
  Audio._duck = 1
end

function Audio.currentSong()
  return Audio._currentSong
end

function Audio.stopAll()
  stop_bgm_source()
  Audio.stopSe()
  Audio.stopCry()
  Audio._currentSong = nil
  Audio._fanfareActive = false
end

function Audio.update(dt)
  dt = dt or 1 / 60
  Audio.tickCry(dt)

  -- Fanfare countdown (frame-exact)
  if Audio._fanfareActive then
    Audio._fanfareFrames = (Audio._fanfareFrames or 0) - dt * 60
    if Audio._fanfareFrames <= 0 then
      Audio._fanfareActive = false
      local restore = Audio._savedSong or Audio._mapSong
      Audio._savedSong = nil
      -- If a stale fade/stop killed the worker, resume alone is silence —
      -- replay map/saved BGM. If still loaded, just unpause.
      if restore and (not Audio._bgmGen or Audio._bgmGen ~= restore) then
        Audio.playSong(restore, { restart = true })
      else
        Audio.resumeBgm()
      end
      local cb = Audio._waitFanfareCb
      Audio._waitFanfareCb = nil
      if cb then cb() end
    end
  end

  -- Cry duck restore
  if Audio._duckHold and Audio._duckHold > 0 then
    Audio._duckHold = Audio._duckHold - dt * 60
  elseif Audio._duck and Audio._duck < 1 and Audio.isCryFinished() then
    Audio._duck = 1
    if Audio._cmdCh then Audio._cmdCh:push({ cmd = "volume", volume = bgm_gain() }) end
    if Audio._bgmSource then Audio._bgmSource:setVolume(bgm_gain()) end
  end

  -- Fade out/in
  if Audio._fadeOut then
    local f = Audio._fadeOut
    f.t = f.t + dt
    local u = math.min(1, f.t / math.max(f.dur, 0.01))
    local stillSame = (f.gen == nil or f.gen == Audio._bgmGen)
      and (f.songId == nil or (Audio._currentSong and Audio._currentSong.id == f.songId))
    if stillSame and Audio._bgmSource then
      local vol = f.start * (1 - u) * (Audio._duck or 1)
      Audio._bgmSource:setVolume(vol)
    end
    if u >= 1 then
      -- Only stop if this fade still owns the current song (not a newer playSong).
      if stillSame then
        stop_bgm_source()
        Audio._currentSong = nil
      end
      Audio._fadeOut = nil
    end
  end
  if Audio._fadeIn and Audio._bgmSource then
    local f = Audio._fadeIn
    f.t = f.t + dt
    local u = math.min(1, f.t / math.max(f.dur, 0.01))
    Audio._bgmSource:setVolume(bgm_gain() * u)
    if u >= 1 then Audio._fadeIn = nil end
  end

  -- Pump worker buffers into QueueableSource without dropping.
  -- Dropping queued PCM while the sequencer has already advanced is what made
  -- songs start correct then race ahead (high/fast/early finish).
  Audio.pumpBgm()

  -- Sync BGM fallback
  if Audio._bgmLocal and Audio._bgmSource and not Audio._worker then
    local src = Audio._bgmSource
    local okFree, free = pcall(src.getFreeBufferCount, src)
    if okFree and type(free) == "number" and free > 0 then
      local n = Player.BUFFER_SAMPLES
      local sd = Player.renderBuffered(Audio._bgmLocal, n, {
        master = bgm_gain(),
        sampleRate = Mix.SAMPLE_RATE,
      })
      if sd then
        pcall(function()
          src:queue(sd)
          if not src:isPlaying() then src:play() end
        end)
      end
    end
  end

  -- waitSe callbacks
  if Audio._waitSe then
    local pending = {}
    for _, w in ipairs(Audio._waitSe) do
      if Audio.isSePlaying(w.id) then
        pending[#pending + 1] = w
      elseif w.cb then
        w.cb()
      end
    end
    Audio._waitSe = pending
  end
end

--- Drain worker → QueueableSource. Safe to call from focus/resume hooks.
function Audio.pumpBgm()
  if Audio._suspended then return end
  if not (Audio._outCh and Audio._bgmSource) or Audio._bgmPaused then return end
  local src = Audio._bgmSource
  local okFree, free = pcall(src.getFreeBufferCount, src)
  if not okFree or type(free) ~= "number" then free = 1 end

  local function accept(msg)
    if type(msg) ~= "table" or not msg.data then return true end
    if msg.gen ~= nil and msg.gen ~= Audio._bgmGen then return true end
    local ok = pcall(src.queue, src, msg.data)
    if not ok then return false end
    if not src:isPlaying() then
      pcall(function()
        src:setVolume(bgm_gain())
        src:play()
      end)
    end
    return true
  end

  if Audio._pendingBgm then
    if free > 0 and accept(Audio._pendingBgm) then
      Audio._pendingBgm = nil
      free = free - 1
    elseif free <= 0 then
      free = 0
    else
      free = 0
    end
  end

  while free > 0 do
    local msg = Audio._outCh:pop()
    if not msg then break end
    if accept(msg) then
      free = free - 1
    else
      Audio._pendingBgm = msg
      break
    end
  end
end

function Audio.setSuspended(flag)
  Audio._suspended = not not flag
end

--- After focus regain / audio device reset: refill hard and restart if drained.
function Audio.onFocusGained()
  Audio._suspended = false
  if not Audio._bgmGen or Audio._bgmPaused then return end
  -- Worker kept synthesizing into the Channel while the main pump stalled;
  -- drain everything we can into the still-valid QueueableSource.
  for _ = 1, 16 do
    Audio.pumpBgm()
  end
  if Audio._bgmSource then
    pcall(function()
      Audio._bgmSource:setVolume(bgm_gain())
      if not Audio._bgmSource:isPlaying() then Audio._bgmSource:play() end
    end)
  end
end

--- Device reset: QueueableSource may be dead — rebuild then refill.
function Audio.rebuildPlayback()
  Audio._suspended = false
  if not (love and love.audio and love.audio.newQueueableSource) then return false end
  if not Audio._bgmGen then return true end
  local ok, src = pcall(
    love.audio.newQueueableSource,
    Audio._bgmRate or Mix.SAMPLE_RATE, 16, 2, Player.BUFFER_COUNT)
  if not ok or not src then return false end
  local old = Audio._bgmSource
  Audio._bgmSource = src
  Audio._pendingBgm = nil
  if old then pcall(function() old:stop() end) end
  if Audio._outCh then Audio._outCh:clear() end
  -- Ask worker to keep producing; drain whatever arrives next frames.
  for _ = 1, 4 do Audio.pumpBgm() end
  pcall(function()
    src:setVolume(bgm_gain())
    src:play()
  end)
  return true
end

return Audio
