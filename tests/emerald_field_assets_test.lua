package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_field_assets_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local raw = f:read("*a")
f:close()
if raw:sub(0xAD, 0xB0) ~= "BPEE" then
  print("emerald_field_assets_test: skipped (not an Emerald ROM)")
  os.exit(0)
end

local rom = { size = #raw }
function rom:get(o) return raw:byte(o + 1) end
function rom:u16(o) local a, b = raw:byte(o + 1, o + 2); return a + b * 256 end
function rom:u32(o) local a, b, c, d = raw:byte(o + 1, o + 4); return a + b * 256 + c * 65536 + d * 16777216 end
function rom:readString(o, n) return raw:sub(o + 1, o + n) end
function rom:readBytes(o, n) return { raw:byte(o + 1, o + n) } end
function rom:ptrOffset(p) if p >= 0x08000000 and p < 0x0A000000 then return p - 0x08000000 end end
function rom:clearCache() end

local files = {}
local cache = {}
function cache:write(rel, body) files[rel] = body; return true end
function cache:read(rel) return files[rel] end
function cache:exists(rel) return files[rel] ~= nil end

local ROOT = "gba"
local Versions = require("src.import.gba.versions")
Versions.select("emerald")

local function manifest(rel)
  local body = files[ROOT .. "/" .. rel]
  if not body then return nil end
  return assert(load(body, "=" .. rel, "t", {}))()
end

local function fnv(s)
  local h = 2166136261
  local M = 4294967296
  for i = 1, #s do
    h = bit.bxor(h, s:byte(i)) % M
    h = (bit.lshift(h, 24) % M + h * 403) % M
  end
  return string.format("%08x", h)
end

local mods = {
  "src.import.gba.field_effect_extract", "src.import.gba.door_anim_extract", "src.import.gba.weather_extract",
  "src.import.gba.cave_transition_extract", "src.import.gba.rse.berry_tree_gfx_extract",
  "src.import.gba.rse.rotating_gate_gfx_extract",
}
for _, m in ipairs(mods) do
  local mod = require(m)
  local ok, err = pcall(mod.run, rom, cache, { cacheRoot = ROOT })
  check(ok, m .. " runs: " .. tostring(err))
  if mod.ready then check(mod.ready(cache, ROOT), m .. " ready after run") end
  for _, rel in ipairs(mod.REQUIRED or {}) do
    check(files[ROOT .. "/" .. rel] ~= nil, m .. " wrote " .. rel)
  end
end

local fx = manifest("field_effects/objects.lua")
eq(fx.count, 37, "37 FLDEFFOBJ templates walked")
eq(#fx.extras, 13, "13 named extra templates")
local byName, sheets, colored = {}, 0, 0
for _, list in ipairs({ fx.objects, fx.extras }) do
  for _, e in ipairs(list) do
    byName[e.name] = e
    if e.file then sheets = sheets + 1 end
    if e.rgba then colored = colored + 1 end
  end
end
eq(sheets, 49, "every template with images has an index sheet")
eq(colored, 48, "every sheet but the unused-tag Deoxys fragment has an rgba bake")
eq(fx.objects[1].name, "shadow_small", "FLDEFFOBJ_SHADOW_S first")
eq(fx.objects[37].name, "rayquaza", "FLDEFFOBJ_RAYQUAZA last")
for name, dims in pairs({
  tall_grass = "16x16x5", surf_blob = "32x32x3", long_grass = "16x16x4", sand_footprints = "16x16x2",
  deep_sand_footprints = "16x16x2", bike_tire_tracks = "16x16x4", ash = "16x16x5", bubbles = "16x32x8",
  sparkle = "16x16x6", tree_disguise = "16x32x7", bird = "32x32x1", shadow_extra_large = "64x32x1",
  arrow = "16x16x8", sand_pile = "16x8x3", exclamation_question_mark = "16x16x2", heart_icon = "16x16x1",
}) do
  local e = byName[name]
  eq(e and (e.fw .. "x" .. e.fh .. "x" .. e.frames), dims, name .. " frame layout")
end
eq(byName.tall_grass.palette, "gFieldEffectObjectPalette1", "tall grass uses FLDEFF_PAL_TAG_GENERAL_1")
eq(byName.splash.palette, "gFieldEffectObjectPalette0", "splash uses FLDEFF_PAL_TAG_GENERAL_0")
eq(byName.surf_blob.palette, "gObjectEventPal_Brendan", "surf blob uses the player slot")
eq(byName.record_mix_lights.palette, "sRecordMixLights_Pal", "record mix lights own palette")
eq(byName.reflection_distortion.file, nil, "reflection distortion has no images")
eq(#byName.sparkle.anims[1] > 6, true, "sparkle anim read from ROM")
eq(#files[ROOT .. "/field_effects/field_move_streaks_outdoors.rgba"], 256 * 80 * 4, "outdoor streaks baked")

local doors = manifest("doors/manifest.lua")
eq(doors.family, "rse", "door manifest is rse")
eq(doors.count, 53, "53 door rows before the terminator")
eq(doors.by_mid[0x248].tile, "littleroot", "METATILE_Petalburg_Door_Littleroot")
eq(doors.by_mid[0x2AD].size_type, 2, "multi corridor door is size 2")
eq(doors.doors.battle_tower_multi_corridor.width, 32, "big door frame is 32 wide")
eq(doors.doors.littleroot.height, 96, "three 16x32 frames")
local pair = doors.pairs["gTileset_General|gTileset_Petalburg"]
check(pair and pair.doors[0x248] and pair.doors[0x248].file == "littleroot__petalburg.rgba",
  "Littleroot door keyed by its tileset pair")
eq(#doors.by_mid[0x21].pairs, 30, "general door present in every General pair")
eq(doors.by_mid[0x3B0].pairs[1], nil, "unused frontier door matches no tileset")
eq(#doors.anim.open, 4, "sDoorOpenAnimFrames rows")
eq(doors.by_mid[0x61].sound, "sliding", "Pokemon Center door slides")
eq(doors.by_mid[0x21B].sound, "arena", "Battle Arena door sound")

local w = manifest("weather/manifest.lua")
eq(w.blobs.rain.w .. "x" .. w.blobs.rain.h, "16x192", "rain sheet")
eq(w.blobs.ash.w .. "x" .. w.blobs.ash.h, "64x128", "ash sheet")
eq(w.blobs.sandstorm.w .. "x" .. w.blobs.sandstorm.h, "64x80", "sandstorm sheet")
eq(w.blobs.cloud.palette, "clouds", "clouds palette")
eq(table.concat(w.cycles.route119, ","), "2,3,5,3", "sWeatherCycleRoute119")
eq(table.concat(w.cycles.route123, ","), "2,2,3,2", "sWeatherCycleRoute123")
eq(#w.color_map_types, 32, "sBasePaletteColorMapTypes")
eq(#files[ROOT .. "/weather/drought_colors.bin"], 49152, "drought color maps")
eq(#files[ROOT .. "/weather/fog_horizontal.rgba"], 64 * 64 * 4, "FR-compatible fog sheet")

eq(#files[ROOT .. "/cave_transition/screen.bin"], 240 * 160, "cave transition screen")

local berries = manifest("berry_trees/manifest.lua")
eq(berries.count, 43, "43 berry trees")
eq(berries.trees[1].sheet, "cheri", "berry 1 is Cheri")
eq(berries.trees[43].sheet, "durin", "Enigma reuses the Durin tree")
eq(#berries.trees[1].frames, 9, "dirt, 2 sprout, 6 tree frames")
eq(berries.trees[1].height, 240, "frames stacked")
eq(#berries.trees[1].stages, 5, "five growth stages")
eq(berries.trees[2].stages[3].paletteSlot, 2, "Chesto stage 3 palette slot")

local gates = manifest("rotating_gates/manifest.lua")
eq(gates.count, 8, "8 gate shapes")
eq(gates.sheets[1].w, 32, "L1 is 32x32")
eq(gates.sheets[2].w, 64, "L2 is 64x64")
eq(#gates.puzzles.fortree, 8, "Fortree gates")
eq(gates.puzzles.trick_house[1].x, 14, "Trick House first gate x")

for rel, hash in pairs({
  ["field_effects/tall_grass.idx"] = "92fa72d7",
  ["field_effects/surf_blob.idx"] = "43843211",
  ["doors/littleroot.idx"] = "d73a2b9b",
  ["weather/rain.idx"] = "0f4fba30",
  ["berry_trees/pecha.idx"] = "9c3eca38",
  ["rotating_gates/gate_5.idx"] = "5a20b264",
}) do
  local body = files[ROOT .. "/" .. rel]
  eq(body and fnv(body), hash, rel .. " matches the pixel-verified sheet")
end

Versions.select("firered")
T.finish("emerald_field_assets_test")
