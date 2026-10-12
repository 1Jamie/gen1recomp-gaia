#!/usr/bin/env luajit
-- pokeruby/src/pokenav.c:2502

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

T.suite("rs pokenav headers")

local Gfx = require("src.ui.game3.rs.pokenav.gfx")
eq(type(Gfx.headerPieces), "function", "headerPieces exists")
if type(Gfx.headerPieces) == "function" then
  for _, key in ipairs({"main_menu", "condition", "ribbons", "trainers_eyes"}) do
    local p = Gfx.headerPieces(key, 0)
    eq(#p, 2, key .. " two pieces")
    eq(p[1].x, 0, key .. " left piece x")
    eq(p[1].w, 64, key .. " left piece width")
    eq(p[2].x, 64, key .. " right piece x")
    eq(p[2].w, 32, key .. " right piece width")
    eq(p[1].x + p[1].w, p[2].x, key .. " right piece meets left piece")
    eq(p[2].y, 33, key .. " right piece y")
    eq(Gfx.headerPieces(key, 32)[2].y, 1, key .. " scrolled y")
  end
  local m = Gfx.headerPieces("hoenn_map", 32, true)
  eq(m[1].x, 120, "hoenn map left x")
  eq(m[2].x, 184, "hoenn map right x")
  eq(m[2].qy, 64, "hoenn map zoomed frame")
end

local Ex = require("src.import.gba.rs.extract_pokenav_condition")
local want = {"search", "party", "beauty", "cute", "smart", "tough", "cool"}
eq(type(Ex.HEADERS), "table", "condition sub-header order exported")
for i, name in ipairs(want) do eq(Ex.HEADERS and Ex.HEADERS[i], name, "sub-header chunk " .. i) end
eq(Ex.packVersion, 1, "condition pack version")

T.finish("rs pokenav headers")
