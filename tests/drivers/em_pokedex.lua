local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_pokedex"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_pokedex failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok, err
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  try("new_game", function()
    game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  end)
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Dex = require("src.core.game3.dex")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Stack = require("src.ui.game3.stack")
  local Pokedex = require("src.ui.game3.rse.pokedex")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session ~= nil, "new game session") then return finish() end

  Flags.setVar(Space.store, nil, C:var("VAR_LITTLEROOT_INTRO_STATE"), 7)
  Flags.setVar(Space.store, nil, C:var("VAR_LITTLEROOT_TOWN_STATE"), 4)
  Flags.setVar(Space.store, nil, C:var("VAR_ROUTE101_STATE"), 3)
  Flags.setFlag(Space.store, nil, C:flag("FLAG_RESCUED_BIRCH"), true)
  try("route101", function() Map.load(nil, game, "EM_ROUTE101", { x = 10, y = 10, facing = "down" }) end)
  U.wait(40)

  local sp = C.species.byName
  session.dex = session.dex or Dex.new()
  for _, name in ipairs({ "SPECIES_TREECKO", "SPECIES_GROVYLE", "SPECIES_ZIGZAGOON", "SPECIES_WURMPLE" }) do
    Dex.setSeen(session.dex, sp[name])
    Dex.setCaught(session.dex, sp[name])
  end
  Dex.setSeen(session.dex, sp.SPECIES_POOCHYENA)

  local function waitFn(name, limit)
    for _ = 1, limit or 600 do
      local s = Pokedex.active()
      if s and s.fn == name then return true end
      U.wait(1)
    end
    local s = Pokedex.active()
    print("[driver] waitFn " .. name .. " timed out at fn=" .. tostring(s and s.fn) .. " state=" .. tostring(s and s.state))
    return false
  end

  local ok, err = try("Pokedex.show", function() Pokedex.show(session.dex, { session = session }) end)
  check(ok, "rse Pokedex opens " .. tostring(err or ""))
  local s = Pokedex.active()
  if not check(s ~= nil and Stack.has(Pokedex.ID), "Pokedex is on the UI stack") then return finish() end
  check(waitFn("mainInput", 300), "Hoenn list page loads and takes input")
  check(s.dexMode == 0 and not s.nationalEnabled, "Hoenn mode (national dex not enabled)")
  check(s.list.count == 14, "Hoenn list runs to the last seen entry, WURMPLE #014 (" .. tostring(s.list.count) .. ")")
  check(s.seenCount == 5 and s.ownCount == 4, string.format("SEEN %d OWN %d", s.seenCount, s.ownCount))
  check(s.list.items[0].dexNum == 252 and s.list.items[0].owned, "entry 0 is TREECKO, owned")
  check(s.list.items[2].seen == false, "entry 2 SCEPTILE unseen")
  U.wait(10)
  U.still(game, DIR .. "/01_hoenn_list.png")
  U.tap(game, "start")
  check(waitFn("startMenu", 30), "START opens the list menu")
  U.wait(20)
  check(s.menuY == 80, "list menu slid up to BG0VOFS 80 (" .. tostring(s.menuY) .. ")")
  U.still(game, DIR .. "/01b_start_menu.png")
  U.tap(game, "b")
  check(waitFn("mainInput", 30), "B closes the list menu")
  U.wait(20)

  U.tap(game, "a")
  check(waitFn("infoInput", 400), "A opens the info page (mon slides to 48,56)")
  local info = s.info
  local texts = {}
  for _, t in ipairs(info and info.text or {}) do texts[#texts + 1] = t.text end
  local joined = table.concat(texts, "|")
  print("[driver] info text: " .. joined:gsub("\n", " "))
  check(joined:find("TREECKO", 1, true) ~= nil, "info shows TREECKO")
  check(joined:find("WOOD GECKO", 1, true) ~= nil, "info shows the category WOOD GECKO POKéMON")
  check(joined:find("11.0 lbs.", 1, true) ~= nil, "info shows the weight 11.0 lbs.")
  U.still(game, DIR .. "/02_info_treecko.png")

  U.tap(game, "b")
  check(waitFn("mainInput", 400), "B returns to the list")
  for _ = 1, 40 do
    if s.selected >= 11 then break end
    U.hold(game, "down", 1)
    for _ = 1, 60 do
      if s.fn == "mainInput" and s.scrollTimer == 0 then break end
      U.wait(1)
    end
    U.wait(1)
  end
  check(s.selected == 11, "list cursor on ZIGZAGOON (" .. tostring(s.selected) .. ")")
  U.wait(10)
  U.still(game, DIR .. "/03_list_zigzagoon.png")
  U.tap(game, "a")
  check(waitFn("infoInput", 400), "ZIGZAGOON info page")
  check(s.selectedScreen == 0, "select bar on AREA")
  U.tap(game, "a")
  check(waitFn("areaInput", 400), "A on AREA opens the area screen")
  local a = s.area
  local secs = {}
  for _, o in ipairs(a and a.found.overworld or {}) do secs[#secs + 1] = o.sec end
  table.sort(secs)
  print("[driver] zigzagoon overworld mapsecs: " .. table.concat(secs, ","))
  check(#secs >= 5, "Zigzagoon glows on several routes (" .. #secs .. ")")
  local has101 = false
  for _, sec in ipairs(secs) do if sec == 16 then has101 = true end end
  check(has101, "Route 101 (mapsec 16) is highlighted")
  U.wait(40)
  U.still(game, DIR .. "/04_area_zigzagoon.png")
  U.wait(30)
  U.still(game, DIR .. "/04_area_zigzagoon_b.png")

  U.tap(game, "right")
  check(waitFn("cryInput", 400), "right on the area screen opens the cry screen")
  U.wait(10)
  U.tap(game, "a")
  U.wait(24)
  U.still(game, DIR .. "/05_cry_zigzagoon.png")
  check(s.cry and s.cry.cryState ~= 0 or s.cryPlaying, "A plays the cry and drives the waveform")
  U.wait(60)

  U.tap(game, "right")
  check(waitFn("sizeInput", 400), "right on the cry screen opens the size screen (owned)")
  U.wait(10)
  U.still(game, DIR .. "/06_size_zigzagoon.png")

  U.tap(game, "b")
  check(waitFn("infoInput", 400), "B returns to info")
  U.tap(game, "b")
  check(waitFn("mainInput", 400), "B returns to the list")

  U.tap(game, "select")
  check(waitFn("searchTopBar", 400), "SELECT opens the search screen")
  U.wait(10)
  U.still(game, DIR .. "/07_search.png")
  U.tap(game, "a")
  check(waitFn("searchMenu", 60), "A on SEARCH enters the parameter menu")
  U.tap(game, "down")
  U.wait(4)
  check(s.searchState.menuItem == 1, "down moves to COLOR")
  U.tap(game, "a")
  check(waitFn("searchParam", 60), "A opens the color list")
  for _ = 1, 4 do
    U.tap(game, "down")
    U.wait(4)
  end
  U.still(game, DIR .. "/08_search_color_green.png")
  local sel = Pokedex.searchModeSelection(s.searchState, 1)
  check(sel == 3, "color selection is GREEN (" .. tostring(sel) .. ")")
  U.tap(game, "a")
  check(waitFn("searchMenu", 60), "A keeps GREEN")
  for _ = 1, 4 do
    U.tap(game, "down")
    U.wait(4)
  end
  check(s.searchState.menuItem == 6, "cursor on OK (" .. tostring(s.searchState.menuItem) .. ")")
  U.tap(game, "a")
  check(waitFn("searchDone", 400), "search completes")
  check(s.list.count == 2, "green search finds TREECKO and GROVYLE (" .. tostring(s.list.count) .. ")")
  U.still(game, DIR .. "/09_search_done.png")
  U.tap(game, "a")
  check(waitFn("mainInput", 400), "search results list")
  check(s.page == 3 and s.isSearchResults, "search results page")
  U.wait(10)
  U.still(game, DIR .. "/10_search_results.png")
  U.tap(game, "b")
  for _ = 1, 30 do
    if s.fn ~= "mainInput" then break end
    U.wait(1)
  end
  check(waitFn("mainInput", 400), "B leaves the search results")
  check(s.page == 0 and s.list.count == 14, "back on the full Hoenn list (" .. tostring(s.page) .. "," .. tostring(s.list.count) .. ")")
  U.tap(game, "b")
  for _ = 1, 200 do
    if not Pokedex.active() then break end
    U.wait(1)
  end
  check(Pokedex.active() == nil and not Stack.has(Pokedex.ID), "B closes the Pokedex")

  Dex.enableNational(session)
  Dex.setSeen(session.dex, sp.SPECIES_PIKACHU)
  Pokedex.show(session.dex, { session = session })
  s = Pokedex.active()
  check(waitFn("mainInput", 300), "national-enabled Pokedex opens")
  check(s.nationalEnabled, "national dex enabled (magic + var + flag)")
  U.wait(10)
  U.still(game, DIR .. "/11_list_national_enabled.png")
  U.tap(game, "b")
  for _ = 1, 200 do
    if not Pokedex.active() then break end
    U.wait(1)
  end

  local done = false
  Pokedex.showCaughtMon(sp.SPECIES_ZIGZAGOON, { session = session, onDone = function() done = true end })
  s = Pokedex.active()
  check(waitFn("caughtInput", 400), "caught-mon registration page (DisplayCaughtMonDexPage)")
  U.wait(10)
  U.still(game, DIR .. "/12_caught_registration.png")
  U.tap(game, "a")
  for _ = 1, 200 do
    if done then break end
    U.wait(1)
  end
  check(done, "caught page returns")
  return finish()
end
