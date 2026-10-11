package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
local K = require("tests.save_compat._codec")

if not K.gen1Available() then
  print("gen1_flash_status skipped (needs data/generated/ for the Gen 1 save codec)")
  os.exit(0)
end

local GenSave = require("src.save_convert.GenSave")
local G1 = require("tests.fixtures.save.gen1_build")
local O = GenSave.OFFSETS

-- ram/wram.asm:1780 wMapPalOffset, home/overworld.asm:498-501
for _, v in ipairs({ "red", "blue", "yellow" }) do
  local data = K.gen1Data(v)
  local cw = GenSave.crosswalks(data)
  local tunnel = cw.mapsIndex.ROCK_TUNNEL_1F
  check(tunnel ~= nil, v .. ": ROCK_TUNNEL_1F has a map index")
  local function cart(pal)
    return G1.build({ version = v, map = tunnel, patch = function(b) b[O.mapPalOffset] = pal end })
  end

  local dark = assert(K.import(1, v, cart(6)))
  eq(dark.player.map, "ROCK_TUNNEL_1F", v .. ": the cart is standing in Rock Tunnel")
  eq(dark.flashLit, nil, v .. ": wMapPalOffset 6 imports dark")
  eq(assert(K.export(1, v, dark, false)):byte(O.mapPalOffset + 1), 6, v .. ": and exports 6")

  local lit = assert(K.import(1, v, cart(0)))
  eq(lit.flashLit, true, v .. ": wMapPalOffset 0 imports as flashLit")
  local out = assert(K.export(1, v, lit, false))
  eq(out:byte(O.mapPalOffset + 1), 0, v .. ": flashLit exports wMapPalOffset 0")
  eq(assert(K.import(1, v, out)).flashLit, true, v .. ": and survives a second import")

  dark.flashLit = true
  eq(assert(K.export(1, v, dark, false)):byte(O.mapPalOffset + 1), 0,
     v .. ": FLASH used after import exports 0")
  lit.flashLit = nil
  eq(assert(K.export(1, v, lit, false)):byte(O.mapPalOffset + 1), 6,
     v .. ": an unlit tunnel exports 6 even from a lit cart")
end

T.finish()
