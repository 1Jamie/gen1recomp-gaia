-- NX fused often cannot mount blue|yellow onto assets/generated. Assets.resolve
-- rewrites to the real save-dir path on NX only; desktop/Android stay unchanged.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local GameVersion = require("src.core.GameVersion")
local Platform = require("src.core.Platform")
local CacheFs = require("src.import.CacheFs")
local Assets = require("src.render.Assets")

local PNG = "assets/generated/tilesets/reds_house.png"
local savedPrefix = CacheFs.prefix
local savedVersion = GameVersion.get()
local savedSystem = love.system

local function clearPath(path)
  love.filesystem.remove(path)
end

local function setOS(osName)
  love.system = {
    getOS = function() return osName end,
  }
  Platform._resetForTests()
end

-- --- Desktop: no rewrite even when yellow/ exists
setOS("OS X")
GameVersion.set("yellow")
CacheFs.prefix = ""
love.filesystem.write("yellow/" .. PNG, "yellow-png-bytes")
clearPath(PNG)
eq(Assets.resolve(PNG), PNG,
  "desktop resolve leaves generated paths unprefixed (mount owns overlay)")

-- --- NX: rewrite to yellow/<path>
setOS("NX")
Assets.flush()
eq(Assets.resolve(PNG), "yellow/" .. PNG,
  "NX resolve maps generated path to yellow/ when unprefixed is missing")

local img = Assets.image(PNG)
check(img ~= nil, "NX Assets.image opens the yellow/ save-dir path")
eq(img.path, "yellow/" .. PNG, "NX newImage receives the versioned path")

local id = Assets.imageData(PNG)
check(id ~= nil, "NX Assets.imageData opens the yellow/ save-dir path")
eq(id.path, "yellow/" .. PNG, "NX newImageData receives the versioned path")

-- --- NX Blue
GameVersion.set("blue")
Assets.flush()
love.filesystem.write("blue/" .. PNG, "blue-png-bytes")
clearPath(PNG)
clearPath("yellow/" .. PNG)
eq(Assets.resolve(PNG), "blue/" .. PNG, "NX resolve maps generated path to blue/")
check(Assets.image(PNG) ~= nil, "NX Assets.image opens the blue/ save-dir path")

-- --- NX Red stays unprefixed
GameVersion.set("red")
Assets.flush()
love.filesystem.write(PNG, "red-png-bytes")
clearPath("blue/" .. PNG)
eq(Assets.resolve(PNG), PNG, "NX Red resolve keeps the unprefixed path")
check(Assets.image(PNG) ~= nil, "NX Assets.image loads Red from the save-dir root")

-- --- NX prefers versioned file over empty unprefixed stub
GameVersion.set("yellow")
Assets.flush()
love.filesystem.write(PNG, "")
love.filesystem.write("yellow/" .. PNG, "yellow-real-png")
eq(Assets.resolve(PNG), "yellow/" .. PNG,
  "NX resolve prefers yellow/ even when an empty unprefixed stub exists")

-- --- Android: same as desktop (no rewrite)
setOS("Android")
Assets.flush()
eq(Assets.resolve(PNG), PNG,
  "Android resolve leaves generated paths unprefixed")

-- --- Non-generated paths untouched
eq(Assets.resolve("assets/launcher/gear.png"), "assets/launcher/gear.png",
  "resolve leaves non-generated paths alone")

-- --- readActive still works for Data:load (all platforms)
setOS("NX")
GameVersion.set("yellow")
CacheFs.prefix = "yellow/"
love.filesystem.write("yellow/data/generated/maps.lua", "return { ok = true }")
local luaBytes = CacheFs.readActive("data/generated/maps.lua")
check(type(luaBytes) == "string" and luaBytes:find("ok", 1, true),
  "readActive still finds yellow/data/generated when CacheFs.prefix is set")

-- ChipSynth.loadBanks: NX prefers the versioned prefix; desktop untouched
setOS("NX")
GameVersion.set("yellow")
local PROG = "assets/generated/audio/programs.bin"
local PROG_BYTES = string.rep("\0", 0x4000 * 2)
love.filesystem.write("yellow/" .. PROG, PROG_BYTES)
clearPath(PROG)
local ChipSynth = require("src.core.ChipSynth")
ChipSynth.invalidateBanks()
local progData = { audio = { programFile = PROG, bankOrder = { 1, 2 } } }
local okB, banks = pcall(ChipSynth._loadBanksForTest, progData)
check(okB and banks ~= nil, "NX loadBanks reads yellow/programs.bin")
if okB and banks then
  eq(banks[1], PROG_BYTES:sub(1, 0x4000), "loadBanks returns the bank 1 bytes")
end

-- ChipSynth honors an explicit programPrefix (worker path; worker has no
-- GameVersion state, so the prefix must arrive via the audio payload)
ChipSynth.invalidateBanks()
local workerData = { audio = {
  programFile = PROG,
  programPrefix = "yellow/",
  bankOrder = { 1, 2 },
} }
local okW, wbanks = pcall(ChipSynth._loadBanksForTest, workerData)
check(okW and wbanks ~= nil, "loadBanks uses audio.programPrefix when set")
if okW and wbanks then
  eq(wbanks[1], PROG_BYTES:sub(1, 0x4000),
    "programPrefix loads the same bank 1 bytes")
end

-- Blue gets the same treatment
ChipSynth.invalidateBanks()
GameVersion.set("blue")
love.filesystem.write("blue/" .. PROG, PROG_BYTES)
clearPath("yellow/" .. PROG)
local okBl, bbanks = pcall(ChipSynth._loadBanksForTest, progData)
check(okBl and bbanks ~= nil, "NX loadBanks reads blue/programs.bin")
clearPath("blue/" .. PROG)
GameVersion.set("yellow")
love.filesystem.write("yellow/" .. PROG, PROG_BYTES)

-- ChipAudio.slimAudio hands the NX prefix to the worker
local ChipAudio = require("src.core.ChipAudio")
local slim = ChipAudio._slimAudioForTest
  and ChipAudio._slimAudioForTest(progData)
  or nil
if slim then
  eq(slim.programPrefix, "yellow/",
    "slimAudio passes the NX cache prefix to the worker")
end

-- Sound.playPikaCry: NX rewrites the pika-cry path before newSource
setOS("NX")
GameVersion.set("yellow")
local Sound = require("src.core.Sound")
local CRY = "assets/generated/audio/pika_cries/cry_01.wav"
love.filesystem.write("yellow/" .. CRY, "RIFF\x24\x00\x00\x00WAVEfmt ")
clearPath(CRY)
local lastNewSource
local savedAudio = love.audio
love.audio = {
  newSource = function(path, mode)
    lastNewSource = path
    return setmetatable({
      stop = function() end,
      play = function() end,
      setVolume = function() end,
    }, { __index = function() return function() end end })
  end,
}
Sound.invalidate("pikacry:1")
local cryData = { audio = { pikaCries = 1 } }
local src = Sound.playPikaCry(cryData, 1)
love.audio = savedAudio
eq(lastNewSource, "yellow/" .. CRY, "NX playPikaCry loads yellow/pika_cries")

-- TitleState/YellowIntro/IntroMovie use Assets.resolve (NX prefix); a static
-- source check keeps them from regressing to raw newImage(path).
local function srcHasResolve(path)
  local f = io.open(path, "r")
  if not f then return false end
  local body = f:read("*a")
  f:close()
  return body:find("Assets%.resolve", 1, false) ~= nil
    or body:find('require%("src%.render%.Assets"%)%.resolve', 1, false) ~= nil
end
check(srcHasResolve("src/ui/TitleState.lua"),
  "TitleState loads art via Assets.resolve")
check(srcHasResolve("src/ui/YellowIntro.lua"),
  "YellowIntro loads art via Assets.resolve")
check(srcHasResolve("src/ui/IntroMovie.lua"),
  "IntroMovie loads art via Assets.resolve")

clearPath("yellow/" .. PROG)
clearPath("yellow/" .. CRY)

love.system = savedSystem
Platform._resetForTests()
CacheFs.prefix = savedPrefix
GameVersion.set(savedVersion)
Assets.flush()
clearPath(PNG)
clearPath("yellow/" .. PNG)
clearPath("blue/" .. PNG)
clearPath("yellow/data/generated/maps.lua")

T.finish()
