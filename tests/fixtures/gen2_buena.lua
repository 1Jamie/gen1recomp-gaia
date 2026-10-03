-- pokecrystal/data/radio/buenas_passwords.asm:1
local metadata = {
  stationName = "BUENA'S PASSWORD",
  categories = {
    { kind = "mon", width = 10, words = { "CYNDAQUIL", "TOTODILE", "CHIKORITA" } },
    { kind = "item", width = 12, words = { "FRESH_WATER", "SODA_POP", "LEMONADE" } },
    { kind = "item", width = 12, words = { "POTION", "ANTIDOTE", "PARLYZ_HEAL" } },
    { kind = "item", width = 12, words = { "POKE_BALL", "GREAT_BALL", "ULTRA_BALL" } },
    { kind = "mon", width = 10, words = { "PIKACHU", "RATTATA", "GEODUDE" } },
    { kind = "mon", width = 10, words = { "HOOTHOOT", "SPINARAK", "DROWZEE" } },
    { kind = "string", width = 16, words = { "NEW BARK TOWN", "CHERRYGROVE CITY", "AZALEA TOWN" } },
    { kind = "string", width = 6, words = { "FLYING", "BUG", "GRASS" } },
    { kind = "move", width = 12, words = { "TACKLE", "GROWL", "MUD_SLAP" } },
    { kind = "item", width = 12, words = { "X_ATTACK", "X_DEFEND", "X_SPEED" } },
    { kind = "string", width = 13, words = { "POKéMON Talk", "POKéMON Music", "Lucky Channel" } },
  },
}
local text = {
  ["_BuenaRadioText1"] = "\nBUENA: BUENA here!{DONE}",
  ["_BuenaRadioText2"] = "\nToday's password!{DONE}",
  ["_BuenaRadioText3"] = "\nLet me think… It's{DONE}",
  ["_BuenaRadioText4"] = "\n{STRBUF}!{DONE}",
  ["_BuenaRadioText5"] = "\nDon't forget it!{DONE}",
  ["_BuenaRadioText6"] = "\nI'm in GOLDENROD's{DONE}",
  ["_BuenaRadioText7"] = "\nRADIO TOWER!{DONE}",
  ["_BuenaRadioMidnightText1"] = "\nBUENA: Oh my…{DONE}",
  ["_BuenaRadioMidnightText2"] = "\nIt's midnight! I{DONE}",
  ["_BuenaRadioMidnightText3"] = "\nhave to shut down!{DONE}",
  ["_BuenaRadioMidnightText4"] = "\nThanks for tuning{DONE}",
  ["_BuenaRadioMidnightText5"] = "\nin to the end! But{DONE}",
  ["_BuenaRadioMidnightText6"] = "\ndon't stay up too{DONE}",
  ["_BuenaRadioMidnightText7"] = "\nlate! Presented to{DONE}",
  ["_BuenaRadioMidnightText8"] = "\nyou by DJ BUENA!{DONE}",
  ["_BuenaRadioMidnightText9"] = "\nI'm outta here!{DONE}",
  ["_BuenaRadioMidnightText10"] = "\n…{DONE}",
  ["_BuenaOffTheAirText"] = "\n{DONE}",
}
return { gen2EventTables = { buenaPassword = metadata }, text = text }
