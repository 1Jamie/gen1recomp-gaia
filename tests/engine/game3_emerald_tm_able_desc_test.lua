#!/usr/bin/env luajit
-- Test Emerald party menu TM learnability descriptions (sDescriptionStringTable indexing)
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

require("tests.game3_cache").stubSpeciesNames()
require("tests.fixture_data.game3_items").install()

-- pokeemerald/src/data/party_menu.h:629 sDescriptionStringTable
local EMERALD_DESCRIPTIONS = {
  [0] = "NO USE",
  [1] = "ABLE",
  [2] = "FIRST",
  [3] = "SECOND",
  [4] = "THIRD",
  [5] = "FOURTH",
  [6] = "ABLE",
  [7] = "NOT ABLE",
  [8] = "ABLE!",
  [9] = "NOT ABLE",
  [10] = "LEARNED",
  [11] = "HAVE",
  [12] = "DON'T HAVE",
}

package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end,
  box = function(key) return key end,
  ascii = function(key) return key end,
  has = function() return true end,
  key = function(n, i) return n .. "[" .. tostring(i) .. "]" end,
  at = function(n, i)
    if n == "sDescriptionStringTable" then return EMERALD_DESCRIPTIONS[i] end
    return n .. "[" .. tostring(i) .. "]"
  end,
  count = function() return 0 end,
  list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local ItemsData = require("src.core.game3.items_data")
local Pokemon = require("src.core.game3.pokemon")

local TM39_ROCK_TOMB = 327
local MOVE_ROCK_TOMB = 317
local GROVYLE, TAILLOW, LOTAD = 253, 276, 270

ItemsData.isTm = function(id) return id == TM39_ROCK_TOMB end
Pokemon.moveFromTmItem = function(id) return id == TM39_ROCK_TOMB and MOVE_ROCK_TOMB or nil end
Pokemon.canLearnTmItem = function(species)
  -- Grovyle can learn Rock Tomb; Taillow and Lotad cannot.
  return species == GROVYLE
end

local PartyMenu = require("src.ui.game3.party_menu")

local function mon(species, moves)
  return {
    species = species,
    speciesId = species,
    level = 15,
    hp = 40,
    maxHp = 40,
    moves = moves or { 33 },
    pp = { 35 },
  }
end

local emeraldSession = {
  version = "emerald",
  game = "emerald",
}

local party = {
  mon(TAILLOW),
  mon(GROVYLE),
  mon(LOTAD),
  mon(GROVYLE, { 33, MOVE_ROCK_TOMB }),
  { species = GROVYLE, speciesId = GROVYLE, isEgg = true, hp = 0, maxHp = 0, moves = {} },
}

PartyMenu.show(party, nil, { mode = "use", item = TM39_ROCK_TOMB, session = emeraldSession })
PartyMenu._item = TM39_ROCK_TOMB
PartyMenu.mode = "use"

check(PartyMenu.slotDescription(1) == "NOT ABLE", "Taillow (incompatible) displays NOT ABLE")
check(PartyMenu.slotDescription(2) == "ABLE!", "Grovyle (compatible) displays ABLE!")
check(PartyMenu.slotDescription(3) == "NOT ABLE", "Lotad (incompatible) displays NOT ABLE")
check(PartyMenu.slotDescription(4) == "LEARNED", "Grovyle with Rock Tomb displays LEARNED")
check(PartyMenu.slotDescription(5) == "NOT ABLE", "Egg displays NOT ABLE")

T.finish()
