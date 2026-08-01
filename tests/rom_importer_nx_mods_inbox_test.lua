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
    ensureImportsDir = RomImporter.ensureImportsDir,
    ensureModsInboxDir = RomImporter.ensureModsInboxDir,
    _setNxModsInboxNotice = RomImporter._setNxModsInboxNotice,
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

-- Cleanup + restore stubs
clearModsInbox()
love.system.getOS = saved.getOS
love.filesystem.getSaveDirectory = saved.getSaveDirectory
love.filesystem.createDirectory = saved.createDirectory
love.filesystem.remove = saved.remove
package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil

S.finish()
