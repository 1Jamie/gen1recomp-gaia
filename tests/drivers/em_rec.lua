local ffi = require("ffi")

local R = {
  tick = 0,
  armed = false,
  frames = 0,
  marks = {},
  bgm = { song = nil, pos = 0 },
  frameBgm = {},
  instances = {},
  sounds = {},
  soundIndex = {},
  calls = {},
}

local srcData = setmetatable({}, { __mode = "k" })
local active = setmetatable({}, { __mode = "k" })

local function Audio() return package.loaded["src.core.game3.audio"] end

local function rate()
  local Mix = package.loaded["src.core.game3.m4a_mix"]
  return (Mix and Mix.SAMPLE_RATE) or 44100
end

local function fmtArgs(...)
  local out = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if type(v) == "table" then
      local parts = {}
      for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. tostring(x) end
      out[#out + 1] = "{" .. table.concat(parts, ",") .. "}"
    else
      out[#out + 1] = tostring(v)
    end
  end
  return table.concat(out, " ")
end

local function relFrame() return R.tick - (R.armTick or 0) end

local function logCall(name, ...)
  if not R.armed then return end
  R.calls[#R.calls + 1] = string.format("%d %s %s", relFrame(), name, fmtArgs(...))
end

local function wrapAudio()
  local A = require("src.core.game3.audio")
  for _, name in ipairs({ "playMapSong", "fadeOutAndPlay", "fadeOutBgm", "fadeInBgm", "pauseBgm", "resumeBgm",
      "playSe", "playFanfare", "playCry", "stopSe", "stopCry", "changeMusicTo", "changeMusicToDefault",
      "mapLoadMusic", "restoreMapSong", "stopAll", "bikeMusic" }) do
    local orig = A[name]
    if type(orig) == "function" then
      A[name] = function(...)
        logCall(name, ...)
        return orig(...)
      end
    end
  end
  local origPlay = A.playSong
  A.playSong = function(id, ...)
    logCall("playSong", id, ...)
    local e0, l0 = A._bgmEpoch, A._bgmLocal
    local res = origPlay(id, ...)
    if (A._bgmEpoch ~= e0 or (A._bgmLocal and A._bgmLocal ~= l0)) and A._bgmGen ~= nil then
      R.bgm.song = A._bgmGen
      R.bgm.pos = 0
      logCall("bgmStart", A._bgmGen)
    end
    return res
  end
end

local function wrapSources()
  local origNew = love.audio.newSource
  love.audio.newSource = function(a, ...)
    local src = origNew(a, ...)
    if type(a) == "userdata" and a.typeOf and a:typeOf("SoundData") and src then
      srcData[src] = a
    end
    return src
  end
  local probe = love.audio.newSource(love.sound.newSoundData(16, 44100, 16, 1), "static")
  local mt = getmetatable(probe)
  local methods = type(mt.__index) == "table" and mt.__index or mt
  print("[rec] source methods table", tostring(type(mt.__index)), tostring(methods.play ~= nil))
  local oPlay, oStop, oPause, oIsPlaying, oTell = methods.play, methods.stop, methods.pause, methods.isPlaying, methods.tell
  local function virtualPlaying(self)
    local inst = active[self]
    if not inst then return nil end
    if inst.loop then return true end
    local n = inst.count - inst.pos
    return (relFrame() - inst.frame) * inst.rate / 60 < n
  end
  methods.isPlaying = function(self, ...)
    if R.armed then
      local v = virtualPlaying(self)
      if v ~= nil then return v end
    end
    return oIsPlaying(self, ...)
  end
  methods.play = function(self, ...)
    local sd = srcData[self]
    if sd and R.armed then
      local was = virtualPlaying(self)
      if was == nil then was = oIsPlaying(self) end
      if not was then
        local idx = R.soundIndex[sd]
        if not idx then
          R.sounds[#R.sounds + 1] = sd
          idx = #R.sounds
          R.soundIndex[sd] = idx
        end
        local inst = { snd = idx, frame = relFrame(), pos = oTell(self, "samples") or 0,
          vol = self:getVolume(), loop = self:isLooping(), count = sd:getSampleCount(), rate = sd:getSampleRate() }
        R.instances[#R.instances + 1] = inst
        active[self] = inst
      end
    end
    return oPlay(self, ...)
  end
  local function ender(orig)
    return function(self, ...)
      local inst = active[self]
      if inst then
        if virtualPlaying(self) then inst.stop = relFrame() end
        active[self] = nil
      end
      return orig(self, ...)
    end
  end
  methods.stop = ender(oStop)
  methods.pause = ender(oPause)
end

local function patchTap()
  local U = require("tests.drivers.util")
  local origTap = U.tap
  U.tap = function(game, btn)
    if R.armed and btn == "a" and (R.textHold or 0) > 0 then
      local M = package.loaded["src.ui.game3.message"]
      local B = package.loaded["src.core.game3.battle"]
      local BU = package.loaded["src.core.game3.battle.ui"]
      if B and B.isActive() and BU and BU.dialogPending and BU.dialogPending() then
        for _ = 1, 40 do
          if M and M.isOpen() then break end
          coroutine.yield()
        end
      end
      for _ = 1, 900 do
        if not (M and M.isOpen()) then break end
        if M.isWaiting() and R.waitStart and R.tick - R.waitStart >= R.textHold then break end
        coroutine.yield()
      end
    end
    return origTap(game, btn)
  end
end

function R.install(game, opts)
  opts = opts or {}
  R.textHold = opts.textHold or tonumber(os.getenv("EM_REC_TEXT_HOLD")) or 50
  patchTap()
  R.game = game
  R.dir = opts.dir or ".bazinga/emerald/rec/tmp"
  R.fast = opts.fast or 200
  os.execute('mkdir -p "' .. R.dir .. '"')
  wrapAudio()
  wrapSources()
  local origUpdate = game.update
  game.update = function(self, dt)
    origUpdate(self, dt)
    R.onTick()
  end
  local Renderer = require("src.render.Renderer")
  local origBegin = Renderer.beginWorldPass
  Renderer.beginWorldPass = function(...)
    R.worldThisFrame = true
    return origBegin(...)
  end
  local origDraw = love.draw
  love.draw = function(...)
    origDraw(...)
    R.onDraw()
  end
  game.driverSpeed = R.fast
end

function R.onTick()
  R.tick = R.tick + 1
  local A = Audio()
  local playing = A and A._bgmGen ~= nil and not A._bgmPaused and R.bgm.song ~= nil
  if A and A._bgmGen == nil then R.bgm.song = nil end
  if R.armed then
    local vol = 0
    if A and A._bgmSource then vol = A._bgmSource:getVolume() end
    R.frameBgm[relFrame()] = { song = playing and R.bgm.song or 0, pos = R.bgm.pos, vol = playing and vol or 0 }
    R.pendingFrames = (R.pendingFrames or 0) + 1
  end
  if playing then R.bgm.pos = R.bgm.pos + rate() / 60 end
  local M = package.loaded["src.ui.game3.message"]
  local waiting = M and M.isWaiting() and (M._page or 0) or false
  if waiting ~= R.waitKey then
    R.waitKey = waiting
    R.waitStart = waiting and R.tick or nil
  end
  if R.onTickHook then R.onTickHook() end
end

function R.arm(label)
  if R.armed then return end
  R.armed = true
  R.armTick = R.tick
  R.game.driverSpeed = 1
  R.pendingFrames = 0
  pcall(love.window.setVSync, 0)
  R.video = io.popen(string.format(
    'ffmpeg -loglevel error -y -f rawvideo -pix_fmt rgba -s 240x160 -r 60 -i - -c:v ffv1 "%s/frames.mkv"', R.dir), "w")
  R.t0 = love.timer.getTime()
  R.behind = 0
  R.mark(label or "arm")
  print("[rec] armed at tick " .. R.tick)
end

function R.mark(label)
  R.marks[#R.marks + 1] = { frame = relFrame(), label = label }
  print(string.format("[rec] mark %d %s", relFrame(), label))
end

function R.onDraw()
  if not (R.armed and R.video) then return end
  local n = R.pendingFrames or 0
  if n <= 0 then return end
  R.pendingFrames = 0
  local Renderer = package.loaded["src.render.Renderer"]
  if not R.cap then
    R.cap = love.graphics.newCanvas(240, 160, { dpiscale = 1 })
    R.cap:setFilter("nearest", "nearest")
  end
  love.graphics.push("all")
  love.graphics.setCanvas(R.cap)
  love.graphics.origin()
  love.graphics.setBlendMode("alpha")
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(1, 1, 1, 1)
  local world = Renderer and Renderer.worldCanvas
  if R.worldThisFrame and world then
    love.graphics.draw(world, math.floor((240 - world:getWidth()) / 2), math.floor((160 - world:getHeight()) / 2))
  end
  if Renderer and Renderer.canvas then love.graphics.draw(Renderer.canvas, 0, 0) end
  love.graphics.setCanvas()
  love.graphics.pop()
  R.worldThisFrame = false
  local bytes = R.cap:newImageData():getString()
  for _ = 1, n do
    R.video:write(bytes)
    R.frames = R.frames + 1
  end
  if R.frames % 600 == 0 then
    print(string.format("[rec] %d frames, %.1f fps", R.frames, R.frames / (love.timer.getTime() - R.t0)))
  end
end

local function writeFloat(path, L, R2, n, mono)
  local buf = ffi.new("float[?]", n * 2)
  for i = 1, n do
    local l, r = L[i] or 0, R2[i] or 0
    if mono then
      local m = (l + r) * 0.5
      l, r = m, m
    end
    buf[(i - 1) * 2] = l
    buf[(i - 1) * 2 + 1] = r
  end
  local f = assert(io.open(path, "wb"))
  f:write(ffi.string(buf, n * 8))
  f:close()
end

function R.finish()
  if not R.armed then return end
  R.armed = false
  if R.video then R.video:close() R.video = nil end
  R.game.driverSpeed = R.fast
  local A = require("src.core.game3.audio")
  local Player = require("src.core.game3.m4a_player")
  local sr = rate()
  local need = {}
  for f = 0, R.frames - 1 do
    local b = R.frameBgm[f]
    if b and b.song ~= 0 then
      need[b.song] = math.max(need[b.song] or 0, b.pos + sr / 60 + 1)
    end
  end
  local meta = assert(io.open(R.dir .. "/audio.txt", "w"))
  meta:write(string.format("rate %d\nframes %d\nmono %s\nbehind %d\n", sr, R.frames, tostring(A._mono), R.behind or 0))
  for id, n in pairs(need) do
    local t0 = love.timer.getTime()
    local L, Rr = Player.bakeSong(A._pack, A._cache, id, { raw = true, maxSec = n / sr + 0.5, sampleRate = sr })
    writeFloat(string.format("%s/song_%d.f32", R.dir, id), L, Rr, #L, A._mono)
    meta:write(string.format("song %d %d\n", id, #L))
    print(string.format("[rec] baked song %d: %d samples (%.1fs) in %.1fs", id, #L, #L / sr, love.timer.getTime() - t0))
  end
  for i, sd in ipairs(R.sounds) do
    local f = assert(io.open(string.format("%s/snd_%d.raw", R.dir, i), "wb"))
    f:write(sd:getString())
    f:close()
    meta:write(string.format("snd %d %d %d %d %d\n", i, sd:getSampleRate(), sd:getBitDepth(), sd:getChannelCount(),
      sd:getSampleCount()))
  end
  for _, inst in ipairs(R.instances) do
    meta:write(string.format("inst %d %d %d %s %.4f %s\n", inst.snd, inst.frame, inst.pos, tostring(inst.stop or -1),
      inst.vol, tostring(inst.loop)))
  end
  for f = 0, R.frames - 1 do
    local b = R.frameBgm[f] or { song = 0, pos = 0, vol = 0 }
    meta:write(string.format("bgm %d %d %d %.4f\n", f, b.song, math.floor(b.pos), b.vol))
  end
  for _, m in ipairs(R.marks) do meta:write(string.format("mark %d %s\n", m.frame, m.label)) end
  meta:close()
  local cf = assert(io.open(R.dir .. "/calls.txt", "w"))
  cf:write(table.concat(R.calls, "\n"), "\n")
  cf:close()
  print(string.format("[rec] finished: %d frames, %d sounds, %d instances, behind %d", R.frames, #R.sounds,
    #R.instances, R.behind or 0))
end

return R
