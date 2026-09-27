local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_main_menu"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_main_menu failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok
end

local function waitFor(pred, limit)
  for _ = 1, limit or 600 do
    if pred() then return true end
    U.wait(1)
  end
  return pred() and true or false
end

local function shot(game, name)
  U.still(game, DIR .. "/" .. name .. ".png")
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
  local menu = toMenu(game)
  if not check(menu ~= nil, "title START opens the Emerald main menu") then return finish() end
  U.wait(60)
  check(menu.items[1] == "NEW_GAME", "no save: NEW GAME first (" .. tostring(menu.items[1]) .. ")")
  shot(game, "01_main_menu_new_game")
  U.tap(game, "down")
  U.wait(20)
  check(menu.cursor == 2, "down moves the highlight to OPTION")
  shot(game, "02_main_menu_option")
  U.tap(game, "a")
  local custom = game.boot.custom
  check(waitFor(function() return menu.state == "options" end, 120), "OPTION opens the option menu")
  U.wait(40)
  shot(game, "03_option_menu")
  U.tap(game, "b")
  check(waitFor(function() return menu.state == "input" end, 200), "B returns to the main menu")
  U.wait(30)

  try("new_game", function()
    game:_handleBootAction({ action = "new_game", name = "NICK", gender = 0 })
  end)
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  if not check(session ~= nil, "new game session") then return finish() end
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local Dex = require("src.core.game3.dex")
  local Options = require("src.core.game3.options")
  local IDS = Flags.forVersion("emerald").IDS
  local store = Space.store or session
  Flags.setFlag(store, nil, IDS.FLAG_SYS_POKEDEX_GET, true)
  for i = 1, 8 do Flags.setFlag(store, nil, IDS[string.format("FLAG_BADGE0%d_GET", i)], true) end
  Dex.enableNational(session)
  Flags.setFlag(store, nil, IDS.FLAG_SYS_NATIONAL_DEX, true)
  Flags.setVar(store, nil, Flags.forVersion("emerald").VAR_IDS.VAR_NATIONAL_DEX, 0x302)
  session.dex = session.dex or Dex.new()
  for sp = 1, 411 do
    local ok, nat = pcall(require("src.core.game3.pokemon").national, sp)
    if ok and nat and nat >= 1 and nat <= 386 then Dex.setCaught(session.dex, sp) end
  end
  session.playtime = { hours = 135, minutes = 30, seconds = 0 }
  session.playTime = session.playtime
  Options.set(session, "frameType", 4)
  local okSave = game:saveGame()
  check(okSave ~= false, "saveGame wrote the slot")
  try("returnToTitle", function() game:returnToTitle() end)
  check(waitFor(function() return game.phase == "boot" and game.boot ~= nil and game.boot.custom ~= nil end, 600),
    "back at the boot state")
  local menu2 = toMenu(game)
  if not check(menu2 ~= nil, "title START opens the main menu again") then return finish() end
  U.wait(60)
  check(menu2.items[1] == "CONTINUE", "saved game: CONTINUE first (" .. tostring(menu2.items[1]) .. ")")
  local info = menu2.info or {}
  print(string.format("[driver] continue info name=%s dex=%s badges=%s time=%s:%s frame=%s", tostring(info.name),
    tostring(info.dexCount), tostring(info.badges), tostring(info.hours), tostring(info.minutes), tostring(info.frameType)))
  check(info.badges == 8 and (info.dexCount or 0) >= 202 and info.name == "NICK", "continue box shows NICK, 8 badges and the caught count")
  shot(game, "04_main_menu_continue")
  U.tap(game, "down")
  U.wait(20)
  shot(game, "05_main_menu_continue_down")
  return finish()
end
