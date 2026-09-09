-- Decode FireRed DirectSound samples (little-endian headers, s8 PCM).

local Sample = {}

local ffiOk, ffi = pcall(require, "ffi")

local function s8_at(pcm, idx)
  local i = math.floor(idx)
  if i < 0 or i >= #pcm then return 0 end
  local b
  if ffiOk and ffi then
    b = ffi.cast("const int8_t *", pcm)[i]
    return b / 128
  end
  b = pcm:byte(i + 1)
  local s = b >= 128 and (b - 256) or b
  return s / 128
end

--- Convert raw s8 PCM bytes to a love SoundData (mono 16-bit).
-- Resamples to outRate when native rate differs (OpenAL is unreliable with odd rates).
function Sample.s8ToSoundData(pcm, sampleRate, opts)
  opts = opts or {}
  if type(pcm) ~= "string" or #pcm == 0 then return nil end
  sampleRate = sampleRate or 13379
  local outRate = opts.outRate or sampleRate
  if not (love and love.sound and love.sound.newSoundData) then return nil end

  local nIn = #pcm
  local nOut = nIn
  local step = 1
  if outRate ~= sampleRate and sampleRate > 0 then
    nOut = math.max(1, math.floor(nIn * outRate / sampleRate + 0.5))
    step = sampleRate / outRate
  end

  local sd = love.sound.newSoundData(nOut, outRate, 16, 1)
  local pos = 0
  for i = 0, nOut - 1 do
    sd:setSample(i, s8_at(pcm, pos))
    pos = pos + step
  end
  return sd
end

--- Mid-C key freq helper: WaveData.freq is typically rate * 1024.
function Sample.waveRate(freqField)
  freqField = tonumber(freqField) or 0
  if freqField <= 0 then return 13379 end
  local rate = math.floor(freqField / 1024 + 0.5)
  if rate < 500 then rate = 13379 end
  if rate > 48000 then rate = 48000 end
  return rate
end

--- Read one sample blob from samples.bin given index meta {offset,size,freq}.
function Sample.loadPcm(samplesBin, meta)
  if type(samplesBin) ~= "string" or type(meta) ~= "table" then return nil end
  local off = meta.offset or 0
  local size = meta.size or 0
  if size <= 0 or off < 0 or off + size > #samplesBin then return nil end
  return samplesBin:sub(off + 1, off + size)
end

function Sample.makeSource(samplesBin, meta, opts)
  opts = opts or {}
  local pcm = Sample.loadPcm(samplesBin, meta)
  if not pcm then return nil end
  local rate = opts.rate or Sample.waveRate(meta.freq)
  local outRate = opts.outRate
  if not outRate then
    local MixOk, Mix = pcall(require, "src.core.game3.m4a_mix")
    outRate = (MixOk and Mix and Mix.SAMPLE_RATE) or 44100
  end
  local sd = Sample.s8ToSoundData(pcm, rate, { outRate = outRate })
  if not sd then return nil end
  if not (love and love.audio and love.audio.newSource) then return nil end
  local src = love.audio.newSource(sd, "static")
  if opts.loop and meta.loopStart and meta.loopStart > 0 and meta.loopStart < (meta.size or 0) then
    src:setLooping(true)
  end
  if opts.volume then src:setVolume(opts.volume) end
  return src, sd
end

-- GameFreak DPCM decode (WaveData.type == 1). Prefer extract-time linear PCM.
local DPCM_DELTA = {
  [0] = 0, 1, 4, 9, 16, 25, 36, 49, -64, -49, -36, -25, -16, -9, -4, -1,
}

function Sample.decodeGfdpcm(src, sampleCount)
  if type(src) ~= "string" or not sampleCount or sampleCount <= 0 then return "" end
  local function s8(b) return b >= 128 and (b - 256) or b end
  local function clamp(v)
    if v > 127 then return 127 end
    if v < -128 then return -128 end
    return v
  end
  local blocks = math.ceil(sampleCount / 64)
  local out, n = {}, 0
  local function push(v)
    v = clamp(v)
    n = n + 1
    out[n] = string.char((v + 256) % 256)
  end
  for bi = 0, blocks - 1 do
    local bp = bi * 0x21
    if bp + 1 > #src then break end
    local acc = s8(src:byte(bp + 1))
    push(acc)
    if n >= sampleCount then break end
    if bp + 2 > #src then break end
    acc = acc + DPCM_DELTA[src:byte(bp + 2) % 16]
    push(acc)
    if n >= sampleCount then break end
    for h = 2, 32 do
      if bp + 1 + h > #src then break end
      local byte = src:byte(bp + 1 + h)
      acc = acc + DPCM_DELTA[math.floor(byte / 16) % 16]
      push(acc)
      if n >= sampleCount then break end
      acc = acc + DPCM_DELTA[byte % 16]
      push(acc)
      if n >= sampleCount then break end
    end
    if n >= sampleCount then break end
  end
  return table.concat(out)
end

return Sample
