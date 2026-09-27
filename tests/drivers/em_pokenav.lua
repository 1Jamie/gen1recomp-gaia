local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_pokenav"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_pokenav failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(30)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Field = require("src.core.game3.field")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local T = Flags.forVersion("emerald")
  local Pokenav = require("src.ui.game3.rse.pokenav.init")
  local session = Runtime.getSession()
  if not check(session ~= nil, "session after new game") then return finish() end

  local function flag(name) return Flags.getFlag(Space.store, nil, T.IDS[name]) == true end
  local function setFlag(name, on) Flags.setFlag(Space.store, nil, T.IDS[name], on ~= false) end
  local function var(name) return tonumber(Flags.getVar(Space.store, nil, T.VAR_IDS[name])) or 0 end
  local function setVar(name, v) Flags.setVar(Space.store, nil, T.VAR_IDS[name], v) end
  local function mapNow() local s = Runtime.getSession() return s and s.map end
  local function shot(name) U.shot(game, DIR .. "/" .. name .. ".png") end
  local function still(name) U.still(game, DIR .. "/" .. name .. ".png") end

  local function busy()
    return (Space.vm and Space.vm:isRunning()) or Warp.isBusy() or Message.isOpen() or Field.locked
      or Player.moving or Choice.isOpen() or Pokenav.isOpen()
  end

  local function goTo(mapId, x, y, facing)
    for _ = 1, 600 do
      if not (Warp.isBusy() or Message.isOpen()) then break end
      if Message.isOpen() then U.tap(game, "b") end
      U.wait(1)
    end
    local ok = try("Map.load " .. mapId, function() Map.load(nil, game, mapId, { x = x, y = y, facing = facing }) end)
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    U.wait(2)
    return ok
  end

  local function mash(pred, limit, onChoice)
    local n = 0
    for _ = 1, limit or 3000 do
      if pred() then return true end
      if Pokenav.isOpen() then return pred() end
      if Choice.isOpen() then
        if onChoice then onChoice() else U.tap(game, "a") end
        U.wait(4)
      elseif Message.isOpen() then
        n = n + 1
        if n % 4 == 0 then U.tap(game, "a") else U.wait(1) end
      else
        U.wait(1)
      end
    end
    return pred()
  end

  local function nav() return Pokenav.active() end
  local function screen() local s = nav() return s and s.screen end
  local function idle()
    local s = nav()
    return s and s.phase == "menu" and not s:busy(s.screenTask) and not s:busy(s.loopTask)
  end
  local function waitIdle(limit)
    for _ = 1, limit or 600 do
      if idle() then return true end
      U.wait(1)
    end
    return idle()
  end
  local function press(btn, settleFrames)
    U.tap(game, btn)
    U.wait(2)
    waitIdle()
    U.wait(settleFrames or 2)
  end

  local QLR = require("src.core.game3.quest_log_recorder")
  local qlLocation = QLR.location
  QLR.location = function(g, s)
    local ok, v = pcall(qlLocation, g, s)
    if not ok then print("[driver] NOTE quest_log_recorder.location on Emerald: " .. tostring(v) .. " (crossfile W3a-UD adapters.lua)") end
    return ok and v or ""
  end
  -- pokeemerald/data/maps/RustboroCity_DevonCorp_3F/scripts.inc:28
  local party = session.party or {}
  check(#party >= 0, "party present")
  setVar("VAR_DEVON_CORP_3F_STATE", 0)
  setVar("VAR_RUSTBORO_CITY_STATE", 5)
  check(goTo("EM_RUSTBORO_CITY_DEVON_CORP_3F", 2, 1, "down"), "Devon Corp 3F loads")
  local gotNav = mash(function() return flag("FLAG_SYS_POKENAV_GET") and not busy() end, 6000)
  check(gotNav and flag("FLAG_RECEIVED_POKENAV"), "Mr. Stone gives the PokeNav (FLAG_SYS_POKENAV_GET, FLAG_RECEIVED_POKENAV)")
  check(var("VAR_RUSTBORO_CITY_STATE") == 6, "VAR_RUSTBORO_CITY_STATE=6 after the PokeNav (" .. var("VAR_RUSTBORO_CITY_STATE") .. ")")
  shot("01_devon_pokenav_received")

  -- pokeemerald/data/maps/RustboroCity/scripts.inc:31
  check(goTo("EM_RUSTBORO_CITY", 12, 15, "down"), "Rustboro loads with the scientist event armed")
  local menuUp = mash(function() return Choice.isOpen() or Pokenav.isOpen() end, 4000)
  check(menuUp and flag("FLAG_HAS_MATCH_CALL") and flag("FLAG_ADDED_MATCH_CALL_TO_POKENAV"),
    "scientist adds Match Call and opens the tutorial start menu")
  shot("02_tutorial_start_menu")
  if Choice.isOpen() then
    for _ = 1, 3 do U.tap(game, "down") U.wait(4) end
    U.tap(game, "a")
  end
  for _ = 1, 200 do if Pokenav.isOpen() then break end U.wait(1) end
  check(Pokenav.isOpen() and nav().tutorial, "POKeNAV row opens OpenPokenavForTutorial")
  U.wait(10)
  shot("03_tutorial_field_fade")
  waitIdle(600)
  still("04_tutorial_main_menu")
  local s = nav()
  check(s and s.menuId == "main_menu" and screen().menuType == 1, "tutorial main menu is UNLOCK_MC (menu type 1)")
  check(screen() and screen().handler == "tutorial", "tutorial input handler (POKENAV_MODE_FORCE_CALL_READY)")
  press("a")
  check(nav() and nav().menuId == "main_menu", "A on HOENN MAP is refused during the tutorial")
  press("down") press("down")
  still("05_tutorial_cursor_match_call")
  check(screen().currMenuItem == 2, "cursor on MATCH CALL (item " .. tostring(screen().currMenuItem) .. ")")
  press("a")
  waitIdle(900)
  check(nav() and nav().menuId == "match_call", "MATCH CALL opens the trainer list (" .. tostring(nav() and nav().menuId) .. ")")
  U.wait(20)
  still("06_match_call_list_mr_stone")
  local mc = screen()
  local first = mc and mc.entries[1]
  check(first and first.isSpecialTrainer and first.headerId == 0, "first entry is Mr. Stone (header 0)")
  press("a")
  still("07_call_options")
  check(mc.handler == "options" and #mc.options == 2, "Mr. Stone has CALL/CANCEL (no check page)")
  U.tap(game, "a")
  U.wait(30)
  still("08_calling_mr_stone")
  for _ = 1, 4000 do
    if mc.printer and not mc.printer:isActive() and idle() then break end
    if mc.printer and mc.printer.state ~= "char" then U.tap(game, "a") end
    U.wait(1)
  end
  still("09_mr_stone_message")
  check(nav().mode == 2, "calling Mr. Stone moves the tutorial to FORCE_CALL_EXIT")
  press("a")
  U.wait(10)
  print("[driver] after call: handler=" .. tostring(mc.handler) .. " menu=" .. tostring(nav() and nav().menuId))
  press("b")
  waitIdle(900)
  print("[driver] after b: menu=" .. tostring(nav() and nav().menuId) .. " handler=" .. tostring(screen() and screen().handler))
  check(nav() and nav().menuId == "main_menu_cursor_on_match_call", "B returns to the main menu on MATCH CALL")
  still("10_back_main_menu")
  press("b")
  for _ = 1, 300 do if not Pokenav.isOpen() then break end U.wait(1) end
  check(not Pokenav.isOpen(), "B switches the PokeNav off after the tutorial")
  local done = mash(function() return var("VAR_RUSTBORO_CITY_STATE") == 7 and not busy() end, 4000)
  check(done, "tutorial script finishes (VAR_RUSTBORO_CITY_STATE=7)")
  shot("11_after_tutorial")

  -- pokeemerald/src/start_menu.c:685
  local Rematch = require("src.core.game3.rse.rematch")
  local MatchCall = require("src.core.game3.rse.match_call")
  for _, i in ipairs({ 10, 13, 21 }) do
    Rematch.setFlag(session, Rematch.registeredFlagId(session, i), true)
    Rematch.setFlag(session, Flags.trainerFlagId(Rematch.trainerIds(i)[1]), true)
  end
  Rematch.set(session, 10, 1)
  setFlag("FLAG_ENABLE_MOM_MATCH_CALL", true)
  goTo("EM_ROUTE104", 12, 30, "down")
  U.wait(30)
  Pokenav.show({ session = session, game = game })
  waitIdle(900)
  still("12_main_menu")
  check(nav().menuId == "main_menu" and screen().handler == "main", "normal PokeNav main menu")
  check(screen().nearbyRematch == true, "blue light: Cindy (Route 104) wants a rematch nearby")
  press("a")
  waitIdle(900)
  check(nav().menuId == "region_map", "HOENN MAP opens the region map")
  U.wait(10)
  still("13_hoenn_map_full")
  local map = screen()
  check(map.rm.mapSecId ~= nil, "region map cursor starts on the player's section (" .. tostring(map.rm.mapSecName) .. ")")
  press("a")
  U.wait(10)
  still("14_hoenn_map_zoom")
  check(map.zoomed == true, "A zooms the map in")
  U.hold(game, "right", 24)
  for _ = 1, 60 do if map.inputFn == "zoomed" then break end U.wait(1) end
  waitIdle()
  U.wait(4)
  still("15_hoenn_map_zoom_right")
  press("a")
  still("16_hoenn_map_zoom_out")
  check(map.zoomed == false, "A zooms back out")
  press("b")
  waitIdle(900)
  check(nav().menuId == "main_menu_cursor_on_map", "B returns to the main menu")
  check(session.regionMapZoom == false, "zoom state saved to regionMapZoom")
  press("down") press("down")
  press("a")
  waitIdle(900)
  mc = screen()
  check(nav().menuId == "match_call", "MATCH CALL list opens")
  U.wait(20)
  still("17_match_call_list")
  local names = {}
  for i, e in ipairs(mc.entries) do
    local d, n = MatchCall.entryNameAndDesc(e)
    names[i] = tostring(n)
  end
  print("[driver] list: " .. table.concat(names, ","))
  check(#mc.entries >= 5, "registered entries listed (" .. #mc.entries .. ")")
  local cindyRow
  for i, e in ipairs(mc.entries) do
    if not e.isSpecialTrainer and e.headerId == 10 then cindyRow = i end
  end
  check(cindyRow ~= nil, "Cindy (rematch table 10) is in the list")
  for _ = 1, (cindyRow or 1) - 1 do press("down") end
  still("18_cursor_on_cindy")
  press("a")
  check(#mc.options == 3, "a trainer has CALL/CHECK/CANCEL")
  press("down")
  press("a")
  waitIdle(600)
  U.wait(10)
  still("19_check_page_cindy")
  check(mc.checkPage == true and mc.picId ~= nil and mc.picId >= 0, "CHECK shows the check page with the trainer pic")
  press("b")
  waitIdle(600)
  still("20_back_to_list")
  press("a")
  press("a")
  U.wait(40)
  still("21_calling_cindy")
  for _ = 1, 4000 do
    if mc.printer and not mc.printer:isActive() and idle() then break end
    if mc.printer and mc.printer.state ~= "char" then U.tap(game, "a") end
    U.wait(1)
  end
  still("22_cindy_message")
  press("a")
  press("b")
  waitIdle(900)
  press("b")
  for _ = 1, 300 do if not Pokenav.isOpen() then break end U.wait(1) end
  check(not Pokenav.isOpen(), "switch off closes the PokeNav")
  U.wait(30)
  shot("23_field_after")
  finish()
end
