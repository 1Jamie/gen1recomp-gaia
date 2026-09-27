local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_pokenav_full"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_pokenav_full failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok, err
end

local function waitFor(pred, limit)
  for _ = 1, limit or 600 do
    if pred() then return true end
    U.wait(1)
  end
  return pred()
end

local function toMenu(game)
  local custom = game.boot and game.boot.custom
  if not custom then return nil end
  for _ = 1, 400 do
    if custom.title or custom.menu then break end
    U.tap(game, "a")
    U.wait(8)
  end
  for _ = 1, 600 do
    if custom.menu then break end
    U.tap(game, "start")
    U.wait(10)
  end
  return custom.menu
end

return function(game)
  if not check(waitFor(function() return game.phase == "boot" and game.boot ~= nil and game.boot.custom ~= nil end, 900),
    "boot reached") then return finish() end
  local menu = toMenu(game)
  if not check(menu ~= nil and menu.items and menu.items[1] == "CONTINUE", "main menu shows CONTINUE") then return finish() end
  U.wait(30)
  U.tap(game, "a")
  local Runtime = require("src.core.game3.runtime")
  if not check(waitFor(function() return game.phase ~= "boot" and Runtime.getSession() ~= nil and Runtime.getSession().map ~= nil end, 1500),
    "CONTINUE loads the champion save") then return finish() end
  U.wait(90)

  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Message = require("src.ui.game3.message")
  local Pokenav = require("src.ui.game3.rse.pokenav.init")
  local Ribbons = require("src.core.game3.rse.ribbons")
  local Graph = require("src.ui.game3.rse.pokenav.graph")
  local Condition = require("src.ui.game3.rse.pokenav.condition")
  local Stack = require("src.ui.game3.stack")
  local T = Flags.forVersion("emerald")
  local session = Runtime.getSession()
  local function flag(name) return Flags.getFlag(Space.store, nil, T.IDS[name]) == true end
  local function shot(name) U.still(game, DIR .. "/" .. name .. ".png") end
  for _ = 1, 600 do
    if not Message.isOpen() then break end
    U.tap(game, "b")
    U.wait(4)
  end

  local party = session.party or {}
  check(#party >= 2, "the champion party has " .. #party .. " mons")
  check(flag("FLAG_SYS_RIBBON_GET") and flag("FLAG_ADDED_MATCH_CALL_TO_POKENAV"), "FLAG_SYS_RIBBON_GET and Match Call set by the story")
  check(Ribbons.get(party[1], "champion") == 1, "GameClear's CHAMPION RIBBON is on the lead")

  -- pokeemerald/src/pokemon.c:4023
  local lead, second = party[1], party[2]
  lead.contest = { cool = 0, beauty = 0, cute = 0, smart = 0, tough = 0, sheen = 0 }
  second.contest = { cool = 200, beauty = 90, cute = 30, smart = 150, tough = 255, sheen = 255 }
  if party[3] then party[3].contest = { cool = 60, beauty = 255, cute = 120, smart = 10, tough = 40, sheen = 100 } end
  Ribbons.set(second, "cool", 4)
  Ribbons.set(second, "tough", 2)
  Ribbons.set(second, "effort", 1)
  Ribbons.set(second, "artist", 1)
  Ribbons.set(second, "marine", 1)
  session.giftRibbons = { 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  local Storage = require("src.core.game3.storage")
  local store = Storage.ensure(session)
  local boxMon
  for b = 1, #store.boxes do
    for slot = 1, 30 do
      local m = store.boxes[b].mons[slot]
      if m and Ribbons.hasSpeciesNotEgg(m) then boxMon = m break end
    end
    if boxMon then break end
  end
  if not boxMon then
    local copy = {}
    for k, v in pairs(party[#party]) do copy[k] = v end
    copy.ribbons = 0
    copy.championRibbon = nil
    store.boxes[1].mons[1] = copy
    boxMon = copy
  end
  Ribbons.set(boxMon, "beauty", 1)
  boxMon.contest = { cool = 250, beauty = 250, cute = 250, smart = 250, tough = 250, sheen = 20 }
  check(Ribbons.count(second) == 1 + 4 + 2 + 1 + 1 + 1, "second mon ribbon count (" .. Ribbons.count(second) .. ")")

  local function nav() return Pokenav.active() end
  local function screen() local s = nav() return s and s.screen end
  local function idle()
    local s = nav()
    return s and s.phase == "menu" and not s:busy(s.screenTask) and not s:busy(s.loopTask)
  end
  local function waitIdle(limit)
    local streak = 0
    for _ = 1, limit or 900 do
      if idle() then
        streak = streak + 1
        if streak >= 8 then return true end
      else
        streak = 0
      end
      U.wait(1)
    end
    return idle()
  end
  local function press(btn, settle)
    U.tap(game, btn)
    U.wait(2)
    waitIdle()
    U.wait(settle or 2)
  end
  local function menuId() return nav() and nav().menuId end

  -- pokeemerald/src/start_menu.c:685
  U.tap(game, "start")
  U.wait(30)
  local StartMenu = require("src.ui.game3.start_menu")
  local opened = false
  for i, e in ipairs(StartMenu.ENTRIES or {}) do
    if e.id == "pokenav" then
      for _ = 1, 20 do
        if StartMenu.cursor == i then break end
        U.tap(game, "down")
        U.wait(6)
      end
      U.tap(game, "a")
      opened = waitFor(function() return Pokenav.isOpen() end, 300)
      break
    end
  end
  if not check(opened, "START > POKeNAV opens the PokeNav") then return finish() end
  waitIdle()
  U.wait(20)
  shot("01_main_menu")
  check(menuId() == "main_menu" and screen().menuType == 2, "main menu is UNLOCK_MC_RIBBONS (" .. tostring(screen().menuType) .. ")")

  -- pokeemerald/src/pokenav_menu_handler.c:214
  press("a")
  check(menuId() == "region_map", "HOENN MAP page opens")
  U.wait(20)
  shot("02_hoenn_map")
  for _ = 1, 10 do
    if menuId() ~= "region_map" then break end
    press("b", 20)
  end
  check(menuId() == "main_menu_cursor_on_map", "B back to the main menu")

  press("down")
  press("a")
  check(screen().menuType == 3, "CONDITION opens the Party/Search submenu")
  U.wait(10)
  shot("03_condition_menu")
  press("a")
  check(menuId() == "condition_graph_party", "PARTY opens the condition graph (" .. tostring(menuId()) .. ")")
  U.wait(30)
  shot("04_graph_party_lead")
  local cs = screen()
  local nonEgg = 0
  for _, m in ipairs(party) do if not require("src.core.game3.pokemon").isEgg(m) then nonEgg = nonEgg + 1 end end
  check(cs.list.listCount == nonEgg + 1, "party list is the non-egg party plus CANCEL (" .. cs.list.listCount .. ")")
  local man = Condition.manifest()
  local zero = Graph.calcPositions(man, { [0] = 0, 0, 0, 0, 0 })
  local cur = cs.graph.cur
  local same = true
  for i = 0, 4 do if cur[i].x ~= zero[i].x or cur[i].y ~= zero[i].y then same = false end end
  check(same, "lead's all-zero conditions draw the small pentagon (cool y=" .. cur[0].y .. ")")
  check(cs.sparkles ~= nil and #cs.sparkles.list == 1, "zero sheen: one sparkle")

  press("down")
  U.wait(40)
  shot("05_graph_party_second")
  local want = Graph.calcPositions(man, { [0] = 200, 255, 150, 30, 90 })
  cur = cs.graph.cur
  same = true
  for i = 0, 4 do if cur[i].x ~= want[i].x or cur[i].y ~= want[i].y then same = false end end
  check(same and cs.list.currIndex == 1, "second mon's graph vertices from its contest stats (cool y=" .. cur[0].y .. ")")
  check(cs.sparkles ~= nil and #cs.sparkles.list == 10, "max sheen: ten sparkles")
  local vertices = {}
  for i = 0, 4 do vertices[#vertices + 1] = cur[i].x .. "," .. cur[i].y end
  print("[driver] graph vertices " .. table.concat(vertices, " "))
  for _ = 1, cs.list.listCount - 2 do press("down") end
  U.wait(30)
  check(cs.list.currIndex == cs.list.listCount - 1 and cs.monX == -80, "cursor on CANCEL slides the mon out")
  shot("06_graph_party_cancel")
  press("down")
  U.wait(30)
  check(cs.list.currIndex == 0 and cs.monX == 0, "down on CANCEL wraps to the lead")
  press("b")
  waitIdle()
  check(menuId() == "condition_menu", "B returns to the Condition submenu (" .. tostring(menuId()) .. ")")

  press("down")
  press("a")
  check(screen().menuType == 4, "SEARCH opens the search submenu")
  U.wait(10)
  shot("07_condition_search_menu")
  press("a")
  check(menuId() == "condition_search_results", "COOL runs the search (" .. tostring(menuId()) .. ")")
  U.wait(20)
  shot("08_search_results_cool")
  local sr = screen()
  local items = sr.monList.items
  local sorted = true
  for i = 2, #items do
    local ma = require("src.ui.game3.rse.pokenav.mon_info").mon(session, items[i - 1])
    local mb = require("src.ui.game3.rse.pokenav.mon_info").mon(session, items[i])
    if (ma.contest and ma.contest.cool or 0) < (mb.contest and mb.contest.cool or 0) then sorted = false end
  end
  check(#items >= #party and sorted, "search lists party + boxes by COOL, highest first (" .. #items .. ")")
  check(items[1].data == 1, "rank 1 heads the list")
  local topMon = require("src.ui.game3.rse.pokenav.mon_info").mon(session, items[1])
  check(topMon == boxMon or (topMon.contest and topMon.contest.cool == 250), "the 250-COOL box mon ranks first")
  press("down")
  shot("09_search_results_down")
  press("up")
  press("a")
  check(menuId() == "condition_graph_search", "A opens the search graph (" .. tostring(menuId()) .. ")")
  U.wait(30)
  shot("10_graph_search")
  press("a")
  check(screen().marksMenu ~= nil, "A opens the markings menu")
  press("a")
  for _ = 1, 4 do press("down") end
  shot("11_markings_menu")
  press("a")
  check((topMon.markings or 0) % 2 == 1, "OK stores the circle marking on the mon (" .. tostring(topMon.markings) .. ")")
  press("b")
  waitIdle()
  check(menuId() == "return_condition_search", "B returns to the search results (" .. tostring(menuId()) .. ")")
  U.wait(10)
  shot("12_search_results_back")
  press("b")
  check(menuId() == "condition_search_menu", "B returns to the search submenu")
  press("b")
  check(screen() and screen().menuType == 3, "B moves back to the Condition submenu")
  press("b")
  check(screen() and screen().menuType == 2, "B moves back to the main menu (" .. tostring(menuId()) .. ")")
  local mm = screen()
  for _ = 1, 8 do
    if mm.currMenuItem == 2 then break end
    press(mm.currMenuItem > 2 and "up" or "down")
  end
  press("a")
  check(menuId() == "match_call", "MATCH CALL page opens")
  U.wait(20)
  shot("13_match_call")
  press("b")
  check(menuId() == "main_menu_cursor_on_match_call", "B back to the main menu on MATCH CALL")
  press("down")
  press("a")
  check(menuId() == "ribbons_mon_list", "RIBBONS opens the ribbon mon list (" .. tostring(menuId()) .. ")")
  U.wait(20)
  shot("14_ribbons_list")
  local rl = screen()
  local ritems = rl.monList.items
  local ok = #ritems >= 2
  for i = 2, #ritems do if ritems[i - 1].data < ritems[i].data then ok = false end end
  check(ok, "ribbon list sorted by ribbon count (" .. #ritems .. " mons)")
  local MonInfo = require("src.ui.game3.rse.pokenav.mon_info")
  check(MonInfo.mon(session, ritems[1]) == second and ritems[1].data == 10, "the ten-ribbon mon heads the list")
  local hasBox = false
  for _, it in ipairs(ritems) do if it.boxId ~= nil then hasBox = true end end
  check(hasBox, "box mons with ribbons are listed")
  press("a")
  check(menuId() == "ribbons_summary_screen", "A opens the ribbon summary (" .. tostring(menuId()) .. ")")
  U.wait(20)
  shot("15_ribbon_summary")
  local rs = screen()
  check(#rs.normalIds == 9 and #rs.giftIds == 1, "summary lays out 9 normal + 1 gift ribbon (" .. #rs.normalIds .. "+" .. #rs.giftIds .. ")")
  check(rs.countText and rs.countText:find("10"), "RIBBONS 10 (" .. tostring(rs.countText) .. ")")
  press("a")
  U.wait(10)
  shot("16_ribbon_expanded")
  check(rs.desc and rs.desc[1] == "gRibbonDescriptionPart1_Champion", "first ribbon is CHAMPION with its description")
  press("right")
  check(rs.selectedPos == 1 and rs.desc and rs.desc[1] == "gRibbonDescriptionPart1_CoolContest", "right: COOL contest ribbon")
  press("down")
  press("down")
  check(rs.selectedPos == 27 and rs.desc and rs.desc[1] == "gGiftRibbonDescriptionPart1_2003RegionalTourney",
    "down to the gift row: MARINE reads giftRibbons[0]=1 (" .. tostring(rs.selectedPos) .. ")")
  U.wait(10)
  shot("17_gift_ribbon")
  press("b")
  check(rs.textMode == "count", "B shrinks the ribbon and reprints the count")
  press("down")
  U.wait(20)
  shot("18_ribbon_summary_next")
  check(rs.monList.currIndex == 1, "down shows the next mon's ribbons")
  press("b")
  waitIdle()
  check(menuId() == "ribbons_return_to_mon_list" and screen().list:selectedIndex() == 1,
    "B returns to the list on the same mon (" .. tostring(menuId()) .. ")")
  U.wait(10)
  shot("19_ribbons_list_back")
  press("b")
  waitIdle()
  check(menuId() == "main_menu_cursor_on_ribbons", "B returns to the main menu on RIBBONS")
  shot("20_main_menu_ribbons")
  press("b")
  check(waitFor(function() return not Pokenav.isOpen() end, 600), "B switches the PokeNav off")
  U.wait(60)
  shot("21_field_after")
  finish()
end
