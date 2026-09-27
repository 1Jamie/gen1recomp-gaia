package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Versions = require("src.import.gba.versions")
local Names = require("src.import.gba.anim_names_emerald")
local S = require("src.import.gba.syms").of("emerald")
local V = Versions.forGame("emerald")
local FR = Versions.forGame("firered")

local function count(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

eq(Names.game, "emerald", "anim name module is for emerald")
eq(Names.moveCount, 355, "355 move anim scripts")
eq(count(Names.templates), 329, "329 sprite templates reached by the scripts")
eq(count(Names.callbacks), 269, "269 sprite callbacks")
eq(count(Names.tasks), 213, "213 visual/sound tasks")
eq(Names.tagNames[0], "BONE", "tag 0")
eq(Names.tagNames[269], "POKEBLOCK", "tag 269 is the pokeblock")
eq(Names.tagNames[288], "BLUE_RING_2", "tag 288")
eq(Names.generalNames[4], "POKEBLOCK_THROW", "general anim 4")
eq(count(Names.generalNames), 23, "23 general anims")
eq(count(Names.specialNames), 7, "7 special anims")
eq(count(Names.statusNames), 9, "9 status anims")

local RENAMED_TASKS = {
  AnimTask_CastformGfxDataChange = "AnimTask_CastformGfxChange",
  AnimTask_GetIceBallCounter = "AnimTask_GetRolloutCounter",
  AnimTask_ShakeBattlePlatforms = "AnimTask_ShakeBattleTerrain",
  AnimTask_LoadPokeblockGfx = "AnimTask_LoadBaitGfx",
  AnimTask_FreePokeblockGfx = "AnimTask_FreeBaitGfx",
  AnimTask_GetBattleEnvironment = "AnimTask_GetBattleTerrain",
  AnimTask_SetAttackerTargetLeftPos = "AnimTask_SafariOrGhost_DecideAnimSides",
}
for em, fr in pairs(RENAMED_TASKS) do
  eq(Names.renamed.tasks[em], fr, "task " .. em .. " canonicalizes to the FR name")
  eq(Names.tasks[em], (fr:gsub("^AnimTask_", "")), "task " .. em .. " short name")
end
eq(Names.renamed.callbacks.AnimShakeMonOrBattlePlatforms, "AnimShakeMonOrBattleTerrain", "callback rename")
eq(Names.callbacks.SpriteCB_PokeBlock_Throw, "SpriteCB_SafariBaitOrRock_Init", "pokeblock throw callback")
eq(Names.renamed.templates.gPokeblockSpriteTemplate, "gSafariBaitSpriteTemplate", "template rename")
eq(table.concat(Names.gameOnly.tasks, ","), "AnimTask_IsBallBlockedByTrainer,AnimTask_ThrowBall_StandingTrainer",
  "emerald-only tasks")
eq(#Names.gameOnly.callbacks, 0, "no emerald-only callbacks")

for key in pairs(Names.callbacks) do
  check(S.hasFunc(key), "callback " .. key .. " resolves through syms")
end
for key in pairs(Names.tasks) do
  check(S.hasFunc(key), "task " .. key .. " resolves through syms")
end
for key in pairs(Names.templates) do
  check(S.has(key), "template " .. key .. " resolves through syms")
end

eq(count(V.ANIM_CALLBACK_NAMES), 269, "callback address map built from syms")
eq(count(V.ANIM_TASK_NAMES), 213, "task address map built from syms")
eq(count(V.ANIM_TEMPLATE_NAMES), 329, "template address map built from syms")
eq(V.ANIM_TASK_NAMES[0x08000000 + S.funcOff("AnimTask_ShakeMon") + 1], "ShakeMon", "thumb address keys")

local A = V.BATTLE_ANIMS
eq(A.moves_table, S.off("gBattleAnims_Moves"), "moves table")
eq(A.move_count, 355, "move count")
eq(A.general_count, 23, "general count")
eq(A.status_count, 9, "status count")
eq(A.special_count, 7, "special count")
eq(A.tag_count, 289, "tag count")
eq(A.bg_count, 27, "anim bg count")
eq(#A.stat_mask_pals, 8, "8 stat change palettes")
eq(count(A.named_bgs), count(FR.BATTLE_ANIMS.named_bgs), "same named anim bgs as FR")

eq(V.BATTLE_AI_SCRIPTS_TABLE, S.off("gBattleAI_ScriptsTable"), "AI script table")
eq(V.BATTLE_AI_SCRIPT_COUNT, 32, "32 AI scripts")
local Ai = require("src.import.gba.battle_ai_extract")
eq(Ai.OPS[0x5E][1], "if_target_is_ally", "AI op 0x5E")
eq(Ai.OPS[0x62][1], "if_holds_item", "AI op 0x62")
eq(Ai.OPS[0x5D][1], "if_target_not_taunted", "FR AI ops unchanged")

local U = V.BATTLE_UI
eq(U.layout, "rse", "rse chrome layout")
eq(U.terrain_count, 10, "10 battle environments")
eq(#U.scenes, 13, "13 scene backgrounds")
eq(U.healthbox_elements_size, 3776, "healthbox element sheet size")
eq(U.window_template_counts.normal, 25, "normal window templates")
eq(FR.BATTLE_UI.layout, nil, "FR chrome keeps the FR path")
eq(FR.BATTLE_UI.terrain_count, nil, "FR terrain count falls back to 20")

local TR = V.BATTLE_TRANSITION
eq(TR.layout, "rse", "rse transitions")
eq(#TR.assets, 15, "15 emerald transition assets")
eq(TR.mugshot_count, 5, "5 mugshots")
eq(TR.big_pokeball_gfx.size, 1408, "big pokeball tiles")
local rayquaza
for _, a in ipairs(TR.assets) do if a.key == "rayquaza" then rayquaza = a end end
eq(rayquaza and rayquaza.tiles.size, 30016, "rayquaza transition tileset is 938 tiles")
eq(FR.BATTLE_TRANSITION.layout, nil, "FR transitions keep the FR path")

eq(V.BALL_OPEN.fade_colors, S.off("gBallOpenFadeColors"), "ball open fade colors")
eq(V.BATTLE_RSE_DATA.steven_mons.size, 60, "3 Steven mons")

local plan = require("src.import.gba.plans.rse")
local anims, assets
for _, t in ipairs(plan.tasks) do
  if t.id == "battle_anims" then anims = t end
  if t.id == "battle_assets" then assets = t end
end
check(anims ~= nil and assets ~= nil, "rse plan has the battle tasks")
eq(anims and anims.steps[1].name, "battle_anim_extract", "anim task step")
eq(anims and anims.steps[1].opts.strict, true, "anim extraction is strict (fatal) on emerald")

local okC, CacheContract = pcall(require, "src.import.CacheContract")
if okC and CacheContract.planFilesFor then
  local files = {}
  for _, p in ipairs(CacheContract.planFilesFor("emerald")) do files[p] = true end
  for _, p in ipairs({
    "data/generated/gba/pokemon/battle_anims/pack.lua",
    "data/generated/gba/battle_ai/pack.lua",
    "data/generated/gba/pokemon/battle/manifest.lua",
    "data/generated/gba/pokemon/battle_transition/manifest.lua",
    "data/generated/gba/pokemon/battle/ball_open/manifest.lua",
    "data/generated/gba/pokemon/battle/rse_data.lua",
  }) do
    check(files[p], "emerald cache contract requires " .. p)
  end
end

local Anim = require("src.import.gba.battle_anim_extract")
Versions.select("emerald")
local ok, err = pcall(Anim.run, nil, nil, { strict = true, force = true })
check(not ok and tostring(err):find("no ROM", 1, true), "strict anim extraction without a ROM raises")
Versions.select("firered")

T.finish("game3_emerald_battle_assets_test")
