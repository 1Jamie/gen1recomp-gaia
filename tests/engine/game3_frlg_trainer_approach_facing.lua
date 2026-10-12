package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local TrainerSight = require("src.core.game3.trainer_sight")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local FieldEffects = require("src.core.game3.field_effects")
local FxRse = require("src.core.game3.field_effects_rse")
local Collision = require("src.core.game3.collision")
local Flags = require("src.core.game3.scripting.flags")
local Space = require("src.core.game3.scripting.space")
local Vm = require("src.core.game3.scripting.vm")
local Task = require("src.core.game3.task")
local Audio = require("src.core.game3.audio")

local dummyGame = { data = { maps = { TEST_MAP = { width = 40, height = 30 } } } }
local store = Flags.newStore()
Space.store = store
local scripts = {
  bug_catcher = { { op = "trainerbattle", type = 0, trainer = 102, introText = "t1", defeatText = "t2" }, { op = "end" } },
}
Space.bundle = { scripts = scripts, text = {}, movements = {}, events = { TEST_MAP = { objects = {} } } }
Space.vm = Vm.new({ store = store, scripts = scripts, adapters = { log = function() end } })
Collision.canEnter = function() return true end
Collision.isLedge = function() return false end
Collision.cell = function() return 0 end
Audio.playSe = function() return true end
Audio.playSong = function() return true end

local started = {}
Space.startScript = function(key, localId, facingDir) started = { key = key, localId = localId, dir = facingDir } end

local function drain(frames)
  for _ = 1, frames do
    FieldEffects.step()
    FxRse.step()
    Objects.update(dummyGame)
    Task.update(1 / 60)
    if started.key then return end
  end
end

local function resetField()
  Field.locked = false
  FieldEffects.invalidate()
  Objects.clearMovements()
  Objects.clear()
  FxRse._list = {}
  Task.clear()
  started = {}
end

local function trainer(facing)
  return {
    localId = 3, cellX = 10, cellY = 10, px = 160, py = 160, facing = facing, sight = 2, trainerType = 1,
    movementType = 0x0A, elevation = 0, visible = true, hidden = false, moving = false, frozen = false,
    scriptBusy = false, scriptKey = "bug_catcher",
  }
end

-- pokefirered/src/trainer_see.c:358-359 CancelPlayerForcedMovement only
for _, v in ipairs({ "firered", "leafgreen" }) do
  GameVersion.set(v)
  Versions.select(v)
  check(Objects.isRse() == false, v .. " session is not RSE")

  resetField()
  local eo = trainer("right")
  Objects._byId[3] = eo
  Objects._order = { 3 }
  Player.reset(12, 10, "up")
  check(TrainerSight.check(dummyGame) == true, v .. " trainer two cells east spots the player")
  drain(400)
  eq(started.localId, 3, v .. " battle script started")
  eq(eo.cellX, 11, v .. " trainer walked one step toward the player")
  eq(eo.facing, "right", v .. " trainer faces the player")
  eq(Player.facing, "up", v .. " player keeps facing up after the approach")
  eq(started.dir, 2, v .. " script facing is the player's own facing")

  resetField()
  eo = trainer("right")
  Objects._byId[3] = eo
  Objects._order = { 3 }
  Player.reset(11, 10, "down")
  check(TrainerSight.check(dummyGame) == true, v .. " adjacent trainer spots the player")
  drain(400)
  eq(started.localId, 3, v .. " adjacent battle script started")
  eq(Player.facing, "down", v .. " player keeps facing down when the trainer is adjacent")
end

-- pokeruby/src/trainer_see.c:327, pokeemerald/src/trainer_see.c:526
for _, v in ipairs({ "sapphire", "emerald" }) do
  GameVersion.set(v)
  Versions.select(v)
  check(Objects.isRse() == true, v .. " session is RSE")
  resetField()
  local eo = trainer("right")
  Objects._byId[3] = eo
  Objects._order = { 3 }
  Player.reset(12, 10, "up")
  check(TrainerSight.check(dummyGame) == true, v .. " trainer two cells east spots the player")
  drain(400)
  eq(started.localId, 3, v .. " battle script started")
  eq(eo.facing, "right", v .. " trainer faces the player")
  eq(Player.facing, "left", v .. " player is turned toward the trainer")
end

-- pokefirered/src/event_object_movement.c:4789 GetDirectionToFace
GameVersion.set("firered")
Versions.select("firered")
resetField()
local npc = { localId = 7, cellX = 10, cellY = 10, facing = "down" }
Objects._byId[7] = npc
Objects._order = { 7 }
local cases = {
  { 11, 13, "right" }, { 9, 13, "left" }, { 11, 7, "right" }, { 9, 7, "left" },
  { 10, 13, "down" }, { 10, 7, "up" }, { 11, 10, "right" }, { 9, 10, "left" }, { 10, 10, "down" },
}
for _, c in ipairs(cases) do
  Player.reset(c[1], c[2], "down")
  npc.facing = "down"
  Objects.facePlayer(7)
  eq(npc.facing, c[3], string.format("facePlayer from (10,10) toward (%d,%d) is %s", c[1], c[2], c[3]))
end

T.finish("game3_frlg_trainer_approach_facing")
