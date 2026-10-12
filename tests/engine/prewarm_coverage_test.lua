-- Extra SFX / cry prewarm coverage on top of ChipAudio's prewarm (Sound.prewarmMove,
-- the Gen 1 battle prewarmCries, Game:prewarmCommonAudio).
--   luajit tests/engine/prewarm_coverage_test.lua
-- The chip worker is driven in-process like chipaudio_prewarm_queue_2732.lua.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("prewarm coverage")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
local ffi = require("ffi")

local SoundData = {}
SoundData.__index = SoundData
function SoundData:setSample(index, a, b)
  if b == nil then self.buf[index * self.channels] = a * 32767
  else self.buf[index * self.channels + (a - 1)] = b * 32767 end
end
function SoundData:getFFIPointer() return self.buf end
function SoundData:getSampleCount() return self.samples end
function SoundData:getSampleRate() return self.rate end
function SoundData:getChannelCount() return self.channels end
love.sound.newSoundData = function(samples, rate, _, channels)
  return setmetatable({ samples = samples, rate = rate, channels = channels,
    buf = ffi.new("int16_t[?]", samples * channels) }, SoundData)
end

local Source = {}
Source.__index = Source
function Source:play() self.playing = true end
function Source:stop() self.playing = false end
function Source:isPlaying() return self.playing end
function Source:setVolume() end
function Source:setPitch() end
function Source:getPitch() return 1 end
function Source:getDuration() return 1 end
love.audio = { newSource = function(sd) return setmetatable({ sd = sd }, Source) end }

local channels = {}
local function channel(name)
  local ch = channels[name]
  if ch then return ch end
  local items = {}
  ch = { items = items }
  function ch:push(v) items[#items + 1] = v end
  function ch:pop() return table.remove(items, 1) end
  function ch:clear() for i = #items, 1, -1 do items[i] = nil end end
  function ch:getCount() return #items end
  channels[name] = ch
  return ch
end
love.thread = {
  newThread = function()
    return { start = function() end, getError = function() return nil end }
  end,
  getChannel = channel,
}

local ChipSynth = require("src.core.ChipSynth")
local ChipAsm = require("src.audio.ChipAsm")
local ChipAudio = require("src.core.ChipAudio")
local Sound = require("src.core.Sound")
local BattleState = require("src.battle.BattleState")

local function def(octave)
  return ChipAsm.sfx{ channels = { { hw = 1, program = {
    { squareNote = { len = 4, volume = 15, fade = 1,
                     frequency = 0x400 + octave * 0x40 } },
  } } } }
end

local function newData()
  local d = {
    audio = {
      sfx = { Foo = def(5), Damage = def(4), Super_Effective = def(6),
              Not_Very_Effective = def(3), Level_Up = def(2),
              Bar = def(1) },
      cries = { A = def(1), B = def(2), C = def(3), D = def(4), E = def(5) },
    },
    moves = {
      TACKLE = { anim = { sound = "Foo", pitch = 0x20, tempo = 0x90 } },
      PLAIN = { anim = { sound = "Bar" } },
    },
  }
  return d
end

local function workerStep()
  local cmdCh, fxCh = channel("chipaudio_cmd"), channel("chipaudio_fx")
  local n = 0
  while true do
    local req = cmdCh:pop()
    if not req then break end
    if req.cmd == "effect" then
      n = n + 1
      fxCh:push({ key = req.key, epoch = req.epoch,
        sd = ChipSynth.renderEffectData({ audio = req.audio }, req.header,
          req.options or {}) })
    end
  end
  return n
end
local function drain()
  for _ = 1, 100 do
    ChipAudio.pumpEffects()
    if workerStep() == 0 then
      ChipAudio.pumpEffects()
      local st = ChipAudio._effectStateForTest()
      if st.queued + st.inFlight == 0 then return end
    end
  end
end

-- ---- move sounds: prewarm key == playMove's plain==0 key -------------------
do
  local data = newData()
  ChipAudio.resetSyncStats()
  check(Sound.prewarmMove(data, data.moves.TACKLE.anim), "pitched move queued")
  check(Sound.prewarmMove(data, data.moves.PLAIN.anim), "default-modifier move queued")
  check(not Sound.prewarmMove(data, { sound = "Missing" }), "unknown sound declined")
  check(not Sound.prewarmMove(data, nil), "no anim declined")
  drain()
  Sound.playMove(data, data.moves.TACKLE.anim)
  Sound.playMove(data, data.moves.PLAIN.anim)
  eq(ChipAudio.stats().syncRenders, 0, "prewarmed move plays render nothing")
  eq(ChipAudio.stats().prewarmHits, 2, "both plays took prewarmed PCM")
end

-- ---- a play before the prewarm lands still gets its Source ------------------
do
  local data = newData()
  data.audio.sfx.Early = def(7)
  ChipAudio.resetSyncStats()
  check(Sound.prewarmSfx(data, "Early"), "queued")
  local before = ChipAudio.stats().syncRenders
  local src = Sound.play(data, "Early")
  check(src ~= nil, "play before the prewarm completes returns a Source")
  eq(ChipAudio.stats().syncRenders, before + 1, "rendered synchronously")
  drain() -- the late result must not disturb the cached Source
  eq(Sound.play(data, "Early"), src, "late result never replaces the cached Source")
end

-- ---- an already cached sound is never re-requested -------------------------
do
  local data = newData()
  data.audio.sfx.Cached = def(7)
  local src = Sound.play(data, "Cached")
  check(src ~= nil, "plays")
  local st = ChipAudio._effectStateForTest()
  check(Sound.prewarmSfx(data, "Cached"), "cached sfx reports true")
  local st2 = ChipAudio._effectStateForTest()
  eq(st2.queued + st2.inFlight + st2.ready, st.queued + st.inFlight + st.ready,
    "and queues nothing")
end

-- ---- Gen 1 battle prewarm: whole parties, lead moves, hit sounds -----------
do
  local data = newData()
  local function mon(species, ...)
    local moves = {}
    for _, id in ipairs({ ... }) do moves[#moves + 1] = { id = id } end
    return { species = species, moves = moves }
  end
  local enemyParty = { mon("A", "PLAIN"), mon("B", "TACKLE"), mon("C") }
  local playerParty = { mon("D", "TACKLE", "PLAIN"), mon("E") }
  local self = {
    data = data,
    enemy = { mon = enemyParty[1] }, player = { mon = playerParty[1] },
    enemyParty = enemyParty,
    playerPartyView = function() return playerParty end,
  }
  ChipAudio.resetSyncStats()
  BattleState.prewarmCries(self)
  drain()
  for _, sp in ipairs({ "A", "B", "C", "D", "E" }) do
    ChipAudio.newCry(data, sp, data.audio.cries[sp])
  end
  eq(ChipAudio.stats().syncRenders, 0, "enemy and player party cries prewarmed")
  Sound.playMove(data, data.moves.TACKLE.anim)
  Sound.playMove(data, data.moves.PLAIN.anim)
  for _, anim in ipairs({ { sound = "Damage", pitch = 0x20 },
      { sound = "Super_Effective", pitch = 0xe0 },
      { sound = "Not_Very_Effective", pitch = 0x50 } }) do
    Sound.playMove(data, anim)
  end
  Sound.play(data, "Level_Up")
  eq(ChipAudio.stats().syncRenders, 0,
    "lead moves, hit sounds and battle SFX prewarmed")
end

S.finish()
