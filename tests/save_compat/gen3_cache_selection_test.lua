package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local check, eq = T.check, T.eq
local GameVersion = require("src.core.GameVersion")
local SaveConvert = require("src.save_convert.SaveConvert")

local data = {
  ["data/generated/gba/meta.json"] = '{"import_id":"firered","version_id":"firered_1_0"}',
  ["data/generated/gba/pokemon/names.lua"] = 'return { [1] = "FIRE RED" }',
}
package.loaded["src.import.CacheFs"] = { prefix = "sentinel/", read = function() return nil end }
package.loaded["src.core.game3.dataset"] = { cache = function()
  return { read = function(_, path) return data[path] end }
end }
GameVersion.set("firered")
eq(SaveConvert.gen3CacheTable("firered", "pokemon/names.lua")[1], "FIRE RED", "matching active edition data is available")
eq(SaveConvert.gen3CacheTable("emerald", "pokemon/names.lua"), nil, "Emerald cannot borrow FireRed data")
GameVersion.set("emerald")
eq(SaveConvert.gen3CacheTable("emerald", "pokemon/names.lua"), nil, "changing active edition cannot relabel stale data")
data["data/generated/gba/meta.json"] = '{"version":"emerald"}'
data["data/generated/gba/pokemon/names.lua"] = 'return { [1] = "EMERALD" }'
eq(SaveConvert.gen3CacheTable("emerald", "pokemon/names.lua")[1], "EMERALD", "verified Emerald metadata permits its data")
GameVersion.set("leafgreen")
data["data/generated/gba/meta.json"] = '{"import_id":"firered","version_id":"leafgreen_1_0"}'
data["data/generated/gba/pokemon/names.lua"] = 'return { [1] = "LEAF GREEN" }'
eq(SaveConvert.gen3CacheTable("leafgreen", "pokemon/names.lua")[1], "LEAF GREEN", "edition metadata outranks the shared FRLG importer id")
GameVersion.set("emerald")
SaveConvert.setGen3CacheDir("emerald", "/nonexistent")
eq(SaveConvert.gen3CacheTable("emerald", "pokemon/names.lua"), nil, "an explicit missing cache never borrows another source")
SaveConvert.setGen3CacheDir("emerald", nil)
eq(package.loaded["src.import.CacheFs"].prefix, "sentinel/", "cache selection restores launcher state")
data["data/generated/gba/meta.json"] = nil
eq(SaveConvert.gen3CacheTable("emerald", "pokemon/names.lua"), nil, "unidentified active cache is refused")
T.finish()
