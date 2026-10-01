package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Objects = require("src.save_convert.Gen2ObjectContext")
local Context = require("src.save_convert.Gen2MapContext")
local Codec = require("src.save_convert.Gen2Save")
local Layout = require("src.save_convert.Gen2Layout")

local function fixture(version)
  local objects = {
    { spriteId = 7, x = 4, y = 4, movement = 7, radius = { x = 1, y = 2 }, palette = 4, sight = 3 },
    { spriteId = 8, x = 10, y = 4, movement = 8 },
    { spriteId = 7, x = 4, y = 10, movement = 9 },
  }
  local blocks = {}; for i = 1, 100 do blocks[i] = 1 end
  local data = require("tests.fixtures.save.gen2_sprite_metadata")({ pokemon = {}, moves = {}, items = {},
    maps = { TEST = { group = 21, map = 14, width = 10, height = 10, blocks = blocks,
      objectEventsAddr = 0x4100, environment = "GATE", objects = objects } } }, version)
  for _, id in ipairs({ 7, 8 }) do data.constants.spriteContext.rows[id] = { type = 1, length = 12, palette = 5 } end
  return data
end
local function state(x, y)
  return { player = { name = "TESTER" }, position = { map = "TEST", mapGroup = 21, mapNumber = 14, x = x, y = y }, events = {} }
end
local function edit(bytes, at, value)
  return bytes:sub(1, at) .. string.char(value) .. bytes:sub(at + 2)
end
local function seal(bytes, L)
  local sum = 0
  for i = L.sGameData + 1, L.sGameDataEnd do sum = (sum + bytes:byte(i)) % 65536 end
  bytes = edit(bytes, L.sChecksum, sum % 256)
  return edit(bytes, L.sChecksum + 1, math.floor(sum / 256))
end

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local data, save = fixture(version), state(4, 4)
  local def, O = data.maps.TEST, Context.offsetsFor(version)
  local masks = assert(Context.objectMaskBytes("TEST", def, version, save))
  local rows = assert(Objects.rows(data, version, def, save, 4, 4, masks, O.firstObjectSlot))
  T.check(rows[1] and rows[2] and not rows[3], version .. " viewport includes right edge and excludes lower edge")
  local row = rows[1]
  T.eq(row[2], O.firstObjectSlot, version .. " native map-object index")
  T.eq(row[3], 12, version .. " NPC sprite follows player tiles")
  T.eq(row[4], 7, version .. " movement preserved")
  T.eq(row[7], 4, version .. " explicit palette overrides sprite palette")
  T.eq(row[9], 4, version .. " facing comes from movement row")
  T.eq(row[12], 1, version .. " standing action")
  T.eq(row[14], 255, version .. " facing initialized STANDING")
  T.eq(row[17], 8, version .. " map X biased")
  T.eq(row[21], 8, version .. " initial X biased")
  T.eq(row[19], 0, version .. " last X stays clear until reset step")
  T.eq(row[23], 0x32, version .. " native radius increments both nibbles")
  T.eq(row[24], 64, version .. " native sprite X")
  T.eq(row[33], 3, version .. " sight range preserved")
  masks[O.firstObjectSlot + 1] = 255
  local hidden = assert(Objects.rows(data, version, def, save, 4, 4, masks, O.firstObjectSlot))
  T.eq(hidden[1], nil, version .. " masked actor is not instantiated")
  local stale = fixture(version); stale.constants.spriteContext = nil
  local refused, why = Objects.rows(stale, version, def, save, 4, 4,
    assert(Context.objectMaskBytes("TEST", def, version, save)), O.firstObjectSlot)
  T.check(refused == nil and why:find("re-import the ROM", 1, true), version .. " visible actors require sprite metadata")

  local base = assert(Codec.encode(save, version, nil, data))
  local L = version == "crystal" and Layout.crystal or Layout.goldSilver
  local at = O.mapObjects + O.firstObjectSlot * 16
  base = seal(edit(base, at + 3, 9), L)
  local decoded = assert(Codec.decode(base, version, data))
  decoded.position.x = 12
  local moved = assert(Codec.encode(decoded, version, base, data))
  T.eq(moved:byte(at + 4), 9, version .. " same-map move preserves scripted object X")
  T.eq(moved:byte(at + 1), 255, version .. " actor outside new viewport loses active struct")
  T.eq(moved:byte(at + 17), 1, version .. " entering actor gets first free struct")
  T.eq(moved:byte(O.objectStructs + 41), 8, version .. " same-map move instantiates newly visible NPC")
  T.eq(moved:byte(O.objectStructs + 40 + 24), 32, version .. " newly visible NPC has new relative sprite X")
  decoded.position.x = 7
  moved = assert(Codec.encode(decoded, version, base, data))
  T.eq(moved:byte(at + 1), 1, version .. " carried scripted NPC remains visible")
  T.eq(moved:byte(O.objectStructs + 40 + 17), 9, version .. " carried scripted X initializes actor")
  T.eq(moved:byte(O.objectStructs + 40 + 24), 32, version .. " actor sprite X follows moved player")
end

local Json = require("src.link.Json")
local function json(path)
  local f = assert(io.open(path, "rb")); local value = assert(Json.decode(f:read("*a"))); f:close(); return value
end
local spriteFixtures = json("tests/fixtures/save/gen2_sprite_context.json")
for index, version in ipairs({ "gold", "silver", "crystal" }) do
  local data = fixture(version)
  local constants = json("tools/rom_manifest_" .. version .. ".json").constants
  constants.spriteContext = spriteFixtures.builds[index].metadata
  data.constants, data.sprites = constants, {}
  for _, name in ipairs(constants.spriteOrder) do data.sprites[name] = {} end
  data.maps = { PLAYERS_HOUSE_2F = { group = 24, map = 7, width = 4, height = 3,
    blocks = { 4, 1, 3, 2, 5, 6, 5, 5, 5, 5, 7, 5 }, objectEventsAddr = 0x4100, objects = {} } }
  for i, coord in ipairs({ { 4, 2 }, { 4, 4 }, { 5, 4 }, { 0, 1 } }) do
    data.maps.PLAYERS_HOUSE_2F.objects[i] = { spriteId = 239 + i, x = coord[1], y = coord[2],
      movement = i == 4 and 32 or 1, eventFlag = 1856 + i }
  end
  local save = { player = { name = "TESTER" }, position = { map = "PLAYERS_HOUSE_2F", x = 3, y = 3 } }
  local O, L = Context.offsetsFor(version), Codec.layoutFor(version)
  local image = assert(Codec.encode(save, version, nil, data))
  T.eq(save.events, nil, version .. " bedroom export does not mutate the caller's events")
  for i = 1, 4 do
    T.eq(image:byte(O.objectMasks + O.firstObjectSlot + i), 255, version .. " empty bedroom object " .. i .. " hidden")
    T.eq(image:byte(O.mapObjects + (O.firstObjectSlot + i - 1) * 16 + 1), 255,
      version .. " empty decoration has no active actor " .. i)
  end
  T.eq(image:byte(O.objectStructs + 41), 0, version .. " default bedroom has no Chris clones")
  local decoded = assert(Codec.decode(image, version, data))
  T.eq(assert(Codec.encode(decoded, version, image, data)), image, version .. " default bedroom masks round-trip exactly")
  decoded.decorations = { bed = 2, poster = 16, console = 21, leftOrnament = 30, rightOrnament = 51, bigDoll = 26 }
  local furnished = assert(Codec.encode(decoded, version, image, data))
  for i, raw in ipairs({ 0x5C, 0x8E, 0x5E, 0x33 }) do
    T.eq(furnished:byte(L.wVariableSprites + i), raw, version .. " placed decoration variable sprite " .. i)
    T.eq(furnished:byte(O.objectMasks + O.firstObjectSlot + i), 0, version .. " placed decoration visible " .. i)
    T.eq(furnished:byte(O.mapObjects + (O.firstObjectSlot + i - 1) * 16 + 1), i,
      version .. " placed decoration has ordered actor " .. i)
  end
  decoded = assert(Codec.decode(furnished, version, data))
  T.eq(assert(Codec.encode(decoded, version, furnished, data)), furnished, version .. " furnished bedroom round-trip exactly")
  decoded.decorations.console = 22
  local changed = assert(Codec.encode(decoded, version, furnished, data))
  T.eq(changed:byte(L.wVariableSprites + 1), 0x5B, version .. " visible console replacement refreshes sprite")
  decoded = assert(Codec.decode(changed, version, data)); decoded.decorations.leftOrnament = 0
  local hidden = assert(Codec.encode(decoded, version, changed, data))
  T.eq(hidden:byte(O.objectMasks + O.firstObjectSlot + 2), 255, version .. " put-away doll stays hidden on Continue")
  T.eq(hidden:byte(O.mapObjects + (O.firstObjectSlot + 1) * 16 + 1), 255, version .. " put-away doll removes actor")
end

local traces = os.getenv("GEN2_OBJECT_TRACE")
if traces then
  local Json = require("src.link.Json")
  local function read(path)
    local f = assert(io.open(path, "rb")); local text = f:read("*a"); f:close(); return text
  end
  local native = assert(Json.decode(read(traces)))
  local fixture = assert(Json.decode(read("tests/fixtures/save/gen2_sprite_context.json")))
  for index, group in ipairs(native) do
    local version = group.edition
    local constants = assert(Json.decode(read("tools/rom_manifest_" .. version .. ".json"))).constants
    constants.spriteContext = fixture.builds[index].metadata
    local sprites = {}; for _, name in ipairs(constants.spriteOrder) do sprites[name] = {} end
    local data = { constants = constants, sprites = sprites }
    for _, sample in ipairs(group.constructors) do
      local object = { spriteId = 47, x = 2, y = 3, movement = sample.movement,
        radius = { x = sample.radius % 16, y = math.floor(sample.radius / 16) }, palette = sample.palette, sight = 5 }
      local def = { environment = "INDOOR", objects = { object } }
      local masks = {}; for i = 1, 16 do masks[i] = 0 end
      local actual = assert(Objects.rows(data, version, def, {}, 4, 5, masks,
        Context.offsetsFor(version).firstObjectSlot))[1]
      T.same(actual, sample.expected, version .. " exact ROM constructor movement " .. object.movement)
    end
  end
end
T.finish("gen2 object context")
