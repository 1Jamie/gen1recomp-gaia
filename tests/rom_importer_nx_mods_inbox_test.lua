-- NX mods zip inbox: ensure imports/mods/, MTP hint (NXMOD-01..05).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("rom importer NX mods inbox")
local eq = S.eq
local check = S.check

local RomImporter = require("src.import.RomImporter")

love.system = love.system or {}
love.filesystem = love.filesystem or {}

local saved = {
  getOS = love.system.getOS,
  getSaveDirectory = love.filesystem.getSaveDirectory,
  createDirectory = love.filesystem.createDirectory,
  remove = love.filesystem.remove,
}

love.system.getOS = function() return "NX" end
love.filesystem.getSaveDirectory = function()
  return "sdmc:/switch/gen1recomp/pokemon-love2d"
end

local createdDirs = {}
love.filesystem.createDirectory = function(name)
  createdDirs[name] = true
  return true
end

local removed = {}
love.filesystem.remove = function(name)
  removed[name] = true
  return saved.remove(name)
end

package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil
RomImporter = require("src.import.RomImporter")

local function clearModsInbox()
  for _, name in ipairs(love.filesystem.getDirectoryItems("imports/mods") or {}) do
    love.filesystem.remove("imports/mods/" .. name)
  end
  for _, name in ipairs(love.filesystem.getDirectoryItems("imports") or {}) do
    love.filesystem.remove("imports/" .. name)
  end
end

local function freshImporter()
  clearModsInbox()
  createdDirs = {}
  removed = {}
  package.loaded["src.import.RomImporter"] = nil
  RomImporter = require("src.import.RomImporter")
  return setmetatable({
    isNX = true,
    android = false,
    launcher = true,
    workState = nil,
    tab = "mods",
    modNotice = nil,
    mods = {},
    ready = { red = false, blue = false, yellow = false },
    ensureImportsDir = RomImporter.ensureImportsDir,
    ensureModsInboxDir = RomImporter.ensureModsInboxDir,
    _setNxModsInboxNotice = RomImporter._setNxModsInboxNotice,
    scanModsInbox = RomImporter.scanModsInbox,
    scanInbox = RomImporter.scanInbox,
    rescanModsAction = RomImporter.rescanModsAction,
    chooseMod = RomImporter.chooseMod,
    _installMod = RomImporter._installMod,
    _refreshMods = function(self)
      self._refreshed = (self._refreshed or 0) + 1
      self.mods = self.mods or {}
    end,
  }, RomImporter)
end

-- NXMOD-01: ensureModsInboxDir creates imports/mods/ under save FS
createdDirs = {}
local ri = freshImporter()
ri:ensureModsInboxDir()
check(createdDirs.imports or createdDirs["imports/mods"],
  "ensureModsInboxDir creates parent imports/ or nested path")
check(createdDirs["imports/mods"],
  "ensureModsInboxDir creates imports/mods/")

-- NXMOD-01: notice/hint includes save dir + relative imports/mods/ MTP path
ri = freshImporter()
ri:_setNxModsInboxNotice()
check(ri.modNotice ~= nil, "NX mods inbox notice is set")
check(ri.modNotice.text:find("sdmc:/switch/gen1recomp/pokemon-love2d/imports/mods/", 1, true),
  "mods notice contains runtime save path + imports/mods/")
check(ri.modNotice.text:find("DBI MTP", 1, true) ~= nil,
  "mods notice contains OpenMTP-oriented hint")
check(ri.modNotice.text:find("switch/gen1recomp/pokemon-love2d/imports/mods/", 1, true),
  "hint uses sdmc-stripped relative imports/mods/ path")

-- NXMOD-02: scanModsInbox returns only *.zip under imports/mods/
ri = freshImporter()
love.filesystem.write("imports/mods/valid.zip", "ZIPDATA")
love.filesystem.write("imports/mods/readme.txt", "nope")
love.filesystem.write("imports/mods/cart.gb", string.rep("R", 16))
love.filesystem.write("imports/other.zip", "WRONGDIR")
local zips = ri:scanModsInbox()
eq(#zips, 1, "scanModsInbox returns one zip candidate")
eq(zips[1], "imports/mods/valid.zip", "scanModsInbox path is under imports/mods/")

-- ROM scanInbox must not treat .zip as ROM
ri = freshImporter()
love.filesystem.write("imports/modpack.zip", "ZIPROM")
love.filesystem.write("imports/mods/also.zip", "ZIPMOD")
local roms = ri:scanInbox(ri.ready)
for _, path in ipairs(roms) do
  check(not path:lower():match("%.zip$"),
    "ROM scanInbox ignores zip: " .. tostring(path))
end
eq(#roms, 0, "ROM scanInbox finds no zip-only inbox entries")

-- Stub LauncherMods.installZip for rescan tests (NXMOD-02..04)
local installCalls = {}
local installBehavior = {} -- path -> {ok=bool, id=string|err}
package.loaded["src.mods.LauncherMods"] = {
  installZip = function(source)
    installCalls[#installCalls + 1] = source
    local b = installBehavior[source]
    if not b then return false, "unexpected source: " .. tostring(source) end
    if b.ok then return true, b.id or "mod-id" end
    return false, b.err or "bad zip"
  end,
}

-- Empty inbox rescan → MTP notice, no install
ri = freshImporter()
installCalls = {}
ri:rescanModsAction()
eq(#installCalls, 0, "empty mods inbox does not call installZip")
check(ri.modNotice ~= nil and ri.modNotice.text:find("imports/mods/", 1, true),
  "empty rescan shows mods MTP notice")

-- Success → refresh; zip retained (no remove)
ri = freshImporter()
installCalls = {}
removed = {}
love.filesystem.write("imports/mods/good.zip", "GOODZIP")
installBehavior["imports/mods/good.zip"] = { ok = true, id = "good-mod" }
ri:rescanModsAction()
eq(#installCalls, 1, "success path calls installZip once")
eq(installCalls[1], "imports/mods/good.zip", "installZip receives inbox path")
check(ri._refreshed and ri._refreshed >= 1, "success refreshes mods list")
check(ri.modNotice and ri.modNotice.ok, "success sets ok notice")
check(not removed["imports/mods/good.zip"], "success retains inbox zip")
check(love.filesystem.read("imports/mods/good.zip") == "GOODZIP",
  "success leaves zip bytes in inbox")

-- Failure → clear notice; zip retained
ri = freshImporter()
installCalls = {}
removed = {}
love.filesystem.write("imports/mods/bad.zip", "BADZIP")
installBehavior["imports/mods/bad.zip"] = { ok = false, err = "missing manifest" }
ri:rescanModsAction()
eq(#installCalls, 1, "failure path still attempts installZip")
check(ri.modNotice and not ri.modNotice.ok, "failure sets clear error notice")
check(ri.modNotice.text:find("missing manifest", 1, true),
  "failure notice includes installZip error")
check(not removed["imports/mods/bad.zip"], "failure does not remove inbox zip")
check(love.filesystem.read("imports/mods/bad.zip") == "BADZIP",
  "failure leaves zip in inbox")

-- Mixed valid/invalid: attempt each; no zip deleted
ri = freshImporter()
installCalls = {}
removed = {}
love.filesystem.write("imports/mods/a-bad.zip", "BAD")
love.filesystem.write("imports/mods/b-good.zip", "GOOD")
installBehavior["imports/mods/a-bad.zip"] = { ok = false, err = "no manifest" }
installBehavior["imports/mods/b-good.zip"] = { ok = true, id = "b-mod" }
ri:rescanModsAction()
eq(#installCalls, 2, "mixed inbox attempts each zip")
check(not removed["imports/mods/a-bad.zip"], "mixed: bad zip retained")
check(not removed["imports/mods/b-good.zip"], "mixed: good zip retained")
check(love.filesystem.read("imports/mods/a-bad.zip") ~= nil, "mixed bad still present")
check(love.filesystem.read("imports/mods/b-good.zip") ~= nil, "mixed good still present")

-- NXMOD-05: chooseMod on NX routes to inbox rescan; no HostShell/chooseZip
local hostShellCalls = 0
package.loaded["src.core.HostShell"] = {
  run = function()
    hostShellCalls = hostShellCalls + 1
    error("HostShell must not run on NX chooseMod")
  end,
  available = function() return false end,
}
ri = freshImporter()
installCalls = {}
love.filesystem.write("imports/mods/from-choose.zip", "CHOOSE")
installBehavior["imports/mods/from-choose.zip"] = { ok = true, id = "choose-mod" }
ri:chooseMod()
eq(hostShellCalls, 0, "NX chooseMod does not require HostShell")
eq(#installCalls, 1, "NX chooseMod rescans and installs inbox zip")
eq(installCalls[1], "imports/mods/from-choose.zip",
  "NX chooseMod installs from imports/mods/")
check(ri.modNotice and ri.modNotice.ok, "NX chooseMod success notice")

-- Cleanup + restore stubs
clearModsInbox()
love.filesystem.remove("imports/other.zip")
love.filesystem.remove("imports/modpack.zip")
package.loaded["src.mods.LauncherMods"] = nil
package.loaded["src.core.HostShell"] = nil
love.system.getOS = saved.getOS
love.filesystem.getSaveDirectory = saved.getSaveDirectory
love.filesystem.createDirectory = saved.createDirectory
love.filesystem.remove = saved.remove
package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil

S.finish()
