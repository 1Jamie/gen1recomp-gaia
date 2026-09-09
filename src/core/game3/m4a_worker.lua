-- BGM mixer worker: lock-free SPSC PCM ring via love.thread Channels.
-- Paces the M4A sequencer in GBA VBlank units (13379 Hz / 224 samples).
-- Sample rate is dictated by the main thread so QueueableSource and SoundData match.

require("love.thread")
require("love.sound")
require("love.timer")
require("love.filesystem")

local cmdCh = love.thread.getChannel("game3_m4a_cmd")
local outCh = love.thread.getChannel("game3_m4a_out")

-- Prefer filesystem load (package.path is unreliable inside love.thread).
local function load_mod(rel)
  local chunk = assert(love.filesystem.load(rel))
  return chunk()
end

local Mix = load_mod("src/core/game3/m4a_mix.lua")
package.loaded["src.core.game3.m4a_mix"] = Mix
local Sample = load_mod("src/core/game3/m4a_sample.lua")
package.loaded["src.core.game3.m4a_sample"] = Sample
local Seq = load_mod("src/core/game3/m4a_seq.lua")
package.loaded["src.core.game3.m4a_seq"] = Seq
local Player = load_mod("src/core/game3/m4a_player.lua")
package.loaded["src.core.game3.m4a_player"] = Player

local pack = nil
local cache = {
  read = function(_, rel)
    return love.filesystem.read(rel)
  end,
}
local bgm = { voices = {}, seq = nil, songId = nil, muted = false, volume = 1 }
local running = true
-- QueueableSource buffer size (underrun safety). Sequencer advances in
-- ~1 GBA vblank quanta inside Player.renderBuffered — not as one batch.
local BUFFER = Player.BUFFER_SAMPLES or 8192
-- Keep ~2s in the Channel so main-thread focus stalls don't underrun OpenAL.
local TARGET_QUEUED = Player.CHANNEL_TARGET or 12
local sampleRate = Mix.SAMPLE_RATE

local function apply_cmd(msg)
  if type(msg) ~= "table" then return end
  if msg.cmd == "quit" then
    running = false
  elseif msg.cmd == "install" then
    if msg.sampleRate then
      sampleRate = Mix.setSampleRate(msg.sampleRate)
      BUFFER = Player.BUFFER_SAMPLES or 8192
      TARGET_QUEUED = Player.CHANNEL_TARGET or 12
    end
    pack = Player.loadPack(cache, msg.root)
  elseif msg.cmd == "play" then
    if not pack then return end
    bgm = { voices = {}, seq = nil, songId = msg.id, muted = false, volume = bgm.volume or 1 }
    Player.start(pack, cache, bgm, msg.id, { forceSeq = true })
  elseif msg.cmd == "stop" then
    bgm.voices = {}
    bgm.seq = nil
    bgm.songId = nil
    bgm.done = true
  elseif msg.cmd == "pause" then
    bgm.muted = true
  elseif msg.cmd == "resume" then
    bgm.muted = false
  elseif msg.cmd == "volume" then
    bgm.volume = msg.volume or 1
  end
end

while running do
  local msg = cmdCh:pop()
  while msg do
    apply_cmd(msg)
    msg = cmdCh:pop()
  end

  local queued = outCh:getCount()
  if pack and bgm.songId and not bgm.muted and queued < TARGET_QUEUED then
    -- Interleave MPlayMain with mix (pret/mGBA: once per vblank).
    local sd = Player.renderBuffered(bgm, BUFFER, {
      master = bgm.volume or 1,
      sampleRate = sampleRate,
    })
    if sd then
      outCh:push({ gen = bgm.songId, data = sd, rate = sampleRate })
    end
    if bgm.done and #(bgm.voices or {}) == 0 then
      outCh:push({
        gen = bgm.songId,
        data = love.sound.newSoundData(BUFFER, sampleRate, 16, 2),
        rate = sampleRate,
        ended = true,
      })
    end
  else
    love.timer.sleep(0.002)
  end
end
