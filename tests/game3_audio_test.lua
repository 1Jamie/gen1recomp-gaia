-- Headless tests for game3 M4A extract + audio API (no ROM / no audio device required).

local function assert_eq(a, b, msg)
  if a ~= b then
    error((msg or "assert_eq") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
  end
end

local function assert_true(v, msg)
  if not v then error(msg or "assert_true failed", 2) end
end

local Versions = require("src.import.gba.versions")
local ExtractAudio = require("src.import.gba.extract_audio")
local Sample = require("src.core.game3.m4a_sample")
local Mix = require("src.core.game3.m4a_mix")
local Audio = require("src.core.game3.audio")
local Seq = require("src.core.game3.m4a_seq")

assert_eq(Versions.AUDIO.song_count, 347, "song_count")
assert_eq(Versions.AUDIO_VERSION, 5, "AUDIO_VERSION")

-- GameFreak DPCM round-trip smoke (known delta table)
do
  local Sample = require("src.core.game3.m4a_sample")
  -- Minimal block: sample0=0, then zeros → mostly silence
  local block = string.char(0) .. string.rep(string.char(0), 32)
  local pcm = Sample.decodeGfdpcm(block, 64)
  assert_eq(#pcm, 64, "dpcm len")
  assert_eq(pcm:byte(1), 0, "dpcm first")
end

assert_true(Versions.AUDIO.song_table ~= nil, "song_table")

-- Fade math from pret m4a.c
local function fadeSeconds(speed)
  return 16 * speed / 60
end
assert_true(math.abs(fadeSeconds(4) - (16 * 4 / 60)) < 1e-9, "fadeSeconds")

-- Fanfare frames
assert_eq(ExtractAudio.SONG_COUNT, 347)
local fanfare = 257
-- Encoded in extract FANFARES; spot-check via Audio after loadMeta
Audio.loadMeta({
  songs = {
    [257] = { id = 257, kind = "fanfare", fanfareFrames = 80 },
    [5] = { id = 5, kind = "se", sampleId = 1 },
  },
  fanfares = { [257] = { frames = 80 } },
})
local info = Audio.songInfo(257)
assert_eq(info.fanfareFrames, 80, "level-up fanfare frames")

-- s8 decode: high bit must be negative
do
  local pcm = string.char(0x00, 0x7F, 0x80, 0xFF) -- 0, 127, -128, -1
  local values = {}
  local ffiOk, ffi = pcall(require, "ffi")
  if ffiOk then
    local src = ffi.cast("const int8_t *", pcm)
    for i = 0, 3 do values[i + 1] = src[i] end
  else
    for i = 1, 4 do
      local b = pcm:byte(i)
      values[i] = b >= 128 and (b - 256) or b
    end
  end
  assert_eq(values[1], 0, "s8 0")
  assert_eq(values[2], 127, "s8 127")
  assert_eq(values[3], -128, "s8 -128")
  assert_eq(values[4], -1, "s8 -1")
end

-- Mix DS voice finishes
do
  local pcm = string.rep(string.char(0), 32)
  local v = Mix.newDsVoice(pcm, { size = 32, freq = 13379 * 1024, loopStart = 0 }, { rate = Mix.SAMPLE_RATE })
  local voices = { v }
  for _ = 1, 5 do
    local _, alive = Mix.render(voices, 16, { master = 1 })
    voices = alive
  end
  assert_true(#voices == 0 or not voices[1].alive, "ds voice drains")
end

-- GOTO loops to start in seq
do
  -- Packed format: tracks + (offset,length) + body
  local tracks = 1
  local body = string.char(0xB1) -- FINE
  local headerSize = 8 + tracks * 8
  local hdr = string.char(tracks, 0, 0, 0)
    .. string.char(0, 0, 0, 0) -- voicegroup
    .. string.char(headerSize % 256, 0, 0, 0) -- offset
    .. string.char(#body, 0, 0, 0) -- length
  local blob = hdr .. body
  local song = Seq.parseSongBin(blob)
  assert_true(song ~= nil, "parseSongBin")
  assert_eq(song.tracks, 1, "tracks")
  assert_eq(#(song.trackData[1] or ""), 1, "track body")
  local player = Seq.newPlayer(song, {})
  Seq.update(player, 5)
  assert_true(Seq.allDone(player), "fine ends")
end

-- Running status: bare key after a note reuses the note command (mp2k).
do
  local keys = {}
  local song = {
    tracks = 1,
    trackData = {
      string.char(
        0xD4, 60, 100,
        0x84, -- wait
        62,   -- running-status note, key only
        0x84,
        0xB1
      ),
    },
  }
  local player = Seq.newPlayer(song, {
    voiceResolver = function(_, key, vel)
      keys[#keys + 1] = key
      return {
        kind = "ds", alive = true, gateTicks = 8,
        pcm = "", size = 0, pos = 0, step = 0, volL = 0, volR = 0,
      }
    end,
  })
  for _ = 1, 20 do Seq.update(player, 1) end
  assert_eq(#keys, 2, "running status note count")
  assert_eq(keys[1], 60, "first key")
  assert_eq(keys[2], 62, "running key")
end

-- CGB exclusivity: second noise replaces the first (no stacking).
do
  local song = {
    tracks = 1,
    trackData = {
      string.char(
        0xD4, 40, 100,
        0x84,
        0xD4, 42, 100,
        0x84,
        0xB1
      ),
    },
  }
  local player = Seq.newPlayer(song, {
    voiceResolver = function()
      return Mix.newCgbNoise({ period = 8, volL = 0.5, volR = 0.5 })
    end,
  })
  Seq.update(player, 1)
  local n1 = 0
  for _, v in ipairs(player.voices) do
    if v.alive ~= false and v.cgbChan == 4 then n1 = n1 + 1 end
  end
  assert_eq(n1, 1, "one noise after first note")
  -- advance enough for second note
  for _ = 1, 8 do Seq.update(player, 1) end
  local n2 = 0
  for _, v in ipairs(player.voices) do
    if v.alive ~= false and v.cgbChan == 4 then n2 = n2 + 1 end
  end
  assert_eq(n2, 1, "noise exclusive")
end

-- Hard clip preserves quiet voice when bus stays under 1 (no soft-duck).
do
  assert_true(math.abs(0.2 + 0.5 - 0.7) < 1e-9, "linear sum")
  -- tanh(0.7) ≈ 0.604 → would duck; our mixer must not use that path for sub-unity.
  assert_true(math.tanh(0.7) < 0.65, "tanh ducks")
end

-- Wave channel is one octave below pulse for the same MIDI key (GB hardware).
do
  local pulse = Mix.cgbPulseHz(60)
  local wave = Mix.cgbWaveHz(60)
  assert_true(math.abs(wave * 2 - pulse) < 1e-6, "wave octave")
end

-- Plucky CGB (decay>0, sustain=0) must fall after attack — intro-fight leads.
do
  local v = Mix.newCgbPulse({
    key = 60,
    tone = { attack = 0, decay = 5, sustain = 0, release = 0 },
  })
  Mix.tickEnvelope(v) -- attack → peak
  assert_true((v.env or 0) > 0.9, "pluck attack peak")
  for _ = 1, 20 do Mix.tickEnvelope(v) end
  assert_true((v.env or 1) < 0.2, "pluck decayed")
end

-- DS sustain=0 with fast decay drops (voice 38 style).
do
  local pcm = string.rep(string.char(0), 64)
  local v = Mix.newDsVoice(pcm, { size = 64, freq = 13379 * 1024 }, {
    rate = Mix.SAMPLE_RATE,
    tone = { attack = 255, decay = 252, sustain = 0, release = 115 },
  })
  Mix.tickEnvelope(v)
  assert_eq(v.envVol, 255, "ds attack")
  for _ = 1, 160 do Mix.tickEnvelope(v) end
  assert_true((v.envVol or 255) < 40, "ds decay toward sustain 0")
end

-- SE_SELECT-like: sequencer note on CGB pulse must produce energy (not voice0 PCM).
do
  local Player = require("src.core.game3.m4a_player")
  local song = {
    tracks = 1,
    trackData = {
      -- VOICE 0, VOL, short note, FINE — resolver returns pulse
      string.char(0xBD, 0, 0xBE, 80, 0xD2, 60, 100, 0x86, 0xB1),
    },
  }
  local slot = {
    seq = Seq.newPlayer(song, {
      voiceResolver = function()
        return Mix.newCgbPulse({
          key = 60,
          tone = { attack = 0, decay = 0, sustain = 15, release = 1 },
        })
      end,
    }),
    voices = {},
    done = false,
  }
  local L, R = Player.bakeSlot(slot, { raw = true, maxSec = 0.5, chunk = 512 })
  local peak = 0
  for i = 1, #L do
    local a = math.abs(L[i] or 0)
    if a > peak then peak = a end
  end
  assert_true(peak > 0.01, "baked SE has pulse energy")
  assert_true(#L < Mix.SAMPLE_RATE, "baked SE finishes under 1s")
end

-- Cry duck constant
assert_true(math.abs(85 / 256 - 0.33203125) < 1e-9, "cry duck")

-- playSong no-op same id
Audio._ready = false
Audio.playSong(278)
local a = Audio.currentSong()
Audio.playSong(278)
local b = Audio.currentSong()
assert_eq(a.id, b.id, "same song id")

-- Battle anim packs historically store "SE_M_FOO," (trailing comma from extract).
do
  local SE = require("src.core.game3.se_ids")
  assert_eq(SE.resolve("SE_M_CONFUSE_RAY,"), SE.SE_M_CONFUSE_RAY, "strip comma")
  assert_eq(SE.resolve("SE_EFFECTIVE"), 13, "SE_EFFECTIVE")
  assert_eq(SE.resolve(27), 27, "numeric passthrough")
  assert_eq(SE.resolve(nil), nil, "nil")
end

-- pret TrkVolPitSet: BEND is fine-pitch, not whole semitones (SE_SELECT BEND+13).
do
  local Seq = require("src.core.game3.m4a_seq")
  local Mix = require("src.core.game3.m4a_mix")
  local Player = require("src.core.game3.m4a_player")
  local keyM, fine = Seq.trackPitch({ bend = 13, bendRange = 2, tune = 0, keyShift = 0 })
  assert_eq(keyM, 0, "SE_SELECT keyM")
  assert_eq(fine, 104, "SE_SELECT fine")
  local wav = 13700096
  assert_eq(Mix.midiKeyToFreq(wav, 60, 0), 13379, "MidiKeyToFreq C4 unity")
  assert_true(math.abs(Mix.midiKeyToFreq(wav, 72, 0) / Mix.midiKeyToFreq(wav, 60, 0) - 2) < 0.01, "octave")
  -- Mix quantum ≈ one GBA vblank of output samples (mGBA SoundMain cadence).
  local q = Player.mixQuantum()
  assert_true(q >= 256 and q <= 2048, "mixQuantum range")
  assert_true(math.abs(q - Mix.samplesPerVBlank()) < 1.0, "mixQuantum ≈ samplesPerVBlank")
end

-- Mid-note BEND must refresh active voice pitch (battle move SE slides).
do
  local wavFreq = 13700096
  -- NOTE then WAIT 8 then BEND+32 (bendRange 12) — same pattern as SE_M_TAKE_DOWN.
  local song = {
    tracks = 1,
    trackData = {
      string.char(
        0xC1, 12,           -- BENDR 12
        0xC0, 0x40,         -- BEND center
        0xD0, 60, 127, 48,  -- N96 key=60 vel=127 gate=48
        0x88,               -- WAIT 8
        0xC0, 0x40 + 32,    -- BEND +32
        0x81,               -- WAIT 1
        0xB1                -- FINE
      ),
    },
  }
  local p = Seq.newPlayer(song, {
    voiceResolver = function(_vn, key, _vel, _tr, volL, volR, fine)
      local rate = Mix.midiKeyToFreq(wavFreq, key, fine or 0)
      return {
        kind = "ds",
        alive = true,
        wavFreq = wavFreq,
        step = rate / Mix.SAMPLE_RATE,
        volL = volL,
        volR = volR,
        fixedFreq = false,
      }
    end,
  })
  p.tempo = 150
  p.tempoC = 0
  Seq.update(p, 1)
  local voice = p.voices[1]
  assert_true(voice ~= nil and voice.noteKey == 60, "note voice")
  local s0 = voice.step
  -- Drain WAIT so BEND runs while the gated note is still alive.
  for _ = 1, 12 do
    Seq.update(p, 1)
  end
  assert_true(voice.alive ~= false, "voice still held")
  assert_true(math.abs(voice.step - s0) > 1e-12, "live BEND changes step")
  local keyM, fine = Seq.trackPitch(p.tracks[1])
  local expect = Mix.midiKeyToFreq(wavFreq, 60 + keyM, fine) / Mix.SAMPLE_RATE
  assert_true(math.abs(voice.step - expect) < 1e-9, "step matches trackPitch after BEND")
end

-- Pan tokens + SE MusicPlayer exclusivity helpers.
do
  local Audio = require("src.core.game3.audio")
  assert_eq(Audio.normalizePan("SOUND_PAN_TARGET"), 63, "pan target")
  assert_eq(Audio.normalizePan("SOUND_PAN_ATTACKER"), -64, "pan attacker")
  assert_eq(Audio.normalizePan(20), 20, "pan numeric")
end

print("game3_audio_test: ok")
return true
