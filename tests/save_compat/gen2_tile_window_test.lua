package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local Ctx = require("src.save_convert.Gen2MapContext")
local Codec = require("src.save_convert.Gen2Save")
local G2 = require("tests.fixtures.save.gen2_build")
local B = require("tests.fixtures.save.bytes")
local K = require("tests.save_compat._codec")
local Events = require("src.world.gen2.Events")

local data = { items = K.gen2Data.items, maps = {}, scripts = {
  door = { { op = "checkevent", event = 803 }, { op = "iffalse", script = "flag" },
    { op = "changeblock", args = { 2, 2, 42 } }, { op = "sjump", script = "flag" } },
  flag = { { op = "checkflag", flag = 11 }, { op = "iftrue", script = "open" }, { op = "endcallback" } },
  open = { { op = "changeblock", args = { 4, 2, 22 } }, { op = "endcallback" } },
} }
local blocks = {}
for i = 1, 16 do blocks[i] = i end
data.maps.TEST_ROOM = { group = 24, map = 7, width = 4, height = 4, blocks = blocks,
  objectEventsAddr = 0x4000, objects = {}, callbacks = { { callback = "MAPCALLBACK_TILES", scriptKey = "door" } } }

local function window(version, save)
  local ctx = assert(Ctx.build(data, version, 24, 7, 4, 4, save))
  return ctx.writes[Ctx.offsetsFor(version).screenSave]
end

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local events = Events.new({ 803 }):serialize()
  local save = { events = events, engineFlags = { [11] = true } }
  local win = window(version, save)
  T.eq(win[8], 42, version .. " event callback closes the door in the saved window")
  T.eq(win[9], 22, version .. " engine flag callback opens the second door")
  T.eq(window(version, {})[8], 6, version .. " untaken branches retain ROM blocks")
  local moved = assert(Ctx.reposition(data, version, 24, 7, 4, 4, save))
  T.eq(moved.writes[Ctx.offsetsFor(version).screenSave][8], 42, version .. " reposition applies callbacks")
  local image = G2.build({ version = version })
  local model = assert(Codec.decode(image, version, data))
  model.rawImport = nil
  model.position.x, model.position.y = 4, 4
  model.events = events
  local initial = assert(Codec.encode(model, version, nil, data))
  model = assert(Codec.decode(initial, version, data))
  local unchanged = assert(Codec.encode(model, version, initial, data))
  T.eq(unchanged, initial, version .. " unchanged callback save remains byte exact")
  local live = Events.new():restore(model.events)
  live:set(803, false)
  model.events = live:serialize()
  local opened = assert(Codec.encode(model, version, initial, data))
  T.eq(opened:byte(Ctx.offsetsFor(version).screenSave + 8), 6,
    version .. " changing the event at the same position refreshes the saved window")
  model = assert(Codec.decode(initial, version, data))
  model.engineFlags[11] = true
  local flagChanged = assert(Codec.encode(model, version, initial, data))
  T.eq(flagChanged:byte(Ctx.offsetsFor(version).screenSave + 9), 22,
    version .. " changing the engine flag at the same position refreshes the saved window")
  model = assert(Codec.decode(initial, version, data))
  model.events[20] = 7
  local bytes = B.fromString(initial)
  B.put(bytes, Ctx.offsetsFor(version).screenSave, 99)
  G2.seal(bytes, version)
  local decorated = B.pack(bytes)
  local changed = assert(Codec.encode(model, version, decorated, data))
  T.eq(changed:byte(Ctx.offsetsFor(version).screenSave + 1), 99,
    version .. " unrelated events preserve transient saved blocks")
end

local room = data.maps.TEST_ROOM
local noScripts = { maps = data.maps }
local bad, why = Ctx.build(noScripts, "gold", 24, 7, 4, 4, {})
T.eq(bad, nil, "missing callback scripts refuse the export")
T.eq(why:find("re-import the ROM", 1, true) ~= nil, true, "missing scripts name the recovery")
data.scripts.door = { { op = "changeblock", args = { 2, 2, 42 } }, { op = "special", id = 7 } }
bad, why = Ctx.build(data, "gold", 24, 7, 4, 4, {})
T.eq(bad, nil, "unsupported commands refuse partially evaluated callbacks")
T.eq(why:find("unsupported command special", 1, true) ~= nil, true, "unsupported commands are named")
data.scripts.door = { { op = "sjump", script = "missing" } }
bad, why = Ctx.build(data, "gold", 24, 7, 4, 4, {})
T.eq(bad, nil, "missing jump destinations refuse callbacks")
data.scripts.door = { { op = "sjump", script = "door" } }
bad, why = Ctx.build(data, "gold", 24, 7, 4, 4, {})
T.eq(bad, nil, "callback loops are bounded")
T.eq(why:find("command limit", 1, true) ~= nil, true, "bounded callback failure is named")
room.callbacks = { { callback = "MAPCALLBACK_TILES", scriptKey = "noop" },
  { callback = "MAPCALLBACK_TILES", scriptKey = "missing" } }
data.scripts.noop = { { op = "endcallback" } }
T.eq(window("gold", {})[8], 6, "only the first callback of a type executes")

T.finish()
