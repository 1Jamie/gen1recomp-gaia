package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
love = love or require("tests.love_stub")

local realTime, now = os.time, 1790855999
os.time = function(t)
  if t then return realTime(t) end
  return now
end

love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end

local Kit = require("src.ui.kit.Kit")
local GameVersion = require("src.core.GameVersion")
local SaveData = require("src.core.SaveData")
local SecretGames = require("src.import.SecretGames")
local RomImporter = require("src.import.RomImporter")
local LauncherView = require("src.import.LauncherView")

love.graphics.getDimensions = function() return 1280, 720 end
love.graphics.getPixelDimensions = function() return 1280, 720 end

local function ids(list)
  local out = {}
  for _, g in ipairs(list) do out[#out + 1] = type(g) == "table" and g.id or g end
  return " " .. table.concat(out, " ") .. " "
end

local function drawRects(imp)
  Kit.focusId = nil
  local ok, err = pcall(LauncherView.draw, imp)
  check(ok, "launcher frame draws: " .. tostring(err))
  ok, err = pcall(LauncherView.draw, imp)
  check(ok, "second launcher frame draws: " .. tostring(err))
  local rects = {}
  for i = 1, (Kit._navPrevN or 0) do
    local slot = Kit._nav[i]
    if slot and slot.id then rects[slot.id] = slot end
  end
  return rects
end

local function newLauncher()
  local imp = RomImporter.new(function() end, { launcher = true })
  for _, v in ipairs(GameVersion.ORDER) do imp.ready[v] = true end
  return imp
end

SecretGames.reload()
check(not SecretGames.visible("emerald"), "emerald starts locked")
check(SecretGames.visible("red") and SecretGames.visible("firered"),
  "ordinary games are always visible")

local imp = newLauncher()
check(not ids(LauncherView.gameTabs(imp)):find(" emerald ", 1, true),
  "locked: emerald is not in the launcher's game list")
check(ids(LauncherView.gameTabs(imp)):find(" leafgreen ", 1, true) ~= nil,
  "locked: the rest of the list is intact")
check(not ids(SecretGames.order(imp)):find(" emerald ", 1, true),
  "locked: emerald is not in the launcher's version order")
check(ids(SecretGames.order({ launcher = false })):find(" emerald ", 1, true) ~= nil,
  "scripted importers still see emerald")

imp._gamePopup = true
local rects = drawRects(imp)
check(rects["gamepop-red"] ~= nil, "the choose-game popup draws")
check(rects["gamepop-emerald"] == nil, "locked: no emerald row in the popup")
imp._gamePopup = nil

imp:_switchTab("emerald")
check(imp.tab ~= "emerald", "locked: switching to emerald is refused")
imp.tab = "leafgreen"
imp:_cycleTab(1)
check(imp.tab ~= "emerald", "locked: tab cycling skips emerald")

local emeraldSha = GameVersion.info("emerald").sha1
check(imp:_versionForSha1(emeraldSha) == nil,
  "locked: the launcher treats the emerald sha1 as unknown")
check(RomImporter._versionForSha1({ launcher = false }, emeraldSha) == "emerald",
  "scripted import still recognizes emerald")

local realData = love.data
love.data = {
  hash = function() return "digest" end,
  encode = function() return emeraldSha end,
}
imp:startData(string.rep("\0", 16 * 1024 * 1024), "emerald.gba")
love.data = realData
check(imp.workState == "error" and tostring(imp.detail):find("^Unsupported ROM") ~= nil,
  "locked: an emerald dump gets the unsupported-ROM message")
check(not tostring(imp.detail):find("Emerald", 1, true),
  "locked: the unsupported-ROM message does not name emerald")
imp.workState, imp.detail = nil, ""

for _ = 1, SecretGames.TAPS - 1 do imp:_logoTap() end
check(not imp._secretPopup, "19 logo presses: no popup")
imp:_logoTap()
check(imp._secretPopup == true, "20th logo press: the BLITZ popup opens")
rects = drawRects(imp)
check(rects["secret-ok"] ~= nil, "the popup has an OK button")

imp:_confirmSecret()
check(imp._secretPopup == nil, "OK closes the popup")
check(SaveData.loadOptions().secretEmerald == true, "OK persists secretEmerald")
check(SecretGames.visible("emerald"), "unlocked: emerald is visible")
check(ids(LauncherView.gameTabs(imp)):find(" emerald ", 1, true) ~= nil,
  "unlocked: emerald is back in the game list")
check(imp:_versionForSha1(emeraldSha) == "emerald",
  "unlocked: the launcher recognizes the emerald sha1")
imp._gamePopup = true
rects = drawRects(imp)
check(rects["gamepop-emerald"] ~= nil, "unlocked: emerald row in the popup")
imp._gamePopup = nil

local taps = imp._logoTaps
imp:_logoTap()
check(imp._logoTaps == taps and not imp._secretPopup,
  "unlocked: further logo presses do nothing")

SecretGames.reload()
check(SecretGames.visible("emerald"), "reloaded settings: emerald stays visible")
local fresh = newLauncher()
check(ids(LauncherView.gameTabs(fresh)):find(" emerald ", 1, true) ~= nil,
  "a new launcher lists emerald after unlock")
check(fresh._logoTaps == nil, "the tap counter starts over with each launcher")

T.eq(SecretGames.EMERALD_RELEASE_AT, 1790856000, "release is October 1 at 12 UTC")

SaveData.saveOptions({ secretEmerald = false, lastVersion = "blue" })
SecretGames.reload()
local timed = newLauncher()
local lockedTabs = LauncherView.gameTabs(timed)
local lockedRev = SecretGames.rev
check(not ids(lockedTabs):find(" emerald ", 1, true), "one second early stays locked")
for _ = 1, SecretGames.TAPS do timed:_logoTap() end
check(timed._secretPopup == true, "a pre-release BLITZ popup can be open at the deadline")

local realSaveOptions, writes = SaveData.saveOptions, 0
SaveData.saveOptions = function(...)
  writes = writes + 1
  return realSaveOptions(...)
end
now = 1790856000
local releasedTabs = LauncherView.gameTabs(timed)
check(releasedTabs ~= lockedTabs, "deadline invalidates the already-cached game list")
T.eq(#releasedTabs, 9, "deadline exposes all nine games")
check(ids(releasedTabs):find(" emerald ", 1, true) ~= nil, "deadline includes Emerald")
T.eq(SecretGames.rev, lockedRev + 1, "scheduled unlock advances the revision once")
T.eq(writes, 1, "scheduled unlock persists once")
local releasedOptions = SaveData.loadOptions()
check(releasedOptions.secretEmerald == true, "scheduled unlock persists secretEmerald")
T.eq(releasedOptions.lastVersion, "blue", "unlock preserves unrelated launcher options")

timed:update(1 / 60)
check(timed._secretPopup == nil and timed._logoTaps == nil,
  "active launcher silently clears an already-open BLITZ popup and tap counter")
timed._gamePopup = true
rects = drawRects(timed)
check(rects["gamepop-emerald"] ~= nil and rects["secret-ok"] == nil,
  "the active launcher draws Emerald without a BLITZ confirmation")
timed._gamePopup = nil
check(timed:_versionForSha1(emeraldSha) == "emerald", "release recognizes Emerald immediately")
for _ = 1, 10 do
  timed:update(1 / 60)
  timed:_logoTap()
  T.eq(LauncherView.gameTabs(timed), releasedTabs, "released game list remains cached")
end
T.eq(writes, 1, "repeated frames and logo taps do not repeat persistence")
T.eq(SecretGames.rev, lockedRev + 1, "repeated frames do not repeat cache invalidation")
check(timed._secretPopup == nil and timed._logoTaps == nil, "released logo taps stay silent")

now = 1790856001
local releaseBoot = RomImporter.new(function() end, { launcher = true, initialTab = "emerald" })
T.eq(releaseBoot.tab, "emerald", "a launcher opened after release accepts its initial Emerald tab")
SecretGames.reload()
check(SecretGames.visible("emerald"), "scheduled unlock survives a settings reload")
T.eq(writes, 1, "reloading the persisted unlock does not rewrite options")
now = 1790855999
SecretGames.reload()
check(SecretGames.visible("emerald"), "a clock rollback cannot relock a persisted unlock")
T.eq(writes, 1, "clock rollback does not rewrite options")
check(ids(SecretGames.order({ launcher = false })):find(" emerald ", 1, true) ~= nil,
  "scheduled availability preserves nonlauncher import recognition")

SaveData.saveOptions = realSaveOptions
SaveData.saveOptions({ secretEmerald = false })
SecretGames.reload()
local polling = newLauncher()
LauncherView.gameTabs(polling)
now = 1790856000
polling:update(1 / 60)
check(SaveData.loadOptions().secretEmerald == true,
  "an already-open launcher update alone applies the scheduled unlock")
check(ids(LauncherView.gameTabs(polling)):find(" emerald ", 1, true) ~= nil,
  "an already-open launcher needs no restart to expose Emerald")

now = 1790855999
SaveData.saveOptions({ secretEmerald = false })
SecretGames.reload()
now = 1790856000
local initial = RomImporter.new(function() end, { launcher = true, initialTab = "emerald" })
T.eq(initial.tab, "emerald", "a fresh deadline boot unlocks before initial tab validation")
check(SaveData.loadOptions().secretEmerald == true, "a fresh deadline boot persists the unlock")

os.time = realTime
T.finish("launcher secret emerald")
