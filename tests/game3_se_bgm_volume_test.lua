#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local Audio = require("src.core.game3.audio")

local failed = 0
local function check(cond, msg)
  if cond then
    print("PASS " .. msg)
  else
    failed = failed + 1
    print("FAIL " .. msg)
  end
end

local function fake_source(playing)
  local s = { vol = nil, playing = playing }
  function s:setVolume(v) self.vol = v end
  function s:getVolume() return self.vol or 1 end
  function s:isPlaying() return self.playing end
  function s:stop() self.playing = false end
  function s:play() self.playing = true end
  return s
end

local bgm = fake_source(true)
Audio._bgmSource = bgm
Audio._bgmVolume = 1
Audio._duck = 1
Audio._duckHold = 0
Audio._fadeOut, Audio._fadeIn = nil, nil

local se = fake_source(true)
Audio._seSources = { se }
Audio._seMeta = { [se] = { id = 1, player = 2, duckBgm = true, loop = false } }
Audio._seByPlayer = { [2] = se }

local gone = fake_source(false)
Audio._seSources[2] = gone
Audio._seMeta[gone] = { id = 2, player = 3, duckBgm = true, loop = false }
Audio._forgetSeSource(gone)
Audio.applyGain()
check(math.abs((bgm.vol or 0) - 1) < 1e-9,
  string.format("one-shot SE leaves BGM at full volume (got %s)", tostring(bgm.vol)))

-- src/sound.c:321
Audio._duck = 85 / 256
Audio.applyGain()
check(math.abs((bgm.vol or 0) - 85 / 256) < 1e-9,
  string.format("cry still ducks BGM to 85/256 (got %s)", tostring(bgm.vol)))

Audio._duck = 1
Audio._helpActive = true
Audio.applyGain()
check(math.abs((bgm.vol or 0) - 0.5) < 1e-9, "help system halves BGM")
Audio._helpActive = false
Audio.applyGain()

local IntroSeq = require("src.core.game3.battle.intro_seq")
local quiet = IntroSeq.quietBgmForDoubleRelease
local restore = IntroSeq.restoreBgmAfterDoubleRelease
check(type(quiet) == "function" and type(restore) == "function",
  "double-intro release BGM hooks exist")
if type(quiet) == "function" and type(restore) == "function" then
  local function settle(frames)
    for _ = 1, frames do pcall(Audio.update, 1 / 60) end
  end

  -- src/pokeball.c:804
  quiet({ double = true })
  settle(30)
  check(math.abs((bgm.vol or 0) - 0.5) < 1e-9,
    string.format("double intro release holds BGM at 128/256 (got %s)", tostring(bgm.vol)))

  -- src/battle_controller_player.c:909
  restore({ double = true })
  check(math.abs((bgm.vol or 0) - 1) < 1e-9, "intro end restores BGM to 256")

  quiet({ double = false })
  check(math.abs((bgm.vol or 0) - 1) < 1e-9, "single battle release leaves BGM alone")

  local paused, resumed = 0, 0
  local realPause, realResume, realStopped = Audio.pauseBgm, Audio.resumeBgm, Audio.isBgmStopped
  Audio.pauseBgm = function() paused = paused + 1 end
  Audio.resumeBgm = function() resumed = resumed + 1 end
  Audio.isBgmStopped = function() return false end
  quiet({ double = true, multi = true })
  restore({ double = true, multi = true })
  Audio.pauseBgm, Audio.resumeBgm, Audio.isBgmStopped = realPause, realResume, realStopped
  check(paused == 1 and resumed == 1 and math.abs((bgm.vol or 0) - 1) < 1e-9,
    "multi battle release stops and continues BGM instead of halving")

  Audio._duck = 85 / 256
  Audio._duckHold = 0
  Audio._duckRestore = true
  settle(3)
  check(math.abs((bgm.vol or 0) - 1) < 1e-9, "finished cry restores BGM to 256")
end

local Anim = require("src.core.game3.battle.anim")
local AnimVm = require("src.core.game3.battle.anim_vm")
Anim._packLoaded = true
Anim._pack = { version = 6, moves = {}, quietBgmMoves = { 47, 195, 320 } }
check(type(Anim.isQuietBgmMove) == "function" and Anim.isQuietBgmMove(47)
  and Anim.isQuietBgmMove(320) and not Anim.isQuietBgmMove(10),
  "quiet BGM move list comes from the battle anim pack")

local vm = AnimVm.new()
local ended = false
vm:launch({ { op = "delay", frames = 2 }, { op = "end" } }, {
  attackerSide = "player", targetSide = "enemy", quietBgm = true,
  onEnd = function() ended = true end,
})
-- src/battle_anim.c:238
check(math.abs((bgm.vol or 0) - 0.5) < 1e-9,
  string.format("quiet BGM move anim launch halves BGM (got %s)", tostring(bgm.vol)))
for _ = 1, 30 do
  if ended then break end
  pcall(vm.update, vm, 1 / 60)
end
-- src/battle_anim.c:508
check(ended and math.abs((bgm.vol or 0) - 1) < 1e-9,
  string.format("anim end restores BGM to 256 (got %s)", tostring(bgm.vol)))

if failed > 0 then os.exit(1) end
print("game3_se_bgm_volume_test: OK")
