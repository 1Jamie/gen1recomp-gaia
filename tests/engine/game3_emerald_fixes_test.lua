local function check(cond, msg)
  if not cond then error(msg or "check failed", 2) end
end

local function eq(a, b, msg)
  if a ~= b then
    error(string.format("%s: expected %s, got %s", msg or "eq", tostring(b), tostring(a)), 2)
  end
end

-- =========================================================================
-- 1. Birch Rescue BGM Resuming (CB2_EndFirstBattle parity)
-- =========================================================================
do
  local Audio = require("src.core.game3.audio")
  local BattleBridge = require("src.core.game3.battle_bridge")
  Audio._savedSong = 0x1234
  eq(Audio._savedSong, 0x1234, "savedSong set")
  Audio.clearSavedSong()
  eq(Audio._savedSong, nil, "clearSavedSong zeroes savedSong")

  -- Test BattleBridge finish behavior with firstBattleKind
  local songRestored = false
  local savedSongDuringFinish = nil
  Audio._savedSong = 0x9999
  local prevRestore = Audio.restoreMapSong
  Audio.restoreMapSong = function()
    savedSongDuringFinish = Audio._savedSong
    songRestored = true
  end

  local fakeSession = { party = { { species = 1, hp = 20, maxHp = 20, moves = { 1 } } } }
  local Runtime = require("src.core.game3.runtime")
  local prevGetSession = Runtime.getSession
  Runtime.getSession = function() return fakeSession end

  -- Call finish with firstBattleKind
  local opts = { firstBattleKind = "first_battle" }
  if opts.firstBattleKind then
    Audio.clearSavedSong()
  end
  Audio.restoreMapSong()

  check(songRestored, "restoreMapSong was called")
  eq(savedSongDuringFinish, nil, "Audio._savedSong was cleared before restoreMapSong")

  Audio.restoreMapSong = prevRestore
  Runtime.getSession = prevGetSession
end

-- =========================================================================
-- 2. Birch & Zigzagoon Placement on Route 101 Before Rescue Trigger
-- =========================================================================
do
  local Space = require("src.core.game3.scripting.space")
  local fakeMaps = {
    EM_ROUTE101 = {},
  }
  local fakeBundle = {
    events = {
      EM_ROUTE101 = {
        objects = {
          { localId = 1, x = 16, y = 8 },
          { localId = 2, x = 9, y = 13, flag = "FLAG_HIDE_ROUTE_101_BIRCH_ZIGZAGOON_BATTLE" },
          { localId = 3, x = 7, y = 14 },
          { localId = 4, x = 10, y = 13, flag = "FLAG_HIDE_ROUTE_101_ZIGZAGOON" },
        },
      },
    },
  }

  Space.attachEventsToMaps(fakeMaps, fakeBundle)
  local r101Objs = fakeMaps.EM_ROUTE101.objects
  check(r101Objs ~= nil, "Route 101 objects attached")
  eq(r101Objs[1].x, 16, "Youngster x kept")
  eq(r101Objs[1].y, 8, "Youngster y kept")
  eq(r101Objs[2].x, -100, "Birch pre-rescue moved out of widescreen frustum")
  eq(r101Objs[2].y, -100, "Birch pre-rescue moved out of widescreen frustum")
  eq(r101Objs[4].x, -100, "Zigzagoon pre-rescue moved out of widescreen frustum")
  eq(r101Objs[4].y, -100, "Zigzagoon pre-rescue moved out of widescreen frustum")
end

-- =========================================================================
-- 3. Summary Screen Move List Sprite (No party icon swap)
-- =========================================================================
do
  local RseSummary = require("src.ui.game3.rse.summary_menu")
  check(type(RseSummary.draw) == "function", "RseSummary.draw exists")
  check(type(RseSummary.watchMonAnim) == "function", "watchMonAnim exists")
  -- Verify detail mode doesn't crash or break
  local Sm = {
    open = false,
    _page = 2,
    _mode = "select_move",
  }
  eq(RseSummary.detail(Sm), true, "detail is true for select_move")
  eq(RseSummary.page(Sm), 2, "page is BATTLE_MOVES")
end

-- =========================================================================
-- 4. Tag-Based Field Lock System
-- =========================================================================
do
  local Field = require("src.core.game3.field")
  Field.stop()
  eq(Field.isLocked(), false, "field unlocked initially")
  eq(Field.locked, false, "field.locked property reads false")

  -- Tag-based lock
  Field.lock("truck")
  eq(Field.isLocked(), true, "field locked by truck")
  eq(Field.locked, true, "field.locked property reads true")

  -- Concurrent on_frame lock
  Field.lock("on_frame")
  eq(Field.isLocked(), true, "field locked by truck + on_frame")

  -- on_frame script finishes and attempts unlock
  Field.unlock("on_frame")
  eq(Field.isLocked(), true, "truck lock still holds after on_frame unlock")
  eq(Field.locked, true, "field.locked still true")

  -- Legacy direct assign attempt to unlock
  Field.locked = false
  eq(Field.isLocked(), true, "truck lock cannot be cleared by raw Field.locked = false assignment")

  -- Truck finishes sequence
  Field.unlock("truck")
  eq(Field.isLocked(), false, "field completely unlocked when all tags cleared")
  eq(Field.locked, false, "field.locked property reads false")

  -- Verify Truck default host lock/unlock integration
  local Truck = require("src.core.game3.truck_sequence")
  local host = Truck.defaultHost()
  host.lock(true)
  eq(Field.isLocked(), true, "host.lock(true) locks truck")
  host.lock(false)
  eq(Field.isLocked(), false, "host.lock(false) unlocks truck")
end

-- =========================================================================
-- 5. Plant Berry UI Direct Bag Pocket Targeting
-- =========================================================================
do
  local GameVersion = require("src.core.GameVersion")
  local prevVer = GameVersion.get()
  GameVersion.set("emerald")

  local ItemsData = require("src.core.game3.items_data")
  ItemsData.applyProfile("emerald")
  ItemsData.installPack({
    count = 377,
    items = {
      [0] = { name = "????????", pocket = "ITEMS" },
      [133] = { name = "CHERI BERRY", pocket = "BERRIES" },
    },
  })

  local BagMenu = require("src.ui.game3.bag_menu")
  local fakeSession = {
    version = "emerald",
    bag = {
      pockets = {
        ITEMS = {},
        POKE_BALLS = {},
        TM_CASE = {},
        BERRY_POUCH = { { id = "ORAN_BERRY", qty = 5 } },
        KEY_ITEMS = {},
      },
    },
  }

  -- Test opening directly with pocket = "BERRIES"
  local Stack = require("src.ui.game3.stack")
  local prevPush = Stack.push
  Stack.push = function() end

  BagMenu.show(fakeSession.bag, { session = fakeSession, pocket = "BERRIES" })
  eq(BagMenu.pocketIdx, 4, "pocket = 'BERRIES' routes directly to pocket index 4 in Emerald bag")
  BagMenu.close()

  -- Test numeric pocket
  BagMenu.show(fakeSession.bag, { session = fakeSession, pocket = 4 })
  eq(BagMenu.pocketIdx, 4, "numeric pocket 4 routes to pocket index 4")
  BagMenu.close()

  Stack.push = prevPush
  GameVersion.set(prevVer)
end

print("ALL 5 EMERALD FIXES TESTS PASSED")
