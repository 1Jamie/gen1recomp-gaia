package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local G = require("src.import.gba.rse.sprite_gfx")

local function fakeRom(bytes)
  local rom = {}
  function rom:get(o) return bytes[o] or 0 end
  function rom:u16(o) return self:get(o) + self:get(o + 1) * 256 end
  function rom:u32(o) return self:u16(o) + self:u16(o + 2) * 65536 end
  function rom:readString(o, n)
    local t = {}
    for i = 0, n - 1 do t[i + 1] = string.char(self:get(o + i)) end
    return table.concat(t)
  end
  return rom
end

local function put16(b, o, v) b[o] = v % 256; b[o + 1] = math.floor(v / 256) % 256 end
local function put32(b, o, v) put16(b, o, v % 65536); put16(b, o + 2, math.floor(v / 65536)) end

do
  local b = {}
  put16(b, 0, 0x0000); put16(b, 2, 0x0000)
  put16(b, 8, 0x4000); put16(b, 10, 0x8000); put16(b, 12, 0x2000)
  put16(b, 16, 0x8000); put16(b, 18, 0xC000)
  local rom = fakeRom(b)
  local o = G.readOam(rom, 0)
  eq(o.w .. "x" .. o.h, "8x8", "oam square size 0 is 8x8")
  local o2 = G.readOam(rom, 8)
  eq(o2.w .. "x" .. o2.h, "32x16", "oam wide size 2 is 32x16")
  eq(o2.paletteNum, 2, "oam paletteNum from attr2 high nibble")
  local o3 = G.readOam(rom, 16)
  eq(o3.w .. "x" .. o3.h, "32x64", "oam tall size 3 is 32x64")
end

do
  local b = {}
  put32(b, 0, 3 + 10 * 65536)
  put32(b, 4, 1 + 5 * 65536 + 4194304)
  put32(b, 8, 0xFFFD + 2 * 65536)
  put32(b, 12, 0xFFFE)
  local cmds = G.readAnim(fakeRom(b), 0)
  eq(#cmds, 4, "anim decodes until jump")
  eq(cmds[1][1] .. cmds[1][2] .. "/" .. cmds[1][3], "frame3/10", "frame image and duration")
  eq(cmds[2][4], true, "frame hFlip bit")
  eq(cmds[3][1] .. cmds[3][2], "loop2", "loop count")
  eq(cmds[4][1], "jump", "jump ends the anim")
  eq(G.maxFrame({ cmds }), 3, "max referenced frame")
end

do
  local b = {}
  local script = 0x100
  put32(b, 0, 0x08000000 + script)
  b[script] = 7
  put32(b, script + 1, 0x08000200)
  put32(b, script + 5, 0x08000300)
  b[script + 9] = 1
  put32(b, script + 10, 0x08000210)
  b[script + 14] = 4
  put32(b, 0x200, 0x08000400); put16(b, 0x204, 0x1004)
  put32(b, 0x210, 0x08000420); put16(b, 0x214, 0x1005)
  local byTag = G.fieldEffectScriptPalettes(fakeRom(b), 0, 1)
  eq(byTag[0x1004], 0x400, "loadfadedpal_callnative palette resolved by tag")
  eq(byTag[0x1005], 0x420, "loadfadedpal palette resolved by tag")
end

do
  local b = {}
  for i = 0, 31 do b[0x40 + i] = (i % 2 == 0) and 0x21 or 0x43 end
  local pix = G.decodeTiles(fakeRom(b), 0x40, 8, 8, {}, 0, 8)
  eq(pix[1] .. pix[2] .. pix[3] .. pix[4], "1234", "4bpp low nibble first")
  eq(#G.idxString(pix, 64), 64, "idx string one byte per pixel")
  local r, g, bl = G.rgb8(0x7FFF)
  eq(r + g + bl, 765, "bgr555 white")
end

eq(G.snake("ShadowExtraLarge"), "shadow_extra_large", "snake case")
eq(G.snake("UnusedGrass2"), "unused_grass_2", "snake case digit")

local Versions = require("src.import.gba.versions")
check(Versions.FAMILY ~= "rse", "facade defaults to frlg")
local FieldEffectExtract = require("src.import.gba.field_effect_extract")
local calledFr = false
local saved = FieldEffectExtract.writeExtract
FieldEffectExtract.writeExtract = function() calledFr = true; return {} end
FieldEffectExtract.run({}, {}, {})
FieldEffectExtract.writeExtract = saved
check(calledFr, "FR run keeps the hand-listed writeExtract path")
eq(FieldEffectExtract.ready({ read = function() return "return { format = 1, count = 37 }" end }), false,
  "FR ready never claims the rse manifest")

local V = Versions.forGame("emerald")
eq(V.FIELD_EFFECT_OBJECTS.count, 37, "gFieldEffectObjectTemplatePointers has 37 FLDEFFOBJ entries")
eq(V.FIELD_EFFECT_OBJECTS.script_count, 67, "gFieldEffectScriptPointers span")
eq(#V.FIELD_EFFECT_OBJECTS.extras, 13, "named extra field sprite templates")
eq(V.DOOR_GRAPHICS_COUNT, 54, "sDoorAnimGraphicsTable rows incl terminator")
eq(V.BERRY_TREE_GFX.count, 43, "berry tree pic tables")
eq(V.ROTATING_GATE.sheet_count, 9, "rotating gate sheets incl terminator")
eq(V.ROTATING_GATE.puzzles.fortree.count, 8, "Fortree gates")
eq(V.ROTATING_GATE.puzzles.trick_house.count, 11, "Trick House gates")
eq(V.OBJ_PALETTE_SLOT_COUNT, 10, "sObjectPaletteTags0 slots")
eq(V.OW_SPRITE_PALETTE_COUNT, 36, "sObjectEventSpritePalettes rows")
eq(#V.WEATHER_GFX.blobs, 9, "weather tile blobs")
eq(V.WEATHER_GFX.drought_colors_size, 6 * 0x1000 * 2, "drought color tables")
eq(V.WEATHER_GFX.cycles.route119.count, 4, "Route 119 weather cycle")
eq(V.FIELD_MOVE_STREAKS.outdoors.tiles, 16, "outdoor streak tiles")
eq(V.FIELD_MOVE_STREAKS.indoors.tiles, 4, "indoor streak tiles")
check(type(V.CAVE_TRANSITION.tiles) == "number", "cave transition tiles resolved")

local Plans = require("src.import.gba.plans.registry")
local plan = Plans.of("emerald")
local ids = {}
for _, t in ipairs(plan.tasks) do ids[t.id] = t end
check(ids.field_fx and ids.field_objects, "rse plan carries the field tasks")
local mods = {}
for _, m in ipairs(Plans.modules(plan)) do mods[m] = true end
for _, m in ipairs({
  "src.import.gba.field_effect_extract", "src.import.gba.door_anim_extract", "src.import.gba.weather_extract",
  "src.import.gba.cave_transition_extract", "src.import.gba.rse.berry_tree_gfx_extract",
  "src.import.gba.rse.rotating_gate_gfx_extract",
}) do
  check(mods[m], "plan module " .. m)
  check(type(require(m).run) == "function", m .. " has run")
end
local req = {}
for _, p in ipairs(Plans.required(plan, "data/generated/gba")) do req[p] = true end
for _, p in ipairs({
  "data/generated/gba/field_effects/objects.lua", "data/generated/gba/doors/manifest.lua",
  "data/generated/gba/weather/manifest.lua", "data/generated/gba/cave_transition/screen.bin",
  "data/generated/gba/berry_trees/manifest.lua", "data/generated/gba/rotating_gates/manifest.lua",
}) do
  check(req[p], "emerald required " .. p)
end

local CacheContract = require("src.import.CacheContract")
local fr = {}
for _, p in ipairs(CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.firered) do fr[p] = true end
check(not fr["data/generated/gba/field_effects/objects.lua"], "FR required list untouched")

T.finish("game3_emerald_field_assets_test")
