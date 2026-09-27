local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_new_game"

return function(game)
  local ok = true
  local function check(c, label)
    print((c and "PASS " or "FAIL ") .. label)
    if not c then ok = false end
  end
  local function finish()
    love.event.quit(ok and 0 or 1)
    U.wait(10)
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  check(game.boot ~= nil, "boot reached")
  if not game.boot then return finish() end

  local Boot = require("src.ui.game3.boot")
  local MainMenu = require("src.ui.game3.rse.main_menu_rse")
  local Birch = require("src.ui.game3.rse.birch_speech")
  local Truck = require("src.core.game3.truck_sequence")
  local Options = require("src.core.game3.options")

  if os.getenv("EM_NG_TIMING") == "1" then
    local textSpeed0 = Options.block(game.options).textSpeed
    local b = Birch.new({ textSpeed = textSpeed0 })
    local marks, seen = {}, {}
    local function mark(name, f)
      if not seen[name] then
        seen[name] = true
        marks[#marks + 1] = string.format("%s=%d", name, f)
      end
    end
    b.onEvent = mark
    local firstPress, period = tonumber(os.getenv("EM_NG_FIRST") or "39"), 60
    for f = 1, 8000 do
      local new, held = {}, {}
      local k = f - firstPress
      if k >= 0 and k % period == 0 then new.a, held.a = true, true end
      if k >= 1 and (k - 1) % period == 0 then held.a = true end
      local r = b:frame({ new = new, held = held, rep = new })
      if b.ball and not b.ball.invisible then mark("ball_visible", f) end
      if b.genderMenu then mark("gender_menu_visible", f) end
      if b.naming and b.naming.stage == "input" then mark("naming_input", f) end
      if b.yesNo then mark("yes_no_visible", f) end
      if r then
        mark("result", f)
        break
      end
    end
    print("[driver] timing (port GBA frames from Init=1, A every 60 from " .. firstPress .. "): "
      .. table.concat(marks, " "))
    print("[driver] timing name=" .. tostring(b.playerName) .. " gender=" .. tostring(b.gender))
    if b.naming then b:destroy() end
    return finish()
  end

  local okMods, BootModules = pcall(require, "src.ui.game3.boot_modules")
  local realPath = okMods and type(BootModules) == "table"
  print("[driver] boot modules resolver " .. (realPath and "present" or "absent (driver hosts the rse screens)"))

  local host = { screen = nil, result = nil, events = {} }
  local origUpdate, origDraw = Boot.update, Boot.draw

  local demo = MainMenu.new({
    hasContinue = true, saveStatus = "ok",
    continueInfo = { name = "MAY", gender = 1, hours = 12, minutes = 34, hasDex = true, dexCount = 27,
      badges = 3, mysteryGift = true, frameType = 0 },
  })
  Boot.draw = function() demo:draw() end
  demo.pal = require("src.core.game3.pal_fade").new()
  demo.state = "input"
  U.still(game, DIR .. "/00a_main_menu_continue_gift.png")
  check(#demo.items == 5 and demo.items[5] == "EXIT", "gift menu: CONTINUE/NEW GAME/MYSTERY GIFT/OPTION/EXIT")
  demo.cursor = 5
  demo:_fixScroll()
  U.still(game, DIR .. "/00b_main_menu_scrolled_exit.png")
  check(demo.scroll > 0, "EXIT row scrolls into view")
  Boot.draw = origDraw
  local textSpeed = Options.block(game.options).textSpeed
  local routed = realPath and game.boot.custom ~= nil
  if routed then
    print("[driver] routing through BootModules (boot.lua custom state)")
    BootModules.startMenu(Boot, game.boot)
    host.screen = game.boot.custom.menu
    host.kind = "menu"
    Boot.update = function(state, input, dt)
      local r = origUpdate(state, input, dt)
      local c = state.custom
      if c and c.newGame and host.kind ~= "birch" then
        host.screen = c.newGame
        host.screen.onEvent = function(name, f) host.events[#host.events + 1] = { name = name, frame = f } end
        host.kind = "birch"
      end
      if r and host.kind == "birch" then host.result = r end
      return r
    end
  else
    host.screen = MainMenu.new({ hasContinue = false, saveStatus = "ok", textSpeed = textSpeed, game = game })
    host.kind = "menu"
    Boot.update = function(_, input, dt)
      local r = host.screen:update(input, dt)
      if r == "newGame" and host.kind == "menu" then
        host.screen = Birch.new({ textSpeed = textSpeed })
        host.screen.onEvent = function(name, f) host.events[#host.events + 1] = { name = name, frame = f } end
        host.kind = "birch"
        return nil
      end
      if r and host.kind == "birch" then
        host.result = r
        return r
      end
      return nil
    end
    Boot.draw = function() host.screen:draw() end
  end

  U.wait(40)
  U.still(game, DIR .. "/01_main_menu_no_save.png")
  check(host.screen.items[#host.screen.items] == "EXIT", "main menu shows a visible EXIT row")
  U.tap(game, "a")
  for _ = 1, 200 do
    if host.kind == "birch" then break end
    U.wait(1)
  end
  check(host.kind == "birch", "NEW GAME opens the Birch speech")
  local birch = host.screen
  local function waitFunc(name, limit)
    for _ = 1, limit or 3000 do
      if birch.main.func == name then return true end
      U.wait(1)
    end
    return false
  end
  local function waitEvent(name, limit)
    for _ = 1, limit or 3000 do
      for _, e in ipairs(host.events) do if e.name == name then return e end end
      U.wait(1)
    end
    return nil
  end

  check(waitEvent("birch_fade_in", 600) ~= nil, "Birch fades in")
  U.wait(30)
  U.still(game, DIR .. "/02_birch_appears.png")
  check(waitFunc("ThisIsAPokemon", 800), "welcome text")
  U.still(game, DIR .. "/03_welcome_text.png")
  for _ = 1, 3000 do
    if birch.ball then break end
    if birch.printer and (birch.printer.state == "clear" or birch.printer.state == "scroll_start") then U.tap(game, "a") end
    U.wait(1)
  end
  local rel = waitEvent("lotad_release", 200)
  check(rel ~= nil, "Poke Ball releases Lotad")
  U.wait(6)
  U.still(game, DIR .. "/04_lotad_release.png")
  check(waitEvent("lotad_cry", 200) ~= nil, "Lotad lands and cries")
  U.wait(20)
  U.still(game, DIR .. "/05_lotad_out.png")

  for _ = 1, 4000 do
    if birch.main.func == "ChooseGender" then break end
    if birch.printer and (birch.printer.state == "clear" or birch.printer.state == "scroll_start") then U.tap(game, "a") end
    U.wait(1)
  end
  check(birch.main.func == "ChooseGender", "gender menu reached")
  U.wait(4)
  U.still(game, DIR .. "/06_gender_menu_boy.png")
  U.tap(game, "down")
  check(waitEvent("gender_slide", 30) ~= nil, "gender slide starts")
  U.wait(12)
  U.still(game, DIR .. "/07_gender_slide.png")
  check(waitFunc("ChooseGender", 200), "slide finished")
  U.still(game, DIR .. "/08_may_selected.png")
  U.tap(game, "a")
  check(waitEvent("chose_girl", 30) ~= nil, "girl chosen")
  for _ = 1, 2000 do
    if birch.main.func == "WaitPressBeforeNameChoice" then break end
    U.wait(1)
  end
  U.tap(game, "a")
  for _ = 1, 400 do
    if birch.naming and birch.naming.stage == "input" then break end
    U.wait(1)
  end
  check(birch.naming ~= nil and birch.naming.stage == "input", "naming screen open")
  U.wait(10)
  U.still(game, DIR .. "/09_naming.png")
  local preset = birch.playerName
  for _, k in ipairs({ "a", "right", "a" }) do
    U.tap(game, k)
    U.wait(3)
  end
  U.tap(game, "start")
  U.wait(3)
  U.still(game, DIR .. "/10_naming_typed.png")
  U.tap(game, "a")
  check(waitEvent("naming_return", 400) ~= nil, "back from naming")
  print("[driver] preset " .. tostring(preset) .. " typed name " .. tostring(birch.playerName)
    .. " trainerIdLower " .. tostring(birch.trainerIdLower))
  check(birch.playerName == "AB", "typed name kept")
  check(type(birch.trainerIdLower) == "number", "trainer id seeded from naming timer")
  check(waitFunc("ProcessNameYesNoMenu", 600), "name yes/no")
  U.still(game, DIR .. "/11_name_yes_no.png")
  U.tap(game, "a")
  check(waitEvent("name_confirmed", 60) ~= nil, "name confirmed")
  for _ = 1, 3000 do
    if birch.main.func == "WaitForPlayerShrink" then break end
    if birch.printer and (birch.printer.state == "clear" or birch.printer.state == "scroll_start") then U.tap(game, "a") end
    U.wait(1)
  end
  check(birch.main.func == "WaitForPlayerShrink", "shrink starts")
  U.wait(24)
  U.still(game, DIR .. "/12_shrink.png")
  check(waitEvent("white_fade_start", 200) ~= nil, "fade player to white")
  U.wait(8)
  U.still(game, DIR .. "/13_white_fade.png")

  for _ = 1, 400 do
    if game.phase == "field" then break end
    U.wait(1)
  end
  Boot.update, Boot.draw = origUpdate, origDraw
  local r = host.result
  check(r ~= nil and r.action == "new_game" and r.fieldCallback == "truck" and r.gender == 1,
    "Birch hands off {new_game, gender=1, fieldCallback=truck}")
  check(game.phase == "field", "field entered")
  local ev = {}
  for _, e in ipairs(host.events) do ev[e.name] = e.frame end
  local function span(a, b) return ev[a] and ev[b] and (ev[b] - ev[a]) or -1 end
  print(string.format("[driver] beats (GBA frames) mus=%s birch_in=%s welcome=%s release=%s cry=%s gender=%s",
    tostring(ev.mus_route122), tostring(ev.birch_fade_in), tostring(ev.welcome_text), tostring(ev.lotad_release),
    tostring(ev.lotad_cry), tostring(ev.gender_menu)))
  print(string.format("[driver] shrink->white=%d white->cleanup=%d", span("shrink_start", "white_fade_start"),
    span("white_fade_start", "cleanup")))
  check(span("mus_route122", "birch_fade_in") == 0xD8 + 1, "Birch appears 216 frames after MUS_ROUTE122")

  local truckEvents = {}
  if not Truck.isRunning() then
    print("[driver] Game3 did not start the truck (crossfile hand-off pending); driver starts it")
    Truck.execute(nil, { onEvent = function(n, f) truckEvents[#truckEvents + 1] = { name = n, frame = f } end })
  else
    local seq = Truck._state.seq
    if seq then seq.onEvent = function(n, f) truckEvents[#truckEvents + 1] = { name = n, frame = f } end end
  end
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  check(session and session.map == "EM_INSIDE_OF_TRUCK", "new game starts inside the truck")
  U.wait(60)
  U.still(game, DIR .. "/14_truck_black.png")
  for _ = 1, 2000 do
    local seen = false
    for _, e in ipairs(truckEvents) do if e.name == "fade_in" then seen = true end end
    if seen then break end
    U.wait(1)
  end
  U.wait(40)
  U.still(game, DIR .. "/15_truck_ride.png")
  for _ = 1, 3000 do
    if not Truck.isRunning() then break end
    U.wait(1)
  end
  check(not Truck.isRunning(), "truck sequence finished")
  local names = {}
  for _, e in ipairs(truckEvents) do names[#names + 1] = e.name .. "@" .. e.frame end
  print("[driver] truck " .. table.concat(names, " "))
  U.wait(4)
  U.still(game, DIR .. "/16_truck_door_open.png")
  local Field = require("src.core.game3.field")
  check(Field.locked == false, "player controls unlocked after the door opens")
  finish()
end
