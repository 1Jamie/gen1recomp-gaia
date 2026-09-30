local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_music_transition"

local function le16(n)
  return string.char(n % 256, math.floor(n / 256) % 256)
end
local function le32(n)
  return le16(n % 65536) .. le16(math.floor(n / 65536))
end
local function writeWav(path, sd)
  local data, rate, channels = sd:getString(), sd:getSampleRate(), sd:getChannelCount()
  local file = assert(io.open(path, "wb"))
  file:write("RIFF", le32(36 + #data), "WAVEfmt ", le32(16), le16(1), le16(channels),
    le32(rate), le32(rate * channels * 2), le16(channels * 2), le16(16), "data", le32(#data), data)
  file:close()
end
local function peak(sd)
  local value = 0
  for i = 0, sd:getSampleCount() - 1 do
    for ch = 1, sd:getChannelCount() do value = math.max(value, math.abs(sd:getSample(i, ch))) end
  end
  return value
end

return function(game)
  local failures = 0
  local deadline = love.timer.getTime() + 25
  local Audio, realOut, realCmd, realSource
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function waitUntil(pred, seconds)
    local untilTime = math.min(deadline, love.timer.getTime() + seconds)
    while love.timer.getTime() < untilTime do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end
  local ok, err = xpcall(function()
    if not check((os.getenv("POKEPORT_IDENTITY") or ""):match("^bsa0930%-") ~= nil,
      "isolated campaign identity") then return end
    game.driverSpeed = 1
    game.speedOverride = 1
    if not check(waitUntil(function() return game.boot ~= nil end, 4), "Gen3 boot ready") then return end
    local Version = require("src.core.GameVersion")
    local version = Version.get()
    local emerald = version == "emerald"
    local mapA, mapB = emerald and "EM_LITTLEROOT_TOWN" or "FR_PALLET_TOWN",
      emerald and "EM_ROUTE101" or "FR_ROUTE_1"
    local x, y = emerald and 5 or 10, emerald and 9 or 8
    game:_handleBootAction({ action = "new_game", name = "RED",
      start = { map = mapA, x = x, y = y, facing = "down" } })
    Audio = require("src.core.game3.audio")
    local Map = require("src.core.game3.map")
    local Runtime = require("src.core.game3.runtime")
    local Message = require("src.ui.game3.message")
    local Field = require("src.core.game3.field")
    local Hud = require("src.ui.game3.hud")
    local Fade = require("src.ui.game3.fade")
    local adapter = require("src.core.game3.scripting.adapters").host(nil, game, nil)
    if not check(waitUntil(function()
      if Message.isOpen() then U.tap(game, "b") end
      return not Field.locked and not Message.isOpen() and not Hud.busy() and not Fade.active
    end, 3), "Gen3 field settled") then return end
    print(string.format("AUDIO ready=%s root=%s pack=%s worker=%s", tostring(Audio._ready),
      tostring(Audio._root), tostring(Audio._pack ~= nil), tostring(Audio._worker ~= nil and Audio._worker ~= false)))
    if not check(waitUntil(Audio.isReady, 3), "real audio pack ready") then return end
    local defs = game.data and game.data.maps
    local rawA, rawB = defs and defs[mapA] and defs[mapA].music, defs and defs[mapB] and defs[mapB].music
    local a, b = Audio.resolveSong(rawA), Audio.resolveSong(rawB)
    print(string.format("MAP SONGS A=%s raw=%s id=%s B=%s raw=%s id=%s", mapA, tostring(rawA),
      tostring(a), mapB, tostring(rawB), tostring(b)))
    if not check(type(a) == "number" and type(b) == "number" and a ~= b and Audio.songInfo(a)
      and Audio.songInfo(b), "cached neighboring maps resolve distinct BGM") then return end
    local ff = Audio.songs().MUS_LEVEL_UP
    if not check(ff and waitUntil(function() return Audio._fanfareSd[ff] ~= nil end, 4),
      "real fanfare PCM baked") then return end

    local captured, commands = {}, {}
    local messages = setmetatable({}, { __mode = "k" })
    realOut, realCmd, realSource = Audio._outCh, Audio._cmdCh, Audio._bgmSource
    if not check(realOut and realCmd and realSource, "real worker and queueable source ready") then return end
    Audio._outCh = setmetatable({}, { __index = function(_, key)
      if key == "pop" then return function()
        local msg = realOut:pop()
        if type(msg) == "table" and msg.data then messages[msg.data] = msg end
        return msg
      end end
      return function(_, ...) return realOut[key](realOut, ...) end
    end })
    Audio._cmdCh = setmetatable({}, { __index = function(_, key)
      if key == "push" then return function(_, msg)
        commands[#commands + 1] = msg
        return realCmd:push(msg)
      end end
      return function(_, ...) return realCmd[key](realCmd, ...) end
    end })
    Audio._bgmSource = setmetatable({}, { __index = function(_, key)
      if key == "queue" then return function(_, sd)
        local queued = realSource:queue(sd)
        local msg = messages[sd]
        if queued ~= false and msg then
          captured[#captured + 1] = { gen = msg.gen, epoch = msg.epoch, at = msg.at, sd = sd, peak = peak(sd) }
        end
        return queued
      end end
      local value = realSource[key]
      if type(value) ~= "function" then return value end
      return function(_, ...) return value(realSource, ...) end
    end })
    local function go(map)
      Map.load(nil, game, map, { x = x, y = y, facing = "down" })
      return Runtime.getSession().map == map
    end
    local function pcm(label, from)
      local packet
      local found = waitUntil(function()
        for i = (from or 0) + 1, #captured do
          local c = captured[i]
          if c.gen == a and c.epoch == Audio._bgmEpoch and c.peak > 0 then packet = c; return true end
        end
        return false
      end, 3)
      check(found and Audio._bgmGen == a and Audio._bgmSource:isPlaying(), label .. " queues audible latest A PCM")
      if packet then
        writeWav(DIR .. "/" .. label .. ".wav", packet.sd)
        print(string.format("PCM %s gen=%s epoch=%s at=%s samples=%d peak=%.6f",
          label, tostring(packet.gen), tostring(packet.epoch), tostring(packet.at), packet.sd:getSampleCount(), packet.peak))
      end
      return found
    end
    check(U.still(game, DIR .. "/01_initial_map.png"), "initial map screenshot")
    for _, speed in ipairs({ 1, 200 }) do
      game.speedOverride = speed
      local prefix = version .. "_" .. speed .. "x"
      check(game:logicSpeed() == speed, prefix .. " uses requested simulation speed")
      check(go(mapA), prefix .. " starts on map A")
      Audio.playSong(a, { restart = true })
      if not pcm(prefix .. "_before", #captured) then return end
      local epoch, count = Audio._bgmEpoch, #commands
      Audio.playSong(a)
      check(Audio._bgmEpoch == epoch and #commands == count, prefix .. " stable same-song avoids restart")

      local from = #captured
      Audio.fadeOutAndPlay(b, 1)
      if not emerald then
        Audio.fadeDefaultBgm(1)
        check(Audio._fadeOut == nil and Audio._currentSong.id == a, prefix .. " default map replaces pending B fade")
      end
      check(go(mapA), prefix .. " reenters A during pending fade to B")
      if not pcm(prefix .. "_fade_return", from) then return end
      check(Audio._fadeOut == nil and Audio._currentSong.id == a, prefix .. " newer A owns interrupted fade")

      from = #captured
      Audio.playFanfare(ff)
      check(Audio._fanfareActive and Audio._fanfareSource and Audio._fanfareSource:isPlaying(), prefix .. " real fanfare starts")
      if not emerald then
        Audio.changeMusicTo(b)
        Audio.changeMusicTo(a)
        check(Audio._fanfareDeferred == a, prefix .. " changeMusicTo replaces deferred B with A")
        Audio.bikeMusic(true, true)
        Audio.bikeMusic(false)
        check(Audio._fanfareDeferred == a, prefix .. " bike dismount replaces deferred cycling with A")
        Audio.changeMusicTo(b)
        Audio.fadeDefaultBgm(1)
        check(Audio._fanfareDeferred == a and Audio._fanfareActive and Audio._bgmPaused,
          prefix .. " default map replaces deferred B while preserving fanfare")
      end
      check(go(mapB) and go(mapA), prefix .. " crosses B and returns A during fanfare")
      check(Audio._fanfareDeferred == a, prefix .. " latest map A replaces deferred B")
      Audio.fadeOutAndPlay(b, 1)
      check(Audio.currentMapMusic() == b, prefix .. " script fixture defers older B during fanfare")
      epoch, count = Audio._bgmEpoch, #commands
      adapter.playBgm(a)
      check(Audio.currentMapMusic() == a and Audio._fanfareDeferred == nil,
        prefix .. " actual script playBgm(A) supersedes fanfare-deferred B")
      check(Audio._fanfareActive and Audio._bgmPaused and Audio._bgmEpoch == epoch and #commands == count,
        prefix .. " actual script same-A preserves fanfare and physical continuation")
      if not check(waitUntil(function() return not Audio._fanfareActive end, 4), prefix .. " fanfare completes") then return end
      check(Audio.currentMapMusic() == a, prefix .. " actual script fanfare finishes on latest A")
      if not pcm(prefix .. "_fanfare_return", from) then return end
      check(U.still(game, DIR .. "/" .. prefix .. "_returned_map.png"), prefix .. " returned map screenshot")

      from = #captured
      Audio.fadeOutBgm(1)
      Audio.playSong(a)
      if not pcm(prefix .. "_standalone_fade", from) then return end
      check(Audio._fadeOut == nil and Audio._currentSong.id == a, prefix .. " same-song cancels standalone fade")

      Audio.playFanfare(ff)
      Audio.playSong(0)
      count = #commands
      if not check(waitUntil(function() return not Audio._fanfareActive end, 4), prefix .. " stopped-BGM fanfare completes") then return end
      local revived = false
      for i = count + 1, #commands do if commands[i].cmd == "play" then revived = true end end
      check(Audio._bgmGen == nil and Audio._currentSong == nil and not Audio._bgmSource:isPlaying()
        and not revived, prefix .. " explicit stop stays silent without revived play")
    end
  end, debug.traceback)
  if Audio and realOut then Audio._outCh, Audio._cmdCh, Audio._bgmSource = realOut, realCmd, realSource end
  if not ok then check(false, tostring(err)) end
  print((failures == 0 and "PASS" or "FAIL") .. " game3_music_transition failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end
