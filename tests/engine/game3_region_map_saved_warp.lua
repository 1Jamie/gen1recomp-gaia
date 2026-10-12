#!/usr/bin/env luajit
-- pokeruby/src/region_map.c:514
-- pokeemerald/src/region_map.c:968

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq, check = T.eq, T.check
love = love or require("tests.love_stub")

T.suite("region map saved warps")

local SEC = {
  LITTLEROOT_TOWN = 0, PETALBURG_CITY = 7, SLATEPORT_CITY = 8, LILYCOVE_CITY = 12, ROUTE_114 = 29,
  ROUTE_121 = 36, ROUTE_124 = 39, ROUTE_126 = 41, ROUTE_131 = 46, ROUTE_132 = 47, UNDERWATER_125 = 82,
  UNDERWATER_128 = 84, INSIDE_OF_TRUCK = 87, SECRET_BASE = 88, DYNAMIC = 89, NONE = 90, EVER_GRANDE_CITY = 15,
  BATTLE_FRONTIER = 58, SOUTHERN_ISLAND = 59, BATTLE_TOWER = 60, UNDERWATER_SEAFLOOR_CAVERN = 83,
  UNDERWATER_MARINE_CAVE = 85, UNDERWATER_126 = 86,
}
local ENTRY = {
  [SEC.PETALBURG_CITY] = { x = 1, y = 9, width = 1, height = 1 },
  [SEC.INSIDE_OF_TRUCK] = { x = 0, y = 0, width = 1, height = 1 },
  [SEC.LILYCOVE_CITY] = { x = 18, y = 3, width = 2, height = 1 },
  [SEC.SLATEPORT_CITY] = { x = 8, y = 10, width = 1, height = 2 },
  [SEC.ROUTE_132] = { x = 21, y = 12, width = 2, height = 1 },
  [SEC.SECRET_BASE] = { x = 0, y = 0, width = 1, height = 1 },
}

local MAPS = {
  PETALBURG = { mapType = 2, regionMapSectionId = SEC.PETALBURG_CITY, width = 30, height = 30 },
  LILYCOVE = { mapType = 2, regionMapSectionId = SEC.LILYCOVE_CITY, width = 80, height = 40 },
  ROUTE132 = { mapType = 6, regionMapSectionId = SEC.ROUTE_132, width = 80, height = 40 },
  TRUCK = { mapType = 8, regionMapSectionId = SEC.INSIDE_OF_TRUCK, width = 10, height = 10 },
  CAVE = { mapType = 4, regionMapSectionId = SEC.ROUTE_114, width = 20, height = 20, allowEscaping = 1 },
  BASE = { mapType = 9, regionMapSectionId = SEC.SECRET_BASE, width = 10, height = 10 },
  DYN = { mapType = 8, regionMapSectionId = SEC.DYNAMIC, width = 10, height = 10 },
  EM_SS_TIDAL_CORRIDOR = { mapType = 8, regionMapSectionId = SEC.ROUTE_131, width = 10, height = 10 },
}
local GROUPNUM = { PETALBURG = { 0, 0 }, LILYCOVE = { 0, 5 }, ROUTE132 = { 0, 42 }, TRUCK = { 25, 40 },
  CAVE = { 24, 1 }, BASE = { 26, 0 }, DYN = { 8, 1 }, EM_SS_TIDAL_CORRIDOR = { 32, 1 } }
local function groupNum(id)
  local g = GROUPNUM[id]
  if g then return g[1], g[2] end
end

package.loaded["src.import.gba.map_catalog"] = {
  mapIdFor = function(g, n)
    for id, v in pairs(GROUPNUM) do if v[1] == g and v[2] == n then return id end end
  end,
  slotKeyFor = function(id)
    local g, n = groupNum(id)
    if g then return g .. "_" .. n end
  end,
}
local game = { data = { maps = MAPS } }
package.loaded["src.core.game3.runtime"] = { _game = game, getGame = function() return game end }
local Player = { cellX = 4, cellY = 4 }
package.loaded["src.core.game3.player"] = Player

local Data = require("src.ui.game3.rs.pokenav.data")
Data.mapGroupNum = function(id) return groupNum(id) end
local man = { mapsecs = SEC, sections = ENTRY, specialPlaces = {} }

local function rsPos(map, extra)
  local session = { map = map }
  for k, v in pairs(extra or {}) do session[k] = v end
  return Data.playerPosition(man, session, game)
end

local p, err = rsPos("TRUCK")
check(p ~= nil, "rs: truck with no escape warp opens the map (" .. tostring(err) .. ")")
if p then
  eq(p.mapSec, SEC.INSIDE_OF_TRUCK, "rs: truck keeps MAPSEC_INSIDE_OF_TRUCK")
  eq(p.x, 1, "rs: truck cursor x")
  eq(p.y, 2, "rs: truck cursor y")
  eq(p.cave, false, "rs: truck is not a cave")
end

p = rsPos("CAVE")
check(p ~= nil, "rs: cave with no escape warp opens the map")
if p then
  eq(p.mapSec, SEC.PETALBURG_CITY, "rs: cave with zeroed escape warp reads map 0.0")
  eq(p.x, 2, "rs: cave cursor x")
  eq(p.y, 11, "rs: cave cursor y")
  eq(p.cave, true, "rs: cave blinks")
end

p = rsPos("BASE")
check(p ~= nil and p.mapSec == SEC.PETALBURG_CITY, "rs: secret base with no dynamic warp reads map 0.0")

p = rsPos("DYN", { escapeWarp = { map = "LILYCOVE", x = 60, y = 5 } })
check(p ~= nil and p.mapSec == SEC.PETALBURG_CITY, "rs: MAPSEC_DYNAMIC indoor reads the dynamic warp, not the escape warp")

p = rsPos("TRUCK", { escapeWarp = { map = "LILYCOVE", x = 60, y = 5 } })
check(p ~= nil and p.mapSec == SEC.INSIDE_OF_TRUCK and p.x == 1, "rs: indoor keeps its own mapsec with a real escape warp")

local man2 = {
  mapsecs = SEC, assetLayout = "emerald", aquaHideoutOld = {}, marineCaveCoords = {}, terraOrMarineCaveMapSecIds = {},
}
package.loaded["src.ui.game3.rse.mapsec"] = { entry = function(id) return ENTRY[id] end }
local RegionMap = require("src.ui.game3.rse.region_map")
RegionMap.manifest = function() return man2 end

local function emInit(map, session)
  session = session or {}
  session.map = map
  session.version = session.version or "emerald"
  local s = { session = session, mapDef = MAPS[map] }
  RegionMap.initFromPlayer(s)
  return s
end

local s = emInit("TRUCK")
eq(s.mapSecId, SEC.INSIDE_OF_TRUCK, "em: truck mapsec")
eq(s.cursorX, 1, "em: truck cursor x")
eq(s.cursorY, 2, "em: truck cursor y")

s = emInit("CAVE")
eq(s.mapSecId, SEC.PETALBURG_CITY, "em: escapable cave with no escape warp reads map 0.0")
eq(s.playerIsInCave, true, "em: cave blinks")

s = emInit("BASE")
eq(s.mapSecId, SEC.PETALBURG_CITY, "em: secret base with no dynamic warp reads map 0.0")

s = emInit("DYN", { escapeWarp = { map = "LILYCOVE", x = 60, y = 5 } })
eq(s.mapSecId, SEC.PETALBURG_CITY, "em: MAPSEC_DYNAMIC indoor with no dynamic warp reads map 0.0")

man2.assetLayout = "rs"
MAPS.CAVE.allowEscaping = 0
s = emInit("CAVE", { version = "sapphire", escapeWarp = { map = "LILYCOVE", x = 60, y = 5 } })
eq(s.mapSecId, SEC.LILYCOVE_CITY, "rs layout: caves read the escape warp without an allowEscaping check")
eq(s.cursorX, 20, "rs layout: cave cursor x from the escape warp")
man2.assetLayout = "emerald"
s = emInit("CAVE", { escapeWarp = { map = "LILYCOVE", x = 60, y = 5 } })
eq(s.mapSecId, SEC.ROUTE_114, "em: non-escapable cave keeps its own mapsec")
MAPS.CAVE.allowEscaping = 1

-- pokeemerald/src/region_map.c:1123
local C = require("src.core.game3.constants").of("emerald")
GROUPNUM.EM_SS_TIDAL_CORRIDOR = { C.map_groups.byName.MAP_SS_TIDAL_CORRIDOR.group, C.map_groups.byName.MAP_SS_TIDAL_CORRIDOR.num }
local r132 = C.map_groups.byName.MAP_ROUTE132
GROUPNUM.ROUTE132 = { r132.group, r132.num }
local function tidal(state, count)
  local vars = { [C:var("VAR_SS_TIDAL_STATE")] = state, [C:var("VAR_CRUISE_STEP_COUNT")] = count }
  return emInit("EM_SS_TIDAL_CORRIDOR", { vars = vars, escapeWarp = { map = "PETALBURG", x = 3, y = 3 } })
end
s = tidal(4, 0)
eq(s.mapSecId, SEC.LILYCOVE_CITY, "em: SS Tidal docked at Lilycove")
eq(s.cursorX, ENTRY[SEC.LILYCOVE_CITY].x + 1, "em: SS Tidal Lilycove cursor x")
s = tidal(1, 0)
eq(s.mapSecId, SEC.SLATEPORT_CITY, "em: SS Tidal docked at Slateport")
s = tidal(2, 150)
eq(s.mapSecId, SEC.ROUTE_132, "em: SS Tidal sailing past Route 132")
eq(s.cursorX, ENTRY[SEC.ROUTE_132].x + 1, "em: SS Tidal Route 132 cursor x")
eq(s.cursorY, ENTRY[SEC.ROUTE_132].y + 2, "em: SS Tidal Route 132 cursor y")
eq(s.playerIsInCave, false, "em: SS Tidal does not blink")

T.finish("region map saved warps")
