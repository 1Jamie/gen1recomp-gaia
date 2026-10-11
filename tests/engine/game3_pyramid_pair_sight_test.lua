package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

local TRAINERS_SRC = "src/core/game3/rse/frontier/trainers.lua"
local trainersSource = assert(io.open(TRAINERS_SRC, "r")):read("*a")

local sess = { frontier = {}, map = "EM_BATTLE_FRONTIER_BATTLE_PYRAMID_FLOOR" }
local calls = { fill = {}, battled = {}, songs = {} }

local D = {
  FACILITY = { TOWER = 0, DOME = 1, PALACE = 2, ARENA = 3, FACTORY = 4, PIKE = 5, PYRAMID = 6 },
}
function D.fillTrainerParty(s, tid, firstMonId, monCount, party, opts)
  calls.fill[#calls.fill + 1] = { tid = tid, first = firstMonId, count = monCount, opts = opts }
  for i = 1, monCount do party[firstMonId + i] = { species = 100 + tid, level = 50, owner = tid } end
  return party
end
function D.opponentClass(_, tid) return 10 + tid end
function D.className(_, classId) return "CLASS" .. tostring(classId) end
function D.frontSpriteId(_, tid) return 20 + tid end
function D.trainerName(_, tid) return "NAME" .. tostring(tid) end
function D.specialTransition(_, group) return group == "B_PYRAMID" and 42 or nil end
for name in pairs(D) do
  if name ~= "FACILITY" then
    T.check(trainersSource:find("function D." .. name .. "(", 1, true) ~= nil,
      "stubbed frontier trainers export exists in " .. TRAINERS_SRC .. ": " .. name)
  end
end
T.check(trainersSource:find("D.FACILITY = {", 1, true) ~= nil, "D.FACILITY is defined by " .. TRAINERS_SRC)
package.loaded["src.core.game3.rse.frontier.trainers"] = D

local function ir(s) return { { t = "text", s = s }, { t = "eos" } } end
local Pyramid = { _ids = { [3] = 7, [5] = 9 } }
function Pyramid.inPyramid() return true end
function Pyramid.localIdToTrainerId(_, localId) return Pyramid._ids[localId] or 0xFFFF end
function Pyramid.speech(_, tid, which) return ir(({ "INTRO", "LOST", "WON" })[which + 1] .. tid) end
function Pyramid.encounterMusic(_, tid) calls.songs[#calls.songs + 1] = tid return 300 + tid end
function Pyramid.markBattled(_, tid, localId) calls.battled[#calls.battled + 1] = { tid, localId } end
package.loaded["src.core.game3.rse.frontier.pyramid"] = Pyramid
package.loaded["src.core.game3.rse.init"] = { session = function() return sess end }
package.loaded["src.core.game3.runtime"] = { _mod = {}, _game = {}, getSession = function() return sess end }
package.loaded["src.core.game3.audio"] = { playSong = function() end }
package.loaded["src.core.game3.scripting.natives"] = {
  outcome_to_code = function(r) return r == "win" and 1 or 2 end,
}
local shown = {}
package.loaded["src.ui.game3.hud"] = {
  openMessage = function(_, text, opts)
    shown[#shown + 1] = text
    if opts and opts.done then opts.done() end
  end,
}
local started
package.loaded["src.core.game3.battle_bridge"] = {
  start = function(_, _, foe, opts) started = { foe = foe, opts = opts } return true end,
}

local TrainerSight = require("src.core.game3.trainer_sight")
local FieldEffects = require("src.core.game3.field_effects")
local Objects = require("src.core.game3.objects")
local Field = require("src.core.game3.field")
local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")

FieldEffects.startExclamation = function(_, onDone) onDone() end
Objects.setTrainerMovementType = nil
Objects.overrideTemplateMovementType = nil
Objects.rememberPerm = nil
Space.store = Flags.newStore()
Space.bundle = { scripts = {}, text = {}, movements = {}, events = {} }

local function trainer(localId, x, y)
  return { localId = localId, cellX = x, cellY = y, facing = "down", visible = true, trainerType = 1, sight = 3 }
end
local a = { eo = trainer(3, 10, 10), dist = 1, facing = "down" }
local b = { eo = trainer(5, 12, 10), dist = 1, facing = "down" }

-- pokeemerald/src/battle_setup.c:1273
local ok, err = pcall(TrainerSight.engagePair, {}, a, b)
T.check(ok, "two Pyramid trainers spotting the player does not error (" .. tostring(err) .. ")")
if not ok then T.finish("game3_pyramid_pair_sight") end

T.eq(sess.frontierOpponentA, 7, "opponent A comes from the Pyramid trainer id table")
T.eq(sess.frontierOpponentB, 9, "opponent B comes from the Pyramid trainer id table")
T.eq(#calls.fill, 2, "FillFrontierTrainersParties fills both opponents")
T.eq(calls.fill[1].count, 1, "opponent A gets one mon")
T.eq(calls.fill[2].count, 1, "opponent B gets one mon")
T.eq(calls.fill[1].opts.facility, 6, "opponent A party uses the Pyramid facility set")
T.eq(calls.fill[2].opts.facility, 6, "opponent B party uses the Pyramid facility set")
T.eq(calls.fill[2].opts.setOwner, 7, "opponent B draws from opponent A's mon set")

T.eq(#shown, 2, "both intro speeches are shown")
T.eq(shown[1][1].s, "INTRO7", "opponent A intro speech")
T.eq(shown[2][1].s, "INTRO9", "opponent B intro speech")
T.same(calls.songs, { 7, 9 }, "encounter music plays for each approaching trainer")

T.check(started ~= nil, "battle starts after both intros")
local opts = started and started.opts or {}
local foe = started and started.foe or {}
T.eq(opts.twoOpponents, true, "battle is a two-opponent battle")
T.eq(opts.double, true, "battle is a double battle")
T.eq(opts.pyramid, true, "battle carries the Pyramid kind")
T.eq(opts.frontier, true, "battle carries the frontier kind")
T.eq(opts.trainerId, 7, "trainer A id")
T.eq(opts.trainerIdB, 9, "trainer B id")
T.eq(opts.frontierFoeHalf, 1, "foe half splits the combined party after opponent A's mon")
T.eq(#foe.party, 2, "combined enemy party holds one mon per opponent")
T.eq(foe.party[1].owner, 7, "first enemy mon belongs to opponent A")
T.eq(foe.party[2].owner, 9, "second enemy mon belongs to opponent B")
T.eq(foe.trainerClass, 17, "foe class comes from GetFrontierOpponentClass")
T.eq(foe.trainerClassName, "CLASS17", "foe class name resolves from the class id")
T.eq(foe.trainerName, "NAME7", "foe name comes from GetFrontierTrainerName")
T.eq(foe.trainerPicId, 27, "foe pic comes from GetFrontierTrainerFrontSpriteId")
T.eq(opts.frontierTrainerB and opts.frontierTrainerB.class, 19, "opponent B class")
T.eq(opts.frontierTrainerB and opts.frontierTrainerB.className, "CLASS19", "opponent B class name")
T.eq(opts.frontierTrainerB and opts.frontierTrainerB.name, "NAME9", "opponent B name")
T.eq(opts.frontierTrainerB and opts.frontierTrainerB.pic, 29, "opponent B pic")
T.eq(opts.defeatText, "WON7", "opponent A defeat text is the player-won speech as plain text")
T.eq(opts.defeatTextB, "WON9", "opponent B defeat text is the player-won speech as plain text")
T.eq(opts.transitionId, 42, "Pyramid battle transition group")
T.check(TrainerSight._pair ~= nil and TrainerSight._pair.a == 7 and TrainerSight._pair.b == 9,
  "pair state records both opponents")

if opts.done then opts.done("win") end
T.eq(#calls.battled, 2, "both Pyramid trainers are marked battled afterwards")
T.same(calls.battled[1], { 7, 3 }, "opponent A marked by trainer id and local id")
T.same(calls.battled[2], { 9, 5 }, "opponent B marked by trainer id and local id")
T.eq(sess.battleOutcome, 1, "battle outcome stored on the session")
T.eq(Field.locked, false, "field unlocks after the battle")
T.eq(TrainerSight._pair, nil, "pair state clears after the battle")

T.finish("game3_pyramid_pair_sight")
