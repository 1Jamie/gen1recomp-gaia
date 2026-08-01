-- Blue/Yellow mountVersion must overlay save-dir caches without FFI (NX).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check

local CacheFs = require("src.import.CacheFs")

love.filesystem._mounts = {}
-- Imply blue/data/generated and blue/assets/generated directories via file keys.
love.filesystem.write("blue/data/generated/maps.lua", "return {}")
love.filesystem.write("blue/assets/generated/fonts/font.png", "x")

check(CacheFs.mountVersion("blue") == true, "mountVersion(blue) returns true")

local sawBlueRoot, sawDataGen, sawAssetsGen = false, false, false
for _, m in ipairs(love.filesystem._mounts) do
  if m.archive == "blue" and m.mountpoint == "" and m.append == false then
    sawBlueRoot = true
  end
  if m.archive == "blue/data/generated" and m.mountpoint == "data/generated"
      and m.append == false then
    sawDataGen = true
  end
  if m.archive == "blue/assets/generated" and m.mountpoint == "assets/generated"
      and m.append == false then
    sawAssetsGen = true
  end
end
check(sawBlueRoot, "prepend-mounts save-dir relative blue/")
check(sawDataGen, "prepend-mounts blue/data/generated -> data/generated")
check(sawAssetsGen, "prepend-mounts blue/assets/generated -> assets/generated")

T.finish()
