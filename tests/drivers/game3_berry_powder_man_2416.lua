local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/bug2416"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_berry_powder_man_2416")
    love.event.quit(0)
  else
    print("FAIL game3_berry_powder_man_2416 failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Bag = require("src.core.game3.bag")
  local Objects = require("src.core.game3.objects")
  local Field = require("src.core.game3.field")
  local Message = package.loaded["src.ui.game3.message"] or require("src.ui.game3.message")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end

  Bag.add(session.bag, 139, 1)
  result(Bag.has(session.bag, 365, 1), "ORAN BERRY auto-granted the BERRY POUCH")

  local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  local mapId = (okC and MapCatalog.pretToEngine and MapCatalog.pretToEngine("CeruleanCity_House5"))
    or "FR_CERULEAN_CITY_HOUSE5"
  Map.load(nil, game, mapId, { x = 8, y = 4, facing = "left" })
  game.session.x, game.session.y, game.session.facing = 8, 4, "left"
  U.wait(30)

  result(Space.store and Flags.getFlag(Space.store, nil, 0x847) == true,
    "FLAG_SYS_GOT_BERRY_POUCH set in the house")
  local man = Objects.find(1)
  if not result(man ~= nil, "Berry Powder man (localId 1) loaded") then return finish() end

  local function vmBusy()
    return Space.vm and Space.vm.isRunning and Space.vm:isRunning()
  end
  local function page()
    return string.upper(Message.currentPage and Message.currentPage() or "")
  end

  U.tap(game, "a")
  local hit, liar = false, false
  for _ = 1, 400 do
    local p = page()
    if p:find("JUST THE THING", 1, true) then hit = true break end
    if p:find("LIE TO ME", 1, true) then liar = true break end
    if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
    U.wait(3)
  end
  result(not liar, "man did not take the NoBerries branch")
  if not result(hit, "man says he has just the thing") then return finish() end
  Message.skipReveal()
  U.wait(10)
  result(U.shot(game, DIR .. "/2416_powder_man_just_the_thing.png"), "screenshot 2416_powder_man_just_the_thing")

  for _ = 1, 400 do
    if not Message.isOpen() and not vmBusy() and not Field.locked then break end
    if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    if Message.isOpen() then U.tap(game, "a") end
    U.wait(3)
  end
  result(Bag.has(session.bag, 372, 1), "POWDER JAR landed in the bag")
  result(Flags.getFlag(Space.store, nil, "FLAG_GOT_POWDER_JAR") == true, "FLAG_GOT_POWDER_JAR set")

  return finish()
end
