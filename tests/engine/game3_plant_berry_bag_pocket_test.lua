local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local prevVer = GameVersion.get()
GameVersion.set("firered")

local ItemsData = require("src.core.game3.items_data")
ItemsData.applyProfile("firered")
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

local Stack = require("src.ui.game3.stack")
local prevPush = Stack.push
Stack.push = function() end

-- Test opening directly with pocket = "BERRIES" from a session with emerald version
BagMenu.show(fakeSession.bag, { session = fakeSession, pocket = "BERRIES" })
eq(BagMenu.pocketIdx, 4, "pocket = 'BERRIES' routes directly to pocket index 4 in Emerald bag even if GameVersion was firered")
eq(BagMenu.currentPocket(), "BERRY_POUCH", "current pocket is BERRY_POUCH")
BagMenu.close()

-- Test numeric pocket index
BagMenu.show(fakeSession.bag, { session = fakeSession, pocket = 4 })
eq(BagMenu.pocketIdx, 4, "numeric pocket 4 routes to pocket index 4")
BagMenu.close()

-- Test pocket switching disabled when location == "berry_tree" in RseBag
local RseBag = require("src.ui.game3.rse.bag_menu")
BagMenu.show(fakeSession.bag, { session = fakeSession, location = "berry_tree", pocket = "BERRIES" })
local inputLeft = {
  wasPressed = function(_, k) return k == "left" end,
  isDown = function() return false end,
}
RseBag.handleInput(inputLeft, BagMenu)
eq(BagMenu.pocketIdx, 4, "left/right pocket switching is disabled when location == 'berry_tree'")
BagMenu.close()

-- Test RseBag.chooseBerry passes pocket = 'BERRIES' and location = 'berry_tree'
local chooseOpts = nil
local prevScreensGet = require("src.ui.game3.screens").get
require("src.ui.game3.screens").get = function(name, sess)
  return {
    show = function(bag, opts)
      chooseOpts = opts
    end,
  }
end

local Rse = require("src.core.game3.rse.init")
local prevRseSession = Rse.session
Rse.session = function() return fakeSession end

RseBag.chooseBerry({ session = fakeSession }, function() end, "berry_tree")
eq(chooseOpts and chooseOpts.pocket, "BERRIES", "RseBag.chooseBerry passes pocket = 'BERRIES'")
eq(chooseOpts and chooseOpts.location, "berry_tree", "RseBag.chooseBerry passes location = 'berry_tree'")

require("src.ui.game3.screens").get = prevScreensGet
Rse.session = prevRseSession
Stack.push = prevPush
GameVersion.set(prevVer)

T.finish("game3_plant_berry_bag_pocket_test")
