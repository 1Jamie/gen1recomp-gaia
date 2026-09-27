package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local before = GameVersion.get()
local Constants = require("src.core.game3.constants")
local MB = require("src.core.game3.mb")
local MbEm = require("src.import.gba.mb_emerald")

local fr = Constants.of("firered").metatile_behaviors
local em = Constants.of("emerald").metatile_behaviors

local frOk, frCount = true, 0
for full, v in pairs(fr.byName) do
  if full:match("^MB_") then
    frCount = frCount + 1
    if MB[full:sub(4)] ~= v then frOk = false end
  end
end
check(frOk, "every FR behavior name keeps its FR value")
eq(frCount, 111, "111 FR behavior names")

local rseOnly, rseLow = 0, 0
for full in pairs(em.byName) do
  if full:match("^MB_") and fr.byName[full] == nil and not MB.RENAMES[full:sub(4)] then
    rseOnly = rseOnly + 1
    if MB[full:sub(4)] < MB.RSE_BASE then rseLow = rseLow + 1 end
  end
end
check(rseOnly > 150, "RSE-only names exist (" .. rseOnly .. ")")
eq(rseLow, 0, "RSE-only names sit at 0x100+")

eq(MB.ICE, 0x23, "ICE keeps the FR id")
eq(MB.BOOKSHELF, 0x81, "BOOKSHELF keeps the FR id")
eq(MB.ANIMATED_DOOR, MB.WARP_DOOR, "ANIMATED_DOOR is WARP_DOOR")
eq(MB.NON_ANIMATED_DOOR, MB.CAVE_DOOR, "NON_ANIMATED_DOOR is CAVE_DOOR")
eq(MB.NO_RUNNING, MB.RUNNING_DISALLOWED, "NO_RUNNING is RUNNING_DISALLOWED")
eq(MB.NO_SURFACING, MB.UNDERWATER_BLOCKED_ABOVE, "NO_SURFACING is UNDERWATER_BLOCKED_ABOVE")
eq(MB.BRIDGE_OVER_OCEAN, 0x170, "BRIDGE_OVER_OCEAN is 0x170")
eq(MB.nameOf(0x69), "WARP_DOOR", "canonical name of 0x69 is the FR name")
eq(MB.nameOf(MB.FORTREE_BRIDGE), "FORTREE_BRIDGE", "RSE-only name round trips")
check(MB.isRseOnly(MB.MUDDY_SLOPE) and not MB.isRseOnly(MB.TALL_GRASS), "isRseOnly")
eq(MB.fromRaw("firered", 0x70), 0x70, "firered raw is canonical")
eq(MB.fromRaw("emerald", 0x70), 0x170, "emerald raw 0x70 is the ocean bridge")

eq(MbEm.canon(0x20), 0x23, "EM ICE 0x20 -> 0x23")
eq(MbEm.canon(0xE1), 0x81, "EM BOOKSHELF 0xE1 -> 0x81")
eq(MbEm.canon(0x69), 0x69, "EM ANIMATED_DOOR -> WARP_DOOR")
eq(MbEm.canon(0x02), 0x02, "EM TALL_GRASS unchanged")
eq(MbEm.canon(0xD0), MB.MUDDY_SLOPE, "EM MUDDY_SLOPE is not cycling road pull")
eq(MbEm.canon(0x84), MB.CABLE_BOX_RESULTS_1, "EM 0x84 is not SIGNPOST")
eq(MbEm.raw(0x23), 0x20, "reverse ICE")
local seen, inj = {}, true
for raw = 0, 255 do
  local c = MbEm.canon(raw)
  if seen[c] then inj = false end
  seen[c] = true
end
check(inj, "EM raw -> canonical is injective")
local warpRange = 0
for raw = 0x70, 0x7F do
  local c = MbEm.canon(raw)
  if c >= 0x60 and c <= 0x7F then warpRange = warpRange + 1 end
end
eq(warpRange, 0, "EM bridges 0x70-0x7F leave the FR warp range")

local Collision = require("src.core.game3.scripting.collision")
local CollFr = require("src.core.game3.scripting.collision_frlg")
local CollRse = require("src.core.game3.scripting.collision_rse")

GameVersion.set("firered")
eq(Collision.impl(), CollFr, "firered classifies with the frlg body")
local frSame = true
for beh = 0, 0xFF do
  for _, kind in ipairs({ "town", "route", "indoor" }) do
    for _, mid in ipairs({ 0x00A, 0x014, 0x070, 0x286, 0x1C5, 0x300 }) do
      for mc = 0, 1 do
        local a1, a2, a3 = Collision.fromCell(mid, mc, beh, kind)
        local b1, b2, b3 = CollFr.fromCell(mid, mc, beh, kind)
        if a1 ~= b1 or a2 ~= b2 or a3 ~= b3 then frSame = false end
      end
    end
  end
end
check(frSame, "dispatcher == frlg body under firered")
eq(Collision.seed("DOOR", nil, "town"), 0x71, "fr door seed")

GameVersion.set("emerald")
eq(Collision.impl(), CollRse, "emerald classifies with the rse body")
CollRse.setTileBits({ [MB.OCEAN_WATER] = 3, [MB.POND_WATER] = 3 })
eq(Collision.fromCell(0x10A, 0, MB.WARP_DOOR, "town"), 0x71, "animated door outdoors")
eq(Collision.fromCell(0x10A, 0, MB.WARP_DOOR, "indoor"), 0x72, "door mat indoors")
eq(Collision.fromCell(5, 0, MB.OCEAN_WATER, "route"), 0x29, "surfable water")
eq(Collision.fromCell(5, 1, MB.OCEAN_WATER, "route"), 0x07, "surfable water with collision")
eq(Collision.fromCell(5, 0, MB.BRIDGE_OVER_OCEAN, "route"), 0x00, "ocean bridge walkable")
eq(Collision.fromCell(5, 0, MB.FORTREE_BRIDGE, "town"), 0x00, "fortree bridge walkable")
eq(Collision.fromCell(5, 0, MB.TALL_GRASS, "route"), 0x18, "tall grass")
eq(Collision.fromCell(5, 0, MB.LONG_GRASS, "route"), 0x18, "long grass")
eq(Collision.fromCell(5, 0, MB.JUMP_SOUTH, "route"), 0xA3, "south ledge")
eq(Collision.fromCell(5, 0, MB.CRACKED_FLOOR_HOLE, "indoor"), 0x72, "cracked floor hole warps")
eq(Collision.fromCell(5, 0, MB.LADDER, "indoor"), 0x72, "ladder warps")
eq(Collision.fromCell(5, 0, MB.PC, "indoor"), 0x93, "pc")
eq(Collision.fromCell(0x014, 0, MB.NORMAL, "route"), 0x00, "no FR tree heuristic on RSE")
eq(Collision.fromCell(0x300, 1, MB.NORMAL, "town"), 0x07, "blocked by map collision")
eq(Collision.fromCell(5, 0, MB.MUDDY_SLOPE, "route"), 0x00, "muddy slope is not tall grass")
CollRse.setTileBits(nil)
eq(Collision.fromCell(5, 0, MB.OCEAN_WATER, "route"), 0x00, "no tile bits, no water guess")

local VoidFill = require("src.core.game3.void_fill")
eq(VoidFill.PRIMARY_MIDS, 512, "em void fill primary split")
eq(VoidFill.SOURCES.trees, "EM_LITTLEROOT_TOWN", "em tree void source")
eq(VoidFill.SOURCES.water, "EM_ROUTE105", "em water void source")
local NativePack = require("src.import.gba.native_pack")
eq(NativePack.atlasPolicy("emerald"), "full", "em atlas policy")
local list = NativePack.fullMidsForPair({ primaryMt = { count = 512 }, secondaryMt = { count = 3 } })
eq(#list, 515, "full atlas lists every metatile")
eq(list[513], 512, "secondary mids start at 512")
eq(list[515], 514, "last secondary mid")

GameVersion.set("firered")
eq(VoidFill.PRIMARY_MIDS, 640, "fr void fill primary split")
eq(VoidFill.SOURCES.trees, "FR_PALLET_TOWN", "fr tree void source")
eq(NativePack.atlasPolicy("firered"), "used", "fr atlas policy")

local AnimPack = require("src.import.gba.tileset_anim_pack")
eq(AnimPack.WATER_TILE, 416, "fr water tile")
eq(AnimPack.WATER_COUNT, 48, "fr water count")
eq(AnimPack.SAND_TILE, 464, "fr sand tile")
eq(AnimPack.FLOWER_COUNT, 4, "fr flower count")
eq(AnimPack.DEFAULT_FRAMES.water.count, 8, "fr water frames")

local S = require("src.import.gba.syms").of("emerald")
local Data = require("src.import.gba.tileset_anims_emerald")
local initsOk, tablesOk, dstOk, inits = true, true, true, 0
for name, init in pairs(Data.INITS) do
  inits = inits + 1
  if not S.hasFunc(name) then initsOk = false end
  for _, row in ipairs(init.anims) do
    for _, p in ipairs(row.parts or {}) do
      for _, sym in ipairs({ p.frames, p.framesB, p.dstTable }) do
        if sym and not S.has(sym) then tablesOk = false end
      end
      if p.dst and (p.dst < 0 or p.dst + p.tiles > 1024) then dstOk = false end
    end
    if row.palette and not S.has(row.palette) then tablesOk = false end
  end
end
eq(inits, 25, "25 pret tileset anim inits")
check(initsOk, "every init is a pret function")
check(tablesOk, "every frame/dest table is a pret symbol")
check(dstOk, "every destination fits VRAM tiles")
eq(Data.INITS.InitTilesetAnim_Underwater.max, 128, "underwater secondary max")
eq(Data.INITS.InitTilesetAnim_SootopolisGym.max, 240, "sootopolis gym secondary max")
eq(Data.INITS.InitTilesetAnim_General.anims[2].parts[1].dst, 432, "em general water dst")

local Oi = require("src.import.gba.object_interactions_extract")
local oiOk = true
for _, row in ipairs(Oi.RSE_INTERACTIONS) do
  if not MB.id(row[1]) or not S.has(row[2]) then oiOk = false end
end
check(oiOk, "every RSE interaction row names a behavior and a pret script")

GameVersion.set(before)
T.finish("game3_mb_collision_rse_test")
