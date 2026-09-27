package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")

local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
local function loadRel(rel)
  local src = cache and cache.read and cache:read("data/generated/gba/" .. rel)
  if type(src) ~= "string" then return nil end
  local chunk = load(src, "@" .. rel, "t", {})
  return chunk and chunk() or nil
end

local manifest = loadRel("pokemon/battle/manifest.lua")
if not (manifest and manifest.layout == "rse") then
  print("emerald_battle_rules_test: skipped (no Emerald cache; set POKEPORT_IDENTITY)")
  os.exit(0)
end

local Versions = require("src.import.gba.versions")
Versions.select("emerald")
local C = require("src.core.game3.constants").of("emerald")
local BattleProfile = require("src.core.game3.battle.profile")
local bp = BattleProfile.get({ version = "emerald" })

local Prize = require("src.core.game3.battle.prize")
local data = Prize.rseData()
eq(#data.pickupItems, 18, "sPickupItems has 18 rows (battle_script_commands.c:784)")
eq(#data.rarePickupItems, 11, "sRarePickupItems has 11 rows")
eq(#data.pickupProbabilities, 9, "sPickupProbabilities has 9 rows")
eq(Prize.pickupBanded(1, 0), C.items.byName.ITEM_POTION, "lv1 rand 0 -> Potion")
eq(Prize.pickupBanded(1, 30), C.items.byName.ITEM_ANTIDOTE, "lv1 rand 30 -> Antidote")
eq(Prize.pickupBanded(1, 99), C.items.byName.ITEM_HYPER_POTION, "lv1 rand 99 -> Hyper Potion")
eq(Prize.pickupBanded(1, 98), C.items.byName.ITEM_NUGGET, "lv1 rand 98 -> Nugget")
eq(Prize.pickupBanded(100, 97), C.items.byName.ITEM_MAX_ELIXIR, "lv100 rand 97 -> Max Elixir")

local Trainers = require("src.core.game3.scripting.trainers")
local calvin = C.trainers.byName.TRAINER_CALVIN_1
local row = Trainers.get(calvin)
check(row ~= nil, "Calvin row exists")
local pack = Trainers.pack()
local value = pack.money[row.class] or pack.moneyDefault
local last = row.party[#row.party].level
eq(Prize.calcRse(calvin, {}), 4 * last * value, "Calvin prize money from gTrainerMoneyTable")
print(string.format("[info] Calvin class %d value %d last lv %d -> %d", row.class, value, last, Prize.calcRse(calvin, {})))

local RomText = require("src.core.game3.rom_text")
for _, key in ipairs({ bp.firstBattle.cantRun, "STRINGID_PLAYERWHITEOUT", "STRINGID_PLAYERWHITEOUT2",
    "STRINGID_PLAYERGOTMONEY", "STRINGID_WILDPKMNFLED", "STRINGID_PKMNGAINEDEXP", "gText_BattleWallyName" }) do
  check(RomText.has(key), "Emerald text has " .. key)
end
check(RomText.plain(bp.firstBattle.cantRun):find("Don't leave me") ~= nil, "DONTLEAVEBIRCH reads Birch's line")

local Ai = require("src.core.game3.battle.ai")
local aiPack = Ai.loadPack({ force = true, required = true })
eq(#aiPack.table, 32, "gBattleAI_ScriptsTable has 32 scripts")
local fb = aiPack.scripts[aiPack.table[32]]
check(fb ~= nil and fb[1].op == "if_hp_equal", "AI_FirstBattle is script 31 (battle_ai_scripts.s:3233)")
local AiCmds = require("src.core.game3.battle.ai_cmds")
local seen = {}
for _, body in pairs(aiPack.scripts) do
  for _, op in ipairs(body) do seen[op.op] = true end
end
for name in pairs(seen) do
  check(AiCmds.CMD[name] ~= nil or name == "end" or name == "goto" or name == "call_if_always_hit"
    or name:find("^nop") ~= nil, "AI op " .. name .. " has a handler")
end

local Anim = require("src.core.game3.battle.anim")
Anim._packLoaded, Anim._pack = false, nil
local reads = {}
local realRead = cache.read
cache.read = function(self, rel)
  reads[#reads + 1] = rel
  return realRead(self, rel)
end
local animPack = Anim.tableScript and select(2, pcall(function() return Anim.tableIndex("general", "POKEBLOCK_THROW") end))
cache.read = realRead
eq(animPack, 4, "general anim 4 is POKEBLOCK_THROW on Emerald")
local fromFr = false
for _, rel in ipairs(reads) do
  if rel:find("^firered/") then fromFr = true end
end
check(not fromFr, "Emerald anim pack load never reads firered/ paths")
eq(Anim.tableIndex("general", "BAIT_THROW"), nil, "Emerald has no BAIT_THROW general anim")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
AnimTasks.init()
check(AnimTasks.REGISTRY.IsBallBlockedByTrainer ~= nil, "IsBallBlockedByTrainer is registered")

GameVersion.set("firered")
T.finish()
