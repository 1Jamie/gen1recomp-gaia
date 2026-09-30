local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_link_trade_menu"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_link_trade_menu failures=" .. failures)
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

local function body(game)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local C = require("src.core.game3.constants").of("emerald")
  local LinkTradeMenu = require("src.ui.game3.link_trade_menu")
  local session = Runtime.getSession()
  if not check(session and session.version == "emerald", "emerald session") then return end
  session.party = {}
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_TORCHIC"), 10)
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_MUDKIP"), 10)

  check(pcall(function() LinkTradeMenu.show() end), "link trade menu opens without throwing")
  check(LinkTradeMenu.open == true, "link trade menu is open")
  check(LinkTradeMenu.message and LinkTradeMenu.message:find("standby", 1, true) ~= nil, "standby message: " .. tostring(LinkTradeMenu.message))
  U.wait(20)
  check(pcall(function() LinkTradeMenu.draw() end), "link trade menu draws")
  U.still(game, DIR .. "/trade_menu.png")
  LinkTradeMenu.close()
  U.wait(10)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  check(game.boot ~= nil, "boot reached")
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(30)
  try("body", function() body(game) end)
  return finish()
end
