#!/usr/bin/env luajit
-- #2494: moving a party mon out of the middle of the party in the PC left a
-- hole, so later slots showed as empty in battle and could not be filled.
-- pokefirered/src/pokemon.c CompactPartySlots keeps the party packed.

package.path = "./?.lua;./?/init.lua;" .. package.path

require("tests.game3_cache").stubSpeciesNames()
require("tests.fixture_data.game3_items").install()
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i) return n .. "[" .. i .. "]" end,
  at = function(n, i) return n .. "[" .. i .. "]" end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local Storage = require("src.core.game3.storage")
local BoxStorageUI = require("src.ui.game3.box_storage_ui")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function mon(species)
  return { species = species, speciesId = species, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } }
end

local function packed(party, n)
  for i = 1, n do
    if party[i] == nil then return false end
  end
  for k in pairs(party) do
    if type(k) ~= "number" or k > n then return false end
  end
  return true
end

print("[test] 1. moving slot 3 of 6 into a box closes the gap")
do
  local session = { party = { mon(1), mon(4), mon(7), mon(10), mon(13), mon(16) } }
  local party = session.party
  Storage.ensure(session)
  local ok = Storage.moveMon(session, "party", 3, "box", 1, nil, 1)
  check(ok == true, "the move succeeds")
  check(session.party == party, "the party table keeps its identity")
  check(packed(session.party, 5), "the party is packed into slots 1..5")
  check(session.party[3].species == 10 and session.party[5].species == 16,
    "later mons shift up in order")
end

print("[test] 2. placing a box mon into an empty far party slot packs it")
do
  local session = { party = { mon(1), mon(4) } }
  Storage.ensure(session)
  BoxStorageUI.show({ session = session })
  local storage = Storage.ensure(session)
  storage.boxes[1].mons[1] = mon(25)
  BoxStorageUI.mode = "party_drawer"
  BoxStorageUI.drawerOpen = true
  BoxStorageUI.holdingMon = storage.boxes[1].mons[1]
  BoxStorageUI.holdingSource = { loc = "box", boxId = 1, slot = 1 }
  BoxStorageUI.partyCursor = 6
  BoxStorageUI.handleInput({
    wasPressed = function(_, k) return k == "a" end,
    isDown = function(_, k) return k == "a" end,
  })
  check(packed(session.party, 3), "the party is packed into slots 1..3")
  check(session.party[3] and session.party[3].species == 25, "the placed mon lands in slot 3")
  check(storage.boxes[1].mons[1] == nil, "the box slot is emptied")
  BoxStorageUI.close()
end

print("[test] 3. a party already saved with a gap is repaired")
do
  local party = { mon(1), mon(4), nil, mon(10), mon(13) }
  party[3] = nil
  Storage.compactParty(party)
  check(packed(party, 4), "numeric gaps close")
  local stringy = { ["1"] = mon(1), ["2"] = mon(4), ["4"] = mon(10) }
  Storage.compactParty(stringy)
  check(packed(stringy, 3) and stringy[3].species == 10, "string-keyed slots close too")
end

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[PASS] game3_pc_party_gap_2494")
