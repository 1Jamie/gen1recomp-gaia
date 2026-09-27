package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Family = require("src.import.gba.family")
local Tileset = require("src.import.gba.tileset")
local Metatile = require("src.import.gba.metatile")
local MapTree = require("src.import.gba.map_tree")
local ExtractMapEvents = require("src.import.gba.extract_map_events")
local MapCatalog = require("src.import.gba.map_catalog")
local MapIds = require("src.core.game3.map_ids")

local before = GameVersion.get()

local function fakeRom(size)
  local bytes = {}
  for i = 0, size - 1 do bytes[i] = 0 end
  local rom = { bytes = bytes }
  function rom:get(o) return self.bytes[o] end
  function rom:u16(o) return self.bytes[o] + self.bytes[o + 1] * 256 end
  function rom:u32(o)
    return self.bytes[o] + self.bytes[o + 1] * 256 + self.bytes[o + 2] * 65536 + self.bytes[o + 3] * 16777216
  end
  function rom:readString(o, n)
    local t = {}
    for i = 0, n - 1 do t[i + 1] = string.char(self.bytes[o + i] or 0) end
    return table.concat(t)
  end
  function rom:readBytes(o, n)
    local t = {}
    for i = 0, n - 1 do t[i + 1] = self.bytes[o + i] or 0 end
    return t
  end
  function rom:ptrOffset(p)
    if not p or p < 0x08000000 or p >= 0x0A000000 then return nil end
    return p - 0x08000000
  end
  function rom:put8(o, v) self.bytes[o] = v % 256 end
  function rom:put16(o, v) self:put8(o, v); self:put8(o + 1, math.floor(v / 256)) end
  function rom:put32(o, v) self:put16(o, v % 65536); self:put16(o + 2, math.floor(v / 65536)) end
  return rom
end

GameVersion.set("red")
eq(Family.active().name, "frlg", "non gen 3 process resolves the frlg family")
eq(Family.active().game, "firered", "non gen 3 process resolves firered")
eq(Family.of("leafgreen").name, "frlg", "leafgreen is frlg")
eq(Family.of("emerald").name, "rse", "emerald is rse")
eq(Family.of("emerald").game, "emerald", "emerald descriptor carries its game")

local FR, EM = Family.of("firered"), Family.of("emerald")
eq(FR.numPrimaryTiles, 640, "fr primary tiles")
eq(FR.numPrimaryMetatiles, 640, "fr primary metatiles")
eq(FR.numPalsInPrimary, 7, "fr primary pals")
eq(EM.numPrimaryTiles, 512, "em primary tiles")
eq(EM.numPrimaryMetatiles, 512, "em primary metatiles")
eq(EM.numPalsInPrimary, 6, "em primary pals")
eq(EM.numPalsTotal, 13, "em total pals")
eq(FR.attrBytes, 4, "fr attr u32")
eq(EM.attrBytes, 2, "em attr u16")
eq(FR.tilesetOffsets.attributes, 20, "fr attributes at +20")
eq(FR.tilesetOffsets.callback, 16, "fr callback at +16")
eq(EM.tilesetOffsets.attributes, 16, "em attributes at +16")
eq(EM.tilesetOffsets.callback, 20, "em callback at +20")
eq(EM.connDirs[5], "dive", "em dive connection")
eq(EM.connDirs[6], "emerge", "em emerge connection")
eq(FR.cloneObjects, true, "fr clone objects")
eq(EM.cloneObjects, false, "em has no clone objects")

eq(FR.behaviorOf(0x600001FF), 0x1FF, "fr behavior 9 bits")
eq(FR.layerOf(0x40000000), 2, "fr layer bits 29-30")
eq(FR.encounterOf(0x01000000), 1, "fr encounter bits 24-26")
eq(EM.behaviorOf(0x21AB), 0xAB, "em behavior 8 bits")
eq(EM.layerOf(0x1000), 1, "em layer bits 12-15")
eq(EM.encounterOf(0x1000), nil, "em encounter type is not in the attr")

GameVersion.set("firered")
eq(Tileset.NUM_PRIMARY_METATILES, 640, "Tileset fr metatiles")
eq(Tileset.NUM_PALS_IN_PRIMARY, 7, "Tileset fr pals")
GameVersion.set("emerald")
eq(Tileset.NUM_PRIMARY_METATILES, 512, "Tileset em metatiles")
eq(Tileset.NUM_PRIMARY_TILES, 512, "Tileset em tiles")
eq(Tileset.NUM_PALS_IN_PRIMARY, 6, "Tileset em pals")
eq(Tileset.NUM_PALS_TOTAL, 13, "Tileset em total pals")

do
  GameVersion.set("emerald")
  local attrs = { data = string.char(0x02, 0x10, 0xE1, 0x20), count = 2 }
  local b, w = Tileset.attrOf(attrs, 1)
  eq(b, 0xE1, "em attr 1 behavior")
  eq(w, 0x20E1, "em attr 1 raw")
  local b2 = Tileset.attrOf(attrs, 513, 512)
  eq(b2, 0xE1, "em secondary attr index uses 512 split")
  local bundle = {
    primaryAttr = attrs,
    secondaryAttr = { data = string.char(0x00, 0x20), count = 1 },
  }
  eq(Metatile.layerType(bundle, 0), 1, "em metatile 0 covered")
  eq(Metatile.layerType(bundle, 512), 2, "em metatile 512 split")
  local rom = fakeRom(64)
  rom.bytes[0], rom.bytes[1], rom.bytes[2], rom.bytes[3] = 1, 2, 3, 4
  eq(Tileset.loadAttributes(rom, 0, 4).count, 2, "em attributes count = bytes / 2")

  GameVersion.set("firered")
  local fattrs = { data = string.char(0xFF, 0x01, 0x00, 0x40), count = 1 }
  local fb, fw = Tileset.attrOf(fattrs, 0)
  eq(fb, 0x1FF, "fr attr behavior")
  eq(fw, 0x400001FF, "fr attr raw")
  eq(Metatile.layerType({ primaryAttr = fattrs }, 0), 2, "fr metatile layer split")
  eq(Tileset.loadAttributes(rom, 0, 8).count, 2, "fr attributes count = bytes / 4")
end

do
  GameVersion.set("emerald")
  local pri, sec = {}, {}
  for p = 0, 15 do
    pri[p], sec[p] = {}, {}
    for c = 0, 15 do pri[p][c] = 100 + p; sec[p][c] = 200 + p end
  end
  local m = Tileset.mergeMapPalettes(pri, sec)
  eq(m[5][1], 105, "em slot 5 from primary")
  eq(m[6][1], 206, "em slot 6 from secondary")
  eq(m[12][1], 212, "em slot 12 from secondary")
  eq(m[0][0], 0, "slot 0 colour 0 black")
  GameVersion.set("firered")
  m = Tileset.mergeMapPalettes(pri, sec)
  eq(m[6][1], 106, "fr slot 6 from primary")
  eq(m[7][1], 207, "fr slot 7 from secondary")
end

do
  local rom = fakeRom(0x400)
  local H, L, TS = 0x100, 0x200, 0x300
  rom:put32(H, 0x08000000 + L)
  rom:put16(H + 16, 0x1A3)
  rom:put16(H + 18, 7)
  rom:put8(H + 20, 9)
  rom:put8(H + 22, 2)
  rom:put8(H + 23, 3)
  rom:put8(H + 24, 1)
  rom:put8(H + 25, 0x0F)
  rom:put8(H + 26, 0x0D)
  rom:put8(H + 27, 5)
  rom:put32(L, 20)
  rom:put32(L + 4, 18)
  rom:put8(L + 24, 3)
  rom:put8(L + 25, 4)
  rom:put8(TS, 1)
  rom:put8(TS + 1, 0)
  rom:put32(TS + 12, 0x08000000 + 0x40)
  rom:put32(TS + 16, 0x08000000 + 0x60)
  rom:put32(TS + 20, 0x08000000 + 0x80)

  GameVersion.set("emerald")
  local h = MapTree.parseHeader(rom, H)
  eq(h.music, 0x1A3, "em header music")
  eq(h.layoutId, 7, "em header layout id")
  eq(h.allowCycling, 1, "em cycling bit 0")
  eq(h.bikingAllowed, 1, "em bikingAllowed alias")
  eq(h.allowEscaping, 0, "em escape bit 1")
  eq(h.allowRunning, 1, "em running bit 2")
  eq(h.showMapName, 1, "em showMapName bits 3-7")
  eq(h.floorNum, nil, "em has no floorNum")
  eq(h.battleType, 5, "em battleType")
  local lay = MapTree.parseLayout(rom, L)
  eq(lay.borderWidth, 2, "em border 2 wide")
  eq(lay.borderHeight, 2, "em border 2 tall")
  local ts = MapTree.parseTileset(rom, 0x08000000 + TS)
  eq(ts.attributesPtr, 0x08000060, "em attributes pointer at +16")
  eq(ts.callbackPtr, 0x08000080, "em callback pointer at +20")
  eq(ts.mid_count, 2, "em metatile count from gap")
  eq(ts.attr_bytes, 4, "em attr bytes = mids * 2")

  GameVersion.set("firered")
  h = MapTree.parseHeader(rom, H)
  eq(h.bikingAllowed, 1, "fr bikingAllowed byte")
  eq(h.allowEscaping, 1, "fr escape bit 0")
  eq(h.allowRunning, 1, "fr running bit 1")
  eq(h.showMapName, 3, "fr showMapName bits 2-7")
  eq(h.floorNum, 13, "fr floorNum")
  eq(h.allowCycling, nil, "fr has no allowCycling")
  lay = MapTree.parseLayout(rom, L)
  eq(lay.borderWidth, 3, "fr border width byte")
  eq(lay.borderHeight, 4, "fr border height byte")
  ts = MapTree.parseTileset(rom, 0x08000000 + TS)
  eq(ts.attributesPtr, 0x08000080, "fr attributes pointer at +20")
  eq(ts.callbackPtr, 0x08000060, "fr callback pointer at +16")
  eq(ts.mid_count, 4, "fr metatile count from gap")
  eq(ts.attr_bytes, 16, "fr attr bytes = mids * 4")
end

do
  local rom = fakeRom(0x800)
  local H, EV, BG, MS, MS6, CN, CL, OBJ = 0x100, 0x140, 0x180, 0x1E0, 0x1F0, 0x200, 0x210, 0x300
  rom:put32(H + 4, 0x08000000 + EV)
  rom:put32(H + 8, 0x08000000 + MS)
  rom:put32(H + 12, 0x08000000 + CN)
  rom:put8(EV, 1)
  rom:put8(EV + 3, 3)
  rom:put32(EV + 4, 0x08000000 + OBJ)
  rom:put32(EV + 16, 0x08000000 + BG)
  rom:put8(BG + 5, 7)
  rom:put16(BG + 8, 0x44)
  rom:put16(BG + 10, 0x0312)
  rom:put8(BG + 12 + 5, 8)
  rom:put32(BG + 12 + 8, 17)
  rom:put8(BG + 24 + 5, 0)
  rom:put32(BG + 24 + 8, 0x08000400)
  rom:put8(MS, 6)
  rom:put32(MS + 1, 0x08000000 + MS6)
  rom:put8(MS + 5, 0)
  rom:put32(CN, 2)
  rom:put32(CN + 4, 0x08000000 + CL)
  rom:put8(CL, 5)
  rom:put8(CL + 8, 0)
  rom:put8(CL + 9, 1)
  rom:put8(CL + 12, 2)
  rom:put32(CL + 16, 0xFFFFFFF6)
  rom:put8(OBJ, 1)
  rom:put8(OBJ + 2, 0)
  rom:put8(OBJ + 9, 12)
  rom:put16(OBJ + 14, 3)

  GameVersion.set("emerald")
  local ev = ExtractMapEvents.parseMapEvents(rom, 0x08000000 + EV)
  local hi = ev.bgEvents[1]
  eq(hi.type, "hidden_item", "em hidden item row")
  eq(hi.item, 0x44, "em hidden item id")
  eq(hi.hiddenItemId, 0x0312, "em hiddenItemId is the full u16")
  eq(hi.quantity, nil, "em hidden item has no quantity")
  eq(hi.underfoot, nil, "em hidden item has no underfoot")
  eq(hi.flag, 0x1F4 + 0x0312, "em hidden flag base 0x1F4")
  eq(ev.bgEvents[2].type, "secret_base", "em kind 8 is a secret base")
  eq(ev.bgEvents[2].secretBaseId, 17, "em secret base id")
  eq(ev.bgEvents[3].scriptKey, "g3:08000400", "em sign script key")
  eq(ev.objects[1].berryTreeId, 3, "em berry tree id from trainerRange_berryTreeId")
  local conns = MapTree.parseConnections(rom, 0x08000000 + CN)
  eq(#conns, 2, "em two connections")
  eq(conns[1].dir, "dive", "em dive connection kept")
  eq(conns[2].dir, "north", "em north connection")
  eq(conns[2].offset, -10, "signed connection offset")
  local events = ExtractMapEvents.extractIsland1(rom, { map_headers = { EM_TEST = H } })
  eq(events.EM_TEST.mapScripts.onDiveWarp, "g3:" .. string.format("%08x", 0x08000000 + MS6),
    "map script 6 is a direct script")

  GameVersion.set("firered")
  ev = ExtractMapEvents.parseMapEvents(rom, 0x08000000 + EV)
  hi = ev.bgEvents[1]
  eq(hi.hiddenItemId, 0x12, "fr hidden item id low byte")
  eq(hi.quantity, 3, "fr hidden item quantity")
  eq(hi.underfoot, false, "fr hidden item underfoot")
  eq(hi.flag, 0x3E8 + 0x12, "fr hidden flag base 0x3E8")
  check(ev.bgEvents[2].type ~= "secret_base", "fr has no secret base rows")
  eq(ev.objects[1].berryTreeId, nil, "fr has no berry tree ids")
  events = ExtractMapEvents.extractIsland1(rom, { map_headers = { FR_TEST = H } })
  eq(type(events.FR_TEST.mapScripts.onDiveWarp), "string", "fr map script 6 is direct too")
end

GameVersion.set("emerald")
eq(MapCatalog.mapIdFor(0, 0), "EM_PETALBURG_CITY", "em 0:0")
eq(MapCatalog.mapIdFor(3, 0), "EM_DEWFORD_TOWN_HOUSE1", "em 3:0 is not an FR alias")
eq(MapCatalog.resolve("LittlerootTown"), "EM_LITTLEROOT_TOWN", "em pret name resolves")
eq(MapCatalog.resolve("MAP_ROUTE101"), "EM_ROUTE101", "em MAP_ constant resolves")
eq(MapCatalog.pretToEngine("InsideOfTruck"), "EM_INSIDE_OF_TRUCK", "em pretToEngine uses MAP_ names")
eq(MapCatalog.slotKeyFor("EM_PETALBURG_CITY"), "0_0", "em slot key")
check(MapCatalog.isKnown("EM_INSIDE_OF_TRUCK"), "em truck is known")
check(not MapCatalog.isKnown("FR_PALLET_TOWN"), "fr ids unknown under emerald")
eq(MapIds.forConst("MAP_LITTLEROOT_TOWN", "emerald"), "EM_LITTLEROOT_TOWN", "MapIds.forConst em")
eq(MapIds.newGameStart("emerald").map, "EM_INSIDE_OF_TRUCK", "em new game start from profile")
local n = 0
for _, g in pairs(Family.of("emerald"):groups().groups) do n = n + #g.maps end
eq(n, 518, "em catalog covers 518 maps")

GameVersion.set("firered")
eq(MapCatalog.mapIdFor(3, 0), "FR_PALLET_TOWN", "fr 3:0 after switching back")
check(MapCatalog.isKnown("FR_PALLET_TOWN"), "fr ids known under firered")
eq(MapIds.newGameStart("firered").map, "FR_PLAYERS_HOUSE_2F", "fr new game start")
GameVersion.set("emerald")
eq(MapCatalog.mapIdFor(3, 0), "EM_DEWFORD_TOWN_HOUSE1", "em index restored after switch")

GameVersion.set(before)
T.finish("game3_layout_family_test")
