#!/usr/bin/env luajit
-- pokeruby/src/pokemon_storage_system.c:664-678

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

local M = require("src.ui.game3.rs.storage_popup")

T.suite("rs box popup sides")

local man = {
  sprites = {box_popup_sides = {rects = {
    {x = 0, y = 0, w = 8, h = 32}, {x = 0, y = 32, w = 8, h = 16},
    {x = 0, y = 48, w = 8, h = 32}, {x = 0, y = 80, w = 8, h = 16},
  }}},
  boxPopup = {center = {x = 160, y = 96}, sides = {{x = 124, y = 80, frame = 0},
    {x = 124, y = 112, frame = 1}, {x = 196, y = 80, frame = 2}, {x = 196, y = 112, frame = 3}}},
}

eq(type(M.sidePlacements), "function", "sidePlacements exists")
if type(M.sidePlacements) == "function" then
  local p = M.sidePlacements(man)
  eq(#p, 4, "four side sprites")
  local want = {{120, 64, 32}, {120, 96, 16}, {192, 64, 32}, {192, 96, 16}}
  for i, w in ipairs(want) do
    eq(p[i].x, w[1], "side " .. i .. " x")
    eq(p[i].y, w[2], "side " .. i .. " y")
    eq(p[i].rect.h, w[3], "side " .. i .. " height")
  end
  eq(p[1].y + p[1].rect.h, p[2].y, "left lower piece meets upper piece")
  eq(p[3].y + p[3].rect.h, p[4].y, "right lower piece meets upper piece")
end

T.finish("rs box popup sides")
