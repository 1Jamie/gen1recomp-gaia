package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local function eqb(a, b, msg) check(a == b, msg) end
local K = require("tests.save_compat._codec")
local H = require("tests.save_compat._gen3_sections")
local Gen3Save = require("src.save_convert.Gen3Save")
local Layout = require("src.save_convert.Gen3Layout")
local Q = require("src.core.game3.quest_log")

local FRLG = Layout.family("frlg")
local QL, OBJ, TPL = FRLG.QUEST_LOG, FRLG.OBJECT_EVENTS, { off = 0x08E0, size = 0x600 }
local MAPVIEW = FRLG.MAP_VIEW

eq(QL.off, 0x1300, "the cart quest log starts at SB1 0x1300")
eq(QL.size, 4 * 0x668, "the cart quest log is 4 scenes of 0x668 bytes (include/global.h:613)")

local SCENE = {
  { "startType", 0, 1 }, { "mapGroup", 1, 1 }, { "mapNum", 2, 1 }, { "warpId", 3, 1 }, { "x", 4, 2 }, { "y", 6, 2 },
  { "objectEvents", 8, 320 }, { "flags", 328, 288 }, { "vars", 616, 512 }, { "objectEventTemplates", 1128, 256 },
  { "script", 1384, 256 },
}
local last = SCENE[#SCENE]
eq(last[2] + last[3], 0x668, "the scene layout tiles the 0x668 struct (script is 128 u16)")

local function cartWithLog(version, seed)
  local rng = H.rng(seed)
  return H.cart(version, function(w)
    H.randomize(w, "sb1", QL.off, QL.size, rng)
    H.randomize(w, "sb1", OBJ.off, OBJ.count * OBJ.size, rng)
    H.randomize(w, "sb2", MAPVIEW.off, MAPVIEW.size, rng)
  end)
end

local function exportOpts(version, template)
  local o = K.gen3Opts(version, template)
  o.mapLayoutId = function(g, n)
    if g == 3 and n == 0 then return 78 end
    return ({ ["4:1"] = 2 })[g .. ":" .. n]
  end
  o.healWarp = function() return { group = 3, num = 0, warpId = -1, x = 6, y = 8 } end
  return o
end

local function region(bytes, version, block, off, size)
  return H.blocks(bytes, version)[block]:sub(off + 1, off + size)
end

for _, version in ipairs({ "firered", "leafgreen" }) do
  for seed = 1, 20 do
    local cart = cartWithLog(version, seed)
    local save = H.import(version, cart)
    local out = H.withTemplate(version, save, cart)
    eqb(region(out, version, "sb1", QL.off, QL.size), region(cart, version, "sb1", QL.off, QL.size),
      ("%s seed %d: an unchanged player keeps the cart quest log byte for byte"):format(version, seed))
    eq(#K.r1Diff(3, version, cart, out), 0, ("%s seed %d: R1 logical round trip with a random quest log"):format(version, seed))

    local moved = H.import(version, cart)
    moved.x = (moved.x or 0) + 1
    local out2 = assert(Gen3Save.forVersion(version).exportPort(moved, exportOpts(version, cart)))
    eqb(region(out2, version, "sb1", QL.off, QL.size), region(cart, version, "sb1", QL.off, QL.size),
      ("%s seed %d: walking on the same map keeps the quest log"):format(version, seed))
    eqb(region(out2, version, "sb1", OBJ.off, OBJ.count * OBJ.size), region(cart, version, "sb1", OBJ.off, OBJ.count * OBJ.size),
      ("%s seed %d: walking on the same map keeps the object events"):format(version, seed))

    local away = H.import(version, cart)
    away.map, away.x, away.y = "FR_PALLET_TOWN", 12, 16
    local out3 = assert(Gen3Save.forVersion(version).exportPort(away, exportOpts(version, cart)))
    eqb(region(out3, version, "sb1", QL.off, QL.size), string.rep("\0", QL.size),
      ("%s seed %d: changing map resets the quest log (src/quest_log.c:200)"):format(version, seed))
    eqb(region(out3, version, "sb1", OBJ.off, OBJ.count * OBJ.size), string.rep("\0", OBJ.count * OBJ.size),
      ("%s seed %d: changing map resets the object events"):format(version, seed))
    eqb(region(out3, version, "sb2", MAPVIEW.off, MAPVIEW.size), string.rep("\0", MAPVIEW.size),
      ("%s seed %d: changing map resets the map view"):format(version, seed))
    eqb(region(out3, version, "sb1", TPL.off, TPL.size), region(cart, version, "sb1", TPL.off, TPL.size),
      ("%s seed %d: object event templates stay with the template"):format(version, seed))
    check(#Gen3Save.forVersion(version).decode(out3).party == #Gen3Save.forVersion(version).decode(cart).party,
      ("%s seed %d: the reset leaves the rest of the save alone"):format(version, seed))

    local bare = H.import(version, cart)
    local fresh = H.fresh(version, bare)
    eqb(region(fresh, version, "sb1", QL.off, QL.size), string.rep("\0", QL.size),
      ("%s seed %d: a templateless export has an empty quest log (src/quest_log.c:200)"):format(version, seed))
    eq(region(fresh, version, "sb1", 0x1300 + 0, 1), "\0", ("%s seed %d: no scene has a start type"):format(version, seed))

    local engineLog = H.import(version, cart)
    engineLog.questLog = { version = 1, scenes = { {
      map = "FR_PALLET_TOWN", frames = { { x = 1, y = 2, actors = {} } },
      events = { { key = "ArrivedInLocation", args = { "PALLET TOWN" }, frame = 1 } }, tiles = {},
    } } }
    local out4 = H.withTemplate(version, engineLog, cart)
    eqb(region(out4, version, "sb1", QL.off, QL.size), region(cart, version, "sb1", QL.off, QL.size),
      ("%s seed %d: the engine's own quest log never rewrites the cart quest log"):format(version, seed))
    local restored = Q.restore(engineLog.questLog)
    eq(#restored.scenes, 1, ("%s seed %d: the engine's own log keeps its format through its own restore"):format(version, seed))
  end
end

do
  local scene = { map = "FR_PALLET_TOWN", frames = {}, events = {}, tiles = {} }
  for i = 1, 3 do
    scene.frames[i] = { x = 16 * i, y = 16, actors = { { id = 255, x = 16 * i, y = 16, graphicsId = "OBJ_EVENT_GFX_RED_NORMAL",
      facing = "down", walkPhase = 0, stepFlip = false } } }
  end
  scene.events[1] = { key = "ArrivedInLocation", args = { "PALLET TOWN" }, frame = 1 }
  local restored = Q.restore({ version = 1, scenes = { scene } })
  local row = restored.scenes[1]
  check(row and row.frames[1].actors[1].graphicsId == "OBJ_EVENT_GFX_RED_NORMAL",
    "an engine scene stores sampled actor frames with symbolic graphics ids, not cart commands")
  check(row.events[1].key == "ArrivedInLocation" and type(row.events[1].args[1]) == "string",
    "an engine event is a message key with rendered string arguments, not a QL_EVENT code")
  eq(row.startType, nil, "an engine scene has no cart startType")
  eq(row.script, nil, "an engine scene has no cart action script")
  eq(Q.MAX_FRAMES, 300, "the engine keeps up to 300 sampled frames per scene")
  eq(Q.MAX_ACTORS, 24, "the engine keeps up to 24 actors per frame")
  check(Q.MAX_FRAMES * 2 * 8 > 256, "one engine scene cannot fit the cart scene's 256 byte action script")
end

T.finish()
