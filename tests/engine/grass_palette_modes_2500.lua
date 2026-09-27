#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
local PaletteFX = require("src.render.PaletteFX")
local okGen, generated = pcall(require, "data.generated.palettes")
local data = { palettes = okGen and generated or {} }

local previous = PaletteFX.mode

PaletteFX.setMode("gbc")
if okGen then
  local sgb = PaletteFX.pal(data, "ROUTE")
  eq(sgb[1][1], 255, "SGB route shade 0 keeps its pale red-channel value")
  eq(sgb[1][2], 239, "SGB route shade 0 is the pale Super Game Boy palette")
  eq(sgb[2][1], 173, "SGB route grass uses the green map palette")
  eq(sgb[2][2], 230, "SGB route grass is not the OG RED pink")
else
  print("grass_palette_modes_2500: SGB route block skipped (needs data/generated/)")
end
eq(PaletteFX.usesSpriteObp(), false, "SGB does not bake the OG RED object palette")

PaletteFX.setMode("ogred")
local og = PaletteFX.pal(data, "ROUTE")
eq(og[2][1], 225, "OG RED uses the softened red display ramp")
eq(og[2][2], 128, "OG RED keeps the softened red background")
eq(og[2][3], 150, "OG RED keeps the softened red background blue channel")
eq(PaletteFX.usesSpriteObp(), true, "OG RED uses the separate green object palette")
local obj = PaletteFX.ogObj()
eq(table.concat(obj[1], ","), "248,248,248", "OG RED object shade 0 is the softened paper")
eq(table.concat(obj[2], ","), "131,198,86", "OG RED object shade 1 is the softened green")
eq(table.concat(obj[3], ","), "16,96,16", "OG RED object shade 2 is the softened dark green")
eq(table.concat(obj[4], ","), "0,0,0", "OG RED object shade 3 is black")

PaletteFX.setMode(previous)
T.finish("grass palette modes #2500")
