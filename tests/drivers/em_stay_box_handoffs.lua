local U = require("tests.drivers.util")
local L = require("tests.drivers.em_battle_loop")

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_stay_box_handoffs failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

return function(game)
  io.stdout:setvbuf("line")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Party = require("src.core.game3.party")
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Stack = require("src.ui.game3.stack")
  local Field = require("src.core.game3.field")
  local Battle = require("src.core.game3.battle")
  local Safari = require("src.core.game3.safari")
  local Encounters = require("src.core.game3.encounters")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not result(session ~= nil, "field session exists") then return finish() end
  Encounters.onStep = function() return nil end
  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_SWAMPERT, 40, "")

  local function running() return Space.vm and Space.vm:isRunning() end
  local function untilTrue(fn, frames, step)
    for _ = 1, frames do
      if fn() then return true end
      U.wait(step or 2)
    end
    return fn() and true or false
  end
  local function answerYes()
    local opened = untilTrue(function()
      if Choice.isOpen and Choice.isOpen() then return true end
      if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
      return false
    end, 900, 4)
    if opened then U.wait(6); U.tap(game, "a") end
    return opened
  end
  local function idle()
    return not running() and not Message.isOpen() and not (Choice.isOpen and Choice.isOpen())
  end
  local function settle(label)
    local ok = untilTrue(function()
      if Message.isOpen() and not Choice.isOpen() then U.tap(game, "a") end
      return not running()
    end, 900, 4)
    result(ok, label .. ": script finished")
    U.wait(30)
  end
  local function load(id, x, y, facing)
    local ok, err = pcall(function() Map.load(nil, game, id, { x = x, y = y, facing = facing }) end)
    result(ok, "load " .. id .. " " .. tostring(err or ""))
    session.map = id
    U.wait(60)
  end
  local function start(label, localId)
    local key = Space.scriptKey(label)
    local ok = key and Space.startScript(key, localId)
    return result(ok and true or false, label .. " starts")
  end

  -- pokeemerald/data/scripts/safari_zone.inc:19 warp after MSGBOX_YESNO
  Safari.enter(session)
  load("EM_SAFARI_ZONE_SOUTH", 10, 20, "up")
  if start("SafariZone_EventScript_RetirePrompt") and answerYes() then
    local warped = untilTrue(function()
      return Map.current == "EM_ROUTE121_SAFARI_ZONE_ENTRANCE" and not running()
    end, 1500, 4)
    result(warped, "safari retire: warped to entrance (" .. tostring(Map.current) .. ")")
    untilTrue(function() return not Field.locked end, 300, 2)
    result(not Message.isOpen(), "safari retire: stay box closed after warp")
    result(not Field.locked, "safari retire: field unlocked after warp")
  else
    result(false, "safari retire: prompt opened")
  end
  Safari.exit(session)

  -- pokeemerald/data/scripts/safari_zone.inc:41 fadescreen + special OpenPokeblockCaseOnFeeder
  Safari.enter(session)
  load("EM_SAFARI_ZONE_SOUTH", 10, 20, "up")
  if start("EventScript_PokeBlockFeeder") and answerYes() then
    local screen = untilTrue(function() return Stack.depth() > 0 or not running() end, 900, 4)
    result(screen, "pokeblock feeder: reached a screen or finished")
    result(not Message.isOpen(), "pokeblock feeder: stay box closed at screen hand-off")
    for _ = 1, 4 do
      if Stack.depth() > 0 then U.tap(game, "b"); U.wait(20) end
    end
    settle("pokeblock feeder")
    result(idle(), "pokeblock feeder: idle afterwards")
    result(not Field.locked, "pokeblock feeder: field unlocked after cancel")
    result(not Field.isLocked(), "pokeblock feeder: no field lock tags remain")
  else
    result(false, "pokeblock feeder: prompt opened")
  end
  Safari.exit(session)

  -- pokeemerald/data/maps/RustboroCity_House1/scripts.inc:12 special ChoosePartyMon
  load("EM_RUSTBORO_CITY_HOUSE1", 4, 6, "up")
  if start("RustboroCity_House1_EventScript_Trader", 1) and answerYes() then
    local party = untilTrue(function() return Stack.has("party") or not running() end, 900, 4)
    result(party and Stack.has("party"), "rustboro trade: party menu opened")
    result(not Message.isOpen(), "rustboro trade: stay box closed at party menu")
    U.tap(game, "b"); U.wait(20)
    settle("rustboro trade")
    result(idle(), "rustboro trade: idle afterwards")
    result(not Field.locked, "rustboro trade: field unlocked")
  else
    result(false, "rustboro trade: prompt opened")
  end

  -- stayed box straight into dowildbattle (synthetic chain over real ops)
  load("EM_ROUTE104", 10, 10, "down")
  local key = "synthetic_stay_wild"
  Space.vm.scripts[key] = {
    { op = "lockall" },
    { op = "message", ptr = "SafariZone_Text_WouldYouLikeToExit" },
    { op = "setwildbattle", C.species.byName.SPECIES_ZIGZAGOON, 3 },
    { op = "dowildbattle" },
    { op = "releaseall" },
    { op = "end" },
  }
  result(Space.startScript(key) and true or false, "synthetic stay+wild battle starts")
  local inBattle = untilTrue(function() return Battle.isActive() end, 1500, 2)
  result(inBattle, "wild battle started")
  if inBattle then
    result(not Message.isOpen(), "stay+wild: stay box closed once battle is up")
    local over = L.run(game, { turnCap = 60, guard = 60000 })
    result(over, "wild battle ended turn=" .. tostring(Battle._st and Battle._st.turn) .. " phase=" .. tostring(Battle._phase))
    U.wait(60)
    settle("stay+wild")
  end
  result(not Message.isOpen(), "stay+wild: stay box closed after battle")
  result(not Field.locked, "stay+wild: field unlocked")

  -- pokeemerald/data/maps/Route104/scripts.inc:832 trainerbattle_single behind a stayed box
  load("EM_ROUTE104", 10, 10, "down")
  local ivanKey = Space.scriptKey("Route104_EventScript_Ivan")
  local ivan = ivanKey and Space.vm.scripts[ivanKey]
  result(type(ivan) == "table", "ivan script resolves")
  if type(ivan) == "table" then
    local chain = { { op = "lockall" }, { op = "message", ptr = "SafariZone_Text_WouldYouLikeToExit", stay = true } }
    for _, row in ipairs(ivan) do chain[#chain + 1] = row end
    Space.vm.scripts["synthetic_stay_trainer"] = chain
    result(Space.startScript("synthetic_stay_trainer") and true or false, "synthetic stay+trainer starts")
    local sawStay = untilTrue(function() return Message.isOpen() end, 300, 1)
    result(sawStay, "stay+trainer: stay box opened first")
    local tb = untilTrue(function()
      if Message.isOpen() and Message.isWaiting() and not Battle.isActive() then U.tap(game, "a") end
      return Battle.isActive()
    end, 3000, 2)
    result(tb, "stay+trainer: trainer battle started")
    if tb then
      result(not Message.isOpen(), "stay+trainer: stay box closed once battle is up")
      local over = L.run(game, { turnCap = 60, guard = 60000 })
      result(over, "trainer battle ended")
      U.wait(60)
      settle("stay+trainer")
    end
    result(not Message.isOpen(), "stay+trainer: stay box closed after battle")
    result(not Field.locked, "stay+trainer: field unlocked")
  end

  -- pokeemerald/data/maps/LavaridgeTown_HerbShop/scripts.inc:7 message then pokemart
  load("EM_LAVARIDGE_TOWN_HERB_SHOP", 3, 4, "up")
  if start("LavaridgeTown_HerbShop_EventScript_Clerk", 1) then
    local ShopMenu = require("src.ui.game3.shop_menu")
    local shop = untilTrue(function()
      if Message.isOpen() and Message.isWaiting() and not ShopMenu.isOpen() then U.tap(game, "a") end
      return ShopMenu.isOpen()
    end, 1500, 2)
    result(shop, "herb shop: shop menu opened")
    result(not Message.isOpen(), "herb shop: stay box closed at shop")
    for _ = 1, 6 do
      if ShopMenu.isOpen() then U.tap(game, "b"); U.wait(20) end
    end
    settle("herb shop")
    result(not Field.locked, "herb shop: field unlocked")
  end

  -- pokeemerald/data/maps/Route112_CableCarStation/scripts.inc:50 stayed box then special CableCar
  load("EM_ROUTE112_CABLE_CAR_STATION", 6, 8, "up")
  Space.vm.scripts["synthetic_stay_cablecar"] = {
    { op = "lockall" },
    { op = "message", ptr = "SafariZone_Text_WouldYouLikeToExit", stay = true },
    { op = "special", id = 155 },
    { op = "releaseall" },
    { op = "end" },
  }
  result(Space.startScript("synthetic_stay_cablecar") and true or false, "synthetic stay+cable car starts")
  local cc = untilTrue(function()
    if Message.isOpen() and Message.isWaiting() and Stack.depth() == 0 then U.tap(game, "a") end
    return Stack.has("cable_car")
  end, 900, 2)
  result(cc, "stay+cable car: scene opened")
  result(not Message.isOpen(), "stay+cable car: stay box closed at scene")
  while Stack.depth() > 0 do Stack.pop() end
  U.wait(10)

  finish()
end
