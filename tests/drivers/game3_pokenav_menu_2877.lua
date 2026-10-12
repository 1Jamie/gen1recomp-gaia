local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_pokenav_menu_2877"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " pokenav_menu_2877 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Ribbons = require("src.core.game3.rse.ribbons")
  local Screens = require("src.ui.game3.screens")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local version = require("src.core.GameVersion").get()
  local C = require("src.core.game3.constants").of(version)
  local rs = version == "ruby" or version == "sapphire"

  local session = Runtime.getSession()
  if not result(session ~= nil, version .. ": new game reached the field") then return finish() end
  session.party = {}
  local _, _, mon = Party.giveMon(session, C:require("species", "SPECIES_ZIGZAGOON"), 12)
  Party.giveMon(session, C:require("species", "SPECIES_TAILLOW"), 10)
  local function setFlag(name, on) Flags.setFlag(Space.store, nil, C:require("flags", name), on ~= false) end
  setFlag("FLAG_SYS_POKENAV_GET")

  local Map = require("src.core.game3.map")
  local route
  for id in pairs(game.data.maps) do if id:sub(-9) == "_ROUTE104" then route = id end end
  local warp = route and game.data.maps[route].warps and game.data.maps[route].warps[1]
  pcall(function() Map.load(Runtime._mod, game, route, { x = warp and warp.x or 10, y = warp and (warp.y + 1) or 10, facing = "down" }) end)
  U.wait(90)
  result(Map.current == route, version .. ": outdoors on " .. tostring(route))
  session = Runtime.getSession()
  local Pokenav = Screens.get("pokenav", session)
  local function shot(name) U.still(game, DIR .. "/2877_" .. name .. ".png") end

  if not rs then
    Pokenav.show({ session = session, game = game })
    local function idle()
      local s = Pokenav.active()
      return s and s.phase == "menu" and not s:busy(s.screenTask) and not s:busy(s.loopTask)
    end
    for _ = 1, 900 do if idle() then break end U.wait(1) end
    result(idle() and Pokenav.active().menuId == "main_menu", "emerald: main menu settles")
    shot("01_em_main_menu")
    U.tap(game, "a")
    for _ = 1, 900 do if idle() and Pokenav.active().menuId == "region_map" then break end U.wait(1) end
    result(Pokenav.active() and Pokenav.active().menuId == "region_map", "emerald: HOENN MAP opens")
    shot("02_em_hoenn_map")
    U.tap(game, "b")
    for _ = 1, 900 do if idle() and Pokenav.active().menuId ~= "region_map" then break end U.wait(1) end
    result(Pokenav.active() and Pokenav.active().menuId == "main_menu_cursor_on_map", "emerald: B returns to the main menu (" .. tostring(Pokenav.active() and Pokenav.active().menuId) .. ")")
    shot("03_em_main_menu_back")
    U.tap(game, "b")
    for _ = 1, 300 do if not Pokenav.isOpen() then break end U.wait(1) end
    result(not Pokenav.isOpen(), "emerald: B switches off")
    return finish()
  end

  local draws, recording = {}, false
  local realDraw = love.graphics.draw
  love.graphics.draw = function(img, a, b, c, ...)
    if recording and type(a) == "userdata" and a.typeOf and a:typeOf("Quad") then
      local qx, qy, qw, qh = a:getViewport()
      draws[#draws + 1] = { img = img, x = b, y = c, qx = qx, qy = qy, w = qw, h = qh }
    end
    return realDraw(img, a, b, c, ...)
  end
  local Kit = require("src.ui.game3.rse.scene_kit")
  local nav = Kit.manifest("rse/pokenav")

  local function settled()
    local s = Pokenav.active()
    if not (s and s.phase == "active" and s.busy == 0 and s.slide == 0) then return false end
    if s.feature then return true end
    for i, off in ipairs(s.offsets) do
      if off ~= ((i - 1 == s.cursor) and -16 or 0) then return false end
    end
    return s.headerScroll == s.headerTarget and s.dotOffset == s.dotTarget
  end
  local function waitSettled()
    for _ = 1, 900 do if settled() then return true end U.wait(1) end
    return settled()
  end
  local function press(btn)
    U.tap(game, btn)
    U.wait(24)
    waitSettled()
    U.wait(4)
  end
  local function headerPieces(key)
    local img = Kit.image(nav.leftHeaders[key].png)
    local out = {}
    draws = {}
    recording = true
    for _ = 1, 600 do
      out = {}
      for _, d in ipairs(draws) do if d.img == img then out[#out + 1] = d end end
      if #out >= 2 then break end
      U.wait(1)
    end
    recording = false
    while #out > 2 do table.remove(out) end
    return out
  end

  Pokenav.show({ session = session, game = game })
  result(waitSettled(), version .. ": main menu settles")
  local s = Pokenav.active()
  result(s and s.menu == "main" and s.cursor == 0, version .. ": main menu, cursor on HOENN MAP")
  local p = headerPieces("main_menu")
  result(#p == 2 and p[1].x == 0 and p[1].y == 33 and p[1].w == 64 and p[2].x == 64 and p[2].y == 33 and p[2].w == 32,
    version .. ": MAIN MENU header pieces at (0,33) 64 wide and (64,33) 32 wide (got " .. (p[2] and (p[2].x .. "," .. p[2].y) or "nil") .. ")")
  shot("01_main_menu_no_ribbons")

  press("down")
  result(s.cursor == 1, version .. ": down moves to CONDITION")
  shot("02_main_menu_cursor_condition")
  press("a")
  result(s.menu == "condition", version .. ": A opens the CONDITION menu")
  p = headerPieces("condition")
  result(#p == 2 and p[2].x == 64 and p[2].y == 33, version .. ": CONDITION header right piece at (64,33)")
  shot("03_condition_menu")
  press("a")
  result(s.menu == "graph_party", version .. ": PARTY opens the condition graph")
  U.wait(30)
  shot("04_condition_graph_party")
  press("b")
  result(s.menu == "condition", version .. ": B returns to the CONDITION menu")
  press("down")
  press("a")
  result(s.menu == "search", version .. ": SEARCH opens the search menu")
  shot("05_condition_search_menu")
  press("a")
  result(s.menu == "condition_results", version .. ": COOL opens the search results")
  U.wait(20)
  shot("06_condition_search_results")
  press("b")
  press("b")
  press("b")
  result(s.menu == "main" and s.cursor == 1, version .. ": B backs out to the main menu on CONDITION")
  press("up")
  press("a")
  result(s.menu == "map", version .. ": HOENN MAP opens (menu " .. tostring(s.menu) .. ", missing " .. tostring(s.missingFeature) .. ")")
  U.wait(20)
  p = headerPieces("hoenn_map")
  result(#p == 2 and p[1].x == 120 and p[2].x == 184, version .. ": HOENN MAP header pieces at x 120 and 184")
  shot("07_hoenn_map")
  press("b")
  result(s.menu == "main" and s.cursor == 0, version .. ": B returns to the main menu on HOENN MAP")

  local r = s.detail.rematches[0]
  Flags.setFlag(Space.store, nil, 0x500 + r.opponentIDs[1], true)
  press("down")
  press("down")
  press("a")
  result(s.menu == "eyes", version .. ": TRAINER'S EYES opens with a fought rematch trainer (menu " .. tostring(s.menu) .. ", cursor " .. s.cursor .. ")")
  U.wait(20)
  p = headerPieces("trainers_eyes")
  result(#p == 2 and p[2].x == 64 and p[2].y == 33 - s.headerScroll, version .. ": TRAINER'S EYES header right piece at x 64 beside the left piece")
  shot("08_trainers_eyes")
  press("b")
  press("b")
  for _ = 1, 300 do if not Pokenav.isOpen() then break end U.wait(1) end
  result(not Pokenav.isOpen(), version .. ": B on the main menu switches off")
  U.wait(30)

  setFlag("FLAG_SYS_RIBBON_GET")
  Ribbons.giveContestRibbon(mon, "cool", 0)
  Pokenav.show({ session = session, game = game })
  result(waitSettled(), version .. ": main menu with RIBBONS settles")
  s = Pokenav.active()
  result(s.rows[4] == true, version .. ": RIBBONS row shown once FLAG_SYS_RIBBON_GET is set")
  shot("09_main_menu_ribbons")
  press("down")
  press("down")
  press("down")
  result(s.cursor == 3, version .. ": cursor reaches RIBBONS")
  press("a")
  result(s.menu == "ribbons_list", version .. ": RIBBONS opens the ribbon list")
  U.wait(20)
  p = headerPieces("ribbons")
  result(#p == 2 and p[2].x == 64 and p[2].y == 33 - s.headerScroll, version .. ": RIBBONS header right piece at x 64 beside the left piece")
  shot("10_ribbons_list")
  press("b")
  press("b")
  for _ = 1, 300 do if not Pokenav.isOpen() then break end U.wait(1) end
  result(not Pokenav.isOpen(), version .. ": switch off after ribbons")
  love.graphics.draw = realDraw
  finish()
end
