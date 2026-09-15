-- Test suite for FireRed Map Name Popup overlay & extraction

local MapSectionsExtract = require("src.import.gba.map_sections_extract")
local MapNamePopup = require("src.ui.game3.map_name_popup")

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("Assertion failed: %s (expected %s, got %s)", tostring(msg), tostring(expected), tostring(actual)))
  end
end

local function assert_true(cond, msg)
  if not cond then
    error(string.format("Assertion failed: %s (expected true)", tostring(msg)))
  end
end

local function assert_false(cond, msg)
  if cond then
    error(string.format("Assertion failed: %s (expected false)", tostring(msg)))
  end
end

print("=== Running Game3 Map Name Popup Tests ===")

-- 1. Section extraction and lookup tests
do
  local pallet = MapSectionsExtract.getInfo(88, "FR_PALLET_TOWN", 0)
  assert_eq(pallet.name, "PALLET TOWN", "Pallet Town name")
  assert_eq(pallet.theme, "marble", "Pallet Town theme")

  local viridianForest = MapSectionsExtract.getInfo(126, "FR_VIRIDIAN_FOREST", 0)
  assert_eq(viridianForest.name, "VIRIDIAN FOREST", "Viridian Forest name")
  assert_eq(viridianForest.theme, "wood", "Viridian Forest theme is wood")

  local mtMoon = MapSectionsExtract.getInfo(127, "FR_MT_MOON", 0)
  assert_eq(mtMoon.name, "MT. MOON", "Mt Moon name")
  assert_eq(mtMoon.theme, "stone", "Mt Moon theme is stone")

  local celadon = MapSectionsExtract.getInfo(94, "FR_CELADON_CITY", 0)
  assert_eq(celadon.name, "CELADON CITY", "Celadon City name")
  assert_eq(celadon.theme, "brick", "Celadon City theme is brick")

  -- Celadon Dept Store override rule
  local dept1F = MapSectionsExtract.getInfo(94, "FR_CELADON_CITY_DEPARTMENT_STORE_1F", 1)
  assert_eq(dept1F.name, "CELADON DEPT. 1F", "Celadon Dept Store 1F name override")
  assert_eq(dept1F.theme, "brick", "Celadon Dept Store theme is brick")

  local deptRoof = MapSectionsExtract.getInfo(94, "FR_CELADON_CITY_DEPARTMENT_STORE_ROOF", 127)
  assert_eq(deptRoof.name, "CELADON DEPT. ROOFTOP", "Celadon Dept Store Rooftop override")

  local caveB1F = MapSectionsExtract.getInfo(141, "FR_CERULEAN_CAVE_B1F", -1)
  assert_eq(caveB1F.name, "CERULEAN CAVE B1F", "Cerulean Cave B1F format")
  assert_eq(caveB1F.theme, "stone", "Cerulean Cave theme is stone")

  print("✓ Section name & theme lookups verified.")
end

-- 2. Strict Indoor Suppression tests
do
  MapNamePopup.dismiss()
  assert_false(MapNamePopup.isActive(), "Popup initially inactive")

  -- Map with showMapName == 0 (indoor lab / house)
  local indoorMap = {
    id = "FR_PLAYERS_HOUSE_1F",
    regionMapSectionId = 88,
    showMapName = 0,
    floorNum = 0,
  }
  local shown = MapNamePopup.show(indoorMap)
  assert_false(shown, "Indoor map with showMapName=0 must be rejected")
  assert_false(MapNamePopup.isActive(), "Popup must remain inactive for showMapName=0")

  -- Outdoor map with showMapName == 1
  local outdoorMap = {
    id = "FR_PALLET_TOWN",
    regionMapSectionId = 88,
    showMapName = 1,
    floorNum = 0,
  }
  shown = MapNamePopup.show(outdoorMap)
  assert_true(shown, "Outdoor map with showMapName=1 must be accepted")
  assert_true(MapNamePopup.isActive(), "Popup must become active")
  assert_eq(MapNamePopup._name, "PALLET TOWN", "Popup name set to PALLET TOWN")
  assert_eq(MapNamePopup._theme, "marble", "Popup theme set to marble")

  print("✓ Strict indoor suppression verified.")
end

-- 3. State Machine & Coordinate Translation tests
do
  MapNamePopup.dismiss()

  local route1 = {
    id = "FR_ROUTE_1",
    regionMapSectionId = 101,
    showMapName = 1,
    floorNum = 0,
  }
  MapNamePopup.show(route1)
  assert_eq(MapNamePopup._state, MapNamePopup.STATE.SLIDE_IN, "State is SLIDE_IN")
  assert_eq(MapNamePopup._tPos, 0, "Initial tPos is 0 (py = -24)")

  -- Tick 6 frames (halfway slid down)
  for _ = 1, 6 do
    MapNamePopup.update(1 / 60)
  end
  assert_eq(MapNamePopup._tPos, 12, "tPos is 12 after 6 frames (2px/frame)")
  assert_eq(MapNamePopup._state, MapNamePopup.STATE.SLIDE_IN, "State still SLIDE_IN")

  -- Tick 6 more frames (fully down)
  for _ = 1, 6 do
    MapNamePopup.update(1 / 60)
  end
  assert_eq(MapNamePopup._tPos, 24, "tPos is 24 after 12 frames (py = 0, fully extended)")
  assert_eq(MapNamePopup._state, MapNamePopup.STATE.HOLD, "State transitions to HOLD")
  assert_eq(MapNamePopup._timer, 0, "Hold timer starts at 0")

  -- Tick 60 frames (1 second of hold)
  for _ = 1, 60 do
    MapNamePopup.update(1 / 60)
  end
  assert_eq(MapNamePopup._timer, 60, "Hold timer at 60 frames")
  assert_eq(MapNamePopup._state, MapNamePopup.STATE.HOLD, "Still in HOLD state")
  assert_eq(MapNamePopup._tPos, 24, "tPos stays 24 during HOLD")

  -- Tick remaining 60 frames of hold
  for _ = 1, 60 do
    MapNamePopup.update(1 / 60)
  end
  assert_eq(MapNamePopup._state, MapNamePopup.STATE.SLIDE_OUT, "State transitions to SLIDE_OUT after 120 frames")

  -- Tick 6 frames of slide out
  for _ = 1, 6 do
    MapNamePopup.update(1 / 60)
  end
  assert_eq(MapNamePopup._tPos, 12, "tPos decrements by 2px/frame to 12")

  -- Tick remaining 6 frames of slide out
  for _ = 1, 6 do
    MapNamePopup.update(1 / 60)
  end
  assert_eq(MapNamePopup._tPos, 0, "tPos reaches 0")
  assert_eq(MapNamePopup._state, MapNamePopup.STATE.IDLE, "State becomes IDLE")
  assert_false(MapNamePopup.isActive(), "Popup is inactive when finished")

  print("✓ State machine timings and 2px/frame coordinate translation verified.")
end

-- 4. Reshow interrupting slide out test
do
  MapNamePopup.dismiss()
  local route1 = { id = "FR_ROUTE_1", regionMapSectionId = 101, showMapName = 1, floorNum = 0 }
  MapNamePopup.show(route1)

  -- Fast-forward to SLIDE_OUT
  for _ = 1, 132 do
    MapNamePopup.update(1 / 60)
  end
  assert_eq(MapNamePopup._state, MapNamePopup.STATE.SLIDE_OUT, "State is SLIDE_OUT")

  -- Enter Viridian Forest while sliding out
  local forest = { id = "FR_VIRIDIAN_FOREST", regionMapSectionId = 126, showMapName = 1, floorNum = 0 }
  MapNamePopup.show(forest)
  assert_true(MapNamePopup._reshow, "Reshow flag set")

  -- Finish slide out -> should immediately restart with Viridian Forest (wood theme)
  while MapNamePopup._state == MapNamePopup.STATE.SLIDE_OUT do
    MapNamePopup.update(1 / 60)
  end

  assert_eq(MapNamePopup._state, MapNamePopup.STATE.SLIDE_IN, "Reshow transitions to SLIDE_IN")
  assert_eq(MapNamePopup._name, "VIRIDIAN FOREST", "Name updated to VIRIDIAN FOREST")
  assert_eq(MapNamePopup._theme, "wood", "Theme updated to wood")

  print("✓ Reshow interruption and theme transition verified.")
end

-- 5. Dismiss test
do
  local route1 = { id = "FR_ROUTE_1", regionMapSectionId = 101, showMapName = 1, floorNum = 0 }
  MapNamePopup.show(route1)
  assert_true(MapNamePopup.isActive(), "Popup active")

  MapNamePopup.dismiss()
  assert_false(MapNamePopup.isActive(), "Popup dismissed immediately")
  assert_eq(MapNamePopup._state, MapNamePopup.STATE.IDLE, "State reset to IDLE")

  print("✓ Dismissal logic verified.")
end

print("\nALL GAME3 MAP NAME POPUP TESTS PASSED SUCCESSFULLY!")
