package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local BT = require("src.core.game3.battle_transition")
local IdsFrlg = require("src.core.game3.battle_transition_ids_frlg")
local IdsRse = require("src.core.game3.battle_transition_ids_rse")
local C = require("src.core.game3.constants").of("emerald")

local prev = GameVersion.get()
Profile.reset()

GameVersion.set("firered")
check(BT.ids() == IdsFrlg, "FireRed uses the frlg id table")
eq(BT.ID.SPIRAL, 17, "FireRed id 17 is SPIRAL")
eq(BT.TUNE, nil, "TUNE is not a BattleTransition field")
eq(IdsFrlg.TUNE.introFades, 2, "FireRed intro fades twice")
eq(BT.pickWild({ playerLevel = 10, enemyLevel = 3 }), 8, "FireRed wild normal lower level is SLICE")
eq(BT.pickTrainer({ trainerClass = 87, trainerId = 411 }), 13, "FireRed Bruno mugshot")
check(BT.defs("frlg")[17] ~= nil, "FireRed keeps its SPIRAL port")

GameVersion.set("emerald")
check(BT.ids() == IdsRse, "Emerald uses the rse id table")
local ID = IdsRse.ID
eq(ID.AQUA, 17, "B_TRANSITION_AQUA")
eq(ID.SPIRAL, nil, "Emerald has no SPIRAL")
eq(ID.RAYQUAZA, 24, "B_TRANSITION_RAYQUAZA")
eq(ID.FRONTIER_CIRCLES_SYMMETRIC_SPIRAL_IN_SEQ, 41, "last frontier transition")
eq(IdsRse.TUNE.introFades, 3, "Emerald intro fades three times")
eq(IdsRse.TUNE.blurDelay, 4, "Emerald blur delay")
eq(IdsRse.TUNE.rippleFadeAt, 81, "Emerald ripple fade timer")

local cls = C.trainer_classes.byName
local tr = C.trainers.byName
local nomap = { mapBehavior = 0, mapType = 3 }
local function opts(t) for k, v in pairs(nomap) do if t[k] == nil then t[k] = v end end return t end
eq(IdsRse.pickTrainer(opts({ trainerClass = cls.TRAINER_CLASS_TEAM_AQUA })), ID.AQUA, "Aqua grunt")
eq(IdsRse.pickTrainer(opts({ trainerClass = cls.TRAINER_CLASS_AQUA_LEADER })), ID.AQUA, "Archie")
eq(IdsRse.pickTrainer(opts({ trainerClass = cls.TRAINER_CLASS_MAGMA_ADMIN })), ID.MAGMA, "Magma admin")
eq(IdsRse.pickTrainer(opts({ trainerClass = cls.TRAINER_CLASS_ELITE_FOUR, trainerId = tr.TRAINER_PHOEBE })), ID.PHOEBE,
  "Phoebe mugshot")
eq(IdsRse.pickTrainer(opts({ trainerClass = cls.TRAINER_CLASS_ELITE_FOUR, trainerId = tr.TRAINER_DRAKE })), ID.DRAKE,
  "Drake mugshot")
eq(IdsRse.pickTrainer(opts({ trainerClass = cls.TRAINER_CLASS_CHAMPION })), ID.CHAMPION, "Wallace")
eq(IdsRse.pickTrainer(opts({ trainerId = IdsRse.TRAINER_SECRET_BASE })), ID.CHAMPION, "secret base")
eq(IdsRse.pickTrainer(opts({ trainerClass = 1, playerLevel = 20, enemyLevel = 5 })), ID.POKEBALLS_TRAIL,
  "ordinary trainer, lower level")
eq(IdsRse.pickTrainer(opts({ trainerClass = 1, playerLevel = 5, enemyLevel = 20 })), ID.ANGLED_WIPES,
  "ordinary trainer, higher level")
eq(IdsRse.pickTrainer(opts({ trainerClass = 1, mapType = 4, playerLevel = 5, enemyLevel = 20 })), ID.BIG_POKEBALL,
  "cave trainer")
eq(IdsRse.pickWild(opts({ playerLevel = 5, enemyLevel = 2 })), ID.SLICE, "wild lower level")
eq(IdsRse.pickWild(opts({ playerLevel = 5, enemyLevel = 7 })), ID.WHITE_BARS_FADE, "wild higher level")
eq(IdsRse.pickWild(opts({ mapType = 5, playerLevel = 5, enemyLevel = 7 })), ID.RIPPLE, "underwater")
eq(IdsRse.pickWild(opts({ flashLevel = 2, playerLevel = 5, enemyLevel = 2 })), ID.BLUR, "dark cave")
eq(IdsRse.pickWild(opts({ pyramid = true, playerLevel = 5, enemyLevel = 7 })), ID.GRID_SQUARES, "pyramid")
eq(IdsRse.pickSpecial("e_reader", { playerLevel = 5, enemyLevel = 9 }), ID.BIG_POKEBALL, "e-reader higher level")
eq(IdsRse.MUGSHOT_PLAYER_PIC.female, C.trainer_classes.byName.TRAINER_PIC_MAY, "May mugshot pic")

local defs = BT.defs("rse")
local frDefs = BT.defs("frlg")
check(defs[ID.SLICE] == frDefs[IdsFrlg.ID.SLICE], "SLICE is shared with FireRed")
check(defs[ID.BIG_POKEBALL] ~= frDefs[IdsFrlg.ID.BIG_POKEBALL], "Emerald BIG_POKEBALL is its own pattern weave")
check(defs[ID.WHITE_BARS_FADE] ~= frDefs[IdsFrlg.ID.WHITE_BARS_FADE], "Emerald WHITE_BARS_FADE is its own port")
check(defs[ID.SIDNEY] == frDefs[IdsFrlg.ID.LORELEI], "E4 mugshots share the FireRed task")
for _, name in ipairs({ "AQUA", "MAGMA", "REGICE", "REGISTEEL", "REGIROCK", "KYOGRE", "GROUDON", "RAYQUAZA",
  "FRONTIER_LOGO_WIGGLE", "FRONTIER_LOGO_WAVE" }) do
  check(type(defs[ID[name]]) == "table" and type(defs[ID[name]].funcs) == "table", name .. " is registered")
end
check(defs[17] ~= frDefs[17], "id 17 means AQUA on Emerald, not SPIRAL")

Profile.reset()
GameVersion.set(prev)
T.finish("game3_battle_transition_rse_test")
