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
