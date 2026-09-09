-- Minimal MP2K/M4A track bytecode interpreter (GOTO = native loop).
-- Sequencer advances in GBA VBlank units (MPlayMain), not wall-clock 60Hz guesses.

local Mix = require("src.core.game3.m4a_mix")

local Seq = {}

-- Matches pret gClockTable (0-based). Waits: [cmd-0x80]; Notes: [cmd-0xCF].
local CLOCK = {
  [0] = 0,
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
  16, 17, 18, 19, 20, 21, 22, 23, 24, 28, 30, 32, 36, 40, 42, 44,
  48, 52, 54, 56, 60, 64, 66, 68, 72, 76, 78, 80, 84, 88, 90, 92, 96,
}

local function clock_at(idx)
  idx = tonumber(idx) or 0
  if idx < 0 then idx = 0 end
  return CLOCK[idx] or idx
end

local function u8(blob, off)
  if off < 0 or off >= #blob then return nil end
  return blob:byte(off + 1)
end

local function u32le(blob, off)
  local b0 = u8(blob, off)
  if not b0 then return nil end
  return b0 + (u8(blob, off + 1) or 0) * 256
    + (u8(blob, off + 2) or 0) * 65536
    + (u8(blob, off + 3) or 0) * 16777216
end

function Seq.parseSongBin(blob)
  if type(blob) ~= "string" or #blob < 8 then return nil end
  local tracks = u8(blob, 0) or 0
  if tracks > 16 then tracks = 0 end
  local out = {
    tracks = tracks,
    blocks = u8(blob, 1),
    priority = u8(blob, 2),
    reverb = u8(blob, 3),
    voicegroup = u32le(blob, 4),
    trackData = {},
  }
  if tracks == 0 then return out end

  local first = u32le(blob, 8) or 0
  local packed = first > 0 and first < #blob and first < 0x01000000

  if packed then
    for t = 0, tracks - 1 do
      local base = 8 + t * 8
      local off = u32le(blob, base) or 0
      local len = u32le(blob, base + 4) or 0
      if off > 0 and len > 0 and off + len <= #blob then
        out.trackData[t + 1] = blob:sub(off + 1, off + len)
      else
        out.trackData[t + 1] = ""
      end
    end
    return out
  end

  local headerSize = 8 + tracks * 4
  local ptrs = {}
  for t = 0, tracks - 1 do
    ptrs[#ptrs + 1] = { idx = t, ptr = u32le(blob, 8 + t * 4) or 0 }
  end
  table.sort(ptrs, function(a, b) return a.ptr < b.ptr end)
  local cursor = headerSize
  local packedOff = {}
  for i, p in ipairs(ptrs) do
    local remainTracks = #ptrs - i + 1
    local remainBytes = #blob - cursor
    local approx = math.floor(remainBytes / remainTracks)
    if ptrs[i + 1] and p.ptr > 0 and ptrs[i + 1].ptr > p.ptr then
      approx = math.min(approx, ptrs[i + 1].ptr - p.ptr)
    end
    approx = math.max(16, math.min(approx, remainBytes))
    packedOff[p.idx] = { off = cursor, len = approx }
    cursor = cursor + approx
  end
  for t = 0, tracks - 1 do
    local p = packedOff[t]
    if p then
      out.trackData[t + 1] = blob:sub(p.off + 1, p.off + p.len)
    else
      out.trackData[t + 1] = ""
    end
  end
  return out
end

local function new_track(data)
  return {
    data = data or "",
    pc = 0,
    wait = 0,
    done = false,
    key = 60,
    vel = 127,
    voice = 0,
    volume = 100,
    pan = 0x40,
    bend = 0,
    bendRange = 2, -- pret MPlayTrack init
    tune = 0,      -- signed, C_V center = 0
    keyShift = 0,
    callStack = {},
    -- pret: commands >= 0xBD update runningStatus; bytes < 0x80 reuse it.
    runningStatus = nil,
  }
end

--- pret TrkVolPitSet pitch half: keyM (semitones) + fine (0..255).
function Seq.trackPitch(tr)
  local bend = (tr.bend or 0) * (tr.bendRange or 2)
  local tune = tr.tune or 0
  local keyShift = tr.keyShift or 0
  local x = (tune + bend) * 4 + (keyShift * 256)
  return math.floor(x / 256), (x % 256)
end

function Seq.newPlayer(song, opts)
  opts = opts or {}
  local tracks = {}
  for i = 1, (song and song.tracks) or 0 do
    tracks[i] = new_track(song.trackData[i])
  end
  return {
    song = song,
    tracks = tracks,
    tempo = 150, -- tempoD
    tempoC = 0,
    voices = {},
    voiceResolver = opts.voiceResolver,
    muted = false,
  }
end

local function track_read(tr)
  if tr.pc >= #tr.data then
    tr.done = true
    return nil
  end
  local b = tr.data:byte(tr.pc + 1)
  tr.pc = tr.pc + 1
  return b
end

local function track_unread(tr)
  if tr.pc > 0 then tr.pc = tr.pc - 1 end
end

local function track_read32(tr)
  local b0 = track_read(tr) or 0
  local b1 = track_read(tr) or 0
  local b2 = track_read(tr) or 0
  local b3 = track_read(tr) or 0
  return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216
end

local MAX_DS = 12

--- pret MPlayMain: after BEND/VOL/PAN, TrkVolPitSet + rewrite active channel freqs.
local function refresh_track_voices(player, tr)
  if not tr then return end
  local keyM, fine = Seq.trackPitch(tr)
  for _, v in ipairs(player.voices) do
    if v.track == tr and v.alive ~= false then
      if tr._volDirty then
        local nvel = v.noteVel or tr.vel or 127
        local vol = (tr.volume or 100) / 127 * (nvel / 127)
        local pan = ((tr.pan or 0x40) - 0x40) / 64
        v.volL = vol * (0.5 - pan * 0.5)
        v.volR = vol * (0.5 + pan * 0.5)
      end
      if tr._pitchDirty and not v.fixedFreq then
        local noteKey = v.noteKey or 60
        local absKey = noteKey + keyM
        if absKey < 0 then absKey = 0 end
        if absKey > 178 then absKey = 178 end
        if v.kind == "ds" and v.wavFreq then
          local rate = Mix.midiKeyToFreq(v.wavFreq, absKey, fine)
          if rate >= 100 then
            v.step = rate / Mix.SAMPLE_RATE
          end
        elseif v.kind == "cgb_pulse" then
          local period = Mix.cgbPeriod(absKey, fine)
          v.periodReg = period
          if not v.sweepEnabled then
            v.freq = Mix.periodToPulseHz(period)
          else
            -- Hardware sweep owns the shadow; still retarget from note pitch.
            v.sweepShadow = period
            v.freq = Mix.periodToPulseHz(period)
          end
        elseif v.kind == "cgb_wave" then
          v.freq = Mix.cgbWaveHz(absKey, fine)
        elseif v.kind == "cgb_noise" then
          v.period = Mix.cgbNoisePeriod(absKey)
        end
      end
    end
  end
  tr._pitchDirty = false
  tr._volDirty = false
end

local function start_note(player, tr, key, vel, gate)
  vel = vel or tr.vel or 100
  local vol = (tr.volume or 100) / 127 * (vel / 127)
  local pan = ((tr.pan or 0x40) - 0x40) / 64
  local volL = vol * (0.5 - pan * 0.5)
  local volR = vol * (0.5 + pan * 0.5)
  if not player.voiceResolver then return end
  local rawKey = tonumber(key) or 60
  local keyM, fine = Seq.trackPitch(tr)
  local absKey = rawKey + keyM
  if absKey < 0 then absKey = 0 end
  if absKey > 178 then absKey = 178 end
  -- Resolver gets absKey for initial freq; we store raw note key for live BEND.
  local voice = player.voiceResolver(tr.voice, absKey, vel, tr, volL, volR, fine)
  if voice then
    gate = tonumber(gate) or 0
    if gate < 1 then gate = 1 end
    voice.gateTicks = gate
    voice.track = tr
    voice.noteKey = rawKey
    voice.noteVel = vel

    -- CGB: one hardware channel each — new note replaces prior occupant.
    if voice.cgbChan then
      for _, v in ipairs(player.voices) do
        if v.cgbChan == voice.cgbChan then
          v.alive = false
        end
      end
    elseif voice.kind == "ds" then
      -- DirectSound: pret maxChans (FireRed typically ≤12). Steal oldest.
      local ds = {}
      for _, v in ipairs(player.voices) do
        if v.alive ~= false and v.kind == "ds" then
          ds[#ds + 1] = v
        end
      end
      while #ds >= MAX_DS do
        local victim = table.remove(ds, 1)
        if victim then victim.alive = false end
      end
    end

    player.voices[#player.voices + 1] = voice
  end
end

local function ply_note(player, tr, cmd)
  local gate = clock_at(cmd - 0xCF)
  local key = track_read(tr)
  if not key then return end
  if key >= 0x80 then
    track_unread(tr)
    key = tr.key or 60
  else
    tr.key = key
    local vel = track_read(tr)
    if not vel then
      start_note(player, tr, key, tr.vel or 0x7F, gate)
      return
    end
    if vel >= 0x80 then
      track_unread(tr)
    else
      tr.vel = vel
      local add = track_read(tr)
      if not add then
        start_note(player, tr, key, vel, gate)
        return
      end
      if add >= 0x80 then
        track_unread(tr)
      else
        gate = gate + add
      end
    end
  end
  start_note(player, tr, key, tr.vel or 0x7F, gate)
end

local function exec_cmd(player, tr, cmd)
  if cmd == 0xB1 then
    tr.done = true
  elseif cmd == 0xB2 then
    local addr = track_read32(tr)
    tr.pc = (addr < #tr.data) and addr or 0
  elseif cmd == 0xB3 then
    local addr = track_read32(tr)
    tr.callStack[#tr.callStack + 1] = tr.pc
    if addr < #tr.data then tr.pc = addr end
  elseif cmd == 0xB4 then
    if #tr.callStack > 0 then tr.pc = table.remove(tr.callStack) end
  elseif cmd == 0xB5 then
    track_read(tr)
    local addr = track_read32(tr)
    tr.callStack[#tr.callStack + 1] = tr.pc
    if addr < #tr.data then tr.pc = addr end
  elseif cmd == 0xBB then
    local t = track_read(tr) or 75
    if t < 1 then t = 75 end
    player.tempo = t * 2
  elseif cmd == 0xBC then
    tr.keyShift = track_read(tr) or 0
    if tr.keyShift > 127 then tr.keyShift = tr.keyShift - 256 end
    tr._pitchDirty = true
  elseif cmd == 0xBD then
    tr.voice = track_read(tr) or 0
  elseif cmd == 0xBE then
    tr.volume = track_read(tr) or 100
    tr._volDirty = true
  elseif cmd == 0xBF then
    tr.pan = track_read(tr) or 0x40
    tr._volDirty = true
  elseif cmd == 0xC0 then
    tr.bend = (track_read(tr) or 0x40) - 0x40
    tr._pitchDirty = true
  elseif cmd == 0xC1 then
    tr.bendRange = track_read(tr) or 2
    tr._pitchDirty = true
  elseif cmd == 0xC8 then
    -- TUNE: signed around 0x40 (C_V)
    tr.tune = (track_read(tr) or 0x40) - 0x40
    tr._pitchDirty = true
  elseif cmd == 0xCD then
    -- Extended commands: CD <op> <args…>. Arity from pret gXcmdTable.
    local xop = track_read(tr) or 0
    local xargs = ({
      [0] = 0,  -- xxx
      [1] = 4,  -- xwave (pointer)
      [2] = 1,  -- xtype
      [3] = 0,  -- unused
      [4] = 1,  -- xatta
      [5] = 1,  -- xdeca
      [6] = 1,  -- xsust
      [7] = 1,  -- xrele
      [8] = 1,  -- xiecv
      [9] = 1,  -- xiecl
      [10] = 1, -- xleng
      [11] = 1, -- xswee
      [12] = 2, -- xwait (u16)
      [13] = 4, -- xcmd_0D
    })[xop] or 1
    for _ = 1, xargs do track_read(tr) end
  elseif cmd == 0xCE then -- endtie: release this track's notes only
    for _, v in ipairs(player.voices) do
      if v.track == tr then
        Mix.releaseVoice(v)
      end
    end
  elseif cmd >= 0xCF then
    ply_note(player, tr, cmd)
  elseif cmd >= 0x80 and cmd <= 0xB0 then
    tr.wait = clock_at(cmd - 0x80)
  elseif cmd == 0xBA or cmd == 0xC2 or cmd == 0xC3 or cmd == 0xC4
      or cmd == 0xC5 or cmd == 0xC6 or cmd == 0xC7
      or cmd == 0xC9 or cmd == 0xCA or cmd == 0xCB or cmd == 0xCC
      or cmd == 0xB9 then
    -- PRIO/LFOS/LFODL/MOD/MODT/… (1 arg); runningStatus already set if >= 0xBD
    track_read(tr)
  end
end

local function tick_track(player, tr)
  if tr.done then return end
  if tr.wait and tr.wait > 0 then
    tr.wait = tr.wait - 1
    return
  end
  local guard = 0
  while not tr.done and (not tr.wait or tr.wait <= 0) and guard < 64 do
    guard = guard + 1
    if tr.pc >= #tr.data then
      tr.done = true
      break
    end
    local b = tr.data:byte(tr.pc + 1)
    local cmd
    if b < 0x80 then
      -- Running status: data byte stays for the command handler (ply_note reads key).
      cmd = tr.runningStatus
      if not cmd or cmd < 0x80 then
        -- No status yet — skip orphan data byte.
        tr.pc = tr.pc + 1
        break
      end
    else
      tr.pc = tr.pc + 1
      cmd = b
      -- pret: only cmds >= 0xBD update runningStatus
      if cmd >= 0xBD then
        tr.runningStatus = cmd
      end
    end
    exec_cmd(player, tr, cmd)
    if tr._pitchDirty or tr._volDirty then
      refresh_track_voices(player, tr)
    end
    if tr.wait and tr.wait > 0 then
      tr.wait = tr.wait - 1
      break
    end
  end
end

local function seq_tick(player)
  -- Age gates / envelopes at the start of the vblank (then new notes are added after).
  for _, v in ipairs(player.voices) do
    if v.gateTicks then
      v.gateTicks = v.gateTicks - 1
      if v.gateTicks <= 0 then
        Mix.releaseVoice(v)
      end
    end
    Mix.tickEnvelope(v)
  end
  for _, tr in ipairs(player.tracks) do
    tick_track(player, tr)
  end
  -- New notes get one envelope step so attack=instant voices are audible this frame.
  for _, v in ipairs(player.voices) do
    if v.adsr and v.envPhase == "attack" and (v.envVol or 0) == 0 then
      Mix.tickEnvelope(v)
    end
  end
end

--- Advance by GBA VBlank units (one MPlayMain ≈ one vblank at 13379 Hz / 224 spv).
function Seq.update(player, vblanks)
  vblanks = tonumber(vblanks) or 1
  if not player or player.muted then return player and player.voices or {} end
  if vblanks <= 0 then return player.voices end

  local tempoI = player.tempo or 150
  player.tempoC = (player.tempoC or 0) + tempoI * vblanks
  local guard = 0
  while player.tempoC >= 150 and guard < 64 do
    guard = guard + 1
    player.tempoC = player.tempoC - 150
    seq_tick(player)
  end

  local alive = {}
  for _, v in ipairs(player.voices) do
    if v.alive ~= false then alive[#alive + 1] = v end
  end
  player.voices = alive
  return alive
end

function Seq.allDone(player)
  if not player then return true end
  for _, tr in ipairs(player.tracks) do
    if not tr.done then return false end
  end
  return #player.voices == 0
end

return Seq
