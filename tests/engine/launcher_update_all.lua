package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ModUpdate = require("src.mods.ModUpdate")
local LauncherMods = require("src.mods.LauncherMods")
local Platform = require("src.core.Platform")
local RomImporter = require("src.import.RomImporter")

local RELEASES = {
  { version = "2.0.0", zip = { url = "https://example.invalid/a.zip" } },
  { version = "1.0.0", zip = { url = "https://example.invalid/b.zip" } },
}

local oldBeginFetch = ModUpdate.beginFetchReleases
local oldBeginZip = ModUpdate.beginDownloadZip
local oldPumpZip = ModUpdate.pumpDownloadZip
local oldInstall = LauncherMods.installDownloadedZip
local oldDeps = LauncherMods.checkDependencies
local oldRemote = Platform.canFetchRemote

local failId = nil
local installs = {}

ModUpdate.beginFetchReleases = function() return {} end
ModUpdate.beginDownloadZip = function() return {} end
ModUpdate.pumpDownloadZip = function() return true, "install.zip" end
LauncherMods.installDownloadedZip = function(id, _, version)
  installs[#installs + 1] = id
  if id == failId then return nil, "the archive had no manifest" end
  return true, version
end
LauncherMods.checkDependencies = function() return { hasIssues = false } end
Platform.canFetchRemote = function() return true end

local function info(status, best)
  return { status = status, latest = best and best.version or nil,
           best = best, releases = RELEASES }
end

local function launcher(secondStatus)
  local ri = setmetatable({
    mods = {
      { id = "one", name = "One", version = "1.0.0", github = "a/one" },
      { id = "two", name = "Two", version = "1.0.0", github = "a/two" },
      { id = "three", name = "Three", version = "1.0.0" },
    },
    modUpdateInfo = {
      one = info("available", RELEASES[1]),
      two = info(secondStatus or "current",
        secondStatus == "available" and RELEASES[1] or nil),
    },
    activeCart = {},
  }, RomImporter)
  ri._refreshMods = function() end
  return ri
end

local function run(ri, frames)
  for _ = 1, frames or 40 do
    if not ri._updateAll then break end
    ri:_pumpUpdateAll()
    ri:_pumpModInstall()
  end
end


do
  local ri = launcher()
  local rows = ri:_updateAllRows()
  eq(#rows, 1, "only a mod whose badge says a release is available is queued")
  eq(rows[1].id, "one", "the current mod and the one with no github stay out")

  ri.modCartPlan = function() return "cart1", { pins = {} }, "gold" end
  eq(#ri:_updateAllRows(), 0, "a cart owns its mod set, so it offers no rows")
end


do
  installs = {}
  local ri = launcher("available")
  check(ri:pressUpdateAllMods(), "the press starts the queue")
  check(ri._busy ~= nil, "behind the blocking overlay")
  check(type(ri._busy.cancel) == "function", "which can be cancelled")
  check(ri._modInfoFetch ~= nil, "the release checks are refreshed first")

  ri:_pumpUpdateAll()
  eq(ri._updateAll.stage, "check", "the queue waits for them to drain")
  eq(#installs, 0, "and installs nothing meanwhile")

  ri._modInfoFetch = nil
  ri:_pumpUpdateAll()
  eq(ri._updateAll.total, 2, "then queues every outdated mod")

  ri:_pumpUpdateAll()
  eq(ri._updateAll.index, 1, "one row is started")
  ri:_pumpUpdateAll()
  eq(ri._updateAll.index, 1, "and the next waits for it, not for the frame")
  eq(#installs, 0, "nothing has unzipped yet")

  run(ri)
  eq(ri._updateAll, nil, "the queue finishes")
  eq(#installs, 2, "having installed both rows")
  eq(installs[1], "one", "in feed order")
  eq(installs[2], "two", "one after the other")
  check(ri.modNotice and ri.modNotice.ok, "and reports the run")
  eq(ri.modNotice.text, "Updated 2 mods.", "as one summary")
  eq(ri._busy, nil, "with the overlay down")
end


do
  installs = {}
  failId = "two"
  local ri = launcher("available")
  ri:pressUpdateAllMods()
  ri._modInfoFetch = nil
  run(ri)
  failId = nil
  eq(#installs, 2, "the queue carries on past a failure")
  check(ri.modNotice and not ri.modNotice.ok, "and says the run was partial")
  eq(ri.modNotice.text, "Updated 1 of 2. 1 failed:", "with the counts")
  eq(#ri.modNotice.failures, 1, "naming what failed")
  check(ri.modNotice.failures[1]:find("Two", 1, true) ~= nil,
    "by the mod's own name")
end


do
  local ri = launcher()
  ri.modUpdateInfo = {}
  ri:pressUpdateAllMods()
  ri._modInfoFetch = nil
  run(ri)
  eq(ri.modNotice.text, "All mods are up to date.",
    "a run with no outdated mod says so rather than going quiet")
end

do
  Platform.canFetchRemote = function() return false end
  local ri = launcher("available")
  check(ri:pressUpdateAllMods() == false, "no remote fetch, no queue")
  eq(ri._updateAll, nil, "nothing is started")
  check(ri.modNotice and not ri.modNotice.ok, "and the refusal is on screen")
  Platform.canFetchRemote = function() return true end
end


do
  installs = {}
  local ri = launcher("available")
  ri:pressUpdateAllMods()
  ri._modInfoFetch = nil
  ri:_pumpUpdateAll()
  ri:_pumpUpdateAll()
  ri:_pumpModInstall()
  eq(#installs, 1, "one row is through")
  ri:_cancelUpdateAll()
  check(ri._updateAll == nil or ri._updateAll.cancelled,
    "the cancel is taken")
  run(ri)
  eq(ri._updateAll, nil, "the queue stops")
  eq(#installs, 1, "without starting the rest")
  check(ri.modNotice.text:find("Stopped after updating", 1, true) ~= nil,
    "and says how far it got")
end

do
  local ri = launcher("available")
  ri:pressUpdateAllMods()
  ri._modInfoFetch = nil
  ri:_pumpUpdateAll()
  ri:_pumpUpdateAll()
  check(ri._modInstall ~= nil, "a row is downloading")
  ri:_cancelUpdateAll()
  check(ri._busy ~= nil,
    "cancelling mid-download keeps the overlay: the download has no abort")
  run(ri)
  eq(ri._busy, nil, "and it comes down once that row is done")
end


do
  installs = {}
  local ri = launcher()
  ri:_beginModInstall({ modId = "one", name = "One", release = RELEASES[1],
                        verb = "Updated", notice = "mod", quiet = true })
  ri:_pumpModInstall()
  eq(ri.modNotice, nil, "a quiet install writes no per-mod notice")
  eq(ri._modDepResolver, nil, "and raises no dependency modal mid-queue")
end

do
  local ri = launcher("available")
  ri.cartFillRows = function()
    return { { id = "one", name = "One", release = RELEASES[1] } }
  end
  eq(ri:pressInstallCartMods("red"), true,
    "a cart fill starts when nothing else is running")
  ri._cartFill = nil

  ri:pressUpdateAllMods()
  check(ri._updateAll ~= nil, "the update-all queue is live")
  eq(ri:pressInstallCartMods("red"), false,
    "a cart fill refuses in the frame the queue is between rows")
  eq(ri._cartFill, nil, "and starts nothing")

  ri:_beginCartInstall({ id = "cart", title = "Cart",
    releases = { { version = "1.0.0", zip = { url = "https://x.invalid/c.zip" } } } })
  eq(ri._cartInstall, nil, "a cart install refuses there too")
  eq(ri.findNotice, nil, "silently, since the overlay owns the screen")
end


do
  love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
  love.graphics.newShader = love.graphics.newShader or function() return {} end
  love.graphics.polygon = love.graphics.polygon or function() end
  local LauncherView = require("src.import.LauncherView")

  local realPrint = love.graphics.print
  local function draw(imp)
    local seen = {}
    love.graphics.print = function(str, ...)
      seen[#seen + 1] = tostring(str)
      return realPrint(str, ...)
    end
    local ok, err = pcall(LauncherView.draw, imp)
    love.graphics.print = realPrint
    check(ok, "the frame draws: " .. tostring(err))
    return table.concat(seen, "\n")
  end
  local function window(w, h)
    love.graphics.getDimensions = function() return w, h end
    love.graphics.getPixelDimensions = function() return w, h end
  end

  local imp = RomImporter.new(function() end, { launcher = true })
  imp._ensureMods = function() end
  imp._refreshMods = function() end
  imp.findLoaded, imp._findFetch = true, nil
  imp.mods = launcher("available").mods
  imp.modUpdateInfo = { one = info("available", RELEASES[1]) }
  imp.tab = "mods"

  window(1400, 900)
  local wide = draw(imp)
  check(wide:find("Update all", 1, true) ~= nil,
    "a wide header carries Update all beside Check for updates")

  local cache = imp._modUpdateCountCache
  eq(cache and cache.count, 1, "the header counts the one outdated mod")
  draw(imp)
  check(rawequal(imp._modUpdateCountCache, cache),
    "and a second frame reuses that count instead of rebuilding a list")
  imp.modUpdateInfo.two = info("available", RELEASES[1])
  imp._modUpdateRev = (imp._modUpdateRev or 0) + 1
  draw(imp)
  eq(imp._modUpdateCountCache.count, 2,
    "a bumped update revision rebuilds it")

  window(430, 860)
  local narrow = draw(imp)
  check(narrow:find("More...", 1, true) ~= nil,
    "a phone-width header collapses to More...")
  imp._modHeaderActionsPopup = true
  local popup = draw(imp)
  imp._modHeaderActionsPopup = nil
  check(popup:find("Update all mods", 1, true) ~= nil,
    "and More... is where a phone reaches Update all")
end

ModUpdate.beginFetchReleases = oldBeginFetch
ModUpdate.beginDownloadZip = oldBeginZip
ModUpdate.pumpDownloadZip = oldPumpZip
LauncherMods.installDownloadedZip = oldInstall
LauncherMods.checkDependencies = oldDeps
Platform.canFetchRemote = oldRemote

T.finish("launcher update all")
