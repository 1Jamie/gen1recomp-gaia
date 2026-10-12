package.path = "./?.lua;./?/init.lua;" .. package.path
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
    [4] = { name = "POKé BALL", pocket = "POKE_BALLS" },
    [13] = { name = "POTION", pocket = "ITEMS" },
    [17] = { name = "ANTIDOTE", pocket = "ITEMS" },
    [20] = { name = "PARLYZ HEAL", pocket = "ITEMS" },
    [3] = { name = "GREAT BALL", pocket = "POKE_BALLS" },
  },
})

local Stack = require("src.ui.game3.stack")
local prevPush, prevPop = Stack.push, Stack.pop
Stack.push = function() end
Stack.pop = function() end

local Bag = require("src.core.game3.bag")
local Ui = require("src.core.game3.battle.ui")
local BagMenu = require("src.ui.game3.bag_menu")
local Fade = require("src.ui.game3.fade")
Fade.clear()

local session = { name = "RED", bag = Bag.new(), party = {}, modData = {} }
Bag.add(session.bag, 17, 3)
Bag.add(session.bag, 20, 2)
Bag.add(session.bag, 3, 7)

local st = { oldManTutorial = true, wild = true, player = { mon = {} } }
Ui.reset({ headless = false })
Ui._session = session
Ui.bindState(st)
Ui.openMenu()

local NO = { wasPressed = function() return false end, isDown = function() return false end }

for _ = 1, 64 do Ui.tick() end
eq(Ui._menuIndex, 2, "cursor moves to BAG after 64 frames (battle_controller_oak_old_man.c:290)")
for _ = 1, 64 do Ui.tick() end
eq(Ui.takeCommand(), nil, "choosing BAG does not throw the ball straight away")
check(Fade.isActive() and Fade.mode == Fade.MODE.TO_BLACK and not BagMenu.isOpen(),
  "the battle fades to black before the bag (battle_controller_oak_old_man.c:1876)")
for _ = 1, 15 do
  Fade.tick(1 / 60)
  Ui.tick()
end
check(Fade.isActive() and not BagMenu.isOpen(), "16-frame fade, bag still closed on frame 15")
Fade.tick(1 / 60)
check(not Fade.isActive() and Fade.t == 0, "fade done and cleared when the bag takes over (item_menu.c:915)")
check(BagMenu.isOpen() and BagMenu.isPokedude(), "the scripted old man bag opens (battle_controller_oak_old_man.c:1872)")
eq(Ui._mode, "bag", "battle UI waits on the bag")

local function ids(pocket)
  local out = {}
  for _, s in ipairs(session.bag.pockets[pocket] or {}) do
    out[#out + 1] = tostring(ItemsData.toNumericId(s.id)) .. "x" .. tostring(s.qty)
  end
  return table.concat(out, ",")
end
eq(ids("ITEMS"), "13x1", "old man bag ITEMS holds one POTION (item_menu.c:2101)")
eq(ids("POKE_BALLS"), "4x1", "old man bag POKé BALLS holds one POKé BALL (item_menu.c:2102)")
eq(BagMenu.currentPocket(), "ITEMS", "bag opens on ITEMS")

local cmd, pocketAt250, pocketAt150, modeAt360
for f = 1, 900 do
  BagMenu.handleInput(f == 120 and { wasPressed = function(_, k) return k == "b" end, isDown = function() return false end } or NO)
  if f == 150 then pocketAt150 = BagMenu.currentPocket() end
  if f == 250 then pocketAt250 = BagMenu.currentPocket() end
  if f == 360 then modeAt360 = BagMenu.mode end
  cmd = Ui.takeCommand()
  if cmd then break end
end
eq(pocketAt150, "KEY_ITEMS", "first pocket switch at 102 lands on KEY ITEMS")
eq(pocketAt250, "POKE_BALLS", "second pocket switch at 204 lands on POKé BALLS")
eq(modeAt360, "action", "POKé BALL selected at 306 opens USE/CANCEL")
check(cmd ~= nil and cmd.kind == "bag" and cmd.itemId == 4, "bag closes at 408 with POKé BALL chosen")
check(not BagMenu.isOpen(), "bag is closed")
eq(ids("ITEMS"), "17x3,20x2", "player ITEMS pocket restored (item_menu.c:2082)")
eq(ids("POKE_BALLS"), "3x7", "player POKé BALLS pocket restored")

Stack.push, Stack.pop = prevPush, prevPop
GameVersion.set(prevVer)
T.finish()
