package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local BattleProfile = require("src.core.game3.battle.profile")
local Kinds = require("src.core.game3.battle.kinds")

local prevVersion = GameVersion.get()
Profile.reset()
BattleProfile.reset()
GameVersion.set("firered")

local fr = BattleProfile.forRow(Profile.of("firered"))
local lg = BattleProfile.forRow(Profile.of("leafgreen"))
local em = BattleProfile.forRow(Profile.of("emerald"))

eq(fr.family, "frlg", "FireRed battle family")
eq(fr.aiVariant, "frlg", "FireRed AI variant")
eq(lg.family, "frlg", "LeafGreen battle family")
eq(fr.kinds.firstBattle, "oak", "FireRed first battle is Oak's")
eq(fr.kinds.tutorial, "oldman", "FireRed tutorial is the old man")
eq(fr.rules.obedienceFocusPunchExempt, true, "FireRed exempts Focus Punch from disobedience")
eq(fr.rules.pickup, "flat", "FireRed pickup is the flat table")
eq(fr.rules.money, "frlg", "FireRed money rule")
eq(fr.rules.whiteout, "frlg", "FireRed whiteout money rule")
eq(fr.rules.lostText, "frlg", "FireRed lost text")
eq(fr.rules.moneyMessageAlways, false, "FireRed prints money only when gained")
eq(fr.rules.legendaryAi, true, "FireRed runs AI for legendaries")
eq(fr.badgeFlags, nil, "FireRed badges stay on the Flags module")
eq(fr.music, nil, "FireRed music stays on the audio roles")
eq(fr.animCacheFallback, "firered/", "FireRed keeps its anim cache prefix fallback")
check(fr.rules.noExp.link and fr.rules.noExp.trainerTower and fr.rules.noExp.eReader, "FireRed no-exp kinds")
eq(fr.rules.noExp.safari, nil, "FireRed gives safari exp rule unchanged")
eq(BattleProfile.aiBit(fr, "CHECK_BAD_MOVE"), 1, "FR AI_SCRIPT_CHECK_BAD_MOVE")
eq(BattleProfile.aiBit(fr, "CHECK_VIABILITY"), 2, "FR AI_SCRIPT_CHECK_VIABILITY bit 1")
eq(BattleProfile.aiBit(fr, "TRY_TO_FAINT"), 4, "FR AI_SCRIPT_TRY_TO_FAINT bit 2")
eq(BattleProfile.aiBit(fr, "SAFARI"), 0x40000000, "FR AI_SCRIPT_SAFARI")
eq(BattleProfile.aiBit(fr, "ROAMING"), 0x20000000, "FR AI_SCRIPT_ROAMING")
eq(BattleProfile.aiFlags(fr, { "CHECK_BAD_MOVE", "TRY_TO_FAINT", "CHECK_VIABILITY" }), 7, "FR legendary flags are 7")

eq(em.family, "rse", "Emerald battle family")
eq(em.aiVariant, "rse", "Emerald AI variant")
eq(em.kinds.firstBattle, "birch", "Emerald first battle is Birch's")
eq(em.kinds.tutorial, "wally", "Emerald tutorial is Wally's")
eq(em.kinds.pokedude, false, "Emerald has no Pokedude")
eq(BattleProfile.aiBit(em, "TRY_TO_FAINT"), 2, "EM AI_SCRIPT_TRY_TO_FAINT bit 1")
eq(BattleProfile.aiBit(em, "CHECK_VIABILITY"), 4, "EM AI_SCRIPT_CHECK_VIABILITY bit 2")
eq(BattleProfile.aiBit(em, "FIRST_BATTLE"), 0x80000000, "EM AI_SCRIPT_FIRST_BATTLE")
eq(BattleProfile.aiBit(em, "DOUBLE_BATTLE"), 0x80, "EM AI_SCRIPT_DOUBLE_BATTLE")
check(not pcall(BattleProfile.aiBit, em, "PREFER_STRONGEST_MOVE"), "EM has no PREFER_STRONGEST_MOVE bit")
eq(em.rules.obedienceFocusPunchExempt, false, "EM drops the Focus Punch exemption")
eq(em.rules.pickup, "level_bands", "EM pickup level bands")
eq(em.rules.whiteout, "half", "EM whiteout halves money")
eq(em.rules.money, "rse", "EM money rule")
eq(em.rules.legendaryAi, false, "EM wild legendaries have no AI")
eq(em.rules.noExp.safari, true, "EM gives no safari exp")
eq(em.rules.noExp.trainerTower, nil, "EM no-exp list replaces FR's")
eq(em.firstBattle.level, 2, "Birch's Zigzagoon is level 2")
eq(em.firstBattle.species, "SPECIES_ZIGZAGOON", "Birch's first battle foe")
eq(em.animCacheFallback, false, "EM never reads FireRed anim files")
eq(#em.badgeFlags, 8, "EM badge flags from the badges block")
eq(em.badgeFlags[1], 0x867, "EM FLAG_BADGE01_GET")
eq(em.badgeFlags[8], 0x86E, "EM FLAG_BADGE08_GET")

local C = BattleProfile.constants(em)
eq(BattleProfile.battleSong(em, { wild = true }), C:song("MUS_VS_WILD"), "EM wild battle song")
eq(BattleProfile.battleSong(em, { link = true }), C:song("MUS_VS_TRAINER"), "EM link battle song")
eq(BattleProfile.battleSong(em, { kind = "kyogreGroudon" }), C:song("MUS_VS_KYOGRE_GROUDON"), "EM Kyogre/Groudon song")
eq(BattleProfile.battleSong(em, { kind = "regi" }), C:song("MUS_VS_REGI"), "EM Regi song")
local function cls(name) return C:id("trainer_classes", name) end
eq(BattleProfile.battleSong(em, { trainerClass = cls("TRAINER_CLASS_LEADER") }), C:song("MUS_VS_GYM_LEADER"), "EM leader song")
eq(BattleProfile.battleSong(em, { trainerClass = cls("TRAINER_CLASS_TEAM_AQUA") }), C:song("MUS_VS_AQUA_MAGMA"), "EM grunt song")
eq(BattleProfile.battleSong(em, { trainerClass = cls("TRAINER_CLASS_MAGMA_LEADER") }), C:song("MUS_VS_AQUA_MAGMA_LEADER"),
  "EM Maxie song")
eq(BattleProfile.battleSong(em, { trainerClass = cls("TRAINER_CLASS_ELITE_FOUR") }), C:song("MUS_VS_ELITE_FOUR"), "EM E4 song")
eq(BattleProfile.battleSong(em, { trainerClass = cls("TRAINER_CLASS_YOUNGSTER") }), C:song("MUS_VS_TRAINER"), "EM default song")
eq(BattleProfile.victorySong(em, { wild = true }), C:song("MUS_VICTORY_WILD"), "EM wild victory")
eq(BattleProfile.victorySong(em, { trainerClass = cls("TRAINER_CLASS_CHAMPION") }), C:song("MUS_VICTORY_LEAGUE"),
  "EM champion victory")
eq(BattleProfile.victorySong(em, { trainerClass = cls("TRAINER_CLASS_AQUA_ADMIN") }), C:song("MUS_VICTORY_AQUA_MAGMA"),
  "EM admin victory")
eq(BattleProfile.victorySong(em, { trainerClass = cls("TRAINER_CLASS_LEADER") }), C:song("MUS_VICTORY_GYM_LEADER"),
  "EM leader victory")
eq(BattleProfile.victorySong(em, { trainerClass = cls("TRAINER_CLASS_HIKER") }), C:song("MUS_VICTORY_TRAINER"),
  "EM trainer victory")

local frSt = { session = { version = "firered" }, wild = true, link = false }
frSt.kinds = Kinds.fromOpts({}, frSt)
eq(Kinds.noExp(frSt), false, "FR wild battle gives exp")
frSt.trainerTower = true
eq(Kinds.noExp(frSt), true, "FR trainer tower gives no exp")
local emSt = { session = { version = "emerald" }, wild = true, safari = true }
emSt.kinds = Kinds.fromOpts({}, emSt)
eq(Kinds.noExp(emSt), true, "EM safari gives no exp")
local birch = { session = { version = "emerald" }, wild = true }
birch.kinds = Kinds.fromOpts({ firstBattleKind = "birch" }, birch)
eq(birch.kinds.firstBattle, "birch", "Birch first battle kind")
eq(Kinds.isBirchFirstBattle(birch), true, "isBirchFirstBattle")
eq(Kinds.noCrit(birch), true, "EM first battle never crits")
check(not pcall(Kinds.fromOpts, { firstBattleKind = "birch" }, { session = { version = "firered" }, wild = true }),
  "FireRed refuses a Birch first battle")
local oak = { session = { version = "firered" }, wild = false, firstBattle = true }
oak.kinds = Kinds.fromOpts({}, oak)
eq(oak.kinds.firstBattle, "oak", "FR first battle kind is oak")
eq(Kinds.noCrit(oak), false, "FR first battle crit rule stays on the Oak path")

local Rules = require("src.core.game3.battle.rules")
local rolled = 0
local function counting_rng() rolled = rolled + 1 return 0 end
eq(Rules.crit.roll({}, { effect = 0 }, false, counting_rng, birch), false, "Birch battle crit roll is false")
eq(rolled, 0, "Birch battle crit roll consumes no RNG (battle_script_commands.c:1281)")
local emWild = { session = { version = "emerald" }, wild = true }
emWild.kinds = Kinds.fromOpts({}, emWild)
eq(Rules.crit.roll({}, { effect = 0 }, false, counting_rng, emWild), true, "EM wild battle crit on a 0 roll")

local Prize = require("src.core.game3.battle.prize")
local data = { pickupItems = {}, rarePickupItems = {}, pickupProbabilities = { 30, 40, 50, 60, 70, 80, 90, 94, 98 } }
for i = 1, 18 do data.pickupItems[i] = { id = 100 + i } end
for i = 1, 11 do data.rarePickupItems[i] = { id = 200 + i } end
eq(Prize.pickupBanded(5, 0, data), 101, "lv5 rand 0 -> sPickupItems[0]")
eq(Prize.pickupBanded(5, 29, data), 101, "lv5 rand 29 -> sPickupItems[0]")
eq(Prize.pickupBanded(5, 30, data), 102, "lv5 rand 30 -> sPickupItems[1]")
eq(Prize.pickupBanded(5, 97, data), 109, "lv5 rand 97 -> sPickupItems[8]")
eq(Prize.pickupBanded(5, 99, data), 201, "lv5 rand 99 -> sRarePickupItems[0]")
eq(Prize.pickupBanded(5, 98, data), 202, "lv5 rand 98 -> sRarePickupItems[1]")
eq(Prize.pickupBanded(11, 0, data), 102, "lv11 shifts one band")
eq(Prize.pickupBanded(10, 0, data), 101, "lv10 is still band 0 ((lv-1)/10)")
eq(Prize.pickupBanded(100, 97, data), 118, "lv100 caps at band 9 -> sPickupItems[17]")
eq(Prize.pickupBanded(100, 98, data), 211, "lv100 rand 98 -> sRarePickupItems[10]")

local Trainers = require("src.core.game3.scripting.trainers")
local savedPack, savedGet = Trainers.pack, Trainers.get
Trainers.pack = function() return { money = { [7] = 12 }, moneyDefault = 5 } end
Trainers.get = function(id)
  if id == 1 then return { class = 7, party = { { level = 9 }, { level = 11 } } } end
  if id == 2 then return { class = 99, party = { { level = 20 } } } end
  return nil
end
eq(Prize.calcRse(1, {}), 4 * 11 * 12, "EM money = 4 * last mon level * class value")
eq(Prize.calcRse(2, {}), 4 * 20 * 5, "EM unknown class uses the table terminator value")
eq(Prize.calcRse(1, { double = true }), 4 * 11 * 2 * 12, "EM double battle pays double")
eq(Prize.calcRse(1, { double = true, twoOpponents = true }), 4 * 11 * 12, "EM two opponents are not doubled")
eq(Prize.rewardRse(1, { double = true, twoOpponents = true, trainerIdB = 2 }), 4 * 11 * 12 + 4 * 20 * 5,
  "EM two-opponent reward sums A and B")
eq(Prize.calcRse(1, { moneyMultiplier = 2 }), 4 * 11 * 12 * 2, "EM Amulet Coin multiplier")
Trainers.pack, Trainers.get = savedPack, savedGet

local BattleBridge = require("src.core.game3.battle_bridge")
local sess = { version = "emerald", money = 3001 }
local lost, kept = BattleBridge.applyWhiteoutMoneyLoss(sess, nil)
eq(kept, 1500, "EM whiteout keeps half (overworld.c:361)")
eq(lost, 1501, "EM whiteout loss")
eq(sess.money, 1500, "EM session money halved")

local Engine = require("src.core.game3.battle.engine")
local function obedience_case(version, rolls)
  local i = 0
  local said = {}
  local ad = {
    rng = function() return function() i = i + 1 return rolls[i] or 0 end end,
    status = function() return nil end,
    abilityOf = function() return "OVERGROW" end,
    uproarActive = function() return false end,
    applyStatus = function() end,
    statusAnim = function() end,
    foeOf = function() return nil end,
  }
  local st = { session = { version = version }, badges = {}, playerTrainerId = 1, playerOtName = "A" }
  local user = { side = "player", species = 1, mon = { level = 50, otId = 2, otName = "B", moves = { 264, 33, 0, 0 },
    pp = { 20, 35, 0, 0 } } }
  local M = { adapter = ad, user = user, st = st, mnum = 264, slot = 1,
    sayId = function(_, id) said[#said + 1] = id end }
  local r1, r2 = Engine.disobedient(M)
  return r1, r2, said
end
local r1, _, said = obedience_case("firered", { 255, 0, 0 })
eq(r1, "stop", "FR Focus Punch skips the random-move roll")
eq(said[1], "STRINGID_PKMNBEGANTONAP", "FR falls through to the nap roll")
local e1, e2, esaid = obedience_case("emerald", { 255, 0, 1 })
eq(e1, "called", "EM Focus Punch can be replaced by a random move (battle_util.c:3909)")
eq(esaid[1], "STRINGID_PKMNIGNOREDORDERS", "EM ignored-orders string")
eq(e2, 2, "EM picks the next usable slot from the roll")

Profile.reset()
BattleProfile.reset()
if prevVersion then GameVersion.set(prevVersion) end
T.finish()
