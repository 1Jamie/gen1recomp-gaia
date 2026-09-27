package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local MB = require("src.core.game3.mb")
local BattleBg = require("src.core.game3.battle.bg")
local EnvRse = require("src.core.game3.battle.env_rse")
local EnvFrlg = require("src.core.game3.battle.env_frlg")

local prev = GameVersion.get()
Profile.reset()

GameVersion.set("firered")
check(BattleBg.env() == EnvFrlg, "FireRed resolves the frlg environment module")
eq(BattleBg.TERRAIN.LORELEI, 15, "FireRed TERRAIN keeps its scene ids")
eq(BattleBg.resolveOverride(BattleBg.TERRAIN.CAVE, { trainer = true, trainerClass = 84 }), BattleBg.TERRAIN.LEADER,
  "FireRed leader class 84 still draws LEADER")

GameVersion.set("emerald")
check(BattleBg.env() == EnvRse, "Emerald resolves the rse environment module")
local E, S, M = EnvRse.ENVIRONMENT, EnvRse.SCENE, EnvRse.MAP_TYPE
eq(BattleBg.TERRAIN.GRASS, 0, "BATTLE_ENVIRONMENT_GRASS")
eq(BattleBg.TERRAIN.PLAIN, 9, "BATTLE_ENVIRONMENT_PLAIN")
eq(BattleBg.TERRAIN.LORELEI, nil, "Emerald has no Lorelei scene")

local none = { surfing = false }
eq(EnvRse.resolveFromBehavior(MB.TALL_GRASS, nil, M.ROUTE, none), E.GRASS, "tall grass")
eq(EnvRse.resolveFromBehavior(MB.LONG_GRASS, nil, M.ROUTE, none), E.LONG_GRASS, "long grass (RSE-only behavior)")
eq(EnvRse.resolveFromBehavior(MB.DEEP_SAND, nil, M.ROUTE, none), E.SAND, "deep sand")
eq(EnvRse.resolveFromBehavior(MB.NORMAL, nil, M.INDOOR, none), E.BUILDING, "indoor map")
eq(EnvRse.resolveFromBehavior(MB.NORMAL, nil, M.UNDERGROUND, none), E.CAVE, "cave map")
eq(EnvRse.resolveFromBehavior(MB.INDOOR_ENCOUNTER, nil, M.UNDERGROUND, none), E.BUILDING, "indoor encounter underground")
eq(EnvRse.resolveFromBehavior(MB.NORMAL, nil, M.UNDERWATER, none), E.UNDERWATER, "underwater map")
eq(EnvRse.resolveFromBehavior(MB.OCEAN_WATER, nil, M.ROUTE, none), E.WATER, "ocean water on a route")
eq(EnvRse.resolveFromBehavior(MB.INTERIOR_DEEP_WATER, nil, M.ROUTE, none), E.WATER, "interior deep water")
eq(EnvRse.resolveFromBehavior(MB.MOUNTAIN_TOP, nil, M.ROUTE, none), E.MOUNTAIN, "mountain top")
eq(EnvRse.resolveFromBehavior(MB.NORMAL, nil, M.ROUTE, none), E.PLAIN, "plain route")

EnvRse.setTileBits({ [MB.POND_WATER] = 2 + 1 })
eq(EnvRse.resolveFromBehavior(MB.POND_WATER, nil, M.ROUTE, none), E.POND, "surfable pond")
eq(EnvRse.resolveFromBehavior(MB.POND_WATER, nil, M.UNDERGROUND, none), E.POND, "surfable in a cave")
eq(EnvRse.resolveFromBehavior(MB.POND_WATER, nil, M.OCEAN_ROUTE, none), E.WATER, "surfable on an ocean route")
EnvRse.setTileBits(nil)

eq(EnvRse.resolveFromBehavior(MB.BRIDGE_OVER_POND_MED, nil, M.ROUTE, { surfing = true }), E.POND,
  "surfing under a pond bridge")
eq(EnvRse.resolveFromBehavior(MB.BRIDGE_OVER_OCEAN, nil, M.ROUTE, { surfing = true }), E.WATER,
  "surfing under an ocean bridge")
eq(EnvRse.resolveFromBehavior(MB.BRIDGE_OVER_OCEAN, nil, M.ROUTE, { surfing = false }), E.PLAIN,
  "walking an ocean bridge")
eq(EnvRse.resolveFromBehavior(MB.NORMAL, nil, M.ROUTE, { mapId = "EM_ROUTE113" }), E.SAND, "Route 113 ash")
eq(EnvRse.resolveFromBehavior(MB.NORMAL, nil, M.ROUTE, { weather = 8 }), E.SAND, "sandstorm weather")
eq(EnvRse.resolveFromBehavior(nil, "cave", nil), E.CAVE, "no behavior falls to the map kind")

eq(EnvRse.resolveOverride(E.GRASS, {}), E.GRASS, "no override keeps the environment")
eq(EnvRse.resolveOverride(E.GRASS, { link = true }), S.FRONTIER, "link battles draw the frontier building")
eq(EnvRse.resolveOverride(E.GRASS, { kinds = { groudon = true } }), S.GROUDON, "Groudon scene")
eq(EnvRse.resolveOverride(E.WATER, { kyogre = true }), S.KYOGRE, "Kyogre scene")
eq(EnvRse.resolveOverride(E.GRASS, { rayquaza = true }), S.RAYQUAZA, "Rayquaza scene")
eq(EnvRse.resolveOverride(E.CAVE, { trainer = true, trainerClass = 32 }), S.LEADER, "TRAINER_CLASS_LEADER")
eq(EnvRse.resolveOverride(E.CAVE, { trainer = true, trainerClass = 38 }), S.CHAMPION, "TRAINER_CLASS_CHAMPION")
eq(EnvRse.resolveOverride(E.CAVE, { trainer = true, trainerClass = 84 }), E.CAVE, "FR leader id means nothing here")
eq(EnvRse.resolveOverride(E.BUILDING, { mapBattleScene = 4 }), S.SIDNEY, "MAP_BATTLE_SCENE_SIDNEY")
eq(EnvRse.resolveOverride(E.BUILDING, { mapBattleScene = 8 }), S.FRONTIER, "MAP_BATTLE_SCENE_FRONTIER")
eq(EnvRse.resolveOverride(E.BUILDING, { mapBattleScene = 1 }), S.GYM, "MAP_BATTLE_SCENE_GYM")
eq(EnvRse.resolveOverride(E.BUILDING, { mapBattleScene = 2 }), S.MAGMA, "MAP_BATTLE_SCENE_MAGMA")
eq(EnvRse.resolveOverride(E.BUILDING, { trainer = true, trainerClass = 32, mapBattleScene = 1 }), S.LEADER,
  "leader class wins over the gym map scene")

local manifest = {
  environments = { [0] = "grass", [1] = "long_grass", [9] = "plain" },
}
eq(EnvRse.sheetFor(E.GRASS, manifest), "grass", "environment sheet from the manifest")
eq(EnvRse.sheetFor(S.KYOGRE, manifest), "kyogre", "scene sheet key")
eq(EnvRse.sheetFor(S.DRAKE, manifest), "drake", "Drake scene sheet key")
eq(EnvRse.sheetFor(99, manifest), nil, "unknown id has no sheet")
check(EnvRse.isEnvironment(E.PLAIN) and not EnvRse.isEnvironment(S.GYM), "environment vs scene ids")

Profile.reset()
GameVersion.set(prev)
T.finish("game3_battle_env_rse_test")
