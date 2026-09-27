package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Versions = require("src.import.gba.versions")
local Plans = require("src.import.gba.plans.registry")
local MonAnim = require("src.import.gba.mon_anim_extract")
local PicCoords = require("src.import.gba.pic_coords_extract")
local PokemonExtract = require("src.import.gba.pokemon_extract")
local EggExtract = require("src.import.gba.egg_extract")

local function fakeRom(bytes)
  local rom = {}
  function rom:get(off) return bytes[off] or 0 end
  function rom:u16(off) return self:get(off) + self:get(off + 1) * 256 end
  function rom:u32(off) return self:u16(off) + self:u16(off + 2) * 65536 end
  return rom
end

local function putWord(bytes, off, lo, hi)
  bytes[off], bytes[off + 1] = lo % 256, math.floor(lo / 256)
  bytes[off + 2], bytes[off + 3] = hi % 256, math.floor(hi / 256)
end

do
  local b = {}
  putWord(b, 0, 0, 6)
  putWord(b, 4, 1, 15 + 64)
  putWord(b, 8, 0xFFFD, 3)
  putWord(b, 12, 2, 1 + 128)
  putWord(b, 16, 0xFFFE, 1)
  local cmds = MonAnim.decodeCmds(fakeRom(b), 0)
  eq(#cmds, 5, "decode stops at JUMP")
  eq(cmds[1].frame, 0, "frame 0")
  eq(cmds[1].duration, 6, "duration 6")
  eq(cmds[2].hFlip, true, "hFlip bit")
  eq(cmds[3].op, "loop", "loop cmd")
  eq(cmds[3].count, 3, "loop count")
  eq(cmds[4].vFlip, true, "vFlip bit")
  eq(cmds[5].op, "jump", "jump cmd")
  eq(cmds[5].target, 1, "jump target")
  local e = {}
  putWord(e, 0, 0xFFFF, 0)
  eq(MonAnim.decodeCmds(fakeRom(e), 0)[1].op, "end", "END cmd")
  check(not pcall(MonAnim.decodeCmds, fakeRom({}), 0, 4), "a list with no END/JUMP raises")
end

do
  local b = { [100] = 0x45, [101] = 14, [104] = 0x88, [105] = 3, [200] = 0x56, [201] = 9, [300] = 0, [301] = 7 }
  local pack = PicCoords.extract(fakeRom(b), {
    front = 100, back = 200, elevation = 300, count = 2, stride = 4, elevationCount = 2,
  })
  eq(pack.front[0].width, 32, "size high nibble is width / 8")
  eq(pack.front[0].height, 40, "size low nibble is height / 8")
  eq(pack.front[0].y, 14, "y_offset byte")
  eq(pack.front[1].y, 3, "stride 4 rows")
  eq(pack.back[0].size, 0x56, "back size")
  eq(pack.elevation[1], 7, "elevation byte")
  local back = assert(load(PicCoords.toLua(pack)))()
  eq(back.front[1].size, 0x88, "pic coords pack round-trips")
  eq(back.elevation[0], 0, "zero elevation rows are kept")
end

local plan = require("src.import.gba.plans.rse.pokemon_gfx")
local ids = {}
for _, task in ipairs(plan.tasks) do
  check(not ids[task.id], "task id unique: " .. task.id)
  ids[task.id] = true
  eq(task.run, "steps", task.id .. " runs steps")
  for _, step in ipairs(task.steps) do
    local mod = require(Plans.moduleFor(step.name))
    eq(type(mod.run), "function", step.name .. ".run")
  end
end
for _, id in ipairs(plan.sequential) do check(ids[id], "sequential names a task: " .. id) end

local rse = require("src.import.gba.plans.rse")
local required = {}
for _, rel in ipairs(Plans.required(rse, "data/generated/gba")) do required[rel] = true end
for _, rel in ipairs({ "pokemon/pic_coords.lua", "pokemon/front_anims.lua", "pokemon/back_anims.lua",
    "pokemon/front_anim/1.rgba", "pokemon/hoenn.lua", "pokemon/regional_dex.lua", "pokemon/egg/hatch.rgba" }) do
  check(required["data/generated/gba/" .. rel], "emerald contract requires " .. rel)
end

local EM = require("src.import.gba.games.emerald")
for _, key in ipairs({ "MON_FRONT_PIC_ANIM", "MON_PIC_DUPLICATE_DEOXYS", "MON_FOOTPRINT_TABLE", "TYPE_NAMES",
    "EXPERIENCE_TABLES", "MON_FRONT_ANIMS_PTR_TABLE", "MON_FRONT_ANIMS_OBJ", "MON_ANIM_FUNCTIONS",
    "EGG_PALETTE", "EGG_HATCH_GFX", "EGG_SHARD_GFX", "SPECIES_UNOWN_B", "SPECIES_UNOWN_QMARK" }) do
  check(EM[key] ~= nil, "emerald key " .. key)
end
eq(EM.MON_PIC_COORDS_COUNT, 440, "gMonFrontPicCoords rows")
eq(EM.MON_FRONT_ANIM_IDS_COUNT, 411, "sMonFrontAnimIdsTable rows")
eq(EM.MON_ANIM_FUNCTIONS_COUNT, 151, "sMonAnimFunctions rows")
eq(EM.GROWTH_RATE_COUNT * EM.EXPERIENCE_LEVELS * 4, EM.SYMS.size("gExperienceTables"), "exp table size")
eq(EM.SPECIES_UNOWN_QMARK, 439, "Unown ? species id")

local FR = Versions.forGame("firered")
check(FR.MON_FRONT_PIC_ANIM == nil, "FR has no animated front pic key")
check(FR.MON_PIC_DUPLICATE_DEOXYS == nil, "FR keeps its one-frame Deoxys output")
check(FR.TYPE_NAMES == nil and FR.SPECIES_TO_HOENN == nil, "FR writes no Hoenn/type packs")

eq(EggExtract.SPECIES_EGG, 412, "SPECIES_EGG on FireRed")
Versions.select("emerald")
eq(EggExtract.SPECIES_EGG, 412, "SPECIES_EGG on Emerald")
check(not pcall(PokemonExtract.runPart, fakeRom({}), {}, { part = "bogus" }), "unknown part raises")
Versions.select("firered")
eq(Versions.active(), "firered", "facade back on FireRed")

for _, path in ipairs({ "src/import/gba/pokemon_extract.lua", "src/import/gba/egg_extract.lua",
    "src/import/gba/pic_coords_extract.lua", "src/import/gba/mon_anim_extract.lua",
    "src/import/gba/games/emerald/pokemon_gfx.lua" }) do
  local h = assert(io.open(path, "r"))
  local src = h:read("*a")
  h:close()
  local lit
  for n in src:gmatch("0x(%x+)") do
    if tonumber(n, 16) >= 0x100000 then lit = n break end
  end
  lit = lit or src:match("or 0x%x%x%x%x+")
  check(lit == nil, path .. " has no ROM offset literal (" .. tostring(lit) .. ")")
end

T.finish("game3_emerald_pokemon_gfx_test")
