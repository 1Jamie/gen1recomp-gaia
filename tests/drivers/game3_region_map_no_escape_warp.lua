local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_region_map_no_escape_warp"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " region_map_no_escape_warp failures=" .. failures)
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
  local Screens = require("src.ui.game3.screens")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Map = require("src.core.game3.map")
  local version = require("src.core.GameVersion").get()
  local C = require("src.core.game3.constants").of(version)
  local rs = version == "ruby" or version == "sapphire"

  local session = Runtime.getSession()
  if not result(session ~= nil, version .. ": new game reached the field") then return finish() end
  Flags.setFlag(Space.store, nil, C:require("flags", "FLAG_SYS_POKENAV_GET"), true)
  local Pokenav = Screens.get("pokenav", session)

  local function emIdle()
    local s = Pokenav.active()
    return s and s.phase == "menu" and not s:busy(s.screenTask) and not s:busy(s.loopTask)
  end
  local function rsSettled()
    local s = Pokenav.active()
    if not (s and s.phase == "active" and s.busy == 0 and s.slide == 0) then return false end
    if s.feature then return true end
    for i, off in ipairs(s.offsets) do
      if off ~= ((i - 1 == s.cursor) and -16 or 0) then return false end
    end
    return s.headerScroll == s.headerTarget and s.dotOffset == s.dotTarget
  end
  local function waitUntil(pred, n)
    for _ = 1, n or 900 do if pred() then return true end U.wait(1) end
    return pred()
  end

  local function openMap(tag, wantSec, wantX, wantY)
    Pokenav.show({ session = Runtime.getSession(), game = game })
    if rs then
      result(waitUntil(rsSettled), version .. " " .. tag .. ": main menu settles")
      local s = Pokenav.active()
      U.tap(game, "a")
      waitUntil(function() return s.menu == "map" or s.missingFeature ~= nil end, 60)
      waitUntil(rsSettled)
      result(s.menu == "map", version .. " " .. tag .. ": HOENN MAP opens (missing " .. tostring(s.missingFeature) .. ")")
      local f = s.feature
      if f and s.menu == "map" then
        result(f.section == wantSec, version .. " " .. tag .. ": cursor mapsec " .. tostring(f.section) .. " want " .. tostring(wantSec))
        result(f.x == wantX and f.y == wantY, version .. " " .. tag .. ": cursor cell (" .. f.x .. "," .. f.y .. ") want (" .. wantX .. "," .. wantY .. ")")
      end
      U.wait(30)
      U.still(game, DIR .. "/regionmap_" .. tag .. ".png")
      U.tap(game, "b")
      waitUntil(function() return s.menu == "main" and rsSettled() end)
      result(s.menu == "main", version .. " " .. tag .. ": one B returns to the main menu")
    else
      result(waitUntil(emIdle), version .. " " .. tag .. ": main menu settles")
      U.tap(game, "a")
      waitUntil(function() return emIdle() and Pokenav.active().menuId == "region_map" end)
      local s = Pokenav.active()
      result(s.menuId == "region_map", version .. " " .. tag .. ": HOENN MAP opens")
      local rm = s.screen and s.screen.rm
      if rm then
        result(rm.mapSecId == wantSec, version .. " " .. tag .. ": cursor mapsec " .. tostring(rm.mapSecId) .. " want " .. tostring(wantSec))
        result(rm.cursorX == wantX and rm.cursorY == wantY, version .. " " .. tag .. ": cursor cell (" .. rm.cursorX .. "," .. rm.cursorY .. ") want (" .. wantX .. "," .. wantY .. ")")
      end
      U.still(game, DIR .. "/regionmap_" .. tag .. ".png")
      U.tap(game, "b")
      waitUntil(function() return emIdle() and s.menuId ~= "region_map" end)
      result(s.menuId == "main_menu_cursor_on_map", version .. " " .. tag .. ": one B on the first idle frame returns to the main menu (" .. tostring(s.menuId) .. ")")
    end
    U.tap(game, "b")
    waitUntil(function() return not Pokenav.isOpen() end, 300)
    result(not Pokenav.isOpen(), version .. " " .. tag .. ": B switches off")
    U.wait(20)
  end

  local secs, entryOf
  if rs then
    local man = require("src.ui.game3.rs.pokenav.gfx").manifest("region_map")
    secs = man and man.mapsecs
    entryOf = function(id) return man.sections[id] end
  else
    local RegionMap = require("src.ui.game3.rse.region_map")
    secs = RegionMap.manifest().mapsecs
    entryOf = function(id) return require("src.ui.game3.rse.mapsec").entry(id) end
  end
  if not result(secs ~= nil, version .. ": region map manifest loaded") then return finish() end

  session = Runtime.getSession()
  result(session.map and session.map:sub(-15) == "INSIDE_OF_TRUCK", version .. ": in the moving truck (" .. tostring(session.map) .. ")")
  result(session.escapeWarp == nil, version .. ": truck has no escape warp")
  local function originCell(id)
    local e = entryOf(id)
    local x, y = 0, 0
    if x >= e.width then x = e.width - 1 end
    if y >= e.height then y = e.height - 1 end
    return e.x + x + 1, e.y + y + 2
  end
  local truckSec = tonumber(game.data.maps[session.map].regionMapSectionId)
  local tx, ty = originCell(truckSec)
  openMap("01_truck", truckSec, tx, ty)

  local store
  for id in pairs(game.data.maps) do if id:match("LILYCOVE_CITY_DEPARTMENT_STORE_1F$") then store = id end end
  pcall(function() Map.load(Runtime._mod, game, store, { x = 4, y = 5, facing = "down" }) end)
  U.wait(60)
  session = Runtime.getSession()
  session.escapeWarp = nil
  result(Map.current == store, version .. ": indoors in " .. tostring(store))
  local storeSec = tonumber(game.data.maps[store].regionMapSectionId)
  local sx, sy = originCell(storeSec)
  openMap("02_indoor_no_escape_warp", storeSec, sx, sy)
  finish()
end
