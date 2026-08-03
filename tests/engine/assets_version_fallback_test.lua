-- Yellow/Blue-only NX: PhysFS may hide prefixed assets/generated trees.
-- Assets must fall back through CacheFs.readActive like Data:load does.
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

-- --- readActive: Yellow-prefixed bytes without unprefixed PhysFS visibility
GameVersion.set("yellow")
CacheFs.prefix = ""
love.filesystem.write("yellow/" .. PNG, "yellow-png-bytes")
clearPath(PNG)
eq(CacheFs.readActive(PNG), "yellow-png-bytes",
  "readActive finds yellow/<rel> when unprefixed path is missing")

-- --- Assets.image fallback (Yellow-only mount hole)
Assets.flush()
local img = Assets.image(PNG)
check(img ~= nil, "Assets.image loads Yellow tileset via readActive fallback")
eq(img.path, PNG, "fallback Image keeps the logical generated path name")

-- --- Assets.imageData fallback
local id = Assets.imageData(PNG)
check(id ~= nil, "Assets.imageData loads Yellow tileset via readActive fallback")
eq(id.path, PNG, "fallback ImageData keeps the logical generated path name")

-- --- Blue prefix
GameVersion.set("blue")
Assets.flush()
love.filesystem.write("blue/" .. PNG, "blue-png-bytes")
clearPath(PNG)
clearPath("yellow/" .. PNG)
local blueImg = Assets.image(PNG)
check(blueImg ~= nil, "Assets.image loads Blue tileset via readActive fallback")

-- --- Red primary path (unprefixed file visible → no fallback needed)
GameVersion.set("red")
Assets.flush()
love.filesystem.write(PNG, "red-png-bytes")
clearPath("blue/" .. PNG)
local redImg = Assets.image(PNG)
check(redImg ~= nil, "Assets.image loads Red tileset from unprefixed path")
eq(love.filesystem.read(PNG), "red-png-bytes",
  "Red still stores generated assets at the save-dir root")

-- --- Missing generated file: no invented bytes
GameVersion.set("yellow")
Assets.flush()
clearPath(PNG)
clearPath("yellow/" .. PNG)
clearPath("blue/" .. PNG)
eq(CacheFs.readActive(PNG), nil,
  "readActive returns nil when the file is absent in every tree")

-- --- Non-generated paths never hit the versioned asset tree
love.filesystem.write("yellow/" .. PNG, "should-not-leak")
eq(CacheFs.readActive("assets/launcher/missing_chip.png"), nil,
  "readActive does not remap unrelated paths onto yellow generated assets")

-- --- readActive with CacheFs.prefix set (Data:load second try)
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
