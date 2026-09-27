package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local before = GameVersion.get()
GameVersion.set("emerald")

local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")

local function item(name, pocket)
  return { name = name, pocket = pocket, fieldUse = "none", price = 0 }
end

local function install()
  ItemsData.applyProfile("emerald")
  ItemsData.installPack({
    count = 377,
    items = {
      [0] = item("????????", "ITEMS"),
      [4] = item("POKé BALL", "POKE_BALLS"),
      [13] = item("POTION", "ITEMS"),
      [14] = item("ANTIDOTE", "ITEMS"),
      [133] = item("CHERI BERRY", "BERRIES"),
      [259] = item("MACH BIKE", "KEY_ITEMS"),
      [289] = item("TM01", "TM_HM"),
      [339] = item("HM01", "TM_HM"),
      [364] = item("TM CASE", "KEY_ITEMS"),
    },
  })
end
install()

print("[test] pocket model (pokeemerald/include/constants/item.h:6)")
eq(table.concat(ItemsData.POCKET_ORDER, ","), "ITEMS,POKE_BALLS,TM_CASE,BERRY_POUCH,KEY_ITEMS", "pret pocket order")
eq(#ItemsData.BAG_POCKET_ORDER, 5, "five visible pockets")
eq(ItemsData.CAPACITY.ITEMS, 30, "ITEMS 30 (global.h:51)")
eq(ItemsData.CAPACITY.POKE_BALLS, 16, "POKE_BALLS 16")
eq(ItemsData.CAPACITY.TM_CASE, 64, "TM_HM 64")
eq(ItemsData.CAPACITY.BERRY_POUCH, 46, "BERRIES 46")
eq(ItemsData.CAPACITY.KEY_ITEMS, 30, "KEY_ITEMS 30")
eq(ItemsData.POCKET_RESULT.POKE_BALLS, 2, "POCKET_POKE_BALLS = 2")
eq(ItemsData.POCKET_RESULT.KEY_ITEMS, 5, "POCKET_KEY_ITEMS = 5")
eq(ItemsData.pocketOf(289), "TM_CASE", "TM_HM maps onto the TM_CASE storage key")
eq(ItemsData.pocketOf(133), "BERRY_POUCH", "BERRIES maps onto the BERRY_POUCH storage key")
eq(ItemsData.pocketOf(259), "KEY_ITEMS", "key items")
eq(ItemsData.pocketResult(4), 2, "Poke Ball pocket id")
eq(next(ItemsData.CONTAINERS), nil, "no container key items")

print("[test] per-slot 99 cap with overflow slots (pokeemerald/src/item.c:238)")
local bag = Bag.new()
check(Bag.add(bag, 13, 150), "150 Potions fit")
eq(#bag.pockets.ITEMS, 2, "split across two slots")
eq(bag.pockets.ITEMS[1].qty, 99, "first slot full")
eq(bag.pockets.ITEMS[2].qty, 51, "second slot holds the rest")
eq(Bag.get(bag, 13), 150, "count sums slots")
check(Bag.remove(bag, 13, 100), "remove 100")
eq(Bag.get(bag, 13), 50, "50 left")
eq(#bag.pockets.ITEMS, 1, "empty slot compacted")
check(not Bag.remove(bag, 13, 51), "cannot remove more than owned")

print("[test] TM/berry pockets never split (pokeemerald/src/item.c:284)")
check(Bag.add(bag, 289, 99), "99 TM01")
check(not Bag.canAdd(bag, 289, 1), "TM slot at 99 refuses more")
check(not Bag.add(bag, 289, 1), "add refuses too")
eq(Bag.get(bag, 289), 99, "TM count unchanged")
check(Bag.add(bag, 133, 999), "berries hold 999 (items.h:455)")
check(not Bag.canAdd(bag, 133, 1), "berry slot full at 999")
eq(Bag.get(bag, 364), 0, "no TM Case granted")
check(Bag.add(bag, 339, 1), "HM01")
eq(bag.pockets.TM_CASE[1].id, 289, "TM/HM pocket sorted by id (item.c:615)")
eq(bag.pockets.TM_CASE[2].id, 339, "HM after TM")

print("[test] pocket capacity")
local full = Bag.new()
check(Bag.add(full, 13, 99 * 29), "29 full Potion slots")
check(Bag.add(full, 14, 99), "30th slot")
check(not Bag.canAdd(full, 13, 1), "no room once 30 slots are full (item.c:174)")
check(Bag.canAdd(full, 4, 1), "other pocket unaffected")

print("[test] FireRed model restored")
GameVersion.set("firered")
ItemsData.ensureModel()
eq(ItemsData.CAPACITY.ITEMS, 42, "FR ITEMS 42")
eq(#ItemsData.BAG_POCKET_ORDER, 3, "FR three visible pockets")
eq(ItemsData.POCKET_RESULT.KEY_ITEMS, 2, "FR POCKET_KEY_ITEMS = 2")
eq(ItemsData.CONTAINERS.TM_CASE.item, 364, "FR TM Case container")
eq(ItemsData.CONTAINERS.BERRY_POUCH.item, 365, "FR Berry Pouch container")
eq(ItemsData.slotMax("ITEMS"), 999, "FR slot max 999")

GameVersion.set(before)
T.finish("game3_emerald_bag_test")
