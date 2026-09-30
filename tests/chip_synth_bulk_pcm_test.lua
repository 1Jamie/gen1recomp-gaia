-- ChipSynth bulk PCM writes (ffi int16 stores through Data:getFFIPointer)
-- must be bit-identical to the per-sample SoundData:setSample path they
-- replace, for streamed music buffers, SFX/cries (renderEffectData) and the
-- synchronous music fallback's sliced staging fill (ChipAudio fillSync).
--   luajit tests/chip_synth_bulk_pcm_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("chip synth bulk pcm")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
local ffi = require("ffi")

-- ffi-backed SoundData.  setSample reproduces LOVE 11.5's 16-bit store,
-- (int16)(value * 32767) in double precision with no clamp -- verified
-- against a real LOVE 11.5 SoundData over 2M values including
-- out-of-range and NaN.  getFFIPointer exposes the same storage.
local FfiSoundData = {}
FfiSoundData.__index = FfiSoundData
function FfiSoundData:setSample(index, a, b)
  if b == nil then
    self.buf[index * self.channels] = a * 32767
  else
    self.buf[index * self.channels + (a - 1)] = b * 32767
  end
end
function FfiSoundData:getSample(index, channel)
  return self.buf[index * self.channels + ((channel or 1) - 1)] / 32767
end
function FfiSoundData:getFFIPointer() return self.buf end
function FfiSoundData:getSampleCount() return self.samples end
function FfiSoundData:getSampleRate() return self.rate end
function FfiSoundData:getBitDepth() return 16 end
function FfiSoundData:getChannelCount() return self.channels end

love.sound = love.sound or {}
love.sound.newSoundData = function(samples, rate, bits, channels)
  local sd = setmetatable({
    samples = samples, rate = rate, channels = channels,
    buf = ffi.new("int16_t[?]", samples * channels),
  }, FfiSoundData)
  return sd
end

-- the conversion itself, including values the synth never produces
do
  local a = love.sound.newSoundData(8, 44100, 16, 1)
  local values = { 0, 1, -1, 1.5, -1.5, 0.99999, 1.5 / 32767, 0 / 0 }
  local expect = { 0, 32767, -32767, -16386, 16386, 32766, 1, 0 }
  for i, v in ipairs(values) do a:setSample(i - 1, v) end
  for i = 1, #expect do
    eq(a.buf[i - 1], expect[i], "LOVE 11.5 int16 store of " .. tostring(values[i]))
  end
end

local ChipSynth = require("src.core.ChipSynth")
local ChipAsm = require("src.audio.ChipAsm")
ChipSynth.setChannelVolumes({ 1, 1, 1, 1 })
ChipSynth.setChannelPitches({ 1, 1, 1, 1 })

-- the fake SoundData really takes the bulk path (and the switch disables it)
check(ChipSynth._int16Pointer(love.sound.newSoundData(1, 44100, 16, 2)),
  "bulk path active on an ffi SoundData")
ChipSynth._setBulkWritesForTest(false)
check(not ChipSynth._int16Pointer(love.sound.newSoundData(1, 44100, 16, 2)),
  "bulk switch off falls back to setSample")
ChipSynth._setBulkWritesForTest(true)

local function same(a, b)
  if a.samples ~= b.samples or a.channels ~= b.channels then
    return false, "shape " .. a.samples .. "x" .. a.channels
      .. " vs " .. b.samples .. "x" .. b.channels
  end
  local n = a.samples * a.channels
  for i = 0, n - 1 do
    if a.buf[i] ~= b.buf[i] then
      return false, ("sample %d: %d vs %d"):format(i, a.buf[i], b.buf[i])
    end
  end
  return true
end

local function nonzero(sd)
  local count = 0
  for i = 0, sd.samples * sd.channels - 1 do
    if sd.buf[i] ~= 0 then count = count + 1 end
  end
  return count
end

local data = { audio = {} }
local song = ChipAsm.song{
  tempo = 0x100,
  channels = {
    { hw = 1, program = {
      { duty = 2 },
      { notetype = { speed = 12, volume = 12, fade = 0 } },
      { octave = 4 },
      { label = "body" },
      { note = "C", len = 8 }, { note = "E", len = 8 }, { note = "G", len = 4 },
      { loop = { count = 0, to = "body" } },
    } },
    { hw = 2, program = {
      { duty = 1 },
      { notetype = { speed = 12, volume = 10, fade = 2 } },
      { octave = 3 },
      { label = "body" },
      { note = "G", len = 4 }, { note = "A", len = 12 },
      { loop = { count = 0, to = "body" } },
    } },
    { hw = 4, program = {
      { label = "body" },
      { drum = 3, len = 4 },
      { loop = { count = 0, to = "body" } },
    } },
  },
  drums = { [3] = { { len = 4, volume = 13, fade = 2, parameter = 0x42 } } },
}

local function render(bulk, fn)
  ChipSynth._setBulkWritesForTest(bulk)
  local ok, result = pcall(fn)
  ChipSynth._setBulkWritesForTest(true)
  assert(ok, result)
  return result
end

-- streamed music buffers (worker + sync fallback), stereo and mono
for _, channels in ipairs({ 2, 1 }) do
  local function music()
    local engine = ChipSynth.newEngine(data, song, { allowLoops = true })
    local first = ChipSynth.soundData(engine, 8192, channels)
    local second = ChipSynth.soundData(engine, 8192, channels)
    return { first, second }
  end
  local slow, fast = render(false, music), render(true, music)
  for i = 1, 2 do
    local ok, why = same(slow[i], fast[i])
    check(ok, ("music buffer %d (%dch) bit-identical %s")
      :format(i, channels, why or ""))
  end
  check(nonzero(fast[1]) > 1000, "music buffer carries audio")
end

-- sliced staging fill == one whole-buffer render
do
  local whole = render(false, function()
    local engine = ChipSynth.newEngine(data, song, { allowLoops = true })
    ChipSynth.soundData(engine, 1000, 2)
    return ChipSynth.soundData(engine, 8192, 2)
  end)
  local sliced = render(true, function()
    local engine = ChipSynth.newEngine(data, song, { allowLoops = true })
    ChipSynth.soundData(engine, 1000, 2)
    local sd = ChipSynth.newBuffer(8192, 2)
    local fill = 0
    for _, n in ipairs({ 1024, 1024, 777, 1024, 3000, 1343 }) do
      ChipSynth.renderInto(engine, sd, fill, n, 2)
      fill = fill + n
    end
    assert(fill == 8192)
    return sd
  end)
  local ok, why = same(whole, sliced)
  check(ok, "sliced staging fill bit-identical " .. (why or ""))
end

-- SFX / cries
local sfx = ChipAsm.sfx{ channels = {
  { hw = 1, program = {
    { squareNote = { len = 8, volume = 15, fade = 1, frequency = 0x600 } },
    { squareNote = { len = 16, volume = 12, fade = 3, frequency = 0x700 } },
  } },
  { hw = 4, program = {
    { noiseNote = { len = 16, volume = 14, fade = 2, parameter = 0x33 } },
  } },
} }

for _, opts in ipairs({
  function() return {} end,
  function() return { frequencyOffset = 0x40, cryLength = 0x60 } end,
  function() return { frequencyOffset = -0x20, frameTicks = 0xC0 } end,
}) do
  local slow = render(false, function()
    return ChipSynth.renderEffectData(data, sfx, opts())
  end)
  local fast = render(true, function()
    return ChipSynth.renderEffectData(data, sfx, opts())
  end)
  check(slow and fast, "effect renders both ways")
  if slow and fast then
    local ok, why = same(slow, fast)
    check(ok, "effect bit-identical " .. (why or ""))
    check(nonzero(fast) > 100, "effect carries audio")
  end
end

-- a second, longer effect after a short one: the reused scratch grows
do
  local notes = {}
  for i = 1, 24 do
    notes[i] = { squareNote = { len = 16, volume = 15, fade = 0,
                                frequency = 0x600 + i * 8 } }
  end
  local long = ChipAsm.sfx{ channels = { { hw = 1, program = notes } } }
  local slow = render(false, function()
    return ChipSynth.renderEffectData(data, long, {})
  end)
  local fast = render(true, function()
    return ChipSynth.renderEffectData(data, long, {})
  end)
  check(slow and fast and slow.samples > 44100,
    "long effect renders past the initial scratch")
  if slow and fast then
    local ok, why = same(slow, fast)
    check(ok, "long effect bit-identical " .. (why or ""))
  end
end

-- synchronous music fallback: the sliced per-tick staging fill queues the
-- same 8192-sample buffers, in order, as whole-buffer renders did
do
  love.thread = nil
  local queued = {}
  local source = { free = 32, playing = false }
  function source:getFreeBufferCount() return self.free end
  function source:queue(sd) self.free = self.free - 1; queued[#queued + 1] = sd end
  function source:play() self.playing = true end
  function source:stop() self.playing = false end
  function source:isPlaying() return self.playing end
  function source:setVolume() end
  love.audio = love.audio or {}
  love.audio.newQueueableSource = function() return source end
  local ChipAudio = require("src.core.ChipAudio")
  ChipAudio.playMusic(data, song, true)
  eq(#queued, 4, "song start queues the initial buffers")
  local maxTick = 0
  local consumed = 0
  for _ = 1, 400 do
    consumed = consumed + ChipSynth.SAMPLE_RATE / 60
    while consumed >= 8192 and source.free < 32 do
      consumed = consumed - 8192
      source.free = source.free + 1
    end
    local before = #queued
    ChipAudio.update()
    maxTick = math.max(maxTick, #queued - before)
  end
  check(#queued > 40, "the queue keeps filling (" .. #queued .. " buffers)")
  check(maxTick <= 1, "at most one buffer completes per tick")
  local engine = ChipSynth.newEngine(data, song, { allowLoops = true })
  local allSame = true
  for i = 1, #queued do
    local ref = ChipSynth.soundData(engine, 8192, 2)
    local ok = same(ref, queued[i])
    if not ok then allSame = false; break end
  end
  check(allSame, "sliced fallback stream bit-identical to whole buffers")
  -- a starved queue (below the low-water mark) renders a whole buffer's
  -- worth in one tick
  source.free = 31
  local before = #queued
  ChipAudio.update()
  check(#queued - before >= 1, "low queue catches up within one tick")
  ChipAudio.stopMusic()
  -- no worker: prewarm declines rather than rendering on this thread
  local fx = { audio = { sfx = { Beep = sfx }, cries = {} } }
  check(ChipAudio.prewarmSfx(fx, "Beep") == false,
    "prewarm is a no-op without a worker")
  eq(ChipAudio._effectStateForTest().pending, 0, "nothing left pending")
end

S.finish()
