local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_itemfinder"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_itemfinder failures=" .. failures)
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
  local Field = require("src.core.game3.field")
  local Itemfinder = require("src.core.game3.itemfinder")
  local RomText = require("src.core.game3.rom_text")
  local Message = require("src.ui.game3.message")
  local session = Runtime.getSession()
  if not check(session and session.version == "emerald", "emerald session") then return end

  check(Itemfinder.textKey("nothing", session) == "gText_ItemFinderNothing", "nothing key")
  check(Itemfinder.textKey("nearby", session) == "gText_ItemFinderNearby", "nearby key")
  check(Itemfinder.textKey("onTop", session) == "gText_ItemFinderOnTop", "on top key")
  for _, k in ipairs({ "gText_ItemFinderNothing", "gText_ItemFinderNearby", "gText_ItemFinderOnTop" }) do
    check(select(1, pcall(RomText.box, k)), "text exists " .. k)
  end

  local ok, kind, text = Field.useItemfinder(session, true)
  check(ok == false and kind == "itemfinder", "itemfinder with nothing nearby returns no response")
  check(text and text:find("no response", 1, true) ~= nil, "nothing text: " .. tostring(text))
  U.wait(40)
  check(Message.isOpen and Message.isOpen(), "message shown")
  U.still(game, DIR .. "/nothing.png")
  Message.close()
  Field.unlock()

  local sawUnderfoot = false
  local ok2 = pcall(function()
    local r = Field.digUpUnderfootItem(Field._game, { flag = 1 })
    sawUnderfoot = (r == false)
  end)
  check(ok2 and sawUnderfoot, "underfoot branch only closes the message on Emerald")
  Field.unlock()
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
