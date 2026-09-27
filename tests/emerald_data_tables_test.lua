package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local f = io.open(ROM_PATH, "rb")
if not f then
  print("emerald_data_tables_test: skipped (no ROM at " .. ROM_PATH .. ")")
  os.exit(0)
end
local data = f:read("*a")
f:close()

local GameVersion = require("src.core.GameVersion")
local prevVersion = GameVersion.get()
GameVersion.set("emerald")
local imports = {
  info = function(_, id) return { id = id, size = #data, md5 = "emerald", file = "memory" } end,
  read = function(_, _, off, len) return data:sub(off + 1, off + len) end,
}
local rom = assert(require("src.import.gba.rom").open(imports, "emerald"))
eq(require("src.import.gba.versions").active(), "emerald", "facade selected emerald")

local store = {}
local cache = {
  write = function(_, rel, bytes) store[rel] = bytes; return true end,
  read = function(_, rel) return store[rel] end,
  exists = function(_, rel) return store[rel] ~= nil end,
}
local ROOT = "data/generated/gba"
local function run(name)
  local mod = require("src.import.gba." .. name)
  local ok, err = pcall(mod.run, rom, cache, { cacheRoot = ROOT })
  check(ok, name .. " runs: " .. tostring(err))
  check(mod.ready(cache, ROOT), name .. " ready after run")
  for _, rel in ipairs(mod.REQUIRED or {}) do
    check(store[ROOT .. "/" .. rel] ~= nil, name .. " wrote " .. rel)
  end
end
local function load(rel)
  local src = store[ROOT .. "/" .. rel]
  if not src then return nil end
  return assert(loadstring(src, "@" .. rel))()
end

for _, name in ipairs({
  "items_extract", "battle_moves_extract", "contest_moves_extract", "tutor_extract",
  "ingame_trades_extract", "berries_extract", "pokedex_entries_extract", "frontier_data_extract",
  "trainer_extract",
}) do run(name) end

local C = require("src.core.game3.constants").of("emerald")

local items = load("items/pack.lua")
eq(items.count, 377, "377 items")
eq(items.items[4].name, "POKé BALL", "item 4 name")
eq(items.items[4].pocket, "POKE_BALLS", "item 4 POKE BALL pocket")
eq(items.items[4].battleUseName, "ItemUseInBattle_PokeBall", "item 4 battle use func")
eq(items.items[375].name, "MAGMA EMBLEM", "item 375 name")
eq(items.items[375].pocket, "KEY_ITEMS", "item 375 key item")
eq(items.items[376].name, "OLD SEA MAP", "item 376 name")
eq(items.items[289].pocket, "TM_HM", "TM01 in TM_HM pocket")
eq(items.items[289].fieldUse, "tm", "TM01 field use")
eq(items.items[13].fieldUse, "heal", "POTION heals")
eq(items.items[83].fieldUse, "repel", "SUPER REPEL repels")
eq(items.items[133].pocket, "BERRIES", "CHERI BERRY in berries pocket")
eq(items.items[C:require("items", "ITEM_POMEG_BERRY")].fieldUseName, "ItemUseOutOfBattle_ReduceEV",
  "POMEG BERRY reduces EVs")

local moves = load("pokemon/battle_moves.lua")
eq(moves.count, 355, "355 battle moves")
eq(moves.moves[267].accuracy, 95, "Nature Power accuracy 95 on Emerald")
eq(moves.moves[289].flags, 0x10, "Snatch flags on Emerald")

local contest = load("pokemon/contest_moves.lua")
eq(contest.count, 355, "355 contest moves")
eq(contest.moves[1].category, 4, "Pound is TOUGH")
eq(contest.moves[1].comboStarterId, 60, "Pound combo starter")
eq(contest.categories[0], "COOL", "category 0 COOL")
eq(contest.effects[0].appeal, 40, "highly appealing effect appeal")

local tutor = load("pokemon/tutor.lua")
local n = 0
for _ in pairs(tutor.moves) do n = n + 1 end
eq(n, 30, "30 tutor moves")
eq(tutor.moves[0], C:require("moves", "MOVE_MEGA_PUNCH"), "first tutor move MEGA PUNCH")
eq(tutor.moves[29], C:require("moves", "MOVE_FURY_CUTTER"), "last tutor move FURY CUTTER")
check((tutor.learnsets[C:require("species", "SPECIES_TREECKO")] or 0) > 0xFFFF,
  "Treecko learnset uses bits above 16")

local trades = load("trades/ingame_trades.lua")
eq(trades.trades[0].nickname, "DOTS", "trade 0 DOTS")
eq(trades.trades[1].nickname, "PLUSES", "trade 1 PLUSES")
eq(trades.trades[2].nickname, "SEASOR", "trade 2 SEASOR")
eq(trades.trades[3].nickname, "MEOWOW", "trade 3 MEOWOW")
eq(trades.trades[4], nil, "only 4 trades")
check(trades.mail[2] ~= nil and trades.mail[3] == nil, "3 trade mails")

local berries = load("berries/berries.lua")
eq(berries.count, 43, "43 berries")
eq(berries.berries[0].name, "CHERI", "berry 0 CHERI")
eq(berries.berries[0].size, 20, "CHERI size")
eq(berries.berries[0].spicy, 10, "CHERI spicy")
eq(berries.pokeblockNames[1], "RED POKéBLOCK", "pokeblock 1 name")

local entries = load("pokemon/pokedex/entries.lua")
local treecko = C:require("species", "SPECIES_TREECKO")
eq(entries[treecko].category, "WOOD GECKO", "Treecko category")
eq(entries[treecko].height, 5, "Treecko height")
eq(entries[treecko].weight, 50, "Treecko weight")
eq(entries[1].pokemonScale, 356, "Bulbasaur pokemonScale")
eq(entries[1].pokemonOffset, 17, "Bulbasaur pokemonOffset")
eq(entries[1].trainerScale, 256, "Bulbasaur trainerScale")
local regional = load("pokemon/pokedex/regional.lua")
eq(regional.count, 202, "202 Hoenn dex")
eq(#regional.numerical, 202, "202 Hoenn order rows")
eq(regional.numerical[1], 252, "Hoenn 1 = national 252")
eq(regional.nationalToRegional[252], 1, "national 252 = Hoenn 1")

local frontierMons = load("frontier/mons.lua")
eq(frontierMons.count, 882, "882 frontier mons")
local frontierTrainers = load("frontier/trainers.lua")
eq(frontierTrainers.count, 300, "300 frontier trainers")
eq(frontierTrainers.trainers[0].name, "BRADY", "frontier trainer 0 BRADY")
eq(#frontierTrainers.trainers[0].speechBefore, 6, "raw easy chat speech")
local banned = load("frontier/banned.lua")
eq(#banned.species, 10, "10 banned species")
local brains = load("frontier/brains.lua")
eq(brains.trainerIds[1], C:require("trainers", "TRAINER_ANABEL"), "tower brain ANABEL")
eq(brains.mons[0][1][1].species, C:require("species", "SPECIES_ALAKAZAM"), "Anabel silver lead Alakazam")
local tents = load("frontier/tents.lua")
local tentMons = 0
for _ in pairs(tents.slateport.mons) do tentMons = tentMons + 1 end
eq(tentMons, 70, "Slateport tent 70 mons")
local apprentices = load("frontier/apprentices.lua")
eq(apprentices.count, 16, "16 apprentices")

local trainers = load("trainers.lua")
eq(trainers.trainerCount, 855, "855 trainers")
eq(trainers.trainers[1].name, "SAWYER", "trainer 1 SAWYER")
eq(trainers.trainers[1].className, "HIKER", "trainer 1 HIKER")
eq(trainers.trainers[1].party[1].species, C:require("species", "SPECIES_GEODUDE"), "Sawyer leads Geodude")
eq(trainers.backPicCount, 8, "8 back pics")
check(store[ROOT .. "/trainers/back_7.rgba"] ~= nil, "back pic 7 (Steven) baked")
eq(#trainers.rematches + 1, 78, "78 rematch rows")
check(trainers.moneyDefault ~= nil, "money table terminator value")
check(next(trainers.trainers[1].dialogs) == nil, "dialogs are not inlined on emerald")

local TrainerExtract = require("src.import.gba.trainer_extract")
local rel = TrainerExtract.writeDialogs(cache, ROOT, {
  S1 = { { op = "trainerbattle", trainer = 1, type = 0, introText = "T_I", defeatText = "T_D" } },
}, { T_I = { { t = "text", s = "HI" } }, T_D = { { t = "text", s = "BYE" } } })
local dialogs = assert(loadstring(store[rel]))()
eq(dialogs[1].scriptKey, "S1", "dialogs.lua scriptKey")
eq(dialogs[1].introTextKey, "T_I", "dialogs.lua intro key")

GameVersion.set(prevVersion)
T.finish("emerald_data_tables_test")
