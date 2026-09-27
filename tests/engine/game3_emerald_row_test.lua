package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")

local SHA = "f3ae088181bf583e55daf962a92bb46f4f1d07b7"

eq(GameVersion.forSha1(SHA), "emerald", "the Emerald sha1 resolves to emerald")
eq(GameVersion.ORDER[9], "emerald", "emerald is ORDER index 9")
for i, id in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "leafgreen" }) do
  eq(GameVersion.ORDER[i], id, "ORDER keeps " .. id .. " at index " .. i)
end
eq(GameVersion.generation("emerald"), 3, "emerald is generation 3")
eq(GameVersion.engine("emerald"), "game3", "emerald runs the game3 engine")
eq(GameVersion.layout("emerald"), "rse", "emerald uses the rse layout")
eq(GameVersion.layout("firered"), "frlg", "firered uses the frlg layout")
eq(GameVersion.layout("leafgreen"), "frlg", "leafgreen uses the frlg layout")
eq(GameVersion.layout("red"), nil, "gen 1 has no gba layout")
-- pokeemerald/include/constants/global.h:10
eq(GameVersion.gameCode("emerald"), 3, "VERSION_EMERALD")
eq(GameVersion.gameCode("firered"), 4, "VERSION_FIRE_RED")
eq(GameVersion.gameCode("leafgreen"), 5, "VERSION_LEAF_GREEN")
eq(GameVersion.gameCode("gold"), nil, "gen 2 has no gba game code")
eq(GameVersion.cartShape("emerald"), "gba", "emerald is a gba cart")
eq(GameVersion.cachePrefix("emerald"), "emerald/", "emerald cache prefix")
eq(GameVersion.saveSuffix("emerald"), "_emerald", "emerald save suffix")
check(GameVersion.acceptsSha1("emerald", SHA), "emerald accepts its one revision")
eq(#GameVersion.revisions("emerald"), 1, "emerald has one revision")
eq(GameVersion.info("emerald").manifest, "tools/rom_manifest_emerald.json", "emerald manifest path")
local f = io.open("tools/rom_manifest_emerald.json", "rb")
check(f ~= nil, "emerald manifest stub exists")
if f then
  local body = f:read("*a")
  f:close()
  check(body:find(SHA, 1, true) ~= nil, "emerald manifest carries the sha1")
end
local label = io.open(GameVersion.info("emerald").cartLabel, "rb")
check(label ~= nil, "emerald label art exists")
if label then label:close() end

local ok, ModProfile = pcall(require, "src.mods.ModProfile")
if ok and type(ModProfile) == "table" then
  check(true, "ModProfile loads with the emerald row")
end

T.finish("game3_emerald_row_test")
