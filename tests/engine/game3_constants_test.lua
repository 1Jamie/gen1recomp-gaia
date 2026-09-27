package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Constants = require("src.core.game3.constants")
local FlagsTable = require("src.core.game3.scripting.flags_table")
local Flags = require("src.core.game3.scripting.flags")
local SE = require("src.core.game3.se_ids")
local Song = require("src.core.game3.song_ids")

local em = Constants.of("emerald")
local fr = Constants.of("firered")

check(Constants.of("leafgreen") == fr, "leafgreen shares the firered tables")
check(not pcall(Constants.of, "red"), "a non-gba id has no constant tables")
check(not pcall(Constants.of, "ruby"), "an unported game errors instead of falling back")
eq(Constants.active({ version = "emerald" }), em, "active reads session.version")

eq(em.flags.byName.FLAG_BADGE01_GET, 0x867, "em FLAG_BADGE01_GET")
eq(em.flags.byName.FLAG_SYS_NATIONAL_DEX, 0x896, "em FLAG_SYS_NATIONAL_DEX")
eq(em.flags.byName.FLAG_HIDDEN_ITEMS_START, 0x1F4, "em FLAG_HIDDEN_ITEMS_START")
eq(em.flags.byName.TRAINER_FLAGS_START, 0x500, "em TRAINER_FLAGS_START")
eq(em.flags.byName.SYSTEM_FLAGS, 0x860, "em SYSTEM_FLAGS")
eq(em.flags.byName.DAILY_FLAGS_START, 0x920, "em DAILY_FLAGS_START")
eq(em.flags.byName.FLAGS_COUNT, 0x960, "em FLAGS_COUNT")
eq(em.vars.byName.VAR_ALTERING_CAVE_WILD_SET, 0x403E, "em VAR_ALTERING_CAVE_WILD_SET")
eq(em:name("flags", 0x867, "FLAG_"), "FLAG_BADGE01_GET", "em flag reverse lookup")

eq(em:song("SE_SELECT"), 5, "em SE_SELECT")
eq(em:song("MUS_TITLE"), 413, "em MUS_TITLE")
eq(em:song("MUS_ROUTE118"), 0x7FFF, "em MUS_ROUTE118")
eq(fr:song("MUS_TITLE"), 278, "fr MUS_TITLE")

eq(em.specials.count, 527, "em specials count")
eq(fr.specials.count, 444, "fr specials count")
eq(em:specialName(0x08), "EnterSecretBase", "em special 0x08")
eq(fr:specialName(0x08), "NullFieldSpecial", "fr special 0x08")
eq(em:special("Script_DoRayquazaScene"), 508, "duplicate special name resolves to the last id")
eq(em.specials.byId[470], "Script_DoRayquazaScene", "first Rayquaza special slot")

eq(em.script_cmds.count, 227, "em script command count")
eq(fr.script_cmds.count, 213, "fr script command count")
eq(em:opcode(0xD3).name, "moverotatingtileobjects", "em 0xD3")
eq(fr:opcode(0xD3).name, "getbraillestringwidth", "fr 0xD3")
eq(em:opcode(0xE2).size, 6, "em bufferitemnameplural size")
eq(em:opcode(0xD7).size, 8, "em warpmossdeepgym size")
eq(em:opcode(0xC7).size, 1, "em textcolor slot is nop1")
check(em:opcode(0x5C).variable == true, "trainerbattle is variable length")
for op = 0xD3, 0xE2 do
  check(em:opcode(op) ~= nil, string.format("em opcode 0x%02X present", op))
end

do
  local n, t = 0, 0
  for k in pairs(em.movement.byName) do
    if k:find("^MOVEMENT_ACTION_") then n = n + 1 end
    if k:find("^MOVEMENT_TYPE_") then t = t + 1 end
  end
  check(n >= 155 and n <= 165, "em MOVEMENT_ACTION count ~160 (" .. n .. ")")
  eq(t, 81, "em MOVEMENT_TYPE count")
  eq(em.movement.byName.MOVEMENT_ACTION_WALK_SLOW_DOWN, 4, "em WALK_SLOW_DOWN")
  eq(fr.movement.byName.MOVEMENT_ACTION_WALK_SLOW_DOWN, 12, "fr WALK_SLOW_DOWN")
  eq(em:name("movement", 4, "MOVEMENT_ACTION_"), "MOVEMENT_ACTION_WALK_SLOW_DOWN", "movement reverse")
end

eq(em.metatile_behaviors.byName.MB_ICE, 0x20, "em MB_ICE")
eq(fr.metatile_behaviors.byName.MB_ICE, 0x23, "fr MB_ICE")
eq(em.items.byName.ITEM_MACH_BIKE, 259, "em ITEM_MACH_BIKE")
eq(em.items.pockets.POCKET_KEY_ITEMS, 5, "em key items pocket")
eq(em.battle.byName.TRAINER_BATTLE_PYRAMID, 9, "em trainerbattle type 9")
eq(em:map("MAP_INSIDE_OF_TRUCK") ~= nil, true, "em map group entry exists")
eq(#em.map_groups.groups, 34, "em map group count")
eq(em.map_groups.byName.MAP_PETALBURG_CITY.group, 0, "em Petalburg group")
eq(em.map_groups.byName.MAP_PETALBURG_CITY.num, 0, "em Petalburg num")

do
  local over, bad = 0, 0
  for k, v in pairs(FlagsTable.FLAGS) do
    local g = fr.flags.byName[k] or fr.vars.byName[k]
    if g ~= nil then
      over = over + 1
      if g ~= v then bad = bad + 1 end
    end
  end
  for k, v in pairs(FlagsTable.VARS) do
    local g = fr.vars.byName[k]
    if g ~= nil then
      over = over + 1
      if g ~= v then bad = bad + 1 end
    end
  end
  check(over > 1500, "fr generated flags overlap flags_table (" .. over .. ")")
  eq(bad, 0, "fr generated flag/var values equal flags_table")
end

do
  local frv = Flags.forVersion("firered")
  eq(frv.IDS, Flags.IDS, "fr forVersion is the live IDS table")
  eq(Flags.forVersion("leafgreen"), frv, "leafgreen resolves to the fr flag table")
  eq(Flags.IDS.FLAG_BADGE01_GET, 0x820, "fr Flags.IDS unchanged")
  local emv = Flags.forVersion("emerald")
  eq(emv.IDS.FLAG_BADGE01_GET, 0x867, "em forVersion flag")
  eq(emv.IDS.BADGE01_GET, 0x867, "em forVersion stripped alias")
  eq(emv.VAR_IDS.ALTERING_CAVE_WILD_SET, 0x403E, "em forVersion var alias")
  eq(emv.BADGES[8].flag, 0x86E, "em badge 8 flag")
  eq(emv.TRAINER_FLAGS_START, 0x500, "em trainer flag base")
  eq(Flags.active({ version = "emerald" }), emv, "Flags.active reads session.version")
end

do
  local frSelect = SE.SE_SELECT
  local frDoor = SE.SE_DOOR
  local before = SE
  eq(SE.forVersion("emerald").SE_SELECT, 5, "em SE_SELECT via forVersion")
  SE.select("emerald")
  check(SE == before, "select keeps table identity")
  eq(SE.SE_SELECT, em:song("SE_SELECT"), "SE selected emerald")
  eq(SE.SE_DOOR, em:song("SE_DOOR"), "SE emerald SE_DOOR")
  SE.select("firered")
  eq(SE.SE_SELECT, frSelect, "SE back to firered")
  eq(SE.SE_DOOR, frDoor, "SE firered SE_DOOR restored")
  local n = 0
  for k, v in pairs(SE) do
    if type(v) == "number" then
      n = n + 1
      if fr:song(k) ~= v then check(false, "fr SE value moved: " .. k) end
    end
  end
  eq(n, 255, "fr SE count after round trip")
end

do
  eq(Song.MUS_TITLE, 278, "song_ids defaults to firered")
  Song.select("emerald")
  eq(Song.MUS_TITLE, 413, "song_ids emerald MUS_TITLE")
  eq(Song.resolve("MUS_ROUTE118"), 0x7FFF, "song_ids resolve")
  eq(Song.nameOf(413), "MUS_TITLE", "song_ids nameOf")
  Song.select("leafgreen")
  eq(Song.MUS_TITLE, 278, "song_ids leafgreen uses firered ids")
  eq(Song.MUS_ROUTE118, nil, "emerald-only names removed on select")
end

T.finish("game3_constants_test")
