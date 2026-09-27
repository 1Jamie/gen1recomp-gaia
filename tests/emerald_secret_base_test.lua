package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_secret_base_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
local imports = {
  info = function(_, id) return { id = id, size = #data, md5 = "emerald", file = "memory" } end,
  read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
}
local rom = assert(require("src.import.gba.rom").open(imports, "emerald"))

local store = {}
local cache = {
  write = function(_, rel, bytes) store[rel] = bytes; return true end,
  read = function(_, rel) return store[rel] end,
  exists = function(_, rel) return store[rel] ~= nil end,
}
local ROOT = "data/generated/gba"
local Plans = require("src.import.gba.plans.registry")
local plan = require("src.import.gba.plans.rse.sb")
for _, step in ipairs(plan.tasks[1].steps) do
  local mod = require(Plans.moduleFor(step.name))
  local ok, err = pcall(mod.run, rom, cache, { cacheRoot = ROOT })
  check(ok, step.name .. " runs: " .. tostring(err))
  for _, rel in ipairs(mod.REQUIRED or {}) do
    check(store[ROOT .. "/" .. rel] ~= nil, step.name .. " wrote " .. rel)
  end
end
check(pcall(require("src.import.gba.rse.decorations_extract").run, rom, cache, { cacheRoot = ROOT }), "decorations table")

local function load(rel)
  return assert(loadstring(assert(store[ROOT .. "/" .. rel], rel), "@" .. rel))()
end

local man = load("secret_base/manifest.lua")
local Decor = require("src.core.game3.rse.decoration")
Decor.install(man, load("decorations/decorations.lua"))

-- pokeemerald/src/secret_base.c:111
eq(#man.entrances + 1, 24, "24 secret base layouts")
eq(man.entrances[13].x, 8, "YELLOW_CAVE2 computer x")
eq(man.entrances[13].y, 7, "YELLOW_CAVE2 computer y")
eq(man.entrances[16].warpId, 0, "entrance warp 0")
eq(#man.entranceMetatiles, 7, "7 entrance metatile pairs")
eq(#man.ownerGfx, 10, "10 owner gfx ids")
eq(man.decorCount, 121, "121 decoration rows")

local C = require("src.core.game3.constants").of("emerald")
local function decor(name) return C:require("decorations", name) end
local function mt(name) return C:require("metatile_labels", name) end

-- pokeemerald/src/data/decoration/tiles.h:3
eq(man.decorTiles[decor("DECOR_SMALL_DESK")][1] + Decor.PRIMARY, mt("METATILE_SecretBase_SmallDesk"), "SMALL DESK metatile")
eq(#man.decorTiles[decor("DECOR_HEAVY_DESK")], 6, "HEAVY DESK is 3x2")
eq(#man.decorTiles[decor("DECOR_RED_TENT")], 9, "RED TENT is 3x3")
eq(man.decorTiles[decor("DECOR_PIKA_POSTER")][1] + Decor.PRIMARY, mt("METATILE_SecretBase_PikaPoster_Left"),
  "PIKA POSTER left metatile")
eq(man.decorTiles[decor("DECOR_PICHU_DOLL")][1], C:require("event_objects", "OBJ_EVENT_GFX_PICHU_DOLL"),
  "PICHU DOLL is an object gfx")
check(Decor.isSprite(decor("DECOR_PICHU_DOLL")), "dolls are sprites")
eq(Decor.info(decor("DECOR_PIKA_POSTER")).permission, Decor.PERM.NA_WALL, "posters hang on the wall")

-- pokeemerald/src/secret_base.c:98
local function pairOf(closed, open)
  for _, e in ipairs(man.entranceMetatiles) do
    if e.closed == mt(closed) then return e.open == mt(open) end
  end
  return false
end
check(pairOf("METATILE_Fortree_SecretBase_Shrub", "METATILE_Fortree_SecretBase_ShrubOpen"), "shrub entrance pair")
check(pairOf("METATILE_General_YellowCaveIndent", "METATILE_General_YellowCaveOpen"), "yellow cave entrance pair")

local MB = require("src.core.game3.mb")

local function grid(cells, w, h)
  local g = { set = {}, objects = {} }
  function g.behavior(x, y)
    local c = cells[y * w + x + 1]
    return c and MB.id(c) or nil
  end
  function g.metatile(x, y) local s = g.set[y * 64 + x] return s and s.mid or 0 end
  function g.metatileId(name) return mt(name) end
  function g.setMetatile(x, y, mid, imp, elev) g.set[y * 64 + x] = { mid = mid, imp = imp, elev = elev } end
  function g.objectAt(x, y) return g.objects[y * 64 + x] end
  function g.size() return w, h end
  function g.original() return 0 end
  function g.restoreMetatile(x, y, elev) g.set[y * 64 + x] = { mid = 0, restored = true, elev = elev } end
  return g
end

local W, H = 6, 5
local cells = {}
for y = 0, H - 1 do
  for x = 0, W - 1 do
    cells[y * W + x + 1] = y == 0 and "SECRET_BASE_NORTH_WALL" or "NORMAL"
  end
end
cells[3 * W + 2 + 1] = "SECRET_BASE_TRAINER_SPOT"
cells[3 * W + 4 + 1] = "HOLDS_SMALL_DECORATION"
cells[3 * W + 5 + 1] = "SECRET_BASE_HOLE"
local g = grid(cells, W, H)
local place = { x = 1, y = 2, initialX = 0, initialY = 4 }

-- pokeemerald/src/decoration.c:1528
check(Decor.canPlace(g, place, decor("DECOR_SMALL_DESK")), "desk on floor")
check(not Decor.canPlace(g, { x = 2, y = 3, initialX = 0, initialY = 4 }, decor("DECOR_SMALL_DESK")),
  "desk not on a trainer spot")
check(not Decor.canPlace(g, { x = 1, y = 0, initialX = 0, initialY = 4 }, decor("DECOR_SMALL_DESK")), "desk not on wall")
check(Decor.canPlace(g, { x = 1, y = 0, initialX = 0, initialY = 4 }, decor("DECOR_PIKA_POSTER")), "poster on wall")
check(not Decor.canPlace(g, place, decor("DECOR_PIKA_POSTER")), "poster not on floor")
check(Decor.canPlace(g, { x = 4, y = 3, initialX = 0, initialY = 4 }, decor("DECOR_PICHU_DOLL")), "doll on a holder")
check(not Decor.canPlace(g, place, decor("DECOR_PICHU_DOLL")), "doll not on bare floor")
check(Decor.canPlace(g, { x = 5, y = 3, initialX = 0, initialY = 4 }, decor("DECOR_SOLID_BOARD")), "board over hole")
check(not Decor.canPlace(g, { x = 5, y = 3, initialX = 0, initialY = 4 }, decor("DECOR_SMALL_DESK")), "desk not in hole")
g.objects[2 * 64 + 1] = 3
check(not Decor.canPlace(g, place, decor("DECOR_SMALL_DESK")), "an object blocks floor placement")
g.objects[2 * 64 + 1] = 0
check(Decor.canPlace(g, place, decor("DECOR_SMALL_DESK")), "the player's own cell does not block a floor decoration")
g.objects[2 * 64 + 1] = nil
local heavy = decor("DECOR_HEAVY_DESK")
check(Decor.canPlace(g, { x = 1, y = 2, initialX = 5, initialY = 4 }, heavy), "heavy desk fits on open floor")
check(Decor.layerType(man.decorTiles[heavy][2]) ~= 0, "heavy desk top row is a covered layer")
check(not Decor.canPlace(g, { x = 1, y = 2, initialX = 2, initialY = 1 }, heavy),
  "a covered tile cannot sit where the player stood at the PC")

-- pokeemerald/src/decoration.c:1208
Decor.showOnMap(g, 1, 2, decor("DECOR_SMALL_DESK"))
eq(g.set[2 * 64 + 1].mid, mt("METATILE_SecretBase_SmallDesk"), "desk metatile written")
Decor.showOnMap(g, 1, 0, decor("DECOR_LONG_POSTER"))
eq(g.set[0 * 64 + 1].mid, man.decorTiles[decor("DECOR_LONG_POSTER")][1] + Decor.PRIMARY, "wall poster keeps base metatile")
local stand = decor("DECOR_STAND")
Decor.showOnMap(g, 1, 3, stand)
local topRow = g.set[2 * 64 + 1]
check(topRow and topRow.elev == man.standElevations[1], "stand writes its elevation table")

-- pokeemerald/src/decoration.c:1685
local sess = { version = "emerald", decorationInventory = nil }
local SB = require("src.core.game3.rse.secret_base")
local bases = SB.bases(sess)
eq(#bases, 20, "20 secret base records")
local DecorInv = require("src.core.game3.rse.decoration_inventory")
DecorInv.add(decor("DECOR_SMALL_DESK"), sess)
DecorInv.add(decor("DECOR_SMALL_DESK"), sess)
DecorInv.add(decor("DECOR_PICHU_DOLL"), sess)
local ctx = Decor.context(sess, false)
eq(Decor.record(ctx, decor("DECOR_SMALL_DESK"), 3, 4), 1, "first decoration slot")
eq(bases[1].decorationPositions[1], 0x34, "position packed x<<4|y")
local inBase = Decor.inUse(sess, Decor.CAT.DESK)
check(inBase[1] and not inBase[2], "one of two desks in use")
check(not Decor.isInPc(sess, Decor.CAT.DESK, 1) and Decor.isInPc(sess, Decor.CAT.DESK, 2), "second desk still in the PC")
local room = Decor.context(sess, true)
Decor.record(room, decor("DECOR_PICHU_DOLL"), 5, 2)
local _, inRoom = Decor.inUse(sess, Decor.CAT.DOLL)
check(inRoom[1], "bedroom doll marked in use")
Decor.toss(sess, Decor.CAT.DESK, 2)
eq(DecorInv.countInCategory(Decor.CAT.DESK, sess), 1, "toss removes the stored desk")

-- pokeemerald/src/decoration.c:2570
local g2 = grid(cells, W, H)
local marked = Decor.markForRemoval(g2, ctx, 3, 4)
eq(#marked, 1, "cursor on the desk marks it")
check(#Decor.markForRemoval(g2, ctx, 2, 4) == 0, "cursor next to it marks nothing")
Decor.clearNonSprites(g2, ctx, marked)
check(g2.set[4 * 64 + 3] and g2.set[4 * 64 + 3].restored and g2.set[4 * 64 + 3].elev == 3, "put away restores the map")
eq(ctx.items[1], 0, "put away clears the slot")

-- pokeemerald/src/secret_base.c:1132
bases[2].trainerId = { 7, 0, 0, 0 }
bases[2].gender = 1
eq(SB.ownerType(1, sess), 7, "owner type = id % 5 + gender * 5")
eq(SB.typeAt(MB.id("SECRET_BASE_SPOT_SHRUB")), SB.TYPE.SHRUB, "shrub spot")
eq(SB.typeAt(MB.id("SECRET_BASE_SPOT_TREE_RIGHT_OPEN")), SB.TYPE.TREE, "open tree spot")
check(SB.isOpenDoor(MB.id("SECRET_BASE_SPOT_YELLOW_CAVE_OPEN")), "open yellow cave is a door")
check(not SB.isOpenDoor(MB.id("SECRET_BASE_SPOT_YELLOW_CAVE")), "closed indent is not a door")
check(SB.isCave(MB.id("SECRET_BASE_SPOT_RED_CAVE")) and not SB.isCave(MB.id("SECRET_BASE_SPOT_RED_CAVE_OPEN")),
  "Secret Power only on closed caves")

-- pokeemerald/src/secret_base.c:381
local events = { { type = "secret_base", secretBaseId = 131, x = 2, y = 1 }, { type = "secret_base", secretBaseId = 141, x = 4, y = 1 } }
local g3 = grid(cells, W, H)
g3.set[1 * 64 + 2] = { mid = mt("METATILE_General_YellowCaveIndent") }
g3.set[1 * 64 + 4] = { mid = mt("METATILE_General_YellowCaveIndent") }
bases[1].secretBaseId = 131
SB.setOccupiedEntrances(events, g3, sess)
eq(g3.set[1 * 64 + 2].mid, mt("METATILE_General_YellowCaveOpen"), "the player's entrance opens on load")
check(g3.set[1 * 64 + 2].imp == true, "open entrance stays impassable")
eq(g3.set[1 * 64 + 4].mid, mt("METATILE_General_YellowCaveIndent"), "an empty spot stays closed")
check(SB.toggleEntrance(4, 1, g3) and g3.set[1 * 64 + 4].mid == mt("METATILE_General_YellowCaveOpen"), "toggle opens")
check(SB.toggleEntrance(4, 1, g3) and g3.set[1 * 64 + 4].mid == mt("METATILE_General_YellowCaveIndent"), "toggle closes")

-- pokeemerald/src/secret_base.c:1804
local SaveSections = require("src.core.game3.save_sections")
local out = {}
local def = SaveSections.register("secretBases", SaveSections.fields({ "secretBases", "playerRoomDecorationPositions" }))
def.export(sess, out)
local back = {}
def.restore(out, back)
eq(back.secretBases[1].secretBaseId, 131, "base id survives a save round trip")
eq(back.playerRoomDecorationPositions[1], 0x52, "bedroom doll position survives")

T.finish()
