local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_controls_menu_2593"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_controls_menu_2593 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    print("[driver] " .. label .. " error: " .. tostring(err))
    failures = failures + 1
  end
  return ok
end

local function topId()
  local top = require("src.ui.game3.stack").top()
  return top and top.id
end

local function keyTap(game, key)
  game:keypressed(key)
  U.wait(2)
  game:keyreleased(key)
  U.wait(4)
end

local function body(game)
  local Runtime = require("src.core.game3.runtime")
  local StartMenu = require("src.ui.game3.start_menu")
  local Screens = require("src.ui.game3.screens")
  local Controls = require("src.ui.game3.controls_menu")
  local SaveData = require("src.core.SaveData")
  local session = Runtime.getSession()
  local version = session and session.version or "?"
  check(session ~= nil, "session up (" .. version .. ")")
  U.wait(60)

  for _ = 1, 40 do
    if StartMenu.isOpen and StartMenu.isOpen() then break end
    U.tap(game, "start")
    U.wait(8)
  end
  check(StartMenu.isOpen(), "start menu open")
  for _ = 1, 20 do
    local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
    if e and e.id == "option" then break end
    U.tap(game, "down")
    U.wait(6)
  end
  U.tap(game, "a")
  U.wait(40)
  check(topId() == "option", "OPTION screen open")

  local Opt = Screens.get("option", session)
  local function curPage()
    if Opt._st then return Opt._st.pages[#Opt._st.pages] end
    return Opt._pages and Opt._pages[#Opt._pages]
  end
  local p = curPage()
  local target
  for i, r in ipairs(p and p.rows or {}) do
    if r.id == "controls" then target = i end
  end
  check(target ~= nil, "CONTROLS row on the OPTION list")
  if not target then return end
  for _ = 1, 40 do
    if p.index == target then break end
    U.tap(game, "down")
    U.wait(6)
  end
  check(p.index == target, "cursor on CONTROLS")
  U.wait(10)
  U.still(game, DIR .. "/2593_01_" .. version .. "_option_list_controls_row.png")

  U.tap(game, "a")
  U.wait(20)
  check(topId() == "controls", "A on CONTROLS opens the controls screen")
  U.still(game, DIR .. "/2593_02_" .. version .. "_controls_screen.png")

  local bm = Controls._bm
  local function rowOf(id)
    for i, it in ipairs(bm.items) do if it.button.id == id then return i end end
  end
  local function moveTo(id)
    local want = rowOf(id)
    for _ = 1, 20 do
      if bm.index == want then break end
      U.tap(game, bm.index < want and "down" or "up")
      U.wait(6)
    end
    return bm.index == want
  end

  check(moveTo("a"), "cursor on the A row")
  U.tap(game, "a")
  U.wait(6)
  check(bm.capture ~= nil and game.input.captureArmed, "A row capture armed")
  U.still(game, DIR .. "/2593_03_" .. version .. "_capture_waiting.png")
  keyTap(game, "k")
  check(game.options.bindings and game.options.bindings.a and game.options.bindings.a.key == "k",
    "A rebound to K in game.options")
  check(bm.items[rowOf("a")].right == "K/A", "A row shows K/A (" .. tostring(bm.items[rowOf("a")].right) .. ")")

  check(moveTo("l"), "cursor on the L row")
  local speedBefore = game.options.speedMenu
  U.tap(game, "a")
  U.wait(6)
  keyTap(game, "1")
  check(game.options.speedMenu == speedBefore, "hotkey 1 did not cycle speed during capture")
  check(game.options.bindings.l and game.options.bindings.l.key == "1", "L rebound to 1")
  U.wait(4)
  U.still(game, DIR .. "/2593_04_" .. version .. "_controls_rebound_a_k_l_1.png")

  U.tap(game, "b")
  U.wait(20)
  check(topId() == "option", "B returns to OPTION")
  check(game.input.keyBindings.k == "a", "K presses A live after close")
  check(game.input.keyBindings["1"] == "l", "1 presses L live after close")
  local GameSpeed = require("src.core.GameSpeed")
  local speedKey = GameSpeed.optionKey(game:speedCategory())
  local speedLive = game.options[speedKey]
  game:keypressed("1")
  U.wait(1)
  local lHeld = game.input:isDown("l")
  game:keyreleased("1")
  U.wait(2)
  check(lHeld == true, "pressing 1 after close holds L")
  check(not game.input:isDown("l"), "releasing 1 releases L")
  check(game.options[speedKey] == speedLive, "pressing 1 after close leaves game speed alone")
  local Help = require("src.ui.game3.help_system")
  if Help.isOpen() then
    check(version == "firered", "L press opened the HELP window only in FRLG HELP button mode")
    U.still(game, DIR .. "/2593_05_" .. version .. "_bound_1_opens_help.png")
    U.tap(game, "l")
    U.wait(6)
    check(not Help.isOpen(), "L closes the HELP window")
  end

  local saved = SaveData.loadOptions()
  check(saved and saved.bindings and saved.bindings.a and saved.bindings.a.key == "k",
    "options.lua on disk has A = K")

  U.tap(game, "b")
  U.wait(30)
  for _ = 1, 4 do
    if topId() == nil then break end
    U.tap(game, "b")
    U.wait(20)
  end
  check(topId() == nil, "back in the field")

  for _ = 1, 40 do
    if StartMenu.isOpen() then break end
    U.tap(game, "start")
    U.wait(8)
  end
  StartMenu.cursor = 1
  for i, e in ipairs(StartMenu.ENTRIES or {}) do
    if e.id == "option" then StartMenu.cursor = i end
  end
  U.wait(4)
  keyTap(game, "k")
  U.wait(30)
  check(topId() == "option", "pressing K confirms in the start menu (A = K applied)")
  for _ = 1, 6 do
    if topId() == nil then break end
    U.tap(game, "b")
    U.wait(20)
  end

  game.options.bindings = nil
  game:writeOptions()
  game.input:applyBindings(nil)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  check(game.boot ~= nil, "boot reached")
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(60)
  try("body", function() body(game) end)
  return finish()
end
