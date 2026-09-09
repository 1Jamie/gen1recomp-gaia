-- tests/game3_doors_test.lua
-- Tests for Game3 Door audio, animations, and script opcodes (FRLG / GBA).

local Doors = require("src.core.game3.doors")
local SE = require("src.core.game3.se_ids")

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", msg or "assertion failed", tostring(expected), tostring(actual)), 2)
  end
end

local function assert_true(cond, msg)
  if not cond then
    error(msg or "expected true, got false/nil", 2)
  end
end

print("--- Running game3_doors_test ---")

-- 1. Door Sound Selection
print("[Test 1] Door sound selection per map / warp type")
assert_eq(Doors.getSoundForWarp("MAP_PALLET_TOWN", 0, 0, "MAP_POKEMON_CENTER_1F", true), Doors.SOUND_SLIDING, "PokéCenter destination -> SE_SLIDING_DOOR")
assert_eq(Doors.getSoundForWarp("FR_VIRIDIAN_CITY", 0, 0, "FR_VIRIDIAN_CITY_POKECENTER_1F", true), Doors.SOUND_SLIDING, "FR PokéCenter destination -> SE_SLIDING_DOOR")
assert_eq(Doors.getSoundForWarp("SEVII_ONE_ISLAND", 0, 0, "SEVII_ONE_ISLAND_POKECENTER", true), Doors.SOUND_SLIDING, "Sevii PokéCenter destination -> SE_SLIDING_DOOR")
assert_eq(Doors.getSoundForWarp("FR_VIRIDIAN_CITY", 0, 0, "FR_VIRIDIAN_CITY_MART", true), Doors.SOUND_SLIDING, "FR Mart destination -> SE_SLIDING_DOOR")
assert_eq(Doors.getSoundForWarp("MAP_CELADON_CITY", 0, 0, "MAP_CELADON_CITY_DEPT_STORE_1F", true), Doors.SOUND_SLIDING, "Dept Store destination -> SE_SLIDING_DOOR")
assert_eq(Doors.getSoundForWarp("MAP_SAFFRON_CITY", 0, 0, "MAP_SILPH_CO_1F", true), Doors.SOUND_SLIDING, "Silph Co destination -> SE_SLIDING_DOOR")
assert_eq(Doors.getSoundForWarp("MAP_SILPH_CO_1F", 0, 0, "MAP_SILPH_CO_ELEVATOR", true), Doors.SOUND_SLIDING, "Elevator destination -> SE_SLIDING_DOOR")
assert_eq(Doors.getSoundForWarp("MAP_FUCHSIA_CITY", 0, 0, "MAP_SAFARI_ZONE_CENTER", true), Doors.SOUND_SLIDING, "Safari Zone destination -> SE_SLIDING_DOOR")
assert_eq(Doors.getSoundForWarp("MAP_CELADON_CITY", 0, 0, "MAP_CELADON_CITY_GAME_CORNER", true), Doors.SOUND_SLIDING, "Game Corner destination -> SE_SLIDING_DOOR")

-- Normal doors
assert_eq(Doors.getSoundForWarp("MAP_PALLET_TOWN", 0, 0, "MAP_PALLET_TOWN_PLAYERS_HOUSE_1F", true), Doors.SOUND_NORMAL, "Player house -> SE_DOOR")
assert_eq(Doors.getSoundForWarp("MAP_PALLET_TOWN", 0, 0, "MAP_PALLET_TOWN_PROFESSOR_OAKS_LAB", true), Doors.SOUND_NORMAL, "Oak lab -> SE_DOOR")
assert_eq(Doors.getSoundForWarp("MAP_CERULEAN_CITY", 0, 0, "MAP_CERULEAN_CITY_GYM", true), Doors.SOUND_NORMAL, "Gym -> SE_DOOR")

-- Non-door warps (stairs / carpet exits)
assert_eq(Doors.getSoundForWarp("MAP_PALLET_TOWN_PLAYERS_HOUSE_1F", 0, 0, "MAP_PALLET_TOWN_PLAYERS_HOUSE_2F", false), Doors.SOUND_EXIT, "Stairs -> SE_EXIT")
assert_eq(Doors.getSoundForWarp("MAP_VIRIDIAN_FOREST", 0, 0, "MAP_ROUTE2", false), Doors.SOUND_EXIT, "Exit mat -> SE_EXIT")

-- 2. Open Door State Machine
print("[Test 2] Door opening state machine")
Doors.reset()
assert_eq(Doors.isBusy(), false, "Initially not busy")

local doneOpen = false
local anim = Doors.open("MAP_PALLET_TOWN", 5, 8, { playSound = false }, function()
  doneOpen = true
end)

assert_true(anim ~= nil, "Active animation created")
assert_eq(Doors.isBusy(), true, "Doors is busy during opening")
assert_eq(anim.frame, 0, "Starts at frame 0")
assert_eq(anim.mode, "open", "Mode is open")

-- Tick through frames
for tick = 1, Doors.FRAME_TICKS do
  Doors.update()
end
assert_eq(anim.frame, 1, "Advanced to frame 1 after FRAME_TICKS")

for tick = 1, Doors.FRAME_TICKS do
  Doors.update()
end
assert_eq(anim.frame, 2, "Advanced to frame 2 (fully open)")

for tick = 1, Doors.FRAME_TICKS do
  Doors.update()
end
assert_eq(doneOpen, true, "onDone callback invoked")
assert_eq(Doors.isBusy(), false, "Doors no longer busy after completion")

-- 3. Close Door State Machine
print("[Test 3] Door closing state machine")
Doors.reset()
local doneClose = false
local closeAnim = Doors.close("MAP_PALLET_TOWN", 5, 8, { playSound = false }, function()
  doneClose = true
end)

assert_true(closeAnim ~= nil, "Active close animation created")
assert_eq(closeAnim.frame, 2, "Starts at frame 2")
assert_eq(closeAnim.mode, "close", "Mode is close")

for tick = 1, Doors.FRAME_TICKS do
  Doors.update()
end
assert_eq(closeAnim.frame, 1, "Advanced to frame 1")

for tick = 1, Doors.FRAME_TICKS do
  Doors.update()
end
assert_eq(closeAnim.frame, 0, "Advanced to frame 0")

for tick = 1, Doors.FRAME_TICKS do
  Doors.update()
end
assert_eq(doneClose, true, "Close onDone callback invoked")
assert_eq(Doors.isBusy(), false, "Doors no longer busy")

-- 4. Drawing & Love stub safety
print("[Test 4] Door drawing overlay")
Doors.open("MAP_VIRIDIAN_CITY", 10, 12, { destMap = "MAP_POKEMON_CENTER_1F", playSound = false })
-- Step to frame 1
for tick = 1, Doors.FRAME_TICKS do Doors.update() end
local ok, err = pcall(function()
  Doors.draw(0, 0)
end)
assert_true(ok, "Doors.draw runs cleanly: " .. tostring(err))
Doors.reset()

-- 5. Hold Open & Delay Close State Machine
print("[Test 5] Hold open and delay close")
Doors.holdOpen("FR_VIRIDIAN_CITY", 13, 19, { destMap = "FR_VIRIDIAN_CITY_POKECENTER_1F" })
assert_eq(Doors.isOpen("FR_VIRIDIAN_CITY", 13, 19), true, "Door is held open at frame 2")
assert_eq(Doors.isBusy(), false, "Door is not busy while held open")

local doneDelayClose = false
Doors.closeAfterDelay("FR_VIRIDIAN_CITY", 13, 19, 10, { playSound = false }, function()
  doneDelayClose = true
end)
assert_eq(Doors.isBusy(), true, "Door is busy during delay close")

-- Tick 10 delay frames
for tick = 1, 10 do
  Doors.update()
end
-- Now in close mode, tick through 3 frame steps (2->1, 1->0, 0->done)
for tick = 1, Doors.FRAME_TICKS do Doors.update() end
assert_eq(Doors.isOpen("FR_VIRIDIAN_CITY", 13, 19), false, "Door has left frame 2")
for tick = 1, Doors.FRAME_TICKS do Doors.update() end
assert_eq(Doors.isOpen("FR_VIRIDIAN_CITY", 13, 19), false, "Door is at frame 0")
for tick = 1, Doors.FRAME_TICKS do Doors.update() end
assert_eq(doneDelayClose, true, "Delay close onDone callback invoked")
assert_eq(Doors.isBusy(), false, "Door is no longer busy")

-- 6. Player Visibility and Step Into Door
print("[Test 6] Player visibility")
local Player = require("src.core.game3.player")
Player.setVisible(true)
assert_eq(Player.isVisible(), true, "Player initially visible")
Player.setVisible(false)
assert_eq(Player.isVisible(), false, "Player hidden when setVisible(false)")
Player.setVisible(true)
assert_eq(Player.isVisible(), true, "Player visible again")

-- 7. Warp API functions
print("[Test 7] Warp door APIs")
local Warp = require("src.core.game3.warp")
assert_true(type(Warp.startDoorEntrance) == "function", "Warp.startDoorEntrance is function")
assert_true(type(Warp.startDoorExit) == "function", "Warp.startDoorExit is function")

-- 8. Warp Metatile Behavior Validation
print("[Test 8] Warp metatile behavior validation")
local Collision = require("src.core.game3.collision")
Collision.clear()
-- Mock mapDef with grid: cell (7, 8) is warp carpet (0x72), (6, 8) and (8, 8) are normal floor (0x00)
local mockMapDef = {
  width = 16,
  height = 10,
  warps = {
    { x = 6, y = 8, destMap = "MAP_TOWN", destWarp = 1 },
    { x = 7, y = 8, destMap = "MAP_TOWN", destWarp = 1 },
    { x = 8, y = 8, destMap = "MAP_TOWN", destWarp = 1 },
  }
}
Collision._widthCells = 16
Collision._heightCells = 10
Collision._grid = {}
for i = 1, 16 * 10 do Collision._grid[i] = 0x00 end
-- Set center carpet to 0x72 (MB_SOUTH_ARROW_WARP)
Collision._grid[8 * 16 + 7 + 1] = 0x72

Collision.installWarps(mockMapDef)
assert_eq(Collision.warpAt(6, 8), nil, "Non-warp floor tile (6, 8) is NOT registered as a warp")
assert_true(Collision.warpAt(7, 8) ~= nil, "Carpet warp tile (7, 8) IS registered as a warp")
assert_eq(Collision.warpAt(8, 8), nil, "Non-warp floor tile (8, 8) is NOT registered as a warp")

-- 9. Specialized Warp APIs (Escalators, Teleporters, Fall Holes, Double Doors)
print("[Test 9] Specialized warp APIs and double sliding doors")
assert_true(type(Warp.startEscalator) == "function", "Warp.startEscalator is function")
assert_true(type(Warp.startTeleport) == "function", "Warp.startTeleport is function")
assert_true(type(Warp.startFall) == "function", "Warp.startFall is function")

local snd, kind = Doors.getSoundForWarp("MAP_CELADON_CITY", 0, 0, "MAP_CELADON_CITY_DEPT_STORE_1F", true)
assert_eq(kind, "sliding_double", "Dept store has sliding_double door kind")
Doors.open("MAP_CELADON_CITY", 10, 10, { destMap = "MAP_CELADON_CITY_DEPT_STORE_1F", playSound = false })
for tick = 1, Doors.FRAME_TICKS do Doors.update() end
local ok, err = pcall(function() Doors.draw(0, 0) end)
assert_true(ok, "Double sliding door draw runs cleanly: " .. tostring(err))
Doors.reset()

-- 10. Escalator Warp Handling and Detection
print("[Test 10] Escalator warp detection and flow")
Collision.clear()
local mockPcMapDef = {
  width = 16,
  height = 10,
  warps = {
    { x = 1, y = 6, destMap = "POKECENTER_2F", destWarp = 1 },
  }
}
Collision._mapId = "VIRIDIAN_CITY_POKEMON_CENTER_1F"
Collision._widthCells = 16
Collision._heightCells = 10
Collision._grid = {}
for i = 1, 16 * 10 do Collision._grid[i] = 0x00 end
Collision._grid[6 * 16 + 1 + 1] = 0x77 -- MB_ESCALATOR_WARP

Collision.installWarps(mockPcMapDef)

local escWarp = Collision.isEscalatorWarp(nil, 1, 6, "left")
assert_true(escWarp ~= nil, "Escalator warp recognized at (1, 6)")
assert_eq(escWarp.destMap, "POKECENTER_2F", "Escalator destination is POKECENTER_2F")
assert_eq(escWarp.escDir, "up", "Escalator direction is up")

-- Non-escalator tile should return nil
assert_eq(Collision.isEscalatorWarp(nil, 2, 6, "left"), nil, "Floor tile (2, 6) is not an escalator warp")

-- Test moving into escalator from adjacent cell
Player.reset(2, 6, "left")
Warp._busy = false
local moveResult = Player.tryMove("left", nil, false)
assert_eq(moveResult, "escalator", "Moving left into escalator at (1, 6) triggers escalator warp flow")
assert_true(Warp.isBusy(), "Warp is busy during escalator flow")
Warp.clear()

-- 11. SpecialFieldAnim (pokefirered special_field_anim.c metatile cycling)
print("[Test 11] SpecialFieldAnim escalator metatile animation")
local SpecialAnim = require("src.core.game3.special_field_anim")
local LayoutNative = require("src.core.game3.layout_native")
local cells = {}
for i = 1, 160 do cells[i] = { mid = 0x2D0, coll = 0x00, elev = 0 } end -- BottomNextRail_Normal (0x2D0)
local mockLayout = LayoutNative.fromDecoded({ width = 16, height = 10, cells = cells }, "VIRIDIAN_CITY_POKEMON_CENTER_1F")

-- Test UP animation cycling (0x2D0 -> 0x30A -> 0x308 -> 0x2D0)
SpecialAnim.startEscalator(mockLayout, 1, 6, true)
assert_true(SpecialAnim.isActive(), "Escalator animation is active")
assert_true(SpecialAnim.isEscalatorMoving(), "Escalator moving is active")

-- Initial tick in startEscalator executes state 0: BottomNextRail transitions 0x2D0 -> 0x30A
local midStage1 = mockLayout:midAt(0, 5)
assert_eq(midStage1, 0x30A, "Going UP initial tick transitioned to Transition1 (0x30A)")

-- Next 8 ticks: advances through states 1..7, 0 -> 0x30A -> 0x308 (Transition2)
for tick = 1, 8 do SpecialAnim.update() end
local midStage2 = mockLayout:midAt(0, 5)
assert_eq(midStage2, 0x308, "Going UP cycle 1 transitioned to Transition2 (0x308)")

-- Next 8 ticks: wraps back to 0x2D0 (Normal)
for tick = 1, 8 do SpecialAnim.update() end
local midStage3 = mockLayout:midAt(0, 5)
assert_eq(midStage3, 0x2D0, "Going UP cycle 2 wrapped back to Normal (0x2D0)")

SpecialAnim.stopEscalator()
assert_eq(SpecialAnim.isActive(), false, "Escalator stopped")
assert_eq(SpecialAnim.isEscalatorMoving(), false, "Escalator stopped and restored")

-- Test DOWN animation cycling (0x2D0 -> 0x308 -> 0x30A -> 0x2D0)
SpecialAnim.startEscalator(mockLayout, 1, 6, false)
-- Initial tick in startEscalator executes state 0: BottomNextRail transitions 0x2D0 -> 0x308
local midDown1 = mockLayout:midAt(0, 5)
assert_eq(midDown1, 0x308, "Going DOWN initial tick transitioned to Transition2 (0x308)")

for tick = 1, 8 do SpecialAnim.update() end
local midDown2 = mockLayout:midAt(0, 5)
assert_eq(midDown2, 0x30A, "Going DOWN cycle 1 transitioned to Transition1 (0x30A)")

for tick = 1, 8 do SpecialAnim.update() end
local midDown3 = mockLayout:midAt(0, 5)
assert_eq(midDown3, 0x2D0, "Going DOWN cycle 2 wrapped back to Normal (0x2D0)")

SpecialAnim.stopEscalator()
assert_eq(SpecialAnim.isActive(), false, "Escalator DOWN stopped and restored")

-- Check Warp.isEscalatorActive API
assert_eq(Warp.isEscalatorActive(), false, "Warp.isEscalatorActive is false when idle")

-- 12. ROM-Derived Door Manifest & Graphics
print("[Test 12] Door manifest and authentic FRLG metatile mappings")
local manifest = require("data.generated.gba.doors.manifest")
assert_true(manifest ~= nil, "Door manifest loaded")
assert_true(manifest.doors ~= nil, "Manifest has doors table")
assert_true(manifest.by_mid ~= nil, "Manifest has by_mid table")

-- Check specific authentic doors
assert_eq(manifest.doors["Pallet"].file, "pallet.rgba", "Pallet sheet filename")
assert_eq(manifest.doors["Pallet"].frame_height, 16, "Pallet 1x1 door frame height")
assert_eq(manifest.doors["DeptStoreElevator"].frame_height, 32, "Elevator 1x2 door frame height")
assert_eq(manifest.doors["CableClub"].frame_height, 32, "Cable club 1x2 door frame height")

-- Check metatile mappings
assert_eq(manifest.by_mid[0x2a3].tile, "Pallet", "Metatile 0x2A3 -> Pallet door")
assert_eq(manifest.by_mid[0x2ac].tile, "OaksLab", "Metatile 0x2AC -> OaksLab door")
assert_eq(manifest.by_mid[0x299].tile, "Viridian", "Metatile 0x299 -> Viridian door")
assert_eq(manifest.by_mid[0x28d].tile, "DeptStoreElevator", "Metatile 0x28D -> DeptStoreElevator door")
assert_eq(manifest.by_mid[0x28d].sound, "sliding", "DeptStoreElevator sound is sliding")

-- Test open door animation with tile metadata
Doors.reset()
local oakAnim = Doors.open("MAP_PALLET_TOWN", 12, 8, { sound = Doors.SOUND_NORMAL, playSound = false })
assert_true(oakAnim ~= nil, "Oak lab door anim created")
assert_true(oakAnim.tile ~= nil, "Anim has tile name assigned")
Doors.reset()

print("--- All game3_doors_test PASSED! ---")
