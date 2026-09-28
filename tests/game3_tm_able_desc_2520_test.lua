#!/usr/bin/env luajit
-- #2520: choosing a TM/HM from the bag opens the party menu without the
-- ABLE! / NOT ABLE! / LEARNED labels on each slot.
-- pokefirered/src/party_menu.c:856 DisplayPartyPokemonDataForMoveTutorOrEvolutionItem
-- -> DisplayPartyPokemonDataToTeachMove.

package.path = "./?.lua;./?/init.lua;" .. package.path

require("tests.game3_cache").stubSpeciesNames()
require("tests.fixture_data.game3_items").install()

-- pokefirered/src/data/party_menu.h:634 sDescriptionStringTable
local DESCRIPTIONS = { [0] = "NO USE", "ABLE", "FIRST", "SECOND", "THIRD", "ABLE",
  "NOT ABLE", "ABLE!", "NOT ABLE!", "LEARNED" }
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i) return n .. "[" .. tostring(i) .. "]" end,
  at = function(n, i)
    if n == "sDescriptionStringTable" then return DESCRIPTIONS[i] end
    return n .. "[" .. tostring(i) .. "]"
  end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local ItemsData = require("src.core.game3.items_data")
local Pokemon = require("src.core.game3.pokemon")

local TM06, TOXIC = 294, 92
local BULBASAUR, CHARMANDER, GEODUDE = 1, 4, 74

ItemsData.isTm = function(id) return id == TM06 end
Pokemon.moveFromTmItem = function(id) return id == TM06 and TOXIC or nil end
Pokemon.canLearnTmItem = function(species) return species ~= CHARMANDER end

local PartyMenu = require("src.ui.game3.party_menu")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function mon(species, moves)
  return { species = species, speciesId = species, level = 10, hp = 20, maxHp = 20,
    moves = moves or { 33 }, pp = { 35 } }
end

local party = {
  mon(BULBASAUR),
  mon(CHARMANDER),
  mon(GEODUDE, { 33, TOXIC }),
  { species = BULBASAUR, speciesId = BULBASAUR, isEgg = true, hp = 0, maxHp = 0, moves = {} },
}
PartyMenu.show(party, nil, { mode = "use", item = TM06 })
PartyMenu._item = TM06
PartyMenu.mode = "use"

check(PartyMenu.slotDescription(1) == "ABLE!",
  "a compatible mon reads ABLE!, got " .. tostring(PartyMenu.slotDescription(1)))
check(PartyMenu.slotDescription(2) == "NOT ABLE!",
  "an incompatible mon reads NOT ABLE!, got " .. tostring(PartyMenu.slotDescription(2)))
check(PartyMenu.slotDescription(3) == "LEARNED",
  "a mon that knows the move reads LEARNED, got " .. tostring(PartyMenu.slotDescription(3)))
check(PartyMenu.slotDescription(4) == "NOT ABLE!",
  "an egg reads NOT ABLE!, got " .. tostring(PartyMenu.slotDescription(4)))

PartyMenu._item = 13 -- a Potion: no label
check(PartyMenu.slotDescription(1) == nil, "a non-TM item shows no label")

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[PASS] game3_tm_able_desc_2520")
