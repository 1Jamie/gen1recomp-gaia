-- engine/menus/pc.asm prints the access text between SFX_ENTER_PC and the
-- farcall: BillsPC (:73-85) picks AccessedBillsPCText / AccessedSomeonesPCText
-- off EVENT_MET_BILL, .playersPC (:50-59) prints AccessedMyPCText.  The port
-- opened BoxMenu / PlayerPC straight from the sound (#1529).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.load()

Data.text._TurnedOnPC1Text = "{PLAYER} turned on\nthe PC."
Data.text._AccessedBillsPCText = "Accessed BILL's\nPC.\fAccessed POKéMON\nStorage System."
Data.text._AccessedSomeonesPCText =
  "Accessed someone's\nPC.\fAccessed POKéMON\nStorage System."
Data.text._AccessedMyPCText = "Accessed my PC.\fAccessed Item\nStorage System."

local SaveData = require("src.core.SaveData")
local OW = require("src.world.OverworldController")

local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end

local pushed, screens = {}, {}
local stackStub = {
  push = function(_, item) pushed[#pushed + 1] = item end,
  top = function() return pushed[#pushed] end,
  pop = function() return table.remove(pushed) end,
}
local subs = {}
local textBoxStub = {
  new = function(_, text, onDone, opts)
    return { kind = "text", text = text, onDone = onDone, opts = opts }
  end,
}
local menuStub = {
  new = function(_, items, opts) return { kind = "menu", items = items, opts = opts or {} } end,
}
package.loaded["src.core.Sound"] = { play = function() end, playCry = function() end }
package.loaded["src.ui.Menu"] = menuStub

local fakeGame = { data = Data, save = SaveData.newGame(), stack = stackStub }
T.check(setUpvalue(OW.openPC, "Game", fakeGame), "Game upvalue on openPC")
T.check(setUpvalue(OW.openPC, "TextBox", textBoxStub), "TextBox upvalue on openPC")
T.check(setUpvalue(OW.openPC, "Screens",
  { push = function(_, id)
      screens[#screens + 1] = id
      local sub = { id = id }
      subs[#subs + 1] = sub
      return sub
    end }), "Screens upvalue on openPC")

local fakeSelf = setmetatable({}, { __index = OW })

local function openMenu(metBill)
  pushed, screens = {}, {}
  fakeGame.save = SaveData.newGame()
  if metBill then fakeGame.save.flags.EVENT_MET_BILL = true end
  fakeSelf:openPC(function() end)
  local pcOn = pushed[#pushed]
  T.eq(pcOn.kind, "text", "the session opens with TurnedOnPC1Text")
  pcOn.onDone()
  local menu = pushed[#pushed]
  T.eq(menu.kind, "menu", "then the PC menu")
  return menu
end

-- === SOMEONE'S PC: the access text before BoxMenu
do
  local menu = openMenu(false)
  menu.items[1].onSelect()
  local box = pushed[#pushed]
  T.eq(box.kind, "text", "the box row opens a text box")
  T.check(tostring(box.text):find("Accessed someone's", 1, true) ~= nil,
    "before meeting BILL it is AccessedSomeonesPCText")
  T.eq(#screens, 0, "and the box screen has NOT opened yet")
  table.remove(pushed)
  box.onDone()
  T.eq(screens[1], "BoxMenu", "BoxMenu follows the text, as the farcall does")
  T.check(menu ~= pushed[#pushed],
    "bills_pc.asm:121 the main menu is wiped once BoxMenu opens")
  menu.index = 3
  subs[1].exit()
  T.check(pushed[#pushed] == menu,
    "pc.asm:86 ReloadMainMenu rebuilds the main menu on return")
  T.eq(menu.index, 1, "bills_pc.asm:81 the cursor is back on row 1")
end

-- === BILL'S PC once EVENT_MET_BILL is set
do
  local menu = openMenu(true)
  menu.items[1].onSelect()
  local box = pushed[#pushed]
  T.check(tostring(box.text):find("Accessed BILL's", 1, true) ~= nil,
    "after meeting BILL it is AccessedBillsPCText")
  box.onDone()
  T.eq(screens[1], "BoxMenu", "and still opens BoxMenu")
end

-- === the player's item storage
do
  local menu = openMenu(false)
  menu.items[2].onSelect()
  local box = pushed[#pushed]
  T.eq(box.kind, "text", "the item row opens a text box")
  T.check(tostring(box.text):find("Accessed my PC.", 1, true) ~= nil,
    "and it is AccessedMyPCText")
  T.eq(#screens, 0, "PlayerPC has not opened yet")
  box.onDone()
  T.eq(screens[1], "PlayerPC", "PlayerPC follows the text")
end

-- engine/menus/pc.asm:86
do
  pushed, screens = {}, {}
  fakeGame.save = SaveData.newGame()
  fakeGame.save.flags.EVENT_GOT_POKEDEX = true
  fakeSelf:openPC(function() end)
  pushed[#pushed].onDone()
  local menu = pushed[#pushed]
  local oakDone
  fakeSelf.openOaksPC = function(_, cb) oakDone = cb end
  local oakRow
  for _, row in ipairs(menu.items) do
    if row.label == "PROF.OAK's PC" then oakRow = row end
  end
  T.check(oakRow, "the PC menu has a PROF.OAK's PC row")
  menu.index = 3
  oakRow.onSelect()
  T.check(pushed[#pushed] == menu,
    "oaks_pc.asm:1 the main menu stays up while Oak's PC runs")
  oakDone()
  T.check(pushed[#pushed] == menu, "and it is still the top menu after")
  T.eq(menu.index, 1, "pc.asm:65 ReloadMainMenu, bills_pc.asm:81 cursor back on row 1")
  fakeSelf.openOaksPC = nil
end

T.finish("PC access text (#1529)")
