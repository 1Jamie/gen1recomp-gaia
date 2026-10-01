package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local Ctx = require("src.save_convert.Gen2MapContext")
local Codec = require("src.save_convert.Gen2Save")
local G2 = require("tests.fixtures.save.gen2_build")
local B = require("tests.fixtures.save.bytes")
local World = require("src.world.gen2.World")
local Game2 = require("src.core.Game2")

local def = { group = 24, map = 7, width = 4, height = 4, objectEventsAddr = 0x4000,
  blocks = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }, objects = {
    { index = 1, spriteId = 1, eventFlag = 803, hours = { -1, -1 } },
    { index = 2, spriteId = 1, eventFlag = 0xFFFF, hours = { -1, 1 } },
    { index = 3, spriteId = 1, eventFlag = 0xFFFF, hours = { 22, 3 } },
    { index = 4, spriteId = 1, eventFlag = 0xFFFF, hours = { 8, 17 } },
  } }
local data = { maps = { TEST_MAP = def }, items = G2.ITEMS }

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local O = Ctx.offsetsFor(version)
  local state = { events = { [100] = 8 }, rtc = { saved = { hour = 12 } } }
  local masks = assert(Ctx.objectMaskBytes("TEST_MAP", def, version, state))
  T.eq(masks[1], 0, version .. " player stays visible")
  T.eq(masks[O.firstObjectSlot + 1], 255, version .. " set event masks an NPC")
  T.eq(masks[O.firstObjectSlot + 2], 255, version .. " morning NPC is masked at noon")
  T.eq(masks[O.firstObjectSlot + 3], 255, version .. " overnight NPC is masked at noon")
  T.eq(masks[O.firstObjectSlot + 4], 0, version .. " day shift NPC is visible at noon")
  T.eq(masks[16], 255, version .. " empty slots stay masked")
  state.mapObjectMasks = { map = "TEST_MAP", masks = { true, false, false, true } }
  masks = assert(Ctx.objectMaskBytes("TEST_MAP", def, version, state))
  T.eq(masks[O.firstObjectSlot + 2], 0, version .. " explicit visibility overrides the clock")
  T.eq(masks[O.firstObjectSlot + 4], 255, version .. " scripted hiding overrides the clock")
  local image = G2.build({ version = version, patch = function(bytes)
    B.put(bytes, O.objectMasks + O.firstObjectSlot, 0x7F)
    B.put(bytes, O.mapObjects + O.firstObjectSlot * 16, 1)
    B.put(bytes, O.objectStructs + 40, 3)
  end })
  local save = assert(Codec.decode(image, version, data))
  T.eq(save.mapObjectMasks.masks[1], true, version .. " imported raw mask has engine meaning")
  T.eq(assert(Codec.encode(save, version, image, data)), image, version .. " odd masks remain byte exact")
  save.mapObjectMasks.masks[1] = false
  local shown = assert(Codec.encode(save, version, image, data))
  T.eq(shown:byte(O.objectMasks + O.firstObjectSlot + 1), 0, version .. " unmasking overrides the raw carrier")
  save.mapObjectMasks.masks[1] = true
  save.mapObjectMasks.raw = nil
  local hidden = assert(Codec.encode(save, version, shown, data))
  T.eq(hidden:byte(O.objectMasks + O.firstObjectSlot + 1), 255, version .. " hiding sets the saved mask")
  T.eq(hidden:byte(O.objectStructs + 41), 0, version .. " hiding clears the active NPC struct")
  T.eq(hidden:byte(O.mapObjects + O.firstObjectSlot * 16 + 1), 255, version .. " hidden NPC has no active struct")
end

local world = setmetatable({ map = { id = "TEST_MAP", def = def },
  player = { cellX = 3, cellY = 4, facing = "down" }, objectMasks = {}, maskScripted = {} }, World)
for i, obj in ipairs(def.objects) do world.objectMasks[world:objectMaskKey(obj, i)] = false end
local model = { map = "TEST_MAP", masks = { true, false, true, false }, raw = { 0, 127 } }
T.eq(world:restoreObjectMasks(model), true, "engine restores the current map's visibility")
T.eq(world.objectMasks["TEST_MAP:1"], true, "flagless scripted hide survives continue")
T.eq(world.maskScripted["TEST_MAP:1"], true, "hour polling keeps a restored visibility override")
T.eq(world:restoreObjectMasks({ map = "OTHER_MAP", masks = { false } }), false, "other maps do not restore stale masks")
local game = setmetatable({ world = world, save = { mapObjectMasks = model }, options = {} }, Game2)
local saved = game:snapshotSave()
T.eq(saved.mapObjectMasks.masks[1], true, "save snapshot keeps live masking")
T.eq(saved.mapObjectMasks.masks[2], false, "save snapshot keeps explicit visible values")
T.eq(saved.mapObjectMasks.raw, model.raw, "save snapshot retains raw mask carriers for the same map")

T.finish()
