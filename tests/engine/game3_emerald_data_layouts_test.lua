package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Layouts = require("src.import.gba.layouts.registry")
local Versions = require("src.import.gba.versions")
local Plans = require("src.import.gba.plans.registry")

local fr = Layouts.of("firered")
eq(fr.id, "frlg", "firered uses the frlg layout")
eq(Layouts.of("leafgreen"), fr, "leafgreen shares the frlg layout")
eq(fr.pokedexEntry.size, 36, "frlg PokedexEntry is 36 bytes")
eq(fr.pokedexEntry.desc2, 20, "frlg keeps the second description pointer")
eq(fr.pokedexEntry.pokemonScale, 26, "frlg pokemonScale at 26")
eq(fr.trainerNameLen, 12, "frlg trainer name 12 bytes")
eq(fr.trainerBackPicCount, 6, "frlg 6 back pics")
eq(fr.tutorLearnsetBytes, 2, "frlg tutor learnsets are u16")
eq(fr.trainerExtras, false, "frlg trainers.lua has no extra sections")
eq(fr.inlineTrainerDialogs, true, "frlg inlines dialogs")
eq(fr.regionalDex, nil, "frlg has no regional order file")

local em = Layouts.of("emerald")
eq(em.id, "emerald", "emerald layout")
eq(em.pokedexEntry.size, 32, "emerald PokedexEntry is 32 bytes")
eq(em.pokedexEntry.desc2, nil, "emerald has one description")
eq(em.pokedexEntry.pokemonScale, 22, "emerald pokemonScale at 22")
eq(em.pokedexEntry.trainerOffset, 28, "emerald trainerOffset at 28")
eq(em.trainerNameLen, 11, "emerald trainer name 11 bytes")
eq(em.tutorLearnsetBytes, 4, "emerald tutor learnsets are u32")
eq(em.regionalDex.name, "hoenn", "emerald regional dex")
eq(em.inlineTrainerDialogs, false, "emerald dialogs go to trainers/dialogs.lua")

local frp = Layouts.pockets(fr)
eq(frp[1], "ITEMS", "fr pocket 1")
eq(frp[2], "KEY_ITEMS", "fr pocket 2")
eq(frp[3], "POKE_BALLS", "fr pocket 3")
eq(frp[4], "TM_CASE", "fr pocket 4")
eq(frp[5], "BERRY_POUCH", "fr pocket 5")
local emp = Layouts.pockets(em)
eq(emp[1], "ITEMS", "em pocket 1")
eq(emp[2], "POKE_BALLS", "em pocket 2")
eq(emp[3], "TM_HM", "em pocket 3")
eq(emp[4], "BERRIES", "em pocket 4")
eq(emp[5], "KEY_ITEMS", "em pocket 5")

local ok = pcall(Layouts.of, "red")
eq(ok, false, "non gen 3 id raises")

local E = Versions.forGame("emerald")
eq(E.ITEMS_COUNT, 377, "377 items")
eq(E.ITEM_EFFECT_FIRST, 13, "item effects start at ITEM_POTION")
eq(E.ITEM_EFFECT_LAST, 175, "163 item effect pointers")
eq(E.TRAINERS_COUNT, 855, "855 trainers")
eq(E.TRAINER_BACK_PIC_COUNT, 8, "8 trainer back pics")
eq(E.TRAINER_MONEY_COUNT, 56, "56 money rows")
eq(E.REMATCH_COUNT, 78, "78 rematch rows")
eq(E.UNION_ROOM_FACILITY_CLASS_COUNT, 16, "16 union room classes")
eq(E.TUTOR_MOVE_COUNT, 30, "30 tutor moves")
eq(E.INGAME_TRADE_COUNT, 4, "4 in-game trades")
eq(E.INGAME_TRADE_MAIL_COUNT, 3, "3 trade mails")
eq(E.BERRY_COUNT, 43, "43 berries")
eq(E.POKEBLOCK_NAME_COUNT, 15, "15 pokeblock names")
eq(E.CONTEST_MOVES_COUNT, 355, "355 contest moves")
eq(E.CONTEST_EFFECTS_COUNT, 48, "48 contest effects")
eq(E.CONTEST_CATEGORY_COUNT, 5, "5 contest categories")
eq(E.FRONTIER.mons.count, 882, "882 frontier mons")
eq(E.FRONTIER.trainers.count, 300, "300 frontier trainers")
eq(E.FRONTIER.heldItems.count, 63, "63 frontier held items")
eq(E.FRONTIER.brainMons.count, 42, "7 brains x 2 symbols x 3 mons")
eq(E.FRONTIER.apprentices.count, 16, "16 apprentices")
eq(#E.FRONTIER.tents, 3, "3 battle tents")
eq(E.FRONTIER.tents[1].mons.count, 70, "Slateport tent 70 mons")
eq(E.FRONTIER.tents[2].trainers.count, 30, "Verdanturf tent 30 trainers")

local S = E.SYMS
for key, name in pairs({
  medicine = "ItemUseOutOfBattle_Medicine", ether = "ItemUseOutOfBattle_PPRecovery",
  repel = "ItemUseOutOfBattle_Repel", reduce_ev = "ItemUseOutOfBattle_ReduceEV",
}) do
  eq(S.funcAt(E.FIELD_USE_FUNCS[key] + 0x08000001), name, "field use " .. key .. " resolves by name")
end

local FRV = Versions.forGame("firered")
eq(FRV.CONTEST_MOVES, nil, "firered has no contest move key")
eq(FRV.FRONTIER, nil, "firered has no frontier key")
eq(FRV.TUTOR_MOVE_COUNT, 15, "firered 15 tutors")

local plan = Plans.of("emerald")
local want = {
  items_extract = true, battle_moves_extract = true, contest_moves_extract = true, tutor_extract = true,
  ingame_trades_extract = true, berries_extract = true, pokedex_entries_extract = true,
  frontier_data_extract = true, trainer_extract = true,
}
local seen = {}
for _, task in ipairs(plan.tasks) do
  for _, step in ipairs(task.steps or {}) do
    if want[step.name] then
      seen[step.name] = true
      local mod = require(Plans.moduleFor(step.name))
      check(type(mod.run) == "function", step.name .. " has run")
      check(type(mod.ready) == "function", step.name .. " has ready")
      check(type(mod.REQUIRED) == "table" and #mod.REQUIRED > 0, step.name .. " exports REQUIRED")
    end
  end
end
for name in pairs(want) do check(seen[name], "rse plan runs " .. name) end
local frPlan = Plans.of("firered")
for _, task in ipairs(frPlan.tasks) do
  for _, step in ipairs(task.steps or {}) do
    check(not want[step.name], "frlg plan does not gain " .. tostring(step.name))
  end
end

local required = Plans.required(plan, "data/generated/gba")
local have = {}
for _, p in ipairs(required) do have[p] = true end
for _, p in ipairs({
  "data/generated/gba/items/pack.lua", "data/generated/gba/trainers.lua",
  "data/generated/gba/pokemon/contest_moves.lua", "data/generated/gba/pokemon/tutor.lua",
  "data/generated/gba/trades/ingame_trades.lua", "data/generated/gba/berries/berries.lua",
  "data/generated/gba/pokemon/pokedex/entries.lua", "data/generated/gba/pokemon/pokedex/regional.lua",
  "data/generated/gba/frontier/mons.lua", "data/generated/gba/frontier/trainers.lua",
}) do
  check(have[p], "emerald contract requires " .. p)
end

T.finish("game3_emerald_data_layouts_test")
