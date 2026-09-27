local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_sav_import"
local SAV = os.getenv("POKEPORT_EM_SAV") or ".claude/skills/pygba-headless/assets/pokemon-emerald-all-shiny-fixed.sav"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_sav_import failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function waitFor(pred, limit)
  for _ = 1, limit or 600 do
    if pred() then return true end
    U.wait(1)
  end
  return pred() and true or false
end

local function shot(game, name)
  U.wait(4)
  U.still(game, DIR .. "/" .. name .. ".png")
end

local function topId()
  local t = require("src.ui.game3.stack").top()
  return t and t.id
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
  if not check(waitFor(function() return game.phase == "boot" and game.boot ~= nil end, 900), "boot reached") then
    return finish()
  end
  local f = io.open(SAV, "rb")
  if not check(f ~= nil, "bundled Emerald .sav at " .. SAV) then return finish() end
  local original = f:read("*a")
  f:close()

  local SaveFileIO = require("src.import.SaveFileIO")
  local SaveData = require("src.core.SaveData")
  local ok, slotId, info = SaveFileIO.importToSlot(SAV, "emerald")
  if not check(ok == true, "the cart imports into an Emerald slot (" .. tostring(slotId) .. ")") then return finish() end
  check(info == nil, "no fallback note")
  check(SaveData.activeSlot("emerald") == slotId, "the imported slot is active")

  pcall(function() game:returnToTitle() end)
  check(waitFor(function() return game.phase == "boot" and game.boot ~= nil and game.boot.custom ~= nil end, 600),
    "back at the title")
  local menu = toMenu(game)
  if not check(menu ~= nil, "title START opens the main menu") then return finish() end
  U.wait(60)
  check(menu.items[1] == "CONTINUE", "CONTINUE is offered (" .. tostring(menu.items[1]) .. ")")
  local box = menu.info or {}
  print(string.format("[driver] continue box name=%s badges=%s dex=%s time=%s:%s", tostring(box.name), tostring(box.badges),
    tostring(box.dexCount), tostring(box.hours), tostring(box.minutes)))
  check(box.name == "NICK", "continue box player NICK")
  check(box.hours == 135 and box.minutes == 30, "continue box play time 135:30")
  check(box.badges == 8, "continue box 8 badges like the cart")
  check(box.dexCount == 386, "continue box POKeDEX 386 like the cart")
  shot(game, "01_main_menu_continue")

  pcall(function() game:_handleBootAction({ action = "continue" }) end)
  local Runtime = require("src.core.game3.runtime")
  local s
  check(waitFor(function()
    s = Runtime.getSession()
    return s ~= nil and game.phase ~= "boot"
  end, 1200), "CONTINUE reached the field")
  U.wait(120)
  s = Runtime.getSession()
  if not s then return finish() end
  print(string.format("[driver] field map=%s x=%s y=%s money=%s coins=%s party=%d", tostring(s.map), tostring(s.x),
    tostring(s.y), tostring(s.money), tostring(s.coins), #(s.party or {})))
  check(s.map == "EM_ROUTE117" and s.x == 51 and s.y == 6, "continue lands on Route 117 at 51,6 like the cart")
  check(s.money == 999999 and s.coins == 9999, "money 999999, coins 9999")
  local C = require("src.core.game3.constants").of("emerald")
  local want = { { "SPECIES_SALAMENCE", 50 }, { "SPECIES_MAGCARGO", 38 }, { "SPECIES_SMEARGLE", 100 } }
  for i, w in ipairs(want) do
    local m = s.party[i] or {}
    check(m.species == C:require("species", w[1]) and m.level == w[2],
      ("party %d is %s Lv%d (%s Lv%s)"):format(i, w[1], w[2], tostring(m.species), tostring(m.level)))
  end
  local boxed = 0
  for _, b in pairs(s.storage and s.storage.boxes or {}) do
    for _ in pairs(type(b) == "table" and b.mons or {}) do boxed = boxed + 1 end
  end
  check(boxed == 411, "411 boxed mons (" .. boxed .. ")")
  check(type(s.berryTrees) == "table", "berry trees restored")
  check(type(s.localTimeOffset) == "table" and type(s.rtcSkew) == "number", "RTC offset and anchor restored")
  shot(game, "02_field_route117")

  U.tap(game, "start")
  U.wait(30)
  if check(topId() == "start", "START opens the start menu") then
    local StartMenu = require("src.ui.game3.start_menu")
    for i, e in ipairs(StartMenu.ENTRIES or {}) do
      if e.id == "pokemon" then
        for _ = 1, 20 do
          if StartMenu.cursor == i then break end
          U.tap(game, "down")
          U.wait(6)
        end
        U.tap(game, "a")
        break
      end
    end
    check(waitFor(function() return topId() == "party" end, 240), "POKEMON opens the party screen")
    U.wait(40)
    shot(game, "03_party")
    for _ = 1, 30 do
      if topId() == nil then break end
      U.tap(game, "b")
      U.wait(8)
    end
  end

  local okSave = game:saveGame()
  check(okSave ~= false, "the imported game saves in the port")
  local exOk, path = SaveFileIO.exportActiveSlot("emerald")
  if check(exOk == true, "the slot exports to a .sav (" .. tostring(path) .. ")") then
    local ef = io.open(path, "rb")
    local bytes = ef and ef:read("*a")
    if ef then ef:close() end
    local out = io.open(DIR .. "/em_sav_import_export.sav", "wb")
    if out and bytes then out:write(bytes); out:close() end
    local E = require("src.save_convert.Gen3Save").forVersion("emerald")
    local c = bytes and E.decode(bytes)
    check(c ~= nil and c.name == "NICK" and c.money == 999999, "the export decodes as Emerald with NICK and 999999")
    local a, b = E.readBlocks(original), bytes and E.readBlocks(bytes)
    if b then
      check(b.counter == a.counter + 1, "export writes the next save counter")
      check(E.decode(original).playHours == c.playHours, "play hours carried")
      local party = 0
      for _ = 1, #c.party do party = party + 1 end
      check(party == 3, "three party mons in the export")
    end
  end
  finish()
end
