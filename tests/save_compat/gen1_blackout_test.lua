package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")
local K = require("tests.save_compat._codec")

if not K.gen1Available() then
  print("gen1_blackout skipped (needs data/generated/ for the Gen 1 save codec)")
  os.exit(0)
end

local GenSave = require("src.save_convert.GenSave")
local G1 = require("tests.fixtures.save.gen1_build")
local P = require("tests.save_compat._pret_asm")
local Game = require("src.core.Game")
local Overworld = require("src.world.OverworldController")

do
  local i = 1
  while true do
    local name = debug.getupvalue(Overworld.escapeWarpTarget, i)
    if not name then break end
    if name == "Game" then debug.setupvalue(Overworld.escapeWarpTarget, i, Game) end
    i = i + 1
  end
end

local O = GenSave.OFFSETS
local table13 = require("src.save_convert.data.blackout_maps")

local function cartWith(version, byte)
  return G1.build({ version = version, patch = function(b) b[G1.OFF.lastBlackoutMap] = byte end })
end

local function isPokeCenter(id)
  return id:match("POKECENTER$") or id == "INDIGO_PLATEAU_LOBBY"
end

local function run(version)
  local data = K.gen1Data(version)
  local cw = GenSave.crosswalks(data)
  local root = P.root(version)
  local tag = version .. ": "

  eq(#table13, 13, tag .. "the blackout table has the 13 FlyWarpDataPtr rows")
  local seen = {}
  for i, row in ipairs(table13) do
    seen[row[1]] = true
    check(cw.mapsIndex[row[1]] ~= nil, tag .. row[1] .. " is a map in the cache")
    local fw = data.field.flyWarps[row[1]]
    check(fw and fw.x == row[2] and fw.y == row[3], tag .. row[1] .. " matches the extracted fly warp")
  end

  local centerCount = 0
  if root then
    local order, coords = P.flyWarpData(root)
    local idx = P.mapIndexes(root)
    eq(#order, #table13, tag .. "pret FlyWarpDataPtr has 13 rows")
    for i, map in ipairs(order) do
      eq(table13[i][1], map, tag .. "row " .. i .. " is " .. map)
      eq(table13[i][2], coords[map][1], tag .. map .. " x from special_warps.asm")
      eq(table13[i][3], coords[map][2], tag .. map .. " y from special_warps.asm")
      eq(cw.mapsIndex[map], idx[map], tag .. map .. " map id matches map_constants.asm")
    end
  else
    print("gen1_blackout: pret checkout missing for " .. version .. ", asm cross-checks skipped")
  end

  for _, row in ipairs(table13) do
    local town, x, y = row[1], row[2], row[3]
    local byte = cw.mapsIndex[town]
    local bytes = cartWith(version, byte)
    local save = assert(K.import(1, version, bytes))
    eq(save.lastHeal.map, town, tag .. town .. ": imports as the heal town")
    eq(save.lastHeal.x, x, tag .. town .. ": heal x is the fly warp x")
    eq(save.lastHeal.y, y, tag .. town .. ": heal y is the fly warp y")
    Game.data, Game.save = data, save
    local map, lx, ly = Overworld.escapeWarpTarget(Overworld)
    eq(map, town, tag .. town .. ": a blackout lands in the town")
    eq(lx, x, tag .. town .. ": a blackout lands at the fly warp x")
    eq(ly, y, tag .. town .. ": a blackout lands at the fly warp y")
    local out = assert(K.export(1, version, save))
    eq(out:byte(O.lastBlackoutMap + 1), byte, tag .. town .. ": the byte survives cart -> recomp -> cart")
    save.lastHeal = { map = town, x = x, y = y }
    out = assert(K.export(1, version, save, false))
    eq(out:byte(O.lastBlackoutMap + 1), byte, tag .. town .. ": a town heal exports its own id")

    local centers = {}
    if root then
      for _, dest in ipairs(P.warpDestinations(root, town)) do
        if isPokeCenter(dest) then centers[#centers + 1] = dest end
      end
    else
      for _, warp in ipairs(data.maps[town].warps or {}) do
        if isPokeCenter(warp.destMap) then centers[#centers + 1] = warp.destMap end
      end
    end
    local uniq, seenCenter = {}, {}
    for _, c in ipairs(centers) do
      if not seenCenter[c] then seenCenter[c] = true; uniq[#uniq + 1] = c end
    end
    centers = uniq
    centerCount = centerCount + #centers
    for _, center in ipairs(centers) do
      for _, withOutdoor in ipairs({ false, true }) do
        local heal = { map = center, x = 4, y = 4 }
        if withOutdoor then heal.outdoor = { id = town, x = x, y = y } end
        save.lastHeal = heal
        local exported = assert(K.export(1, version, save, false))
        eq(exported:byte(O.lastBlackoutMap + 1), byte,
          ("%s%s heal exports %s (%s outdoor)"):format(tag, center, town, withOutdoor and "with" or "without"))
      end
      Game.data, Game.save = data, { lastHeal = { map = center, x = 4, y = 4 } }
      local m, mx, my = Overworld.escapeWarpTarget(Overworld)
      check(m ~= town or (mx == x and my == y), tag .. center .. ": the engine itself resolves a center-only heal sanely")
    end
  end

  eq(centerCount, 12, tag .. "12 Pokemon Center style maps hang off the 13 blackout towns")

  local pallet = assert(K.import(1, version, cartWith(version, 0)))
  eq(pallet.lastHeal.map, "PALLET_TOWN", tag .. "a never-healed cart blacks out to Pallet Town")
  eq(assert(K.export(1, version, pallet)):byte(O.lastBlackoutMap + 1), 0, tag .. "and exports 0")

  local route1 = cw.mapsIndex.ROUTE_1
  for _, bad in ipairs({ route1, 0xFF, 0x55 }) do
    local save = assert(K.import(1, version, cartWith(version, bad)))
    eq(save.lastHeal.map, "PALLET_TOWN", tag .. ("byte %02X is not a FlyWarpDataPtr row, the recomp uses Pallet"):format(bad))
    eq(assert(K.export(1, version, save)):byte(O.lastBlackoutMap + 1), bad, tag .. ("byte %02X is preserved on the way out"):format(bad))
    save.lastHeal = { map = "CELADON_POKECENTER", x = 3, y = 3 }
    eq(assert(K.export(1, version, save)):byte(O.lastBlackoutMap + 1), cw.mapsIndex.CELADON_CITY,
      tag .. ("byte %02X is replaced once the player heals"):format(bad))
  end

  local dungeon = assert(K.import(1, version, cartWith(version, 0)))
  dungeon.lastHeal = { map = "SEAFOAM_ISLANDS_B1F", x = 23, y = 7 }
  dungeon.cartBlackoutMap = nil
  local before = dungeon.rawImport:byte(O.lastBlackoutMap + 1)
  eq(assert(K.export(1, version, dungeon)):byte(O.lastBlackoutMap + 1), before,
    tag .. "a dungeon escape spot is never written as wLastBlackoutMap")
end

run("red")
run("yellow")

T.finish()
