-- Content gate for Switch transfer runbooks (XFER-01..06 for transfer.md).
-- Self-contained: luajit tests/switch_transfer_docs_test.lua
-- Later tasks extend assertions for cross-links and NXMOD-12.

local T = require("tests.harness")
local check = T.check

local function read(path)
  local f, err = io.open(path, "r")
  if not f then error("cannot read " .. path .. ": " .. tostring(err)) end
  local s = f:read("*a")
  f:close()
  return s
end

local function mustContain(body, needle, label)
  check(body:find(needle, 1, true) ~= nil,
    label .. " must contain " .. string.format("%q", needle))
end

local transfer = read("docs/switch-transfer.md")

mustContain(transfer, "MTP", "transfer")
mustContain(transfer, "Hekate UMS", "transfer")
mustContain(transfer, "FTP", "transfer")
mustContain(transfer, "sdmc:/switch/gen1recomp/", "transfer")
mustContain(transfer, "imports/", "transfer")
mustContain(transfer, "imports/mods/", "transfer")
mustContain(transfer, "one contributor example", "transfer")
mustContain(transfer, "Linux", "transfer")
mustContain(transfer, "Windows", "transfer")
mustContain(transfer, "macOS", "transfer")
mustContain(transfer, "title override", "transfer")
mustContain(transfer, "Applet Mode", "transfer")
mustContain(transfer, "nxlink", "transfer")
mustContain(transfer, "deferred", "transfer")
mustContain(transfer, "gvfs-mtp", "transfer")
mustContain(transfer, "Portable Devices", "transfer")
mustContain(transfer, "MTP USB Device", "transfer")
mustContain(transfer, "AppleDouble", "transfer")
mustContain(transfer, "card reader", "transfer")
mustContain(transfer, "Canonical methods", "transfer")
mustContain(transfer, "OpenMTP", "transfer")

-- Cross-links from install / build (XFER rewire)
local install = read("docs/switch-install.md")
local build = read("docs/switch-build.md")
mustContain(install, "switch-transfer.md", "install")
mustContain(build, "switch-transfer.md", "build")
mustContain(build, "nxlink", "build")

local development = read("docs/switch-development.md")
mustContain(development, "switch-transfer.md", "development")
check(development:find("Non-macOS contributor MTP runbooks", 1, true) == nil,
  "development must not list Non-macOS runbooks as absent")
check(development:find("VoxelMod (and other community mods) OLED smoke still **pending**", 1, true) == nil,
  "development must not list VoxelMod smoke as pending")

print("switch_transfer_docs_test: OK")
