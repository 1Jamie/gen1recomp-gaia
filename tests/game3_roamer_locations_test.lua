#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Cache = require("tests.game3_cache")
if not Cache.mount("roamer/locations.lua") then
  print("[skip] game3_roamer_locations: " .. tostring(Cache.reason))
  os.exit(0)
end

require("src.core.GameVersion").set("firered")
require("src.import.gba.versions").select("firered")
local Roamer = require("src.core.game3.roamer")

-- pokefirered/src/roamer.c:36
local sets = Roamer.locationSets(Roamer.config({ version = "firered" }))
eq(#sets, 25, "FireRed has 25 roamer location sets")
for i, set in ipairs(sets) do
  eq(#set, 7, "set " .. i .. " has NUM_LOCATIONS_PER_SET slots")
end
local first = sets[1]
eq(first[1], "FR_ROUTE_1", "set 1 starts at Route 1")
eq(first[2], "FR_ROUTE_2", "set 1 reaches Route 2")
eq(first[3], "FR_ROUTE_21_NORTH", "set 1 reaches Route 21 North")
eq(first[4], "FR_ROUTE_22", "set 1 reaches Route 22")
eq(first[5], false, "set 1 pads with MAP_UNDEFINED")
local five = sets[5]
eq(table.concat({ five[1], five[2], five[3], five[4], five[5], five[6], five[7] }, ","),
  "FR_ROUTE_5,FR_ROUTE_4,FR_ROUTE_6,FR_ROUTE_7,FR_ROUTE_8,FR_ROUTE_9,FR_ROUTE_24", "set 5 is the full Route 5 row")
local last = sets[25]
eq(last[1], "FR_ROUTE_25", "set 25 starts at Route 25")
eq(last[2], "FR_ROUTE_24", "set 25 reaches Route 24")
eq(last[3], "FR_ROUTE_9", "set 25 reaches Route 9")

local heads, known = {}, true
local MapCatalog = require("src.import.gba.map_catalog")
for _, set in ipairs(sets) do
  heads[set[1]] = true
  for _, id in ipairs(set) do
    if id and not MapCatalog.isKnown(id) then known = false end
  end
end
check(known, "every roamer map id is a FireRed map")
check(heads.FR_ROUTE_22 and heads.FR_ROUTE_23, "Routes 22 and 23 are roamer location sets")

T.finish("game3_roamer_locations")
