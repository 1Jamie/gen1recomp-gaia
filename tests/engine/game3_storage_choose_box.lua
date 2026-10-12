package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

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

local GameVersion = require("src.core.GameVersion")
local Storage = require("src.core.game3.storage")
local BoxStorageUI = require("src.ui.game3.box_storage_ui")
local Choose = require("src.ui.game3.storage_choose_box")

local function mon(species)
  return { species = species, speciesId = species, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } }
end

local function settle()
  for _ = 1, 600 do
    if not BoxStorageUI.isPresentationBusy() then break end
    BoxStorageUI.update(1 / 60)
  end
end

local function press(key)
  settle()
  BoxStorageUI.handleInput({
    wasPressed = function(_, k) return k == key end,
    isDown = function(_, k) return k == key end,
  })
  settle()
end

local function open(version)
  GameVersion.set(version)
  local session = { version = version, party = { mon(1), mon(4), mon(7), mon(10) } }
  Storage.ensure(session)
  BoxStorageUI.show({ session = session, subMode = "deposit" })
  for _ = 1, 600 do
    if not BoxStorageUI.isPresentationBusy() then break end
    BoxStorageUI.update(1 / 60)
  end
  return session, Storage.ensure(session)
end

local function store(slot)
  BoxStorageUI.mode, BoxStorageUI.drawerOpen, BoxStorageUI.partyCursor = "party_drawer", true, slot
  press("a")
  eq(BoxStorageUI.mode, "action_menu", "A on a party mon opens its menu")
  eq((BoxStorageUI._activeActions or {})[BoxStorageUI.actionCursor], "STORE", "the cursor sits on STORE")
  press("a")
end

for _, version in ipairs({ "firered", "leafgreen", "emerald" }) do
  print("[test] " .. version)
  local session, storage = open(version)
  storage.currentBox = 5
  -- pokefirered/src/pokemon_storage_system_tasks.c:1196
  store(2)
  eq(BoxStorageUI.mode, "pick_box", version .. ": STORE asks which box")
  eq(BoxStorageUI._pickBox, 1, version .. ": the first deposit starts on BOX 1")
  eq(#session.party, 4, version .. ": nothing is stored before a box is chosen")
  press("right"); press("right")
  eq(BoxStorageUI._pickBox, 3, version .. ": right steps to BOX 3")
  press("left"); press("left"); press("left")
  eq(BoxStorageUI._pickBox, Storage.TOTAL_BOXES_COUNT, version .. ": left from BOX 1 wraps to the last box")
  press("right"); press("right"); press("right")
  press("a")
  eq(#session.party, 3, version .. ": A stores the mon")
  eq(Choose.boxCount(storage.boxes[3]), 1, version .. ": the mon went into BOX 3")
  eq(Choose.boxCount(storage.boxes[5]), 0, version .. ": the current box was not used")
  eq(BoxStorageUI.mode, "party_drawer", version .. ": the party drawer comes back")

  -- pokefirered/src/pokemon_storage_system_tasks.c:1216
  store(1)
  eq(BoxStorageUI._pickBox, 3, version .. ": the next deposit starts on the last box used")
  press("b")
  eq(BoxStorageUI.mode, "party_drawer", version .. ": B cancels the chooser")
  eq(#session.party, 3, version .. ": cancel stores nothing")

  for i = 1, 30 do storage.boxes[4].mons[i] = mon(16) end
  store(1)
  press("right")
  press("a")
  eq(BoxStorageUI.mode, "deposit_box_full", version .. ": a full box says so")
  eq(#session.party, 3, version .. ": a full box stores nothing")
  press("up")
  eq(BoxStorageUI.mode, "pick_box", version .. ": any direction returns to the chooser")
  press("b")

  -- pokefirered/src/pokemon_storage_system_tasks.c:1833
  BoxStorageUI.mode, BoxStorageUI.boxMenuCursor = "box_menu", 1
  press("a")
  eq(BoxStorageUI.mode, "pick_box", version .. ": SWITCH BOX opens the chooser")
  eq(BoxStorageUI._pickBox, 5, version .. ": the jump chooser starts on the current box")
  press("right"); press("right")
  press("a")
  eq(storage.currentBox, 7, version .. ": A jumps to the chosen box")
  BoxStorageUI.reset()
end

-- pokefirered/src/pokemon_storage_system_menu.c:642
local seen = {}
for f = 0, 23 do seen[#seen + 1] = Choose.arrowOffset(f) end
eq(table.concat(seen, ""), "000011112222333344445555", "choose-box arrows step one pixel every 4 frames for 6 steps")
eq(Choose.arrowOffset(24), 0, "the arrow bounce restarts after 24 frames")

T.finish("game3_storage_choose_box")
