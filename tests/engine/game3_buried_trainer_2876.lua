package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local MovementTypes = require("src.core.game3.movement_types")
local Prepare = require("src.core.game3.object_prepare")

-- pokeruby/include/constants/event_object_movement.h:67
-- pokeemerald/include/constants/event_object_movement.h:67
for _, v in ipairs({ "ruby", "sapphire", "emerald" }) do
  eq(MovementTypes.canon(v, 0x3F), 0x3F, v .. " raw 0x3F is the buried trainer type")
  local name = v == "emerald" and "MOVEMENT_TYPE_BURIED" or "MOVEMENT_TYPE_HIDDEN"
  eq(MovementTypes.canonOf(v, name), 0x3F, v .. " " .. name .. " canon id")
  local eo = Prepare.instance({ localId = 9, x = 29, y = 6, graphicsId = 5, movementType = 0x3F,
    trainerType = 3, sight = 1 }, { version = v, rse = true })
  check(eo.rseKind == "buried" and eo.buried == true and eo.invisible == true,
    v .. " cached buried trainer starts invisible")
end

local FieldEffects = require("src.core.game3.field_effects")
local FxRse = require("src.core.game3.field_effects_rse")
local manifest
local requested
local function row(index, name)
  return { index = index, name = name, fw = 16, fh = 16, frames = 5, rgba = name .. ".rgba",
    anims = { { { "frame", 0, 6 }, { "frame", 1, 6 }, { "frame", 2, 6 }, { "frame", 3, 6 }, { "frame", 4, 6 }, { "end" } } } }
end
FieldEffects.manifest = function() return manifest end
FieldEffects.manifestObject = function(name)
  for _, o in ipairs(manifest.objects) do if o.name == name then return o end end
  return nil
end
FieldEffects.loadSheet = function(name)
  requested = name
  local o = FieldEffects.manifestObject(name)
  if not o then return nil end
  return { fw = o.fw, fh = o.fh, frames = o.frames, image = {}, quads = { [0] = {}, {}, {}, {}, {} } }
end
FieldEffects.invalidate()

-- pokeemerald/src/data/field_effects/field_effect_object_template_pointers.h:72
manifest = { family = "rse", objects = { row(6, "ash"), row(32, "ash_puff"), row(33, "ash_launch") } }
local puff = FxRse.startAshPuff(29, 6)
check(puff and puff.name == "ash_puff" and requested == "ash_puff", "emerald pop out uses ash_puff")
FxRse._list = {}
-- pokeemerald/src/field_effect.c:2127 FldEff_AshLaunch, slot 33
local launch = FxRse.startAshLaunch(4, 12)
check(launch and launch.name == "ash_launch" and requested == "ash_launch", "emerald B1F launch uses ash_launch")
FxRse._list = {}
-- pokeruby/src/data/field_effects/field_effect_object_template_pointers.h:78
-- pokeruby/src/data/field_effects/field_effect_object_template_pointers.h:79
manifest = { family = "rse", objects = { row(6, "ash"), row(32, "pop_out_of_ash"), row(33, "lavaridge_gym_warp") } }
requested = nil
puff = FxRse.startAshPuff(29, 6)
check(puff and puff.name == "pop_out_of_ash" and requested == "pop_out_of_ash",
  "ruby/sapphire pop out uses the cached pop_out_of_ash sheet")
FxRse._list = {}
-- pokeruby/src/field_effect.c:1728 FldEff_LavaridgeGymWarp, slot 33
requested = nil
launch = FxRse.startAshLaunch(4, 12)
check(launch and launch.name == "lavaridge_gym_warp" and requested == "lavaridge_gym_warp",
  "ruby/sapphire B1F launch uses the cached lavaridge_gym_warp sheet")
FxRse._list = {}

GameVersion.set("sapphire")
Versions.select("sapphire")

local TrainerSight = require("src.core.game3.trainer_sight")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local Collision = require("src.core.game3.collision")
local Flags = require("src.core.game3.scripting.flags")
local Space = require("src.core.game3.scripting.space")
local Vm = require("src.core.game3.scripting.vm")
local Task = require("src.core.game3.task")
local Audio = require("src.core.game3.audio")

check(Objects.isRse() == true, "sapphire session is RSE")

local dummyGame = { data = { maps = { TEST_MAP = { width = 40, height = 30 } } } }
local store = Flags.newStore()
Space.store = store
local scripts = {
  lavaridge_axle = { { op = "trainerbattle", type = 0, trainer = 258, introText = "t1", defeatText = "t2" }, { op = "end" } },
  route113_lao = { { op = "trainerbattle", type = 0, trainer = 83, introText = "t1", defeatText = "t2" }, { op = "end" } },
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

-- pokeruby/data/maps/LavaridgeTown_Gym_1F/map.json:61
resetField()
local axle = {
  localId = 4, cellX = 4, cellY = 12, px = 64, py = 192, facing = "down", sight = 1, trainerType = 3,
  movementType = 8, elevation = 0, visible = true, hidden = false, moving = false, frozen = false,
  scriptBusy = false, scriptKey = "lavaridge_axle",
}
Objects._byId[4] = axle
Objects._order = { 4 }
Player.reset(5, 12, "left")
check(TrainerSight.check(dummyGame) == true, "see-all trainer east of him engages")
drain(200)
eq(started.localId, 4, "see-all trainer battle script started")
-- pokeruby/src/trainer_see.c:293 MOVEMENT_ACTION_FACE_PLAYER
eq(axle.facing, "right", "see-all trainer turns to face the player")
-- pokeruby/src/trainer_see.c:311 GetOppositeDirection
eq(Player.facing, "left", "player faces the see-all trainer, not up")
eq(axle.movementType, 0x0A, "see-all trainer keeps facing the player afterwards")

resetField()
Player.reset(4, 11, "down")
axle.facing, axle.scriptBusy, axle.frozen, axle.movementType = "down", false, false, 8
Objects._byId[4] = axle
Objects._order = { 4 }
check(TrainerSight.check(dummyGame) == true, "see-all trainer north of him engages")
drain(200)
eq(axle.facing, "up", "see-all trainer faces up at the player")
eq(Player.facing, "down", "player faces down at the see-all trainer")

-- pokeruby/data/maps/LavaridgeTown_Gym_1F/scripts.inc:40 setobjectmovementtype 2, 63
resetField()
axle.facing, axle.scriptBusy, axle.frozen, axle.invisible = "down", false, false, false
Objects._byId[4] = axle
Objects._order = { 4 }
Objects.setTrainerMovementType(4, 63)
check(axle.buried == true and axle.invisible == true and axle.movementType == 0x3F,
  "gym on-transition setobjectmovementtype 63 buries the trainer on sapphire")
Objects.setTrainerMovementType(4, 8)
check(axle.buried == nil and axle.invisible == false, "face-down movement type digs him back up")

-- pokeruby/data/maps/Route113/map.json:139
resetField()
local lao = Prepare.instance({ localId = 9, x = 29, y = 6, graphicsId = 5, movementType = 0x3F,
  trainerType = 3, sight = 1, scriptKey = "route113_lao" }, { version = "sapphire", rse = true })
Objects._byId[9] = lao
Objects._order = { 9 }
Player.reset(30, 6, "left")
check(#Objects.forDraw() == 0, "buried ninja is not drawn before the approach")
check(TrainerSight.check(dummyGame) == true, "buried ninja engages from the east")
local popFrame
for frame = 1, 400 do
  FieldEffects.step()
  FxRse.step()
  Objects.update(dummyGame)
  Task.update(1 / 60)
  if FxRse.isActive("FLDEFF_ASH_PUFF") then
    if not popFrame then
      popFrame = frame
      check(lao.invisible == true, "ninja is still hidden when the ash puff starts")
      check(FxRse._list[#FxRse._list].name == "pop_out_of_ash", "sapphire reveal spawns pop_out_of_ash")
    end
  elseif popFrame and started.key then
    break
  end
end
check(popFrame ~= nil, "ash puff ran during the reveal")
-- pokeruby/src/trainer_see.c:386 sub_8084654
check(lao.invisible == false and lao.buried == nil, "ninja is visible after popping out")
eq(started.localId, 9, "ninja battle script started after the pop out")
eq(lao.facing, "right", "ninja faces the player")
eq(Player.facing, "left", "player faces the revealed ninja")

T.finish("game3_buried_trainer_2876")
