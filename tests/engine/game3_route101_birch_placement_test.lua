local T = require("tests.harness")
local check, eq = T.check, T.eq

local Space = require("src.core.game3.scripting.space")
local fakeMaps = {
  EM_ROUTE101 = {},
}
local fakeBundle = {
  events = {
    EM_ROUTE101 = {
      objects = {
        { localId = 1, x = 16, y = 8 },
        { localId = 2, x = 9, y = 13, flag = "FLAG_HIDE_ROUTE_101_BIRCH_ZIGZAGOON_BATTLE" },
        { localId = 3, x = 7, y = 14 },
        { localId = 4, x = 10, y = 13, flag = "FLAG_HIDE_ROUTE_101_ZIGZAGOON" },
      },
    },
  },
}

Space.attachEventsToMaps(fakeMaps, fakeBundle)
local r101Objs = fakeMaps.EM_ROUTE101.objects
check(r101Objs ~= nil, "Route 101 objects attached")
eq(r101Objs[1].x, 16, "Youngster x kept")
eq(r101Objs[1].y, 8, "Youngster y kept")
eq(r101Objs[2].x, -100, "Birch pre-rescue moved out of widescreen frustum")
eq(r101Objs[2].y, -100, "Birch pre-rescue moved out of widescreen frustum")
eq(r101Objs[4].x, -100, "Zigzagoon pre-rescue moved out of widescreen frustum")
eq(r101Objs[4].y, -100, "Zigzagoon pre-rescue moved out of widescreen frustum")

T.finish("game3_route101_birch_placement_test")
