package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Syms = require("src.import.gba.syms")
local S = Syms.of("emerald")

local SPOT = {
  gSpeciesNames = 0x3185C8,
  gSpeciesInfo = 0x3203CC,
  gMoveNames = 0x31977C,
  gItems = 0x5839A0,
  gMapGroups = 0x486578,
  gMapLayouts = 0x481DD4,
  gStdScripts = 0x1DC2A0,
  gFontNormalLatinGlyphs = 0x64C2E4,
  gSpecials = 0x1DBA64,
  gScriptCmdTable = 0x1DB67C,
  gSongTable = 0x6B49F0,
  gCryTable = 0x69DCF4,
}
for name, off in pairs(SPOT) do
  eq(S.off(name), off, "syms " .. name)
end
eq(S.addr("gSpeciesNames"), 0x083185C8, "addr adds the ROM base")
eq(S.size("gSpeciesInfo"), 11536, "ELF size of gSpeciesInfo")
eq(S.sizeKind("gSpeciesInfo"), "elf", "gSpeciesInfo size comes from the ELF")
eq(S.sizeKind("gMapGroups"), "span", "gMapGroups is an asm label measured to the next symbol")
eq(S.count("gMapGroups", 4), 34, "34 map groups")
eq(S.obj("pokemon.o:sDeoxysBaseStats"), "pokemon.o", "statics carry their object file")
check(S.has("frontier_pass.o:sMapCursor_Gfx"), "object-qualified lookup")
check(not S.has("definitelyNotASymbol"), "has() is false for an unknown name")
check(not pcall(S.off, "definitelyNotASymbol"), "unknown name raises")
check(not pcall(S.count, "gSpeciesInfo", 5), "count raises on a non-multiple stride")
eq(S.funcAt(S.funcOff("AgbMain") + 0x08000001), "AgbMain", "funcAt takes a thumb pointer")
check(S.hasFunc("CB2_InitTitleScreen"), "function table resolves")

local collided
do
  local src = require("src.import.gba.syms.emerald")
  collided = src.collide:match("([^\n]+)")
  package.loaded["src.import.gba.syms.emerald"] = nil
end
check(collided ~= nil, "the ELF has colliding statics")
if collided then
  local ok, err = pcall(S.off, collided)
  check(not ok and tostring(err):find("several objects", 1, true) ~= nil,
    "a bare lookup of a colliding static raises")
end

local V = require("src.import.gba.games.emerald")
eq(V.SPECIES_NAMES, 0x3185C8, "SPECIES_NAMES")
eq(V.SPECIES_INFO, 0x3203CC, "SPECIES_INFO")
eq(V.MOVE_NAMES, 0x31977C, "MOVE_NAMES")
eq(V.ITEMS, 0x5839A0, "ITEMS")
eq(V.G_MAP_GROUPS, 0x486578, "G_MAP_GROUPS")
eq(V.G_MAP_LAYOUTS, 0x481DD4, "G_MAP_LAYOUTS")
eq(V.STD_SCRIPTS, 0x1DC2A0, "STD_SCRIPTS")
eq(V.FONT_LATIN_NORMAL, 0x64C2E4, "FONT_LATIN_NORMAL")
eq(V.NUM_SPECIES, 412, "pokeemerald/include/constants/species.h:420")
eq(V.MOVES_COUNT, 355, "pokeemerald/include/constants/moves.h:360")
eq(V.ABILITIES_COUNT, 78, "pokeemerald/include/constants/abilities.h:83")
eq(V.ITEMS_COUNT, 377, "gItems entries")
eq(V.NUM_OBJ_EVENT_GFX, 239, "pokeemerald/include/constants/event_objects.h:256")
eq(V.NUM_MAP_GROUPS, 34, "34 map groups")
eq(V.STD_SCRIPTS_COUNT, 11, "11 std scripts")
eq(V.SPECIALS_COUNT, 527, "527 specials")
eq(V.MULTICHOICE_COUNT, 114, "114 multichoice lists")
eq(V.NUM_HEAL_LOCATIONS, 22, "22 heal locations")
eq(V.TRAINERS_COUNT, 855, "855 trainers")
eq(V.BATTLE_STRINGS_COUNT, 369, "369 battle strings")
eq(V.POKEDEX_ENTRY_SIZE, 32, "Emerald dex entries are 32 bytes")
eq(V.NATIONAL_DEX_COUNT, 386, "386 national dex entries")
eq(V.AUDIO.cry_count, 388, "388 cries")
for _, key in ipairs({ "DEX_CATEGORIES", "GHOST_FRONT_PIC", "TRAINER_TOWER_HEADER", "TEACHY_TV_GFX",
    "FAME_BG_GFX", "MAP_PREVIEW_SCREEN_DATA", "TM_CASE_BG_GFX", "BERRY_POUCH_BG_GFX", "INTRO",
    "FRLG_MAP_TO_FR", "MAP_HEADERS", "TILESETS" }) do
  eq(V[key], nil, "FRLG-only key " .. key .. " is absent")
end
check(type(V.CACHE_VERSION) == "number" and V.CACHE_VERSION >= 1, "Emerald has its own cache stamp")
check(V.lookup("f3ae088181bf583e55daf962a92bb46f4f1d07b7") ~= nil, "lookup knows the Emerald sha1")
check(V.lookup("41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc") == nil, "lookup rejects FireRed")
check(not pcall(V.select, "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc"), "select rejects FireRed")

local Versions = require("src.import.gba.versions")
local Frlg = require("src.import.gba.versions_frlg")
local prev = Versions.active()
check(Versions.forGame("emerald") == V, "forGame hands out the Emerald module")
eq(Versions.active(), prev, "forGame leaves the active game alone")
eq(Versions["for"]("emerald").CACHE_VERSION, V.CACHE_VERSION, "Versions['for'] is forGame")
eq(Versions.select("f3ae088181bf583e55daf962a92bb46f4f1d07b7"), "emerald", "select by Emerald sha1")
eq(Versions.SPECIES_NAMES, 0x3185C8, "the facade forwards to Emerald")
eq(Frlg.SPECIES_NAMES, 0x245EE0, "FireRed keeps its offsets")
eq(Versions.select("leafgreen"), "leafgreen", "select leafgreen")
check(Versions.SPECIES_NAMES ~= 0x3185C8, "the facade leaves Emerald")
eq(Versions.select("firered"), "firered", "select firered")
eq(Versions.SPECIES_NAMES, 0x245EE0, "FireRed offsets restored")

T.finish("game3_emerald_offsets_test")
