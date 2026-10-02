local FieldView = require("src.core.game3.field_view")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")

print("[test] 1. Software subpriority sorting & painter's algorithm")
do
  -- In painter's algorithm, actors are sorted descending by subpriority:
  -- higher subpriority = drawn first (behind/underneath).
  -- lower subpriority = drawn last (in front/on top).
  local actors = {
    { i = 1, y = 100, elevation = 3, eventObject = { subpriority = 115, fixedPriority = false } },
    { i = 2, y = 100, elevation = 3, eventObject = { subpriority = 83, fixedPriority = true } }, -- Briney (0+83)
    { i = 3, y = 100, elevation = 3, eventObject = { subpriority = 84, fixedPriority = true } }, -- Player (1+83)
  }

  local under, over = FieldView.applyDrawOrder(actors, {}, {}, 0)
  -- Expected order in under/over:
  -- actor 1 (subpriority calculated from dynamic y/base: e.g. 115 + (16-6)*2 + 1 = 136)
  -- actor 3 (subpriority 84) -> drawn before actor 2
  -- actor 2 (subpriority 83) -> drawn after actor 3 (so actor 2 is ON TOP of actor 3)
  assert(#under == 3, "expected 3 under actors, got " .. tostring(#under))
  assert(under[1].i == 1, "actor 1 should be drawn first (underneath), got " .. tostring(under[1].i))
  assert(under[2].i == 3, "actor 3 (Player, subpriority 84) should be drawn before actor 2 (Briney, subpriority 83)")
  assert(under[3].i == 2, "actor 2 (Briney, subpriority 83) should be drawn last (on top)")
  print("  -> Subpriority painter order verified: Briney (83) drawn on top of Player (84) on same Y.")
end

print("[test] 2. SetObjectSubpriority & ResetObjectSubpriority for Player and EventObjects")
do
  Player.reset(10, 10, "down")
  Objects.setSubpriority(0xFF, 0, 0, 84)
  assert(Player.fixedPriority == true, "Player fixedPriority should be true")
  assert(Player.subpriority == 84, "Player subpriority should be 84")

  Objects.resetSubpriority(0xFF, 0, 0)
  assert(Player.fixedPriority == nil, "Player fixedPriority should be cleared")
  assert(Player.subpriority == nil, "Player subpriority should be cleared")
  print("  -> Set/ResetObjectSubpriority for Player passed.")
end

print("[test] 3. Foreign Carried Object lifecycle and hideobjectat")
do
  Objects.clear()
  Objects._mapId = "MAP_DEWFORD_TOWN"
  
  -- Simulate Dewford boat (localId 2) on Dewford Town (mapGroup 0, mapNum 0)
  local boat = {
    localId = 2,
    originLocalId = 2,
    originMapId = "MAP_DEWFORD_TOWN",
    originMapGroup = 0,
    originMapNum = 0,
    cellX = 10,
    cellY = 10,
    px = 160,
    py = 160,
    visible = true,
    hidden = false,
  }
  Objects._byId[2] = boat
  Objects._order = { 2 }
  Objects._tracks[2] = { actions = {}, i = 1, done = false }

  -- Sail across to Route 109: carryOut -> carryIn
  local carry = Objects.carryOut(10, 0)
  assert(#carry.list == 1, "carried 1 boat")
  
  -- Load Route 109
  Objects.clear()
  Objects._mapId = "MAP_ROUTE_109"
  Objects.carryIn(carry)

  -- The carried boat is now on Route 109 with FOREIGN_BASE id (0xC0)
  local carriedBoat = Objects._byId[0xC0]
  assert(carriedBoat ~= nil, "carried boat should exist under foreign id 0xC0")
  assert(carriedBoat.originLocalId == 2, "originLocalId should be preserved as 2")
  assert(carriedBoat.originMapGroup == 0, "originMapGroup should be preserved as 0")
  assert(carriedBoat.originMapNum == 0, "originMapNum should be preserved as 0")

  -- Finding object by origin (localId 2, mapGroup 0, mapNum 0) should find carriedBoat
  local found = Objects.findObjectByLocalIdAndMap(2, 0, 0)
  assert(found == carriedBoat, "findObjectByLocalIdAndMap should find the carried boat")

  -- Script executes: hideobjectat LOCALID_DEWFORD_BOAT, MAP_DEWFORD_TOWN
  local hiddenOk = Objects.hideObjectAt(2, 0, 0)
  assert(hiddenOk == true, "hideObjectAt should return true")
  assert(carriedBoat.invisible == true, "carriedBoat should be invisible")
  assert(carriedBoat.hidden ~= true, "hideobjectat leaves the boat active")
  assert(carriedBoat.visible == true, "hideobjectat does not clear visible")

  -- Check forDraw: carried boat should NOT be in draw list
  local drawList = Objects.forDraw()
  for _, eo in ipairs(drawList) do
    assert(eo ~= carriedBoat, "hidden carried boat must not be in drawList")
  end
  print("  -> Carried foreign object origin lookup and hideobjectat passed.")
end

print("game3_boat_subpriority_test passed successfully!")
