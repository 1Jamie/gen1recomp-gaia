package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
love = love or require("tests.love_stub")

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

T.finish("launcher secret emerald")
