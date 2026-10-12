local Identity = require("src.online.xgen.Identity")
local Strings = require("src.core.Strings")

local Board = {}

Board.TYPE_ID = Identity.GEN3_TYPE_ID
Board.TYPE_NAME = Identity.GEN3_TYPES

-- pokefirered/src/union_room_message.c:430
Board.S = {
  welcome = Strings.source("Welcome to the\nTRADING BOARD.\fYou may register\nyour POKéMON and\voffer it up for\va trade.\fWould you like to\nregister one of\vyour POKéMON?"),
  info = Strings.source("This TRADING BOARD\nis used for\voffering a POKéMON\vfor a trade.\fAll you need to do\nis register a\vPOKéMON for a\vtrade.\fAnother TRAINER\nmay offer a party\vPOKéMON in return\vfor the trade."),
  whichMon = Strings.source("Which of your\nparty POKéMON will\vyou offer in\vtrade?"),
  chooseType = Strings.source("Please choose the\ntype of POKéMON\vthat you would\vlike in the trade."),
  canceled = Strings.source("Registration has\nbeen canceled."),
  completed = Strings.source("Registration has\nbeen completed."),
  cancelReg = Strings.source("Cancel the\nregistration of\vyour Lv.%s %s?"),
  canceled2 = Strings.source("The registration\nhas been canceled."),
  checked = Strings.source("%s checked the\nTRADING BOARD."),
  noType = Strings.source("You don't have a\n%s-type POKéMON\vthat %s wants."),
  askTrade = Strings.source("Would you like to\nask %s to\vmake a trade?"),
}

-- pokefirered/src/union_room.c:3347
function Board.entry(national, level, typeName)
  local want = Board.TYPE_ID[typeName or ""]
  national, level = tonumber(national), tonumber(level)
  if not (national and level and want) then return nil end
  return { species = national, level = level, wantType = want }
end

-- pokefirered/src/union_room.c:4400
function Board.offers(room, dexMax)
  local out = {}
  for _, p in ipairs(room and room:members() or {}) do
    local b = type(p.board) == "table" and p.board or nil
    local species = b and tonumber(b.species)
    if species and species >= 1 and species <= (dexMax or 0) and p.online ~= false then
      local want = tonumber(b.wantType) or -1
      out[#out + 1] = { p = p, species = species, level = tonumber(b.level) or 0,
                        wantType = want, typeName = Board.TYPE_NAME[want] }
    end
  end
  return out
end

function Board.isEgg(mon)
  return type(mon) == "table" and mon.isEgg == true
end

function Board.national(data, mon)
  local def = data and data.pokemon and mon and data.pokemon[mon.species]
  return def and tonumber(def.dex) or nil
end

function Board.speciesName(data, national)
  for _, def in pairs(data and data.pokemon or {}) do
    if type(def) == "table" and tonumber(def.dex) == national then return def.name end
  end
  return "?"
end

function Board.monTypes(data, mon, gen)
  local out = {}
  if Board.isEgg(mon) then return out end
  local def = data and data.pokemon and mon and data.pokemon[mon.species]
  for _, t in ipairs(def and def.types or {}) do
    local name = Identity.canonType(t, gen)
    if name then out[#out + 1] = name end
  end
  return out
end

function Board.partyTypes(data, party, gen)
  local out = {}
  for _, mon in ipairs(party or {}) do out[#out + 1] = Board.monTypes(data, mon, gen) end
  return out
end

function Board.typeLabel(data, name, gen)
  local TypeChart = require("src.battle.TypeChart")
  for key in pairs(data and data.type_chart and data.type_chart.types or {}) do
    if Identity.canonType(key, gen) == name then return TypeChart.displayName(key, data) end
  end
  return name or "?"
end

function Board.types(gen)
  return gen == 1 and Identity.GEN1_TYPES or Identity.TYPES
end

-- pokefirered/src/union_room.c:4422
function Board.hasType(typeLists, typeName)
  if not typeName then return false end
  for _, list in ipairs(typeLists or {}) do
    for _, t in ipairs(list) do
      if t == typeName then return true end
    end
  end
  return false
end

return Board
