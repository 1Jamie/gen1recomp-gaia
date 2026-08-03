-- Blue/Yellow generated art lives under blue/ / yellow/. Desktop exposes it
-- via mountVersion; NX fused often cannot. Assets.resolve must point
-- newImage at the real save-dir path (yellow/assets/generated/...).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local GameVersion = require("src.core.GameVersion")
local CacheFs = require("src.import.CacheFs")
local Assets = require("src.render.Assets")

local PNG = "assets/generated/tilesets/reds_house.png"
local savedPrefix = CacheFs.prefix
local savedVersion = GameVersion.get()

local function clearPath(path)
  love.filesystem.remove(path)
end

-- --- resolve → yellow/<path> when that file exists
GameVersion.set("yellow")
CacheFs.prefix = ""
love.filesystem.write("yellow/" .. PNG, "yellow-png-bytes")
clearPath(PNG)
eq(Assets.resolve(PNG), "yellow/" .. PNG,
  "resolve maps generated path to yellow/ when unprefixed is missing")

Assets.flush()
local img = Assets.image(PNG)
check(img ~= nil, "Assets.image opens the yellow/ save-dir path")
eq(img.path, "yellow/" .. PNG, "newImage receives the versioned path")

local id = Assets.imageData(PNG)
check(id ~= nil, "Assets.imageData opens the yellow/ save-dir path")
eq(id.path, "yellow/" .. PNG, "newImageData receives the versioned path")

-- --- Blue
GameVersion.set("blue")
Assets.flush()
love.filesystem.write("blue/" .. PNG, "blue-png-bytes")
clearPath(PNG)
clearPath("yellow/" .. PNG)
eq(Assets.resolve(PNG), "blue/" .. PNG,
  "resolve maps generated path to blue/")
check(Assets.image(PNG) ~= nil, "Assets.image opens the blue/ save-dir path")

-- --- Red stays unprefixed
GameVersion.set("red")
Assets.flush()
love.filesystem.write(PNG, "red-png-bytes")
clearPath("blue/" .. PNG)
eq(Assets.resolve(PNG), PNG, "Red resolve keeps the unprefixed path")
check(Assets.image(PNG) ~= nil, "Assets.image loads Red from the save-dir root")

-- --- Prefer versioned file over a stale empty unprefixed stub
GameVersion.set("yellow")
Assets.flush()
love.filesystem.write(PNG, "")
love.filesystem.write("yellow/" .. PNG, "yellow-real-png")
eq(Assets.resolve(PNG), "yellow/" .. PNG,
  "resolve prefers yellow/ even when an empty unprefixed stub exists")

-- --- Non-generated paths untouched
eq(Assets.resolve("assets/launcher/gear.png"), "assets/launcher/gear.png",
  "resolve leaves non-generated paths alone")

-- --- readActive still works for Data:load
GameVersion.set("yellow")
CacheFs.prefix = "yellow/"
love.filesystem.write("yellow/data/generated/maps.lua", "return { ok = true }")
local luaBytes = CacheFs.readActive("data/generated/maps.lua")
check(type(luaBytes) == "string" and luaBytes:find("ok", 1, true),
  "readActive still finds yellow/data/generated when CacheFs.prefix is set")

CacheFs.prefix = savedPrefix
GameVersion.set(savedVersion)
Assets.flush()
clearPath(PNG)
clearPath("yellow/" .. PNG)
clearPath("blue/" .. PNG)
clearPath("yellow/data/generated/maps.lua")

T.finish()
