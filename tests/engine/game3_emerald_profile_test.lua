package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local Capabilities = require("src.core.game3.capabilities")
local Ctx = require("src.core.game3.scripting.ctx")

local prevVersion = GameVersion.get()
Profile.reset()
GameVersion.set("firered")

local em = Profile.of("emerald")
eq(em.id, "emerald", "the Emerald row loads")
eq(em.label, "Emerald", "Emerald label")
eq(em.family, "rse", "Emerald is the rse family")
eq(em.generation, 3, "Emerald is generation 3")
eq(em.engine, "game3", "Emerald runs on the game3 engine")
check(Profile.of("emerald") == em, "the row is cached")

eq(em.map.prefixes[1], "EM_", "Emerald map prefix")
eq(em.map.enginePrefix, "EM_", "Emerald engine prefix")
eq(em.map.newGameStart.map, "EM_INSIDE_OF_TRUCK", "new game starts in the truck")
eq(em.map.newGameStart.x, 2, "truck spawn x is the layout centre")
eq(em.map.newGameStart.y, 2, "truck spawn y is the layout centre")
eq(em.map.newGameStart.facing, "down", "new game faces south")

eq(em.species.num, 412, "Emerald NUM_SPECIES")
eq(em.species.egg, 412, "Emerald SPECIES_EGG")
eq(em.badges.count, 8, "eight Hoenn badges")
eq(em.badges.flagBase, 0x867, "badge flags start at FLAG_BADGE01_GET")
local badgeNames = { "STONE", "KNUCKLE", "DYNAMO", "HEAT", "BALANCE", "FEATHER", "MIND", "RAIN" }
for i, name in ipairs(badgeNames) do
  eq(em.badges.names[i], name, "badge " .. i .. " is " .. name)
end

local okAudit, problems = Capabilities.audit(em.capabilities)
check(okAudit, "the Emerald capability row audits clean"
  .. (okAudit and "" or (": " .. table.concat(problems, "; "))))
for _, cap in ipairs({ "helpSystem", "tmCase", "fameChecker", "teachyTV", "vsSeeker", "trainerTower",
    "seagallop", "trainerFanClub", "berryPouch", "sevii", "questLog", "mapPreview", "signpostFrame",
    "trainersEyes" }) do
  check(em.capabilities[cap] == nil, "Emerald leaves " .. cap .. " off")
end
for _, cap in ipairs({ "contests", "secretBase", "battleTower", "pokeNav", "matchCall", "rtc", "tv",
    "berryTrees", "battleFrontier", "battlePyramid", "pyramidBag", "frontierPass", "apprentice",
    "trainerHill", "lilycoveLady", "rayquazaScene", "battleTents", "easyChat", "daycare" }) do
  eq(em.capabilities[cap], true, "Emerald enables " .. cap)
end
for cap in pairs(Capabilities.RSE) do
  eq(em.capabilities[cap], true, "Emerald carries RSE capability " .. cap)
end
eq(Capabilities.RSE.matchCall, nil, "Match Call is Emerald-only, not RSE-wide")
eq(Capabilities.gate({ version = "emerald" }, "fame_checker"), false, "Fame Checker is gated off on Emerald")
eq(Capabilities.gate({ version = "emerald" }, "battle_frontier"), true, "Battle Frontier is open on Emerald")
eq(Capabilities.nativeAllowed({ version = "emerald" }, "natives_tower"), false,
  "Trainer Tower natives are filtered out on Emerald")

eq(type(em.nativeModules), "table", "Emerald names its natives modules")
local SHARED = { natives_daycare = true, natives_elevator = true, natives_gift = true, natives_moveteach = true }
for _, m in ipairs(em.nativeModules) do
  check(SHARED[m] or (Capabilities.nativeFeature(m) ~= nil and not Capabilities.nativeAllowed({ version = "firered" }, m)),
    "Emerald natives module " .. m .. " is RSE-gated, not a FireRed module")
end
eq(type(em.extractors), "table", "Emerald names its extractor list")
eq(type(em.coreSpecials), "table", "Emerald allow-lists shared core specials")
for _, key in ipairs({ "module", "widths", "smallWidths" }) do
  eq(type(em.font[key]), "string", "Emerald font block has " .. key)
end

local fr = Profile.of("firered")
eq(fr.family, "frlg", "FireRed is the frlg family")
eq(Profile.of("leafgreen").family, "frlg", "LeafGreen inherits the frlg family")
local FRLG_CAPS = {
  "berries", "berryPouch", "braille", "daycare", "easyChat", "eggs", "fameChecker", "helpSystem",
  "marts", "moveRelearner", "mysteryGift", "pokecenter", "seagallop", "sevii", "sizeRecord",
  "teachyTV", "tmCase", "trainerFanClub", "trainerTower", "unionRoom", "vsSeeker",
}
local seen = {}
for cap, value in pairs(fr.capabilities) do
  seen[#seen + 1] = cap
  eq(value, true, "FireRed capability " .. cap .. " is on")
end
table.sort(seen)
eq(table.concat(seen, ","), table.concat(FRLG_CAPS, ","), "FireRed capability set is unchanged")
local frlgSet = {}
for cap in pairs(Capabilities.FRLG) do frlgSet[#frlgSet + 1] = cap end
table.sort(frlgSet)
eq(table.concat(frlgSet, ","), table.concat(FRLG_CAPS, ","), "Capabilities.FRLG is unchanged")

eq(Profile.forSession({ version = "emerald" }).id, "emerald", "forSession reads the session version")
eq(Profile.forSession(nil).id, "firered", "forSession falls back to the active version")
eq(Profile.family({ version = "emerald" }), "rse", "family() reads the session row")
GameVersion.set("emerald")
eq(Profile.active().id, "emerald", "active() follows an Emerald session")
eq(Profile.forSession({}).id, "emerald", "a session without a version uses the active game")
GameVersion.set("red")
eq(Profile.active().id, "firered", "non-Gen3 processes still resolve to FireRed")
eq(Profile.of("not-a-game").id, "firered", "unknown non-Gen3 ids still fall back")

GameVersion.VERSIONS.gen3_fixture = { id = "gen3_fixture", generation = 3, engine = "game3" }
T.raises(function() return Profile.of("gen3_fixture") end, "gen3_fixture",
  "a Gen 3 id without a profile row raises instead of becoming FireRed")
GameVersion.set("gen3_fixture")
T.raises(function() return Profile.active() end, "gen3_fixture",
  "an active Gen 3 id without a row raises")
GameVersion.set("red")
GameVersion.VERSIONS.gen3_fixture = nil

GameVersion.set("firered")
local frCtx = Ctx.new({})
eq(frCtx.specialVars[0x8012], Ctx.TEXT_COLOR_DEFAULT, "FireRed seeds VAR_TEXT_COLOR")
check(not Ctx.isSpecial(0x8015), "0x8015 is not a FireRed special var")
local emCtx = Ctx.new({ version = "emerald" })
eq(emCtx.specialVars[0x8012], nil, "Emerald does not seed VAR_MON_BOX_ID with a text colour")
emCtx.specialVars[0x8012] = 3
Ctx.wipeSpecial(emCtx)
eq(emCtx.specialVars[0x8012], nil, "Emerald wipe leaves 0x8012 clear")
GameVersion.set("emerald")
check(Ctx.isSpecial(0x8015), "VAR_TRAINER_BATTLE_OPPONENT_A is an Emerald special var")
check(not Ctx.isSpecial(0x8016), "0x8016 is past SPECIAL_VARS_END")
eq(Ctx.specialLayout().trainerBattleOpponentA, 0x8015, "Emerald layout names 0x8015")

Profile.reset()
GameVersion.set(prevVersion)
T.finish("game3_emerald_profile_test")
