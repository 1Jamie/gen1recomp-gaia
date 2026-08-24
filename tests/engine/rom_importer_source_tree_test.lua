-- Shared cache readiness uses the selected version's source-tree contract.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local CacheContract = require("src.import.CacheContract")
local GameVersion = require("src.core.GameVersion")

local present = {}
for _, path in ipairs(CacheContract.requiredFiles("gold")) do
  present[GameVersion.cachePrefix("gold") .. path] = true
end
local fs = {
  read = function() return nil end,
  getInfo = function(path) return present[path] and { type = "file" } or nil end,
  getRealDirectory = function(path) return present[path] and "/source" or nil end,
  getSource = function() return "/source" end,
}

local inspected = CacheContract.inspect("gold", fs, { allowSource = true })
T.eq(inspected and inspected.kind, "source",
  "Gold source tree uses Gold's required-file contract")

present["gold/assets/generated/battle/hud/balls.png"] = nil
T.eq(CacheContract.inspect("gold", fs, { allowSource = true }), nil,
  "missing Gold-only trainer HUD asset makes the source tree incomplete")

local required = {}
for _, path in ipairs(CacheContract.requiredFiles("gold")) do required[path] = true end
T.eq(required["data/generated/rom_text.lua"], true,
  "Gold requires generated ROM text")
T.eq(required["assets/generated/pc/mail_item.png"], true,
  "Gold requires PC mail art")
T.eq(required["assets/generated/trade/game_boy.png"], nil,
  "Gold does not inherit the Gen 1 trade-art contract")

T.finish()
