#!/usr/bin/env luajit
-- Comprehensive unit and integration test for:
-- 1. StepEvents Engine (lockstep queue, lethal poison, whiteout flush, repel, happiness, egg cycles, vs seeker charge)
-- 2. VS Seeker Engine (battery charge across movement modes, indoor rejection, outdoor ping, battery drain)
-- 3. TM Case & Berry Pouch Sub-Containers & Bag state persistence

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

-- Mock Love2D globals if not present
if not _G.love then
  _G.love = {
    graphics = {
      setColor = function() end,
      rectangle = function() end,
      circle = function() end,
      arc = function() end,
      draw = function() end,
      newImage = function() return { setFilter = function() end } end,
      newQuad = function() return {} end,
    },
    timer = { getTime = function() return 0 end },
    filesystem = { read = function() return nil end },
  }
end

local StepEvents = require("src.core.game3.step_events")
local VsSeeker = require("src.core.game3.vs_seeker")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local ItemUse = require("src.core.game3.item_use")
local TmCase = require("src.ui.game3.tm_case")
local BerryPouch = require("src.ui.game3.berry_pouch")
local BagMenu = require("src.ui.game3.bag_menu")
local Pokemon = require("src.core.game3.pokemon")

print("=== 1. StepEvents Engine & Lockstep Queue Tests ===")

StepEvents.flush()
check(not StepEvents.busy(), "Initial StepEvents is not busy")

local eventOrder = {}
StepEvents.queueEvent(function() table.insert(eventOrder, "first") end)
StepEvents.queueEvent(function() table.insert(eventOrder, "second") end)
check(StepEvents.busy(), "StepEvents is busy with 2 queued events")

StepEvents.update(0.1)
check(#eventOrder == 1 and eventOrder[1] == "first", "First event executed")
check(StepEvents.busy(), "StepEvents still busy with remaining event")

StepEvents.update(0.1)
check(#eventOrder == 2 and eventOrder[2] == "second", "Second event executed")
check(not StepEvents.busy(), "Queue drained, StepEvents is no longer busy")

print("=== 2. VS Seeker Battery Management across Locomotion Modes ===")

local session = {
  vsSeekerCharge = 0,
  repelSteps = 10,
  party = {
    { species = 25, nickname = "PIKACHU", hp = 20, maxHp = 20, friendship = 70 },
  },
}

-- Step counting across locomotion modes
for i = 1, 50 do
  StepEvents.onStep(session, { running = false, biking = false, surfing = false })
end
check(VsSeeker.getBattery(session) == 50, "VS Seeker charged 50 steps via walking")

for i = 1, 30 do
  StepEvents.onStep(session, { running = true, biking = false, surfing = false })
end
check(VsSeeker.getBattery(session) == 80, "VS Seeker charged +30 steps via running (total 80)")

for i = 1, 20 do
  StepEvents.onStep(session, { running = false, biking = true, surfing = false })
end
check(VsSeeker.getBattery(session) == 100, "VS Seeker reached 100 charge via biking")

-- Charging capped at 100
StepEvents.onStep(session, { running = false, biking = false, surfing = true })
check(VsSeeker.getBattery(session) == 100, "VS Seeker charge capped at 100")

print("=== 3. Repel Countdown & Single Wear-off Mechanics ===")

check(session.repelSteps == 0, "Repel wore off after 10 steps (started at 10)")
-- Verify repel queued wear off event
check(StepEvents.busy(), "Repel wear-off event queued")
local handledRepel = false
local mockHud = {
  showDialogue = function(msg, opts)
    if msg:find("Repel's effect wore off") then
      handledRepel = true
    end
    if opts and opts.onDone then opts.onDone() end
  end
}
package.loaded["src.ui.game3.hud"] = mockHud
StepEvents.update(0.1)
check(handledRepel, "Repel displayed retail 'Repel's effect wore off...' message without prompt")

print("=== 4. Happiness & Egg Cycles Mechanics ===")

local eggMon = { species = 175, nickname = "EGG", isEgg = true, eggCycles = 2 }
local partyMon = { species = 25, nickname = "PIKA", hp = 30, maxHp = 30, friendship = 100 }
session.party = { partyMon, eggMon }
StepEvents.flush()

-- Step 128 times for friendship
for i = 1, 128 do
  StepEvents.onStep(session, {})
end
check(partyMon.friendship == 101, "Party mon gained +1 friendship after 128 steps")

-- Step another 128 times (total 256 steps) for egg cycle decrement
for i = 1, 128 do
  StepEvents.onStep(session, {})
end
check(eggMon.eggCycles == 1, "Egg decremented 1 egg cycle after 256 steps")

print("=== 5. Gen 3 Lethal Poison & Whiteout Queue Flush ===")

StepEvents.flush()
local poisonedMon1 = { species = 1, nickname = "BULBA", hp = 2, maxHp = 20, status = "PSN" }
local poisonedMon2 = { species = 4, nickname = "CHAR", hp = 1, maxHp = 20, status = "PSN" }
session.party = { poisonedMon1, poisonedMon2 }

-- 4 steps trigger 1 HP poison damage
for i = 1, 4 do
  StepEvents.onStep(session, {})
end
check(poisonedMon1.hp == 1, "Poisoned mon 1 took 1 HP damage (now 1 HP)")
check(poisonedMon2.hp == 0, "Poisoned mon 2 dropped to 0 HP and fainted")

-- Process queued poison faint dialogue
local faintedMsg = false
mockHud.showDialogue = function(msg, opts)
  if msg:find("CHAR fainted") or msg:find("fainted") then
    faintedMsg = true
  end
  if opts and opts.onDone then opts.onDone() end
end
StepEvents.update(0.1)
check(faintedMsg, "Lethal poison faint event processed")

-- Next 4 steps drop last Pokémon to 0 HP -> Whiteout
for i = 1, 4 do
  StepEvents.onStep(session, {})
end
check(poisonedMon1.hp == 0, "Poisoned mon 1 dropped to 0 HP (entire party fainted)")

local whiteoutTriggered = false
session.onWhiteout = function()
  whiteoutTriggered = true
end
StepEvents.update(0.1)
check(whiteoutTriggered, "Whiteout triggered and StepEvents queue cleanly flushed")
check(not StepEvents.busy(), "StepEvents queue completely empty after whiteout")

print("=== 6. VS Seeker Outdoor Ping & Indoor Rejection ===")

VsSeeker.setBattery(session, 100)
session.map = "VIRIDIAN_FOREST" -- Invalid indoor/cave map

local indoorDenied = false
mockHud.showDialogue = function(msg, opts)
  if msg:find("can't be used here") then
    indoorDenied = true
  end
  if opts and opts.onDone then opts.onDone() end
end

local okUse = VsSeeker.use(session, nil)
check(not okUse and indoorDenied, "VS Seeker rejected in indoor/forest map")
check(VsSeeker.getBattery(session) == 100, "Battery preserved at 100 on indoor rejection")

-- Outdoor route with no trainers
session.map = "MAP_ROUTE_1"
local noResponseMsg = false
mockHud.showDialogue = function(msg, opts)
  if msg:find("no response") then
    noResponseMsg = true
  end
  if opts and opts.onDone then opts.onDone() end
end

local okOutdoor = VsSeeker.use(session, nil)
check(not okOutdoor and noResponseMsg, "Outdoor ping returned 'There is no response...'")
check(VsSeeker.getBattery(session) == 0, "Battery drained to 0 on valid outdoor radar ping")

print("=== 7. TM Case & Berry Pouch Sub-Containers & Bag State Persistence ===")

local bag = Bag.new()
Bag.add(bag, 289, 1) -- TM01
Bag.add(bag, 290, 2) -- TM02
Bag.add(bag, 139, 5) -- ORAN BERRY
Bag.add(bag, 142, 3) -- SITRUS BERRY

session.bag = bag
session.party = {
  { species = 1, nickname = "BULBASAUR", hp = 20, maxHp = 20, moves = { 33, 45 } },
}

-- TM Case listing
TmCase.show(session, bag)
check(TmCase.isOpen(), "TmCase opened")
local tmList = TmCase.list()
check(#tmList == 2, "TmCase has 2 TMs listed")
TmCase.close()
check(not TmCase.isOpen(), "TmCase closed cleanly")

-- Berry Pouch listing
BerryPouch.show(session, bag)
check(BerryPouch.isOpen(), "BerryPouch opened")
local berryList = BerryPouch.list()
check(#berryList == 2, "BerryPouch has 2 Berries listed")
BerryPouch.close()
check(not BerryPouch.isOpen(), "BerryPouch closed cleanly")

-- BagMenu sub-container transition & state preservation
BagMenu.show(session, { bag = bag })
BagMenu.pocketIdx = 2 -- KEY_ITEMS
BagMenu.cursor = 1
BagMenu.scroll = 0

-- Simulate selecting TM Case from Key Items
BagMenu.mode = "action"
BagMenu.actionCursor = 1 -- USE
local mockRow = { id = ItemsData.ITEM_TM_CASE, name = "TM CASE" }
-- Mock rows in BagMenu
BagMenu.list = function() return { mockRow } end

local mockInput = {
  wasPressed = function(self, key)
    return key == "a"
  end
}
BagMenu.handleInput(mockInput)
check(TmCase.isOpen(), "Using TM CASE from BagMenu opens TmCase UI")

-- Close TM Case and verify BagMenu state restored
TmCase.close()
check(BagMenu.pocketIdx == 2, "BagMenu pocketIdx preserved (2 = KEY_ITEMS)")
check(BagMenu.cursor == 1, "BagMenu cursor preserved")
check(BagMenu.mode == "list", "BagMenu mode returned to list")
BagMenu.close()

print(string.format("\n=========================================="))
if failed == 0 then
  print("ALL TESTS PASSED SUCCESSFULLY!")
else
  print(string.format("TESTS FAILED WITH %d ERRORS", failed))
  os.exit(1)
end
