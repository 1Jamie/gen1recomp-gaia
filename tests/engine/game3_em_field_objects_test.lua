package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local before = GameVersion.get()

local MovementTypes = require("src.core.game3.movement_types")
for raw = 0, 0x4C do
  eq(MovementTypes.canon("emerald", raw), raw, "EM movement type " .. raw .. " keeps the FR meaning")
end
for raw = 0x4D, 0x50 do
  eq(MovementTypes.canon("emerald", raw), 0x100 + raw, "EM walk-slowly-in-place " .. raw .. " is RSE-only")
end
for raw = 0, 0x50 do
  eq(MovementTypes.canon("firered", raw), raw, "FR movement type " .. raw .. " unchanged")
end
eq(MovementTypes.canon("emerald", 0x14F), 0x14F, "canon is idempotent")
eq(MovementTypes.nameOf("emerald", 0x44), "MOVEMENT_TYPE_JOG_IN_PLACE_DOWN", "EM name of the fast in-place type")
eq(MovementTypes.canonOf("emerald", "MOVEMENT_TYPE_RUN_IN_PLACE_LEFT"), 0x4A, "EM run-in-place is FR jog-in-place")

local Objects = require("src.core.game3.objects")
GameVersion.set("firered")
local fr = Objects.hostSpec(0x47, 0, 0)
eq(fr.movement, "STAY", "FR keeps in-place types as STAY")
eq(Objects.canonMovementType(0x4F), 0x4F, "FR raise-hand type is not remapped")
GameVersion.set("emerald")
local em = Objects.hostSpec(0x47, 0, 0)
eq(em.movement, "IN_PLACE", "EM jog-in-place walks in place")
eq(em.face, "right", "EM jog-in-place right faces right")
eq(em.frames, 8, "EM jog-in-place uses the fast in-place step")
eq(Objects.hostSpec(0x40, 0, 0).frames, 16, "EM walk-in-place down is a normal in-place step")
eq(Objects.hostSpec(0x4B, 0, 0).frames, 4, "EM run-in-place is the faster in-place step")
local slow = Objects.hostSpec(0x14F, 0, 0)
eq(slow.movement .. "/" .. slow.face .. "/" .. slow.frames, "IN_PLACE/left/32", "EM walk-slowly-in-place left")
eq(Objects.canonMovementType(0x4F), 0x14F, "EM setobjectmovementtype 0x4F is walk-slowly-in-place")
eq(Objects.hostSpec(2, 1, 1).movement, "WALK", "EM wander around stays a walker")

local OwSprites = require("src.core.game3.ow_sprites")
local avatars = {
  player = {
    { state = "NORMAL", male = 0, female = 89 },
    { state = "MACH_BIKE", male = 1, female = 90 },
    { state = "ACRO_BIKE", male = 63, female = 91 },
    { state = "SURFING", male = 2, female = 92 },
    { state = "UNDERWATER", male = 111, female = 112 },
    { state = "FIELD_MOVE", male = 3, female = 93 },
    { state = "FISHING", male = 137, female = 138 },
    { state = "WATERING", male = 191, female = 192 },
  },
}
eq(OwSprites.avatarGraphicsId("NORMAL", false, avatars), 0, "Brendan normal")
eq(OwSprites.avatarGraphicsId("NORMAL", true, avatars), 89, "May normal")
eq(OwSprites.avatarGraphicsId("SURFING", true, avatars), 92, "May surfing")
eq(OwSprites.avatarGraphicsId("ACRO_BIKE", false, avatars), 63, "Brendan acro bike")
eq(OwSprites.avatarGraphicsId("NO_SUCH_STATE", false, avatars), 0, "unknown state draws the normal avatar")
eq(OwSprites.avatarState({ surfing = true }), "SURFING", "surfing avatar state")
eq(OwSprites.avatarState({ biking = true }), "MACH_BIKE", "bike defaults to the Mach Bike")
eq(OwSprites.avatarState({ fieldMoveAnim = 3, surfing = true }), "FIELD_MOVE", "field move pose wins")
eq(OwSprites.avatarState({ fishing = true }), "FISHING", "fishing avatar state")
eq(OwSprites.avatarState(nil), "NORMAL", "no player is the normal avatar")

local spr = { frameCount = 18 }
local function run(facing, phase, flip)
  local f, h = OwSprites.pose(spr, facing, 1, flip, { running = phase })
  return f .. (h and "h" or "")
end
eq(run("down", 0, true), "12", "EM run south lead frame A")
eq(run("down", 0, false), "13", "EM run south lead frame B")
eq(run("down", 1, true), "9", "EM run south tail frame")
eq(run("up", 0, true), "14", "EM run north lead")
eq(run("right", 0, false), "17h", "EM run east is west flipped")
GameVersion.set("firered")
eq(run("down", 0, true), "9", "FR run south base frame unchanged")
eq(run("down", 1, true), "10", "FR run south frame A unchanged")
eq(run("left", 1, false), "17", "FR run west frame B unchanged")

local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")
local MB = require("src.core.game3.mb")
local savedBehavior, savedDef = Collision.behavior, Collision._mapDef
local beh = MB.id("TALL_GRASS")
Collision.behavior = function() return beh end
Collision._mapDef = { allowRunning = 1 }
check(not Player.runningDisallowed(0, 0), "FR has no running rules here")
GameVersion.set("emerald")
check(not Player.runningDisallowed(0, 0), "EM runs on tall grass")
beh = MB.id("LONG_GRASS")
check(Player.runningDisallowed(0, 0), "EM long grass disallows running")
beh = MB.id("NO_RUNNING")
check(Player.runningDisallowed(0, 0), "EM MB_NO_RUNNING disallows running")
beh = MB.id("FORTREE_BRIDGE")
Player.currentElevation = 4
check(Player.runningDisallowed(0, 0), "EM Fortree bridge at an even elevation disallows running")
Player.currentElevation = 3
check(not Player.runningDisallowed(0, 0), "EM Fortree bridge at an odd elevation allows running")
beh = MB.id("NORMAL")
Collision._mapDef = { allowRunning = 0 }
check(Player.runningDisallowed(0, 0), "EM map header allowRunning=0 disallows running")
Collision.behavior, Collision._mapDef = savedBehavior, savedDef
Player.currentElevation = 0

local FieldEffects = require("src.core.game3.field_effects")
GameVersion.set("firered")
eq(FieldEffects.fldeffName(67), "FLDEFF_MOVE_DEOXYS_ROCK", "FR FLDEFF 67")
eq(FieldEffects.fldeffName(68), "FLDEFF_DESTROY_DEOXYS_ROCK", "FR FLDEFF 68")
GameVersion.set("emerald")
eq(FieldEffects.fldeffName(66), "FLDEFF_MOVE_DEOXYS_ROCK", "EM FLDEFF 66")
eq(FieldEffects.fldeffName(65), "FLDEFF_DESTROY_DEOXYS_ROCK", "EM FLDEFF 65")
eq(FieldEffects.fldeffName(46), "FLDEFF_HEART_ICON", "EM FLDEFF 46")
eq(FieldEffects.fldeffName(25), "FLDEFF_POKECENTER_HEAL", "EM FLDEFF 25")
check(FieldEffects.HANDLERS.FLDEFF_EXCLAMATION_MARK_ICON ~= nil, "EM exclamation icon has a handler")

FieldEffects._anims = {}
local target = { px = 0, py = 0, cellX = 0, cellY = 0 }
local anim = FieldEffects.startEmote(target, "exclamation")
check(anim and anim.rse, "EM emote uses the RSE icon")
eq(anim.sheet, "exclamation_question_mark", "EM exclamation sheet")
eq(anim.frame, 0, "EM exclamation frame")
eq(FieldEffects.startEmote(target, "question").frame, 1, "EM question mark frame")
eq(FieldEffects.startEmote(target, "heart").sheet, "heart_icon", "EM heart icon sheet")
local offs = {}
for _ = 1, 12 do
  FieldEffects.step()
  offs[#offs + 1] = anim.yOffset
end
eq(table.concat(offs, ","), "-5,-9,-12,-14,-15,-15,-14,-12,-9,-5,0,0", "EM icon bounce (SpriteCB_TrainerIcons)")
check(FieldEffects.isFieldEffectActive(0), "EM exclamation icon is an active field effect")
for _ = 1, 60 do FieldEffects.step() end
check(not FieldEffects.isFieldEffectActive(0), "EM exclamation icon ends after 60 frames")
FieldEffects._anims = {}

local function sheet() return { frames = 4, fw = 16, fh = 16, quads = {}, quadsFront = {} } end
local seqLong = { { "frame", 1, 3 }, { "frame", 2, 3 }, { "frame", 0, 4 }, { "frame", 3, 4 }, { "frame", 0, 4 },
  { "frame", 3, 4 }, { "frame", 0, 4 }, { "end" } }
FieldEffects._manifest = {
  aliases = {},
  _byName = {
    long_grass = { name = "long_grass", rgba = "long_grass.rgba", fw = 16, fh = 16, frames = 4, anims = { seqLong } },
    tall_grass = { name = "tall_grass", rgba = "tall_grass.rgba", fw = 16, fh = 16, frames = 5,
      anims = { { { "frame", 1, 10 }, { "frame", 2, 10 }, { "frame", 3, 10 }, { "frame", 4, 10 }, { "frame", 0, 10 }, { "end" } } } },
  },
}
FieldEffects._sheets = { long_grass = sheet(), tall_grass = sheet() }
local grassBeh = MB.id("LONG_GRASS")
Collision.behavior = function() return grassBeh end
FieldEffects.tallGrassAt(3, 4, false)
eq(FieldEffects._fx and FieldEffects._fx.sheet, "long_grass", "EM long grass cell uses the long grass sheet")
local frames = { FieldEffects._fx.frame }
for _ = 1, 26 do
  FieldEffects.step()
  frames[#frames + 1] = FieldEffects._fx and FieldEffects._fx.frame
end
eq(table.concat(frames, ""), "111222000033330000333300000", "EM long grass anim (sAnim_LongGrass durations)")
FieldEffects.clearTallGrass()
grassBeh = MB.id("TALL_GRASS")
FieldEffects.tallGrassAt(3, 4, true)
eq(FieldEffects._fx.sheet .. ":" .. FieldEffects._fx.frame, "tall_grass:0", "EM tall grass spawn seeks to the last frame")
FieldEffects.clearTallGrass()

local fp = { { "frame", 0, 1, false, true }, { "end" } }
FieldEffects._manifest._byName.sand_footprints = { name = "sand_footprints", rgba = "sand_footprints.rgba", fw = 16, fh = 16,
  frames = 2, anims = { fp, fp, { { "frame", 0, 1, false, false } }, { { "frame", 1, 1, false, false } },
  { { "frame", 1, 1, true, false } } } }
FieldEffects._sheets.sand_footprints = sheet()
Collision.behavior = function(x, y) return (x == 3 and y == 4) and MB.id("SAND") or MB.id("NORMAL") end
FieldEffects._anims, FieldEffects._ground = {}, nil
Player.moving, Player.jumping, Player.biking = true, false, false
Player.cellX, Player.cellY, Player.targetX, Player.targetY = 3, 4, 4, 4
Player.prevCellX, Player.prevCellY, Player.facing = 3, 4, "right"
FieldEffects.groundEffects()
local tr = FieldEffects._anims[1]
eq(tr and (tr.kind .. " " .. tr.cx .. "," .. tr.cy), "tracks 3,4", "leaving sand leaves footprints on the previous cell")
eq(tr and (tr.frame .. tostring(tr.hflip)), "1true", "east footprints use frame 1 flipped")
local vis = {}
for _ = 1, 60 do
  FieldEffects.step()
  vis[#vis + 1] = FieldEffects._anims[1] == tr and (tr.visible and "1" or "0") or "-"
end
eq(table.concat(vis), string.rep("1", 41) .. "010101010101010" .. "----", "footprints hold 41 frames, flicker, then end")
Player.moving = false
FieldEffects._anims, FieldEffects._ground = {}, nil
Collision.behavior = savedBehavior
FieldEffects._manifest, FieldEffects._sheets = nil, {}

GameVersion.set("firered")
local frAnim = FieldEffects.startEmote(target, "exclamation")
check(frAnim and not frAnim.rse, "FR emote keeps the emoticon sheet path")
FieldEffects._anims = {}

local SE = require("src.core.game3.se_ids")
local Doors = require("src.core.game3.doors")
eq(Doors.SOUND_NORMAL, SE.SE_DOOR, "FR door sound resolves SE_DOOR")
eq(Doors.SOUND_SLIDING, SE.SE_SLIDING_DOOR, "FR sliding door sound")
GameVersion.set("emerald")
SE.select("emerald")
eq(Doors.SOUND_NORMAL, 8, "EM SE_DOOR by name")
eq(Doors.soundFor("arena"), SE.SE_REPEL, "EM arena door plays SE_REPEL")
eq(Doors.soundFor("sliding"), SE.SE_SLIDING_DOOR, "EM sliding door")

local savedMap = package.loaded["src.core.game3.map"]
local savedOn = Collision.behaviorOn
local layout = { pair = "general__petalburg", midAt = function(_, x, y) return (x == 5 and y == 8) and 584 or 1 end }
package.loaded["src.core.game3.map"] = { current = "EM_TEST", _def = { id = "EM_TEST", midLayout = layout, pair = "general__petalburg" } }
local doorBeh = MB.id("ANIMATED_DOOR")
Collision.behaviorOn = function() return doorBeh end
Doors._manifestLoaded = true
Doors._manifest = {
  family = "rse",
  doors = { littleroot = { file = "littleroot.idx", width = 16, height = 96, frame_width = 16, frame_height = 32, frames = 3 } },
  pairs = {
    ["gTileset_General|gTileset_Petalburg"] = {
      primary = "gTileset_General", secondary = "gTileset_Petalburg",
      doors = { [584] = { index = 4, tile = "littleroot", file = "littleroot__petalburg.rgba", sound = "normal", size_type = 1 } },
    },
  },
}
local entry, info = Doors.getDoorEntryAt("EM_TEST", 5, 8)
eq(entry and entry.tile, "littleroot", "EM door by tileset pair + metatile")
eq(entry and entry.file, "littleroot__petalburg.rgba", "EM door sheet baked with the pair palettes")
eq(entry and entry.size, "1x2", "EM door size")
eq(info and info.frames, 3, "EM door frame count")
eq(Doors.getDoorEntryAt("EM_TEST", 4, 8), nil, "no door on another metatile")
doorBeh = MB.id("PETALBURG_GYM_DOOR")
check(Doors.getDoorEntryAt("EM_TEST", 5, 8) ~= nil, "Petalburg gym door behavior animates")
doorBeh = MB.id("NORMAL")
eq(Doors.getDoorEntryAt("EM_TEST", 5, 8), nil, "a non-door behavior never animates")
local snd = Doors.getSoundForWarp("EM_TEST", 5, 8, nil, true)
eq(snd, SE.SE_SLIDING_DOOR, "no door entry falls back to the sliding door sound")
Collision.behaviorOn = savedOn
package.loaded["src.core.game3.map"] = savedMap
Doors._manifestLoaded, Doors._manifest = false, nil
Doors.release()

SE.select("firered")
GameVersion.set(before)
T.finish()
