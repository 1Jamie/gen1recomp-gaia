package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local check, eq = T.check, T.eq
local GameVersion = require("src.core.GameVersion")
local before = GameVersion.get()
GameVersion.set("firered")
local FieldEffects = require("src.core.game3.field_effects")
local MB = require("src.core.game3.mb")
local reflective = {
  "POND_WATER", "PUDDLE", "UNUSED_WATER", "CYCLING_ROAD_WATER", "ICE",
}
for _, name in ipairs(reflective) do
  check(FieldEffects.isFrlgReflective(MB.id(name)), name .. " is reflective in FireRed")
end
check(not FieldEffects.isFrlgReflective(MB.id("NORMAL")), "normal ground is not reflective")
local water = MB.id("POND_WATER")
local plain = MB.id("NORMAL")
local tiles = { ["4,6"] = water, ["5,6"] = water }
local behaviorAt = function(x, y) return tiles[x .. "," .. y] or plain end
check(FieldEffects.frlgReflectionType(4, 5, 4, 5, 16, 32, behaviorAt),
  "a reflective tile below the object's footprint enables its reflection")
check(not FieldEffects.frlgReflectionType(4, 2, 4, 2, 16, 32, behaviorAt),
  "water outside the object's reflection footprint does not enable a reflection")
tiles["3,6"] = water
check(FieldEffects.frlgReflectionType(4, 5, 3, 5, 16, 32, behaviorAt),
  "the previous movement cell is included while an object moves")
GameVersion.set(before)
T.finish()
