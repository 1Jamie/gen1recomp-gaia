package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local prevVersion = GameVersion.get()
GameVersion.set("firered")

local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Constants = require("src.core.game3.constants")
local Runtime = require("src.core.game3.runtime")

Natives.bind("firered")

local FR = Constants.of("firered").specials
local EM = Constants.of("emerald").specials

local SNAPSHOT = {
  natives = { 0x0, 0x36, 0x38, 0x39, 0x3A, 0x3C, 0x5F, 0x60, 0x7C, 0x7D, 0x9D, 0x9E, 0x9F, 0xB4, 0xD6, 0xD7, 0xE6, 0xF9, 0xFA, 0xFB, 0x106, 0x107, 0x110, 0x137, 0x138, 0x139, 0x13A, 0x143, 0x156, 0x15B, 0x164, 0x166, 0x169, 0x16F, 0x172, 0x17D, 0x17E, 0x17F, 0x181, 0x184, 0x187, 0x188, 0x18F, 0x190, 0x193, 0x197, 0x198, 0x199, 0x1B2, 0xF001, 0xF002, 0xF003 },
  natives_corner = { 0x15E },
  natives_cutscene = { 0x108, 0x113, 0x114, 0x18B, 0x18C, 0x191, 0x1A1, 0x1A5, 0x1B5, 0x1B7, 0x1BA },
  natives_daycare = { 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBB, 0xBC, 0xBD, 0xBE, 0xBF, 0xC0, 0x15F, 0x176, 0x177, 0x178, 0x179, 0x17A },
  natives_elevator = { 0xD8, 0x111, 0x132, 0x160, 0x1B8 },
  natives_events = { 0x8D, 0x8E, 0xAB, 0xCD, 0xCE, 0x129, 0x135, 0x136, 0x155, 0x157, 0x15C, 0x15D, 0x161, 0x167, 0x168, 0x170, 0x171, 0x19A, 0x1AB, 0x1AC, 0x1B9, 0x1BB },
  natives_fame = { 0x173, 0x174 },
  natives_fan_club = { 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA },
  natives_gift = { 0x180, 0x186, 0x189 },
  natives_link = { 0x1, 0x2, 0x3, 0x4, 0x5, 0x1C, 0x1D, 0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x2A, 0x3D, 0x5D, 0x127, 0x128, 0x14B, 0x16A, 0x16B, 0x16C, 0x16D, 0x16E, 0x182, 0x183, 0x1B3 },
  natives_listmenu = { 0x158, 0x159 },
  natives_moveteach = { 0xDB, 0xDC, 0xDD, 0xDE, 0xDF, 0xE0, 0x18D, 0x1A3, 0x1A4 },
  natives_queries = { 0x7B, 0x83, 0x84, 0x85, 0x94, 0x96, 0xBA, 0xC5, 0xC6, 0xD4, 0x11E, 0x11F, 0x130, 0x147, 0x148, 0x14F, 0x150, 0x153, 0x162, 0x163, 0x165, 0x17C, 0x18A, 0x196, 0x19B, 0x1AA, 0x1AD, 0x1AE, 0x1B0, 0x1B1, 0x1B4, 0x1B6 },
  natives_seagallop = { 0x17B, 0x1A7, 0x1A8, 0x1A9 },
  natives_size_record = { 0x77, 0x78, 0x79, 0x7A, 0xD5 },
  natives_tower = { 0x27, 0x28, 0x29, 0xC4, 0xEC, 0xF6, 0xF8, 0x194 },
  natives_trade = { 0xFC, 0xFD, 0xFE, 0xFF },
  natives_wireless = { 0xEB, 0x11D, 0x142, 0x18E, 0x192, 0x195, 0x19C, 0x19D, 0x19E, 0x19F, 0x1A0, 0x1A2, 0x1A6 },
}

local function sourceOf(fn)
  return debug.getinfo(fn, "S").short_src:match("([%w_]+)%.lua$")
end

local function boundIds()
  local ids = {}
  for key, fn in pairs(Natives.ALLOW) do
    local id = tonumber(key:match("^special:(%d+)$"))
    if id then ids[id] = fn end
  end
  return ids
end

local expected, expectedCount = {}, 0
for file, ids in pairs(SNAPSHOT) do
  for _, id in ipairs(ids) do
    expected[id] = file
    expectedCount = expectedCount + 1
  end
end

local frBound = boundIds()
local frCount = 0
for id, fn in pairs(frBound) do
  frCount = frCount + 1
  eq(sourceOf(fn), expected[id], string.format("FireRed special 0x%X is served by its snapshot module", id))
end
eq(frCount, expectedCount, "FireRed binds exactly the snapshot id set")

local aliases = Std.SPECIAL_ALIASES
for name, id in pairs(Std.SPECIAL) do
  local pret = aliases[name] or name
  if id < Std.SPECIAL_ENGINE_BASE then
    eq(FR.byId[id], pret, "Std.SPECIAL." .. name .. " is pret special " .. pret)
  end
  local fn = Natives.BY_NAME[pret]
  if fn then
    check(Natives.ALLOW["special:" .. id] == fn,
      string.format("FireRed id 0x%X resolves through its name %s to the same handler", id, pret))
  end
end

for base, mod in pairs(Natives.MODULES) do
  check(type(mod.BY_NAME) == "table", base .. " exports handlers by pret name")
  for name, fn in pairs(mod.BY_NAME or {}) do
    check(FR.byName[name] ~= nil or EM.byName[name] ~= nil or Std.SPECIAL[name] ~= nil,
      base .. "." .. name .. " is a pret special name")
    for id, legacy in pairs(mod.HANDLERS or {}) do
      if FR.byId[id] == name then
        check(legacy == fn, string.format("%s legacy HANDLERS[0x%X] is the %s handler", base, id, name))
      end
    end
  end
end
for name in pairs(Natives.CORE) do
  check(FR.byName[name] ~= nil or Std.SPECIAL[name] ~= nil,
    "core handler " .. name .. " is a pret special name or an engine special")
end

GameVersion.set("emerald")
Natives.resetLog()
check(Natives.ensureBound() == true, "an Emerald session rebinds the natives")
eq(Natives.boundGame, "emerald", "bound to the Emerald special table")
local SHARED = { natives_daycare = true, natives_elevator = true, natives_gift = true, natives_moveteach = true }
for m in pairs(Natives.MODULES) do
  local Capabilities = require("src.core.game3.capabilities")
  check(SHARED[m] or (Capabilities.nativeFeature(m) ~= nil and not Capabilities.nativeAllowed({ version = "firered" }, m)),
    "Emerald loads only RSE-gated natives modules (" .. m .. ")")
end

local emBound = boundIds()
for id, fn in pairs(emBound) do
  local name = Std.specialName("emerald", id)
  check(name ~= nil, string.format("Emerald bound id 0x%X has a pret name", id))
  check(Natives.BY_NAME[name] == fn, string.format("Emerald 0x%X runs the %s handler", id, tostring(name)))
end
eq(emBound[EM.byName.HealPlayerParty], Natives.CORE.HealPlayerParty, "Emerald HealPlayerParty is the shared heal handler")
local ereaderNames = { "ValidateEReaderTrainer", "CopyEReaderTrainerGreeting", "BufferEReaderTrainerName",
  "SetEReaderTrainerGfxId" }
for _, name in ipairs(ereaderNames) do
  local id = EM.byName[name]
  check(id ~= nil and emBound[id] ~= nil, "Emerald " .. name .. " is bound")
end
local ereaderSpecial = EM.byName.ValidateEReaderTrainer
local oldEreaderSession = Runtime.session
Runtime.session = { version = "emerald", frontier = { ereaderTrainer = {
  name = "ALPHA", party = { { species = 1 } }, greeting = "WELCOME", facilityClass = 0,
} } }
local ereaderCtx = { specialVars = {}, stringVars = {} }
Natives.special(ereaderCtx, ereaderSpecial, {})
eq(ereaderCtx.specialVars[0x800D], 0, "valid saved e-Reader trainer returns FALSE")
local ereaderWritten = {}
Natives.special(ereaderCtx, EM.byName.BufferEReaderTrainerName, {
  setStringVar = function(i, value) ereaderWritten[i] = value end,
})
eq(ereaderCtx.stringVars[1], "ALPHA", "e-Reader name is buffered in string variable 1")
eq(ereaderWritten[1], "ALPHA", "e-Reader name is sent to the script adapter")
Natives.special(ereaderCtx, EM.byName.CopyEReaderTrainerGreeting, {
  setStringVar = function(i, value) ereaderWritten[i] = value end,
})
eq(ereaderCtx.stringVars[4], "WELCOME", "e-Reader greeting is buffered in string variable 4")
local EReaderTrainers = require("src.core.game3.rse.frontier.trainers")
local oldFacilityClassToGfx = EReaderTrainers.facilityClassToGfx
local Space = require("src.core.game3.scripting.space")
local oldEReaderStore = Space.store
Space.store = { vars = {} }
EReaderTrainers.facilityClassToGfx = function(facilityClass)
  eq(facilityClass, 0, "e-Reader gfx lookup receives the saved facility class")
  return 77
end
Natives.special(ereaderCtx, EM.byName.SetEReaderTrainerGfxId, {})
local EReaderConstants = require("src.core.game3.constants").of("emerald")
local gfxVar = EReaderConstants:var("VAR_OBJ_GFX_ID_0")
eq(Space.store.vars[gfxVar], 77, "e-Reader graphic is assigned to Emerald's object graphics variable")
EReaderTrainers.facilityClassToGfx = oldFacilityClassToGfx
Space.store = oldEReaderStore
Runtime.session = { version = "emerald", frontier = { ereaderTrainer = {} } }
Natives.special(ereaderCtx, ereaderSpecial, {})
eq(ereaderCtx.specialVars[0x800D], 1, "empty e-Reader record returns TRUE")
Runtime.session = { version = "emerald", frontier = { ereaderTrainer = {
  name = "BROKEN", party = { { species = 1 } }, checksumValid = false,
} } }
Natives.special(ereaderCtx, ereaderSpecial, {})
eq(ereaderCtx.specialVars[0x800D], 1, "invalid e-Reader checksum returns TRUE")
Runtime.session = oldEreaderSession
local trainerIntro = EM.byName.ShowTrainerIntroSpeech
local trainerCantBattle = EM.byName.ShowTrainerCantBattleSpeech
local prepareSecondTrainer = EM.byName.TryPrepareSecondApproachingTrainer
local trainerApproach = EM.byName.DoTrainerApproach
check(Natives.BY_NAME.DoTrainerApproach ~= nil
  and Natives.ALLOW["special:" .. trainerApproach] ~= nil,
  "Emerald DoTrainerApproach has a deliberate TrainerSight no-op handler")
check(prepareSecondTrainer ~= nil and emBound[prepareSecondTrainer] ~= nil,
  "Emerald TryPrepareSecondApproachingTrainer is bound")
local secondTrainerCtx = { specialVars = { [0x800D] = 1 } }
eq(Natives.special(secondTrainerCtx, prepareSecondTrainer, {}), false,
  "TryPrepareSecondApproachingTrainer completes synchronously")
eq(secondTrainerCtx.specialVars[0x800D], 0, "no queued second approach clears VAR_RESULT")
check(trainerIntro ~= nil and emBound[trainerIntro] ~= nil, "Emerald ShowTrainerIntroSpeech is bound")
check(trainerCantBattle ~= nil and emBound[trainerCantBattle] ~= nil,
  "Emerald ShowTrainerCantBattleSpeech is bound")
local TrainerData = require("src.core.game3.scripting.trainers")
local Pyramid = require("src.core.game3.rse.frontier.pyramid")
local Hill = require("src.core.game3.rse.trainer_hill")
local oldDialogs, oldInPyramid, oldInHill = TrainerData.dialogs, Pyramid.inPyramid, Hill.inChallenge
TrainerData.dialogs = function(trainerId)
  eq(trainerId, 321, "trainer speech resolves the active opponent id")
  return { intro = "CHALLENGER!", notEnough = "NOT ENOUGH POKEMON!" }
end
Pyramid.inPyramid, Hill.inChallenge = function() return false end, function() return false end
Runtime.session = { version = "emerald" }
local trainerMessages = {}
local trainerCtx = { trainerBattleOpponentA = 321, specialVars = {} }
Natives.special(trainerCtx, trainerIntro, { openMessageAsync = function(message, done)
  trainerMessages[#trainerMessages + 1] = message
  done()
end })
eq(trainerMessages[1], "CHALLENGER!", "ShowTrainerIntroSpeech opens the trainer intro text")
eq(trainerCtx.trainerIntroShown, true, "field intro is marked to prevent duplicate trainerbattle text")
Natives.special(trainerCtx, trainerCantBattle, { openMessageAsync = function(message, done)
  trainerMessages[#trainerMessages + 1] = message
  done()
end })
eq(trainerMessages[2], "NOT ENOUGH POKEMON!", "ShowTrainerCantBattleSpeech opens the refusal text")
TrainerData.dialogs, Pyramid.inPyramid, Hill.inChallenge = oldDialogs, oldInPyramid, oldInHill
local Vm = require("src.core.game3.scripting.vm")
local Ops = require("src.core.game3.scripting.ops_a")
local oldFoeFromId = TrainerData.foeFromId
TrainerData.dialogs = function() return { intro = "DUPLICATE INTRO" } end
TrainerData.foeFromId = function(id) return { trainerId = id } end
local duplicateIntroCount = 0
local introVm = Vm.new({ version = "emerald", adapters = {} })
introVm.ctx.trainerIntroShown = true
introVm.ctx.pc = { listKey = "test", index = 1 }
introVm.adapters.openMessageAsync = function(_, done)
  duplicateIntroCount = duplicateIntroCount + 1
  done()
end
introVm.adapters.startTrainerBattle = function(_, done) done("lose") end
Ops.dispatch(introVm, { op = "trainerbattle", type = 0, trainer = 321 })
eq(duplicateIntroCount, 0, "trainerbattle does not repeat an intro already shown by the special")
eq(introVm.ctx.trainerIntroShown, nil, "trainerbattle consumes the intro-shown marker")
TrainerData.dialogs, TrainerData.foeFromId = oldDialogs, oldFoeFromId
Runtime.session = oldEreaderSession
check(emBound[EM.byName.ShouldTryRematchBattle] ~= Natives.CORE.ShouldTryRematchBattle, "the VS Seeker rematch handler is not bound on Emerald")
local frRematchId = FR.byName.ShouldTryRematchBattle
eq(Std.specialName("emerald", frRematchId), "GetTrainerFlag",
  "the FireRed rematch id means Emerald GetTrainerFlag at that index")
eq(emBound[frRematchId], Natives.BY_NAME.GetTrainerFlag,
  "the overlapping Emerald index dispatches by Emerald special name")
eq(emBound[0xF001], Natives.CORE.FadeScreen, "engine specials stay bound on Emerald")
check(emBound[EM.byName.ChooseMonForWirelessMinigame] ~= nil,
  "Emerald wireless minigame party selection uses the shared eligibility-aware picker")
local porthole = EM.byName.LookThroughPorthole
check(porthole ~= nil and emBound[porthole] ~= nil,
  "Emerald LookThroughPorthole is bound to the route sailing scene")
local PortholeScene = require("src.core.game3.special_scene_rse")
local portholeGroups = {
  MAP_ROUTE132 = { group = 0, num = 47 },
  MAP_ROUTE133 = { group = 0, num = 48 },
  MAP_ROUTE134 = { group = 0, num = 49 },
}
local function portholeDest(state, steps)
  return PortholeScene.portholeDestination(state, steps, portholeGroups)
end
local dest = portholeDest(2, 0)
eq(dest.map, "MAP_ROUTE134", "Slateport departure begins sailing across Route 134")
eq(dest.x, 19, "Slateport departure starts at the Emerald Route 134 coordinate")
eq(portholeDest(2, 60).map, "MAP_ROUTE133", "eastbound sailing crosses to Route 133 at step 60")
eq(portholeDest(2, 140).x, 0, "eastbound sailing starts Route 132 at x=0")
eq(portholeDest(7, 0).x, 65, "westbound halfway sailing starts Route 132 at x=65")
eq(portholeDest(7, 66).map, "MAP_ROUTE133", "westbound sailing crosses to Route 133 at step 66")
eq(portholeDest(7, 146).x, 78, "westbound sailing enters Route 134 at x=78")
eq(portholeDest(99, 0), nil, "invalid porthole cruise states have no route destination")
local logs = {}
local adapters = { log = function(m) logs[#logs + 1] = m end }
local poisonWhiteOut = EM.byName.TryFieldPoisonWhiteOut
check(poisonWhiteOut ~= nil and Natives.ALLOW["special:" .. poisonWhiteOut] ~= nil,
  "Emerald TryFieldPoisonWhiteOut is bound")
local Pokemon = require("src.core.game3.pokemon")
local RomText = require("src.core.game3.rom_text")
local oldPoisonSession, oldIsEgg = Runtime.session, Pokemon.isEgg
local oldAdjust, oldName, oldMapSec, oldBox = Pokemon.adjustFriendship, Pokemon.displayMonName,
  Pokemon.currentMapSec, RomText.box
local poisonSession = { version = "emerald", map = "EM_LITTLEROOT_TOWN", vars = {}, party = {
  { species = 1, hp = 0, status = "PSN" }, { species = 4, hp = 0 },
} }
Runtime.session = poisonSession
Pokemon.isEgg = function(mon) return mon.isEgg == true end
Pokemon.adjustFriendship = function() end
Pokemon.displayMonName = function() return "MON" end
Pokemon.currentMapSec = function() return 0 end
RomText.box = function(key, ctx) return key .. ":" .. ctx.stringVars[1] end
local poisonMessageCount, poisonCtx = 0, { specialVars = {} }
Natives.special(poisonCtx, poisonWhiteOut, { openMessageAsync = function(msg, done)
  poisonMessageCount = poisonMessageCount + 1
  check(msg:find("MON", 1, true) ~= nil, "poison faint message buffers the fainted Pokémon")
  done()
end })
eq(poisonMessageCount, 1, "poison whiteout shows each poison faint once")
eq(poisonCtx.specialVars[0x800D], 1, "ordinary party wipe returns FLDPSN_WHITEOUT")
eq(poisonSession.party[1].status, nil, "poison faint clears the status")
Runtime.session, Pokemon.isEgg, Pokemon.adjustFriendship, Pokemon.displayMonName,
  Pokemon.currentMapSec, RomText.box = oldPoisonSession, oldIsEgg, oldAdjust, oldName, oldMapSec, oldBox
local rematchStart = EM.byName.BattleSetup_StartRematchBattle
check(rematchStart ~= nil and Natives.ALLOW["special:" .. rematchStart] ~= nil,
  "Emerald BattleSetup_StartRematchBattle is bound")
local Trainers = require("src.core.game3.scripting.trainers")
local Rematch = require("src.core.game3.rse.rematch")
local oldRematchSession, oldFoeFromId, oldRematchWon = Runtime.session, Trainers.foeFromId, Rematch.onRematchBattleWon
local rematchSession = { version = "emerald", flags = {}, vars = {}, trainerRematches = {} }
Runtime.session = rematchSession
Trainers.foeFromId = function(id) return { trainerId = id, species = 1, level = 10 } end
local wonTrainer, startOptions
Rematch.onRematchBattleWon = function(sess, id) wonTrainer = id; eq(sess, rematchSession, "rematch completion uses active session") end
local battleStarted = false
Natives.special({ trainerBattleOpponentA = 123, trainerBattleMode = 4 }, rematchStart, {
  startTrainerBattle = function(foe, done, opts)
    battleStarted, startOptions = foe.trainerId == 123, opts
    done("win")
  end,
})
eq(battleStarted, true, "rematch special starts the active trainer battle")
eq(startOptions and startOptions.double, true, "double rematch preserves its battle type")
eq(wonTrainer, 123, "won rematch updates Emerald rematch state")
Runtime.session, Trainers.foeFromId, Rematch.onRematchBattleWon = oldRematchSession, oldFoeFromId, oldRematchWon
local partnerNames = EM.byName.GetLinkPartnerNames
check(partnerNames ~= nil and Natives.ALLOW["special:" .. partnerNames] ~= nil,
  "Emerald GetLinkPartnerNames is bound")
local Link = require("src.core.game3.link.init")
local oldLink = Link.link
local partnerPlayers = {
  { seat = 0, name = "BRENDAN", isLocal = true },
  { seat = 1, name = "MAY", isLocal = false },
  { seat = 2, name = "WALLY", isLocal = false },
}
Link.link = { role = "host", isOpen = function() return true end,
  players = function() return partnerPlayers end }
local partnerCtx, writtenNames = { stringVars = {} }, {}
Natives.special(partnerCtx, partnerNames, { setStringVar = function(i, v) writtenNames[i] = v end })
eq(partnerCtx.stringVars[1], "MAY", "GetLinkPartnerNames fills the first remote name")
eq(partnerCtx.stringVars[2], "WALLY", "GetLinkPartnerNames fills the second remote name")
eq(writtenNames[1], "MAY", "GetLinkPartnerNames writes through the VM adapter")
eq(require("src.core.game3.link.battle").playerCount(), 3, "test link has three multiplayer players")
local gfxSpecial = EM.byName.SetBattleTowerLinkPlayerGfx
check(gfxSpecial ~= nil and Natives.ALLOW["special:" .. gfxSpecial] ~= nil,
  "Emerald SetBattleTowerLinkPlayerGfx is bound")
local oldRuntimeSession, oldSetVar = Runtime.session, Link.setVar
Runtime.session = { version = "emerald" }
local gfxRows = {
  { seat = 0, gender = 0, isLocal = true },
  { seat = 1, gender = 1, isLocal = false },
}
Link.link.players = function() return gfxRows end
local gfxVars = {}
Link.setVar = function(_, id, value) gfxVars[id] = value end
Natives.special({ specialVars = {} }, gfxSpecial, adapters)
local EC = require("src.core.game3.constants").of("emerald")
local gfxVar = EC:var("VAR_OBJ_GFX_ID_F")
eq(gfxVars[gfxVar], EC:require("event_objects", "OBJ_EVENT_GFX_BRENDAN_NORMAL"),
  "link graphics special selects Brendan for a male player")
eq(gfxVars[gfxVar - 1], EC:require("event_objects", "OBJ_EVENT_GFX_RIVAL_MAY_NORMAL"),
  "link graphics special selects May for a female partner")
local spawnPartners = EM.byName.SpawnLinkPartnerObjectEvent
check(spawnPartners ~= nil and Natives.ALLOW["special:" .. spawnPartners] ~= nil,
  "Emerald SpawnLinkPartnerObjectEvent is bound")
local VirtualObjects = require("src.core.game3.virtual_objects")
local Player = require("src.core.game3.player")
local BattleLink = require("src.core.game3.link.battle")
local oldFacing, oldCellX, oldCellY, oldMultiplayerId = Player.facing, Player.cellX, Player.cellY,
  BattleLink.multiplayerId
Runtime.session = { version = "emerald" }
Player.facing, Player.cellX, Player.cellY = "right", 10, 10
BattleLink.multiplayerId = function() return 0 end
Link.link.players = function() return gfxRows end
VirtualObjects.remove(0x7F01)
Natives.special({ specialVars = { [0x8004] = 2 } }, spawnPartners, adapters)
local partnerAvatar = VirtualObjects.get(0x7F01)
check(partnerAvatar ~= nil, "partner spawn creates a virtual avatar for the remote seat")
eq(partnerAvatar.graphicsId, EC:require("event_objects", "OBJ_EVENT_GFX_RIVAL_MAY_NORMAL"),
  "partner avatar uses Emerald's female trainer sprite")
eq(partnerAvatar.x, 11, "partner avatar uses the Emerald facing-relative seat x")
eq(partnerAvatar.y, 11, "partner avatar uses the Emerald facing-relative seat y")
VirtualObjects.remove(0x7F01)
gfxRows[2].version = "sapphire"
Natives.special({ specialVars = { [0x8004] = 2 } }, spawnPartners, adapters)
partnerAvatar = VirtualObjects.get(0x7F01)
eq(partnerAvatar.graphicsId, EC:require("event_objects", "OBJ_EVENT_GFX_LINK_RS_MAY"),
  "Ruby/Sapphire link partner keeps the legacy R/S player graphics")
VirtualObjects.remove(0x7F01)
gfxRows[2].version = nil
Player.facing, Player.cellX, Player.cellY, BattleLink.multiplayerId = oldFacing, oldCellX, oldCellY,
  oldMultiplayerId
Runtime.session, Link.setVar = oldRuntimeSession, oldSetVar
Link.link = oldLink
local startWired = EM.byName.Script_StartWiredTrade
check(Natives.BY_NAME.Script_StartWiredTrade == nil
  and Natives.ALLOW["special:" .. startWired] == nil,
  "Emerald Script_StartWiredTrade is left unbound until wired trade flow exists")
local saveGameSpecial = EM.byName.CableClubSaveGame
local oldGame = Runtime._game
local saved = false
Runtime._game = { saveGame = function() saved = true end }
check(saveGameSpecial ~= nil and Natives.ALLOW["special:" .. saveGameSpecial] ~= nil,
  "Emerald CableClubSaveGame is bound")
Natives.special({ specialVars = {} }, saveGameSpecial, adapters)
eq(saved, true, "CableClubSaveGame calls the live game's save function")
local towerSave = EM.byName.SaveForBattleTowerLink
check(towerSave ~= nil and Natives.ALLOW["special:" .. towerSave] ~= nil,
  "Emerald SaveForBattleTowerLink is bound")
saved = false
Natives.special({ specialVars = {} }, towerSave, adapters)
eq(saved, true, "SaveForBattleTowerLink saves before Tower link play")
Runtime._game = oldGame

local weatherSpecial = EM.byName.Unused_SetWeatherSunny
check(weatherSpecial ~= nil and Natives.ALLOW["special:" .. weatherSpecial] ~= nil,
  "Emerald Unused_SetWeatherSunny has a runtime handler")
local Weather = require("src.core.game3.weather")
local WeatherEngine = require("src.core.game3.field_weather_rse")
local oldSetWeather, oldSetCurrent = Weather.setWeather, WeatherEngine.setCurrentAndNextWeather
local savedWeather, currentWeather
Weather.setWeather = function(id) savedWeather = id end
WeatherEngine.setCurrentAndNextWeather = function(id) currentWeather = id end
Natives.special({ specialVars = {} }, weatherSpecial, adapters)
eq(savedWeather, Weather.SUNNY, "sunny special updates the saved weather")
eq(currentWeather, Weather.SUNNY, "sunny special immediately updates current and next weather")
Weather.setWeather, WeatherEngine.setCurrentAndNextWeather = oldSetWeather, oldSetCurrent

oldGame = Runtime._game
Runtime._game = {}
local softReset = EM.byName.DoSoftReset
check(softReset ~= nil and Natives.ALLOW["special:" .. softReset] ~= nil,
  "Emerald DoSoftReset has a runtime handler")
Natives.special({ specialVars = {} }, softReset, adapters)
eq(Runtime._game.softResetRequested, true, "soft-reset special schedules the existing title reset")
Runtime._game = oldGame

GameVersion.set("firered")
check(Natives.ensureBound() == true, "switching back to FireRed rebinds")
local again = boundIds()
local same = true
for id, fn in pairs(frBound) do
  if again[id] ~= fn then same = false end
end
for id in pairs(again) do
  if frBound[id] == nil then same = false end
end
check(same, "FireRed binding is identical after an Emerald round trip")
eq(Natives.MODULES.natives_queries, Natives.Queries, "Natives.Queries tracks the bound module set")

GameVersion.set("leafgreen")
eq(Natives.ensureBound(), false, "LeafGreen shares the FireRed binding")

GameVersion.set(prevVersion)
Natives.bind(prevVersion)
T.finish("game3_specials_by_name_test")
