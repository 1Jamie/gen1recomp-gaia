-- DirectSound + lightweight CGB mix for game3 M4A.
-- Output rate matches ChipSynth / QueueableSource; sequencer paced in GBA vblanks.

local Mix = {}

-- FireRed m4aSoundMode: SOUND_MODE_FREQ_13379 → 224 PCM samples per VBlank.
Mix.GBA_MIX_RATE = 13379
Mix.GBA_SAMPLES_PER_VBLANK = 224
-- True GBA refresh: 13379/224 ≈ 59.7275 Hz (not 60).
Mix.GBA_VBLANK_HZ = Mix.GBA_MIX_RATE / Mix.GBA_SAMPLES_PER_VBLANK

local function load_chip_synth()
  -- love.thread workers often cannot resolve package.path requires; mirror chip_worker.
  if love and love.filesystem and love.filesystem.load then
    local ok, mod = pcall(function()
      return assert(love.filesystem.load("src/core/ChipSynth.lua"))()
    end)
    if ok and type(mod) == "table" then return mod end
  end
  local ok, mod = pcall(require, "src.core.ChipSynth")
  if ok and type(mod) == "table" then return mod end
  return nil
end

local ChipSynth = load_chip_synth()

-- Never fall back to a random rate (old 32768) — that desyncs QueueableSource vs SoundData.
Mix.SAMPLE_RATE = (ChipSynth and ChipSynth.SAMPLE_RATE) or 44100

function Mix.setSampleRate(rate)
  rate = tonumber(rate)
  if not rate or rate < 8000 or rate > 48000 then return Mix.SAMPLE_RATE end
  Mix.SAMPLE_RATE = math.floor(rate)
  return Mix.SAMPLE_RATE
end

--- How many output samples equal one GBA VBlank (one MPlayMain call).
function Mix.samplesPerVBlank()
  return Mix.SAMPLE_RATE * Mix.GBA_SAMPLES_PER_VBLANK / Mix.GBA_MIX_RATE
end

--- Convert an output PCM length into GBA VBlank units for the sequencer.
function Mix.vblanksForSamples(n)
  n = tonumber(n) or 0
  if n <= 0 then return 0 end
  return n / Mix.samplesPerVBlank()
end

local DUTY = {
  [0] = { 0.125, 1, -1 },
  [1] = { 0.25, 1, -1 },
  [2] = { 0.5, 1, -1 },
  [3] = { 0.75, 1, -1 },
}

-- pret gCgbScaleTable / gCgbFreqTable / gNoiseTable (m4a_tables.c)
local CGB_SCALE = {
  [0]=0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0A,0x0B,
  0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,0x18,0x19,0x1A,0x1B,
  0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,0x29,0x2A,0x2B,
  0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x3B,
  0x40,0x41,0x42,0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x4A,0x4B,
  0x50,0x51,0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5A,0x5B,
  0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6A,0x6B,
  0x70,0x71,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B,
  0x80,0x81,0x82,0x83,0x84,0x85,0x86,0x87,0x88,0x89,0x8A,0x8B,
  0x90,0x91,0x92,0x93,0x94,0x95,0x96,0x97,0x98,0x99,0x9A,0x9B,
  0xA0,0xA1,0xA2,0xA3,0xA4,0xA5,0xA6,0xA7,0xA8,0xA9,0xAA,0xAB,
}

local CGB_FREQ = {
  [0]=-2004,-1891,-1785,-1685,-1591,-1501,-1417,-1337,-1262,-1192,-1125,-1062,
}

local NOISE_TABLE = {
  [0]=0xD7,0xD6,0xD5,0xD4,0xC7,0xC6,0xC5,0xC4,
  0xB7,0xB6,0xB5,0xB4,0xA7,0xA6,0xA5,0xA4,
  0x97,0x96,0x95,0x94,0x87,0x86,0x85,0x84,
  0x77,0x76,0x75,0x74,0x67,0x66,0x65,0x64,
  0x57,0x56,0x55,0x54,0x47,0x46,0x45,0x44,
  0x37,0x36,0x35,0x34,0x27,0x26,0x25,0x24,
  0x17,0x16,0x15,0x14,0x07,0x06,0x05,0x04,
  0x03,0x02,0x01,0x00,
}

local NOISE_DIV = { [0]=8, 16, 32, 48, 64, 80, 96, 112 }

-- pret gScaleTable / gFreqTable for MidiKeyToFreq (DirectSound)
local DS_SCALE = {
  [0]=0xE0,0xE1,0xE2,0xE3,0xE4,0xE5,0xE6,0xE7,0xE8,0xE9,0xEA,0xEB,
  0xD0,0xD1,0xD2,0xD3,0xD4,0xD5,0xD6,0xD7,0xD8,0xD9,0xDA,0xDB,
  0xC0,0xC1,0xC2,0xC3,0xC4,0xC5,0xC6,0xC7,0xC8,0xC9,0xCA,0xCB,
  0xB0,0xB1,0xB2,0xB3,0xB4,0xB5,0xB6,0xB7,0xB8,0xB9,0xBA,0xBB,
  0xA0,0xA1,0xA2,0xA3,0xA4,0xA5,0xA6,0xA7,0xA8,0xA9,0xAA,0xAB,
  0x90,0x91,0x92,0x93,0x94,0x95,0x96,0x97,0x98,0x99,0x9A,0x9B,
  0x80,0x81,0x82,0x83,0x84,0x85,0x86,0x87,0x88,0x89,0x8A,0x8B,
  0x70,0x71,0x72,0x73,0x74,0x75,0x76,0x77,0x78,0x79,0x7A,0x7B,
  0x60,0x61,0x62,0x63,0x64,0x65,0x66,0x67,0x68,0x69,0x6A,0x6B,
  0x50,0x51,0x52,0x53,0x54,0x55,0x56,0x57,0x58,0x59,0x5A,0x5B,
  0x40,0x41,0x42,0x43,0x44,0x45,0x46,0x47,0x48,0x49,0x4A,0x4B,
  0x30,0x31,0x32,0x33,0x34,0x35,0x36,0x37,0x38,0x39,0x3A,0x3B,
  0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,0x28,0x29,0x2A,0x2B,
  0x10,0x11,0x12,0x13,0x14,0x15,0x16,0x17,0x18,0x19,0x1A,0x1B,
  0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0A,0x0B,
}

local DS_FREQ = {
  [0]=2147483648, 2275179671, 2410468894, 2553802834,
  2705659852, 2866546760, 3037000500, 3217589947,
  3408917802, 3611622603, 3826380858, 4053909305,
}

-- ChipSynth-style GB capacitor HPF (restores brightness vs DC-coupled bus).
local GB_CLOCK = 4194304
local function hpf_charge()
  return 0.999958 ^ (GB_CLOCK / Mix.SAMPLE_RATE)
end

local function midi_to_hz(key)
  key = tonumber(key) or 60
  return 440 * (2 ^ ((key - 69) / 12))
end

local function umul_hi32(a, b)
  -- high 32 bits of a*b for unsigned 32-bit operands (Lua number).
  a = tonumber(a) or 0
  b = tonumber(b) or 0
  if a < 0 then a = a + 4294967296 end
  if b < 0 then b = b + 4294967296 end
  return math.floor(a * b / 4294967296)
end

local function ds_scale_freq(key)
  key = math.floor(tonumber(key) or 60)
  if key < 0 then key = 0 end
  if key > 178 then key = 178 end
  local s = DS_SCALE[key] or 0
  return math.floor((DS_FREQ[s % 16] or 0) / (2 ^ math.floor(s / 16)))
end

--- pret MidiKeyToFreq → Q10 sample rate (divide by 1024 for Hz).
function Mix.midiKeyToFreq(wavFreq, key, fine)
  wavFreq = tonumber(wavFreq) or 0
  key = math.floor(tonumber(key) or 60)
  fine = math.floor(tonumber(fine) or 0)
  if fine < 0 then fine = 0 end
  if fine > 255 then fine = 255 end
  if key > 178 then
    key = 178
    fine = 255
  end
  if key < 0 then key = 0 end
  local val1 = ds_scale_freq(key)
  local val2 = ds_scale_freq(key + 1)
  local delta = val2 - val1
  -- pret: umul3232H32(delta, fine<<24); fine<<24 = fine * 2^24
  local interp = umul_hi32(delta, fine * 16777216)
  return umul_hi32(wavFreq, val1 + interp)
end

--- pret MidiKeyToCgbFreq for pulse/wave → 11-bit-ish period register.
function Mix.cgbPeriod(key, fine)
  key = tonumber(key) or 60
  fine = math.floor(tonumber(fine) or 0)
  if fine < 0 then fine = 0 end
  if fine > 255 then fine = 255 end
  if key <= 35 then
    fine = 0
    key = 0
  else
    key = key - 36
    if key > 130 then
      key = 130
      fine = 255
    end
  end
  local s1 = CGB_SCALE[key] or 0
  local val1 = math.floor((CGB_FREQ[s1 % 16] or 0) / (2 ^ math.floor(s1 / 16)))
  local s2 = CGB_SCALE[key + 1] or s1
  local val2 = math.floor((CGB_FREQ[s2 % 16] or 0) / (2 ^ math.floor(s2 / 16)))
  return val1 + math.floor((fine * (val2 - val1)) / 256) + 2048
end

function Mix.cgbPulseHz(key, fine)
  local p = Mix.cgbPeriod(key, fine)
  local denom = 2048 - p
  if denom < 1 then denom = 1 end
  return 131072 / denom
end

-- Hardware wave clock is half of pulse → one octave lower for same period.
function Mix.cgbWaveHz(key, fine)
  return Mix.cgbPulseHz(key, fine) * 0.5
end

function Mix.periodToPulseHz(periodReg)
  local denom = 2048 - (tonumber(periodReg) or 0)
  if denom < 1 then denom = 1 end
  return 131072 / denom
end

function Mix.cgbNoiseNr43(key)
  key = tonumber(key) or 60
  if key <= 20 then
    key = 0
  else
    key = key - 21
    if key > 59 then key = 59 end
  end
  return NOISE_TABLE[key] or 0
end

--- Convert NR43-style noise control into LFSR step period at Mix.SAMPLE_RATE.
function Mix.cgbNoisePeriod(key)
  local nr43 = Mix.cgbNoiseNr43(key)
  local shift = math.floor(nr43 / 16) % 16
  local div = NOISE_DIV[nr43 % 8] or 8
  local hz = 524288 / (div * (2 ^ shift))
  if hz < 1 then hz = 1 end
  local period = math.floor(Mix.SAMPLE_RATE / hz + 0.5)
  if period < 1 then period = 1 end
  if period > 4096 then period = 4096 end
  return period
end

--- Attach MP2K ADSR. CGB uses 0..15 sustain; DS uses 0..255.
function Mix.attachAdsr(voice, tone, isCgb)
  if not voice then return voice end
  tone = tone or {}
  voice.adsr = {
    attack = tonumber(tone.attack) or (isCgb and 0 or 255),
    decay = tonumber(tone.decay) or 0,
    sustain = tonumber(tone.sustain) or (isCgb and 15 or 255),
    release = tonumber(tone.release) or 0,
    isCgb = isCgb and true or false,
  }
  voice.envPhase = "attack"
  voice.envVol = 0
  voice.env = 0
  return voice
end

--- One sequencer-tick envelope step (pret SoundMain cadence ≈ per MPlayMain).
function Mix.tickEnvelope(v)
  if not v or not v.alive then return end
  local a = v.adsr
  if not a then
    v.env = 1
    return
  end
  local phase = v.envPhase or "attack"
  if phase == "attack" then
    if a.isCgb then
      if (a.attack or 0) == 0 then
        v.envVol = 15
        v.envPhase = "decay"
      else
        v.envVol = math.min(15, (v.envVol or 0) + 1)
        if v.envVol >= 15 then v.envPhase = "decay" end
      end
    else
      if (a.attack or 0) >= 255 then
        v.envVol = 255
        v.envPhase = "decay"
      else
        v.envVol = (v.envVol or 0) + (a.attack or 0) + 1
        if v.envVol >= 255 then
          v.envVol = 255
          v.envPhase = "decay"
        end
      end
    end
  elseif phase == "decay" then
    if a.isCgb then
      local sus = a.sustain or 0
      if (a.decay or 0) == 0 then
        v.envVol = sus
        v.envPhase = "sustain"
      else
        v.envVol = (v.envVol or 15) - 1
        if v.envVol <= sus then
          v.envVol = sus
          v.envPhase = "sustain"
        end
      end
    else
      local sus = a.sustain or 0
      if (a.decay or 0) == 0 then
        v.envVol = sus
        v.envPhase = "sustain"
      else
        v.envVol = math.floor(((v.envVol or 255) * (a.decay or 0)) / 256)
        if v.envVol <= sus then
          v.envVol = sus
          v.envPhase = "sustain"
        end
      end
    end
  elseif phase == "sustain" then
    -- hold until gate → release
  elseif phase == "release" then
    if a.isCgb then
      if (a.release or 0) == 0 then
        v.envVol = 0
        v.alive = false
      else
        v.envVol = (v.envVol or 0) - 1
        if v.envVol <= 0 then
          v.envVol = 0
          v.alive = false
        end
      end
    else
      if (a.release or 0) == 0 then
        v.envVol = 0
        v.alive = false
      else
        v.envVol = math.floor(((v.envVol or 0) * (a.release or 0)) / 256)
        if v.envVol <= 0 then
          v.envVol = 0
          v.alive = false
        end
      end
    end
  end
  local maxv = a.isCgb and 15 or 255
  if maxv < 1 then maxv = 1 end
  v.env = (v.envVol or 0) / maxv
end

function Mix.releaseVoice(v)
  if not v then return end
  if v.adsr then
    v.envPhase = "release"
    v.gateTicks = nil
  else
    v.alive = false
  end
end

function Mix.newDsVoice(pcm, meta, opts)
  opts = opts or {}
  local rate = opts.rate or Mix.waveRate(meta and meta.freq)
  local v = {
    kind = "ds",
    pcm = pcm,
    pos = 0,
    size = meta and meta.size or #pcm,
    loopStart = (meta and meta.loopStart) or 0,
    loop = opts.loop and true or false,
    step = rate / Mix.SAMPLE_RATE,
    volL = opts.volL or 0.5,
    volR = opts.volR or 0.5,
    env = opts.env or 1,
    alive = true,
  }
  if opts.tone then Mix.attachAdsr(v, opts.tone, false) end
  return v
end

function Mix.waveRate(freqField)
  freqField = tonumber(freqField) or 0
  if freqField <= 0 then return Mix.GBA_MIX_RATE end
  local rate = math.floor(freqField / 1024 + 0.5)
  if rate < 500 then rate = Mix.GBA_MIX_RATE end
  if rate > 48000 then rate = 48000 end
  return rate
end

-- Hardware: 4 exclusive CGB channels (pulse1, pulse2, wave, noise).
Mix.MAX_DS_CHANNELS = 12

function Mix.newCgbPulse(opts)
  opts = opts or {}
  local key = opts.key or 60
  local fine = opts.fine or 0
  local periodReg = opts.periodReg or Mix.cgbPeriod(key, fine)
  local v = {
    kind = "cgb_pulse",
    cgbChan = opts.cgbChan or 1, -- 1 or 2
    duty = opts.duty or 2,
    phase = 0,
    periodReg = periodReg,
    freq = opts.freq or Mix.periodToPulseHz(periodReg),
    volL = opts.volL or 0.4,
    volR = opts.volR or 0.4,
    env = opts.env or 1,
    alive = true,
  }
  -- Channel 1 only: ToneData.pan_sweep is NR10 when bit7 clear (pret ply_note).
  local panSweep = opts.tone and tonumber(opts.tone.pan) or 0
  if v.cgbChan == 1 and panSweep > 0 and math.floor(panSweep / 128) % 2 == 0 then
    local time = math.floor(panSweep / 16) % 8
    local shift = panSweep % 8
    if time > 0 or shift > 0 then
      v.sweepNr10 = panSweep % 128
      v.sweepShadow = periodReg
      v.sweepTimer = (time == 0) and 8 or time
      v.sweepAcc = 0
      v.sweepEnabled = true
    end
  end
  if opts.tone then Mix.attachAdsr(v, opts.tone, true) end
  return v
end

function Mix.newCgbWave(opts)
  opts = opts or {}
  local wave = opts.wave or {}
  local key = opts.key or 60
  local fine = opts.fine or 0
  local v = {
    kind = "cgb_wave",
    cgbChan = 3,
    wave = wave,
    phase = 0,
    freq = opts.freq or Mix.cgbWaveHz(key, fine),
    volL = opts.volL or 0.35,
    volR = opts.volR or 0.35,
    env = opts.env or 1,
    alive = true,
  }
  if opts.tone then Mix.attachAdsr(v, opts.tone, true) end
  return v
end

function Mix.newCgbNoise(opts)
  opts = opts or {}
  local v = {
    kind = "cgb_noise",
    cgbChan = 4,
    lfsr = 0x7FFF,
    clock = 0,
    period = opts.period or Mix.cgbNoisePeriod(opts.key or 60),
    volL = opts.volL or 0.3,
    volR = opts.volR or 0.3,
    env = opts.env or 1,
    alive = true,
  }
  if opts.tone then Mix.attachAdsr(v, opts.tone, true) end
  return v
end

local function clip1(x)
  if x > 1 then return 1 end
  if x < -1 then return -1 end
  return x
end

local function s8_at(pcm, idx)
  local i = math.floor(idx)
  if i < 0 or i >= #pcm then return 0 end
  local b = pcm:byte(i + 1)
  return (b >= 128 and (b - 256) or b) / 128
end

--- Linear interpolate s8 PCM (reduces stair-step harshness on upsample).
local function s8_lerp(pcm, pos, size)
  if pos < 0 then return 0 end
  local i0 = math.floor(pos)
  if i0 >= size then return 0 end
  local frac = pos - i0
  local s0 = s8_at(pcm, i0)
  if frac < 1e-6 or i0 + 1 >= size then return s0 end
  local s1 = s8_at(pcm, i0 + 1)
  return s0 + (s1 - s0) * frac
end

-- GB channel-1 hardware sweep (~128 Hz clock).
local function tick_sweep_sample(v)
  if not v.sweepEnabled then return end
  local clocksPerSec = 128
  v.sweepAcc = (v.sweepAcc or 0) + clocksPerSec / Mix.SAMPLE_RATE
  while v.sweepAcc >= 1 do
    v.sweepAcc = v.sweepAcc - 1
    local nr10 = v.sweepNr10 or 0
    local time = math.floor(nr10 / 16) % 8
    if time == 0 then return end
    v.sweepTimer = (v.sweepTimer or time) - 1
    if v.sweepTimer > 0 then
      -- wait
    else
      v.sweepTimer = time
      local shift = nr10 % 8
      if shift == 0 then return end
      local shadow = v.sweepShadow or 0
      local delta = math.floor(shadow / (2 ^ shift))
      local negate = math.floor(nr10 / 8) % 2
      local newf = (negate == 1) and (shadow - delta) or (shadow + delta)
      if newf > 2047 or newf < 0 then
        v.alive = false
        return
      end
      v.sweepShadow = newf
      v.periodReg = newf
      v.freq = Mix.periodToPulseHz(newf)
    end
  end
end

local function render_voice(v, n, outL, outR)
  if not v or not v.alive then return end
  local env = v.env
  if env == nil then env = 1 end
  if env <= 0 then return end
  if v.kind == "ds" then
    for i = 1, n do
      if v.pos >= v.size then
        if v.loop and v.loopStart < v.size then
          v.pos = v.loopStart
        else
          v.alive = false
          break
        end
      end
      local s = s8_lerp(v.pcm, v.pos, v.size) * env
      outL[i] = outL[i] + s * v.volL * 0.35
      outR[i] = outR[i] + s * v.volR * 0.35
      v.pos = v.pos + v.step
    end
  elseif v.kind == "cgb_pulse" then
    local duty = DUTY[v.duty] or DUTY[2]
    local thresh, hi, lo = duty[1], duty[2], duty[3]
    for i = 1, n do
      tick_sweep_sample(v)
      if not v.alive then break end
      local inc = v.freq / Mix.SAMPLE_RATE
      local s = (v.phase < thresh) and hi or lo
      -- Was 0.12 — left CGB SE (doors/select) ~3× under DS; pret CGB is louder.
      s = s * env * 0.28
      outL[i] = outL[i] + s * v.volL
      outR[i] = outR[i] + s * v.volR
      v.phase = v.phase + inc
      if v.phase >= 1 then v.phase = v.phase - 1 end
    end
  elseif v.kind == "cgb_wave" then
    local wave = v.wave
    local inc = v.freq / Mix.SAMPLE_RATE
    for i = 1, n do
      local idx = math.floor(v.phase * 32) % 32
      local nibble = wave[idx + 1] or 8
      local s = ((nibble / 7.5) - 1) * 0.25 * env
      outL[i] = outL[i] + s * v.volL
      outR[i] = outR[i] + s * v.volR
      v.phase = v.phase + inc
      if v.phase >= 1 then v.phase = v.phase - 1 end
    end
  elseif v.kind == "cgb_noise" then
    for i = 1, n do
      v.clock = v.clock + 1
      if v.clock >= v.period then
        v.clock = 0
        local lo = v.lfsr % 2
        local hi = math.floor(v.lfsr / 2) % 2
        local bit = (lo == hi) and 0 or 1
        v.lfsr = math.floor(v.lfsr / 2) + bit * 0x4000
      end
      local s = ((v.lfsr % 2) == 0) and 0.14 or -0.14
      s = s * env
      outL[i] = outL[i] + s * v.volL
      outR[i] = outR[i] + s * v.volR
    end
  end
end

function Mix.render(voices, n, opts)
  opts = opts or {}
  n = n or 1024
  local outL, outR = {}, {}
  for i = 1, n do outL[i] = 0; outR[i] = 0 end
  for _, v in ipairs(voices) do
    render_voice(v, n, outL, outR)
  end
  local alive = {}
  for _, v in ipairs(voices) do
    if v.alive then alive[#alive + 1] = v end
  end

  -- Capacitor HPF (ChipSynth model) — restores highs vs a DC-coupled bus.
  local master = opts.master or 1
  local charge = hpf_charge()
  local capL = opts.hpfCapL
  local capR = opts.hpfCapR
  if capL == nil then capL = Mix._hpfCapL or 0 end
  if capR == nil then capR = Mix._hpfCapR or 0 end
  for i = 1, n do
    local inl = outL[i] * master
    local inr = outR[i] * master
    local hpL = inl - capL
    capL = inl - hpL * charge
    local hpR = inr - capR
    capR = inr - hpR * charge
    outL[i] = hpL
    outR[i] = hpR
  end
  Mix._hpfCapL = capL
  Mix._hpfCapR = capR
  if opts.hpfState then
    opts.hpfState.l = capL
    opts.hpfState.r = capR
  end

  if opts.raw then
    return outL, outR, alive
  end
  if not (love and love.sound and love.sound.newSoundData) then
    return outL, alive
  end
  local ch = opts.mono and 1 or 2
  local rate = opts.sampleRate or Mix.SAMPLE_RATE
  local sd = love.sound.newSoundData(n, rate, 16, ch)
  -- Hard clip only. Soft clip (tanh) ducks every other voice whenever
  -- a loud hit (noise / stacked CGB) pushes the bus — sounds like channel dimming.
  for i = 1, n do
    local l = clip1(outL[i])
    local r = clip1(outR[i])
    if ch == 1 then
      sd:setSample(i - 1, (l + r) * 0.5)
    else
      sd:setSample(i - 1, 1, l)
      sd:setSample(i - 1, 2, r)
    end
  end
  return sd, alive
end

function Mix.midiToHz(key)
  return midi_to_hz(key)
end

return Mix
