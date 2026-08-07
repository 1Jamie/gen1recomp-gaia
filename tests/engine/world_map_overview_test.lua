package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local WorldAPI = require("src.world.WorldAPI")

local api = WorldAPI.new({ stack = { states = {} } }, "tester")
local overview, err = api:mapOverview()
T.eq(overview, nil, "map overview is unavailable outside the overworld")
T.eq(err, "no overworld", "map overview reports why it is unavailable")

local map = { id = "TEST_MAP", widthCells = 2, heightCells = 2 }
function map:isWarpTileCell(x, y) return x == 1 and y == 0 end
function map:isWaterCell(x, y) return x == 0 and y == 1 end
function map:isWalkableCell(x, y) return x == 0 and y == 0 end

api = WorldAPI.new({ stack = { states = {
  { isOverworld = true, map = map },
} } }, "tester")
overview = api:mapOverview()
T.eq(overview.mapId, "TEST_MAP", "map overview identifies the active map")
T.eq(overview.width, 2, "map overview reports its width")
T.eq(overview.height, 2, "map overview reports its height")
T.eq(overview.rows[1], ".+", "walkable land and warps are distinct")
T.eq(overview.rows[2], "~ ", "water and blocked terrain are distinct")

T.finish("world map overview")
