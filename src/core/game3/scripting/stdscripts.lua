-- Shared FRLG std / common scripts (not map-local). Same role as pret
-- data/scripts/pc.inc + pkmn_center_nurse.inc — one definition, every map.

local Flags = require("src.core.game3.scripting.flags")
local Opcodes = require("src.core.game3.scripting.opcodes")
local TextIR = require("src.core.game3.scripting.text_ir")

local Std = {}

local function T(ascii)
  ascii = ascii:gsub("^\n", ""):gsub("\r\n", "\n"):gsub("\n", "\\n")
  return TextIR.fromAscii(ascii)
end

-- 0-based def_special order of pokefirered/data/specials.inc
Std.SPECIAL = {
  HealPlayerParty = 0x00,
  SetUsedPkmnCenterQuestLogEvent = 0x169,
  QuestLog_StartRecordingInputsAfterDeferredEvent = 0x184,
  GetQuestLogState = 0x187,
  QuestLog_CutRecording = 0x188,
  ShowPokemonStorageSystemPC = 0x3C,
  BufferMonNickname = 0x7C, -- pokefirered/data/specials.inc:135
  IsMonOTIDNotPlayers = 0x7D, -- pokefirered/data/specials.inc:136
  ChangePokemonNickname = 0x9E, -- pokefirered/data/specials.inc:169
  ChoosePartyMon = 0x9F, -- pokefirered/data/specials.inc:170
  ChooseMonForMoveTutor = 0x18D, -- pokefirered/data/specials.inc:408
  FieldShowRegionMap = 0xFB, -- pokefirered/data/specials.inc:262 ShowTownMap
  AnimatePcTurnOn = 0xD6,
  AnimatePcTurnOff = 0xD7,
  BedroomPC = 0xF9, -- pokefirered/data/specials.inc:260
  PlayerPC = 0xFA,
  CreatePCMenu = 0x106,
  EnterHallOfFame = 0x110, -- 272 (special HallOfFame / GameClear)
  EnableNationalPokedex = 0x16F, -- pokefirered/data/specials.inc:378
  SetUnlockedPokedexFlags = 0x181, -- pokefirered/data/specials.inc:396
  IsNationalPokedexEnabled = 0x193, -- pokefirered/data/specials.inc:414
  Script_SetHelpContext = 0x17D,
  BackupHelpContext = 0x17E,
  RestoreHelpContext = 0x17F,
  SetHelpContextForMap = 0x190,
  HelpSystem_Disable = 0x198,
  HelpSystem_Enable = 0x199,
  StartMarowakBattle = 0x156, -- pokefirered/data/specials.inc:353
  Script_HasTrainerBeenFought = 0x36, -- pokefirered/data/specials.inc:65
  PlayTrainerEncounterMusic = 0x38, -- pokefirered/data/specials.inc:67
  ShouldTryRematchBattle = 0x39, -- pokefirered/data/specials.inc:68
  IsTrainerReadyForRematch = 0x3A, -- pokefirered/data/specials.inc:69
  HasEnoughMonsForDoubleBattle = 0x3D, -- pokefirered/data/specials.inc:72
  SetUpTrainerMovement = 0x13A, -- pokefirered/data/specials.inc:325
  VsSeekerResetObjectMovementAfterChargeComplete = 0x164, -- pokefirered/data/specials.inc:367
  VsSeekerFreezeObjectsAfterChargeComplete = 0x172, -- pokefirered/data/specials.inc:381
  SetBattledTrainerFlag = 0x18F, -- pokefirered/data/specials.inc:410
  ShowEasyChatScreen = 0x5F, -- 95 pokefirered/data/specials.inc:106
  ShowEasyChatMessage = 0x60, -- 96 pokefirered/data/specials.inc:107
  GetBattleOutcome = 0xB4, -- pokefirered/data/specials.inc:191
  GetLeadMonFriendship = 0xE6, -- pokefirered/data/specials.inc:241
  DaisyMassageServices = 0x197, -- pokefirered/data/specials.inc:418
  GetDaycareState = 0xB6, -- pokefirered/data/specials.inc:193
  StartOldManTutorialBattle = 0x9D, -- pokefirered/data/specials.inc:168
  StartGroudonKyogreBattle = 0x137, -- 311 (pokefirered/data/specials.inc:322)
  StartLegendaryBattle = 0x138, -- 312 (pokefirered/data/specials.inc:323)
  StartRegiBattle = 0x139, -- 313 (pokefirered/data/specials.inc:324)
  StartSouthernIslandBattle = 0x143, -- 323 (pokefirered/data/specials.inc:334)
  SetVermilionTrashCans = 0x15B, -- 347 (pokefirered/data/specials.inc:358)
  NameRaterWasNicknameChanged = 0x7B, -- pokefirered/data/specials.inc:134
  CalculatePlayerPartyCount = 0x83, -- pokefirered/data/specials.inc:142
  CountPartyNonEggMons = 0x84, -- pokefirered/data/specials.inc:143
  CountPartyAliveNonEggMons_IgnoreVar0x8004Slot = 0x85, -- pokefirered/data/specials.inc:144
  BufferBigGuyOrBigGirlString = 0x94, -- pokefirered/data/specials.inc:159
  SetHiddenItemFlag = 0x96, -- pokefirered/data/specials.inc:161
  GetSelectedMonNicknameAndSpecies = 0xBA, -- pokefirered/data/specials.inc:197
  IsEnoughForCostInVar0x8005 = 0xC5, -- pokefirered/data/specials.inc:208
  SubtractMoneyFromVar0x8005 = 0xC6, -- pokefirered/data/specials.inc:209
  GetPokedexCount = 0xD4, -- pokefirered/data/specials.inc:223
  GetRandomSlotMachineId = 0x11E, -- pokefirered/data/specials.inc:297
  IsThereRoomInAnyBoxForMorePokemon = 0x130, -- pokefirered/data/specials.inc:315
  GetPartyMonSpecies = 0x147, -- pokefirered/data/specials.inc:338
  IsSelectedMonEgg = 0x148, -- pokefirered/data/specials.inc:339
  HasAllKantoMons = 0x14F, -- pokefirered/data/specials.inc:346
  IsMonOTNameNotPlayers = 0x150, -- pokefirered/data/specials.inc:347
  DoesPartyHaveEnigmaBerry = 0x153, -- pokefirered/data/specials.inc:350
  GetStarterSpecies = 0x162, -- pokefirered/data/specials.inc:365
  SetSeenMon = 0x163, -- pokefirered/data/specials.inc:366
  ShouldShowBoxWasFullMessage = 0x165, -- pokefirered/data/specials.inc:368
  DoesPlayerPartyContainSpecies = 0x17C, -- pokefirered/data/specials.inc:391
  GetPCBoxToSendMon = 0x18A, -- pokefirered/data/specials.inc:405
  HasAtLeastOneBerry = 0x19B, -- pokefirered/data/specials.inc:422
  GetPlayerFacingDirection = 0x1AA, -- pokefirered/data/specials.inc:437
  DoSeagallopFerryScene = 0x17B, -- pokefirered/data/specials.inc:390
  DrawSeagallopDestinationMenu = 0x1A7, -- pokefirered/data/specials.inc:434
  GetSelectedSeagallopDestination = 0x1A8, -- pokefirered/data/specials.inc:435
  GetSeagallopNumber = 0x1A9, -- pokefirered/data/specials.inc:436
  IsPlayerLeftOfVermilionSailor = 0x1AD, -- pokefirered/data/specials.inc:440
  IsBadEggInParty = 0x1AE, -- pokefirered/data/specials.inc:441
  HasAllMons = 0x1B0, -- pokefirered/data/specials.inc:443
  IsPlayerNotInTrainerTowerLobby = 0x1B1, -- pokefirered/data/specials.inc:444
  PlayerPartyContainsSpeciesWithPlayerID = 0x1B4, -- pokefirered/data/specials.inc:447
  IsDodrioInParty = 0x1B6, -- pokefirered/data/specials.inc:449
  BufferUnionRoomPlayerName = 0x183, -- pokefirered/data/specials.inc:398
  -- Engine-extension specials (not cart indices) for shared primitives.
  FadeScreen = 0xF001,
  OpenNaming = 0xF002,
  PlayCry = 0xF003,
}

Std.SPECIAL_ALIASES = {
  FieldShowRegionMap = "ShowTownMap", -- pokefirered/data/specials.inc:262
}

Std.SPECIAL_ENGINE_BASE = 0xF000

Std.SPECIAL_NAME_BY_ID = {}
for name, id in pairs(Std.SPECIAL) do
  if id < Std.SPECIAL_ENGINE_BASE then
    Std.SPECIAL_NAME_BY_ID[id] = Std.SPECIAL_ALIASES[name] or name
  end
end

Std.TEXT = {
  Text_TownMap = T([[
It's a TOWN MAP.]]),
  Text_WelcomeWantToHealPkmn = T([[
Welcome to our POKéMON CENTER!\p
Would you like me to heal your
POKéMON to perfect health?]]),
  Text_TakeYourPkmnForFewSeconds = T([[
OK, may I see your POKéMON?]]),
  Text_RestoredPkmnToFullHealth = T([[
Thank you for waiting.
Your POKéMON are fully healed.]]),
  Text_WeHopeToSeeYouAgain = T([[
We hope to see you again!]]),
  Text_BootedUpPC = T([[
{PLAYER} booted up the PC.]]),
  Text_UsualPCServicesUnavailable = T([[
The usual PC services aren't
available right now…]]),
  -- obtain_item.inc (simplified host strings)
  Text_ObtainedTheX = T([[
{PLAYER} obtained
the {STR_VAR_2}!]]),
  Text_PutItemAway = T([[
{PLAYER} put away the
{STR_VAR_2} in the {STR_VAR_3}.]]),
  Text_TooBadBagFull = T([[
Too bad!
The BAG is full…]]),
  Text_FoundOneItem = T([[
{PLAYER} found one {STR_VAR_2}!]]),
  Text_FoundTMHMContainsMove = T([[
{PLAYER} found
{STR_VAR_2}!]]),
}

-- Cart EventScript_PC (simplified host path: open full storage UI).
Std.SCRIPTS = {
  EventScript_WallTownMap = {
    { op = "lockall" },
    { op = "loadword", dest = 0, value = "Text_TownMap" },
    { op = "callstd", std = Opcodes.STD.MSGBOX_DEFAULT },
    { op = "fadescreen", [1] = 1 },
    { op = "special", id = Std.SPECIAL.FieldShowRegionMap },
    { op = "waitstate" },
    { op = "releaseall" },
    { op = "end" },
  },
  EventScript_PC = {
    { op = "lockall" },
    { op = "setvar", var = 0x8004, value = 0 },
    { op = "special", id = Std.SPECIAL.AnimatePcTurnOn },
    { op = "loadword", dest = 0, value = "Text_BootedUpPC" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "special", id = Std.SPECIAL.CreatePCMenu },
    { op = "waitstate" },
    { op = "setvar", var = 0x8004, value = 0 },
    { op = "special", id = Std.SPECIAL.AnimatePcTurnOff },
    { op = "releaseall" },
    { op = "end" },
  },
  -- Pret shape: welcome → YES/NO → take&heal (turn left → FLDEFF_POKECENTER_HEAL
  -- → turn down → HealPlayerParty) → restored → bow → goodbye.
  EventScript_PkmnCenterNurse = {
    { op = "loadword", dest = 0, value = "Text_WelcomeWantToHealPkmn" },
    { op = "callstd", std = Opcodes.STD.MSGBOX_YESNO },
    { op = "compare_var_to_value", var = 0x800D, value = 0 },
    { op = "goto_if", cond = 1, target = "EventScript_PkmnCenterNurse_Goodbye" },
    { op = "loadword", dest = 0, value = "Text_TakeYourPkmnForFewSeconds" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "call", target = "EventScript_PkmnCenterNurse_TakeAndHealPkmn" },
    { op = "goto", target = "EventScript_PkmnCenterNurse_ReturnPkmn" },
  },
  -- pret EventScript_PkmnCenterNurse_TakeAndHealPkmn
  EventScript_PkmnCenterNurse_TakeAndHealPkmn = {
    -- WalkInPlaceFasterLeft / Down (0x2F / 0x2D) + step_end
    { op = "applymovement", localId = 0x800F, movement = { 0x2F, 0xFE } },
    { op = "waitmovement", localId = 0x800F },
    { op = "dofieldeffect", [1] = 25 },
    { op = "waitfieldeffect", [1] = 25 },
    { op = "applymovement", localId = 0x800F, movement = { 0x2D, 0xFE } },
    { op = "waitmovement", localId = 0x800F },
    { op = "special", id = Std.SPECIAL.HealPlayerParty },
    { op = "return" },
  },
  EventScript_PkmnCenterNurse_ReturnPkmn = {
    { op = "loadword", dest = 0, value = "Text_RestoredPkmnToFullHealth" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    -- nurse_joy_bow (0x5B) + delay_4 (0x1A) + step_end
    { op = "applymovement", localId = 0x800F, movement = { 0x5B, 0x1A, 0xFE } },
    { op = "waitmovement", localId = 0x800F },
    { op = "goto", target = "EventScript_PkmnCenterNurse_Goodbye" },
  },
  EventScript_PkmnCenterNurse_Goodbye = {
    { op = "loadword", dest = 0, value = "Text_WeHopeToSeeYouAgain" },
    { op = "callstd", std = Opcodes.STD.MSGBOX_DEFAULT },
    { op = "return" },
  },
  -- Economy / item stds (pret obtain_item.inc). Pocket name → STR_VAR_3.
  EventScript_RestorePrevTextColor = { -- data/scripts/obtain_item.inc:6
    { op = "copyvar", [1] = 0x8012, [2] = 0x8013 },
    { op = "return" },
  },
  ["std:0"] = { -- STD_OBTAIN_ITEM, data/scripts/obtain_item.inc:10
    { op = "copyvar", [1] = 0x8013, [2] = 0x8012 },
    { op = "textcolor", color = 3, [1] = 3 },
    { op = "additem", [1] = 0x8000, [2] = 0x8001 },
    { op = "copyvar", [1] = 0x8007, [2] = 0x800D },
    { op = "call", target = "EventScript_ObtainItemMessage" },
    { op = "copyvar", [1] = 0x8012, [2] = 0x8013 },
    { op = "return" },
  },
  EventScript_ObtainItemMessage = {
    { op = "bufferitemname", dest = 1, src = 0x8000 }, -- STR_VAR_2
    { op = "checkitemtype", [1] = 0x8000 },
    { op = "call", target = "EventScript_BufferPocketName" },
    { op = "compare_var_to_value", var = 0x8007, value = 1 },
    { op = "goto_if", cond = 1, target = "EventScript_ObtainedItem" },
    { op = "setvar", var = 0x800D, value = 0 },
    { op = "return" },
  },
  EventScript_ObtainedItem = {
    { op = "playfanfare", [1] = 257 }, -- MUS_LEVEL_UP
    { op = "loadword", dest = 0, value = "Text_ObtainedTheX" },
    { op = "message", ptr = 0 },
    { op = "waitfanfare" },
    { op = "waitmessage" },
    { op = "loadword", dest = 0, value = "Text_PutItemAway" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "setvar", var = 0x800D, value = 1 },
    { op = "return" },
  },
  EventScript_BufferPocketName = {
    { op = "compare_var_to_value", var = 0x800D, value = 1 },
    { op = "goto_if", cond = 1, target = "EventScript_BufferItemsPocket" },
    { op = "compare_var_to_value", var = 0x800D, value = 2 },
    { op = "goto_if", cond = 1, target = "EventScript_BufferKeyItemsPocket" },
    { op = "compare_var_to_value", var = 0x800D, value = 3 },
    { op = "goto_if", cond = 1, target = "EventScript_BufferPokeBallsPocket" },
    { op = "compare_var_to_value", var = 0x800D, value = 4 },
    { op = "goto_if", cond = 1, target = "EventScript_BufferTMCase" },
    { op = "compare_var_to_value", var = 0x800D, value = 5 },
    { op = "goto_if", cond = 1, target = "EventScript_BufferBerryPouch" },
    { op = "bufferstdstring", dest = 2, src = 24 }, -- STR_VAR_3 ITEMS POCKET
    { op = "return" },
  },
  EventScript_BufferItemsPocket = {
    { op = "bufferstdstring", dest = 2, src = 24 },
    { op = "return" },
  },
  EventScript_BufferKeyItemsPocket = {
    { op = "bufferstdstring", dest = 2, src = 25 },
    { op = "return" },
  },
  EventScript_BufferPokeBallsPocket = {
    { op = "bufferstdstring", dest = 2, src = 26 },
    { op = "return" },
  },
  EventScript_BufferTMCase = {
    { op = "bufferstdstring", dest = 2, src = 27 },
    { op = "return" },
  },
  EventScript_BufferBerryPouch = {
    { op = "bufferstdstring", dest = 2, src = 28 },
    { op = "return" },
  },
  ["std:1"] = { -- STD_FIND_ITEM
    { op = "checkitemspace", [1] = 0x8000, [2] = 0x8001 },
    { op = "copyvar", [1] = 0x8007, [2] = 0x800D },
    { op = "bufferitemname", dest = 1, src = 0x8000 },
    { op = "checkitemtype", [1] = 0x8000 },
    { op = "call", target = "EventScript_BufferPocketName" },
    { op = "compare_var_to_value", var = 0x8007, value = 1 },
    { op = "goto_if", cond = 1, target = "EventScript_PickUpItem" },
    { op = "loadword", dest = 0, value = "Text_TooBadBagFull" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "setvar", var = 0x800D, value = 0 },
    { op = "return" },
  },
  EventScript_PickUpItem = {
    { op = "removeobject", [1] = 0x800F },
    { op = "additem", [1] = 0x8000, [2] = 0x8001 },
    { op = "playfanfare", [1] = 257 }, -- MUS_LEVEL_UP
    { op = "loadword", dest = 0, value = "Text_FoundOneItem" },
    { op = "message", ptr = 0 },
    { op = "waitfanfare" },
    { op = "waitmessage" },
    { op = "loadword", dest = 0, value = "Text_PutItemAway" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "setvar", var = 0x800D, value = 1 },
    { op = "return" },
  },
  ["std:2"] = { -- MSGBOX_NPC, data/scripts/std_msgbox.inc:6
    { op = "lock" },
    { op = "faceplayer" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "release" },
    { op = "return" },
  },
  ["std:3"] = { -- MSGBOX_SIGN, data/scripts/std_msgbox.inc:14
    { op = "lockall" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "releaseall" },
    { op = "return" },
  },
  ["std:4"] = { -- MSGBOX_DEFAULT, data/scripts/std_msgbox.inc:22
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "return" },
  },
  ["std:5"] = { -- MSGBOX_YESNO, data/scripts/std_msgbox.inc:27
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "yesnobox", [1] = 20, [2] = 8 },
    { op = "return" },
  },
  ["std:6"] = { -- MSGBOX_AUTOCLOSE, data/scripts/std_msgbox.inc:32
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "release" },
    { op = "return" },
  },
  ["std:8"] = { -- STD_PUT_ITEM_AWAY
    { op = "bufferitemname", dest = 1, src = 0x8000 },
    { op = "checkitemtype", [1] = 0x8000 },
    { op = "call", target = "EventScript_BufferPocketName" },
    { op = "loadword", dest = 0, value = "Text_PutItemAway" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "return" },
  },
  ["std:9"] = { -- STD_RECEIVED_ITEM (msgreceiveditem)
    { op = "textcolor", color = 3, [1] = 3 }, -- data/scripts/std_msgbox.inc:30
    { op = "compare_var_to_value", var = 0x8002, value = 318 }, -- MUS_OBTAIN_KEY_ITEM
    { op = "goto_if", cond = 1, target = "EventScript_ReceivedItemFanfareKeyItem" },
    { op = "compare_var_to_value", var = 0x8002, value = 258 }, -- MUS_OBTAIN_ITEM
    { op = "goto_if", cond = 1, target = "EventScript_ReceivedItemFanfareItem" },
    { op = "compare_var_to_value", var = 0x8002, value = 257 }, -- MUS_LEVEL_UP
    { op = "goto_if", cond = 1, target = "EventScript_ReceivedItemFanfareLevelUp" },
    { op = "goto", target = "EventScript_ReceivedItemFanfareDefault" },
  },
  EventScript_ReceivedItemFanfareKeyItem = {
    { op = "playfanfare", [1] = 318 }, -- MUS_OBTAIN_KEY_ITEM
    { op = "goto", target = "EventScript_ReceivedItemShowMsg" },
  },
  EventScript_ReceivedItemFanfareItem = {
    { op = "playfanfare", [1] = 258 }, -- MUS_OBTAIN_ITEM
    { op = "goto", target = "EventScript_ReceivedItemShowMsg" },
  },
  EventScript_ReceivedItemFanfareLevelUp = {
    { op = "playfanfare", [1] = 257 }, -- MUS_LEVEL_UP
    { op = "goto", target = "EventScript_ReceivedItemShowMsg" },
  },
  EventScript_ReceivedItemFanfareDefault = {
    { op = "playfanfare", [1] = 0x8002 }, -- VAR_0x8002 fallback
    { op = "goto", target = "EventScript_ReceivedItemShowMsg" },
  },
  EventScript_ReceivedItemShowMsg = {
    { op = "message", ptr = 0 },
    { op = "waitfanfare" },
    { op = "waitmessage" },
    { op = "callstd", std = 8 }, -- STD_PUT_ITEM_AWAY
    { op = "call", target = "EventScript_RestorePrevTextColor" },
    { op = "return" },
  },
}

return Std
