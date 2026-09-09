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

-- specials.inc indices (FireRed)
Std.SPECIAL = {
  HealPlayerParty = 0x00,
  ShowPokemonStorageSystemPC = 0x3C,
  BufferMonNickname = 0x7D, -- 125
  ChangePokemonNickname = 0x9F, -- 159
  -- ShowRegionMap / Sevii town map (Tier A special → game3 region UI).
  ShowRegionMap = 0xAF,
  AnimatePcTurnOn = 0xD6,
  AnimatePcTurnOff = 0xD7,
  PlayerPC = 0xFA,
  CreatePCMenu = 0x106,
  EnterHallOfFame = 0x110, -- 272 (special HallOfFame / GameClear)
  EnableNationalPokedex = 0x179, -- 377
  SetUnlockedPokedexFlags = 0x18B, -- 395
  IsNationalPokedexEnabled = 0x19D, -- 413
  -- Engine-extension specials (not cart indices) for shared primitives.
  FadeScreen = 0xF001,
  OpenNaming = 0xF002,
  PlayCry = 0xF003,
}

Std.TEXT = {
  Text_WelcomeWantToHealPkmn = T([[
Welcome to our POKéMON CENTER!
Would you like me to rest your
POKéMON to good health?]]),
  Text_TakeYourPkmnForFewSeconds = T([[
OK. I'll take your POKéMON for a
few seconds.]]),
  Text_RestoredPkmnToFullHealth = T([[
Thank you for waiting.
We've restored your POKéMON to
full health.]]),
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
  EventScript_PC = {
    { op = "lockall" },
    { op = "special", id = Std.SPECIAL.AnimatePcTurnOn },
    { op = "loadword", dest = 0, value = "Text_BootedUpPC" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "special", id = Std.SPECIAL.CreatePCMenu },
    { op = "waitstate" },
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
  ["std:0"] = { -- STD_OBTAIN_ITEM
    { op = "additem", [1] = 0x8000, [2] = 0x8001 },
    { op = "copyvar", [1] = 0x8007, [2] = 0x800D },
    { op = "bufferitemname", dest = 1, src = 0x8000 }, -- STR_VAR_2
    { op = "checkitemtype", [1] = 0x8000 },
    { op = "call", target = "EventScript_BufferPocketName" },
    { op = "compare_var_to_value", var = 0x8007, value = 1 },
    { op = "goto_if", cond = 1, target = "EventScript_ObtainedItem" },
    { op = "setvar", var = 0x800D, value = 0 },
    { op = "return" },
  },
  EventScript_ObtainedItem = {
    { op = "loadword", dest = 0, value = "Text_ObtainedTheX" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
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
    { op = "loadword", dest = 0, value = "Text_FoundOneItem" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "loadword", dest = 0, value = "Text_PutItemAway" },
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
    { op = "setvar", var = 0x800D, value = 1 },
    { op = "return" },
  },
  ["std:6"] = { -- MSGBOX_AUTOCLOSE
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitbuttonpress" },
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
    { op = "message", ptr = 0 },
    { op = "waitmessage" },
    { op = "waitfanfare" },
    { op = "waitbuttonpress" },
    { op = "return" },
  },
}

return Std
