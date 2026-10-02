local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/menu_speed_bug2578"
local failed = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failed = failed + 1 end
  return ok
end

local function gen1(game)
  game.speedOverride = 200
  game.save.party = { require("src.pokemon.Pokemon").new(game.data, "PIKACHU", 20) }
  U.teleport(game, "PALLET_TOWN", 10, 12, "down")
  local Screens = require("src.ui.Screens")
  local Game = require("src.core.Game")
  local opts = game.save.options
  opts.speedOverworld, opts.speedBattle, opts.speedMenu = 4, 10, 2
  game.speedOverride = nil
  check(game:logicSpeed() == 4, "2578_gen1_field_speed")
  for _, name in ipairs({ "StartMenu", "PartyMenu", "BagMenu" }) do
    Screens.push(game, name)
    U.wait(20)
    check(Game.speedCategoryInStack(game.stack) == "menu" and game:logicSpeed() == 2,
      "2578_gen1_field_" .. name .. "_menu_speed")
    check(U.still(game, DIR .. "/2578_gen1_field_" .. name .. ".png"), "2578_gen1_" .. name .. "_shot")
    game.stack:pop()
    check(game:logicSpeed() == 4, "2578_gen1_" .. name .. "_pop_restores_field")
  end
  local Menu = require("src.ui.Menu")
  local function reachPCMenu()
    for _ = 1, 600 do
      local top = game.stack:top()
      if getmetatable(top) == Menu then return top end
      U.tap(game, "a")
      U.wait(2)
    end
    error("actual interactive PC menu was not reached")
  end
  game.overworld:openPC()
  local pc = reachPCMenu()
  check(#pc.items >= 3 and pc.noSound and Game.speedCategoryInStack(game.stack) == "menu"
    and game:logicSpeed() == 2, "2578_gen1_pc_main_uses_MENU_SPEED")
  check(U.still(game, DIR .. "/2578_gen1_pc_main.png"), "2578_gen1_pc_main_shot")
  U.tap(game, "b")
  U.wait(2)
  check(game.stack:top() == game.overworld and game:logicSpeed() == 4,
    "2578_gen1_pc_main_pop_restores_field")

  game.speedOverride = 200
  U.teleport(game, "BILLS_HOUSE", 2, 3, "up")
  game.speedOverride = nil
  game.overworld:billsHousePokemonList()
  local bill = reachPCMenu()
  check(#bill.items == 5 and bill.items[1].keepOpen and Game.speedCategoryInStack(game.stack) == "menu"
    and game:logicSpeed() == 2, "2578_gen1_bill_pc_viewer_uses_MENU_SPEED")
  check(U.still(game, DIR .. "/2578_gen1_bill_pc_viewer.png"), "2578_gen1_bill_pc_viewer_shot")
  U.tap(game, "b")
  U.wait(2)
  check(game.stack:top() == game.overworld and game:logicSpeed() == 4,
    "2578_gen1_bill_pc_viewer_pop_restores_field")
  game.speedOverride = 200
  U.teleport(game, "PALLET_TOWN", 10, 12, "down")
  game.speedOverride = nil
  local battle = require("src.battle.BattleState").newWild(game, "RATTATA", 3)
  game.overworld:pushBattle(battle)
  game.speedOverride = 200
  for _ = 1, 1500 do
    if game.stack:top() == battle and battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(2)
  end
  game.speedOverride = nil
  check(Game.speedCategoryInStack(game.stack) == "battle" and game:logicSpeed() == 10,
    "2578_gen1_actual_battle_speed")
  for _, name in ipairs({ "PartyMenu", "BagMenu" }) do
    Screens.push(game, name, { battle = battle })
    U.wait(20)
    check(game:logicSpeed() == 2, "2578_gen1_battle_" .. name .. "_menu_speed")
    check(U.still(game, DIR .. "/2578_gen1_battle_" .. name .. ".png"), "2578_gen1_battle_" .. name .. "_shot")
    game.stack:pop()
    check(game:logicSpeed() == 10, "2578_gen1_battle_" .. name .. "_pop_restores_battle")
  end
end

local function gen3(game)
  game.speedOverride = 200
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  assert(session, "new game did not reach field")
  session.party = {}
  require("src.core.game3.party").giveMon(session, 25, 20)
  local Stack = require("src.ui.game3.stack")
  local Start = require("src.ui.game3.start_menu")
  local Party = require("src.ui.game3.party_menu")
  local Bag = require("src.ui.game3.bag_menu")
  game.options.speedOverworld, game.options.speedBattle, game.options.speedMenu = 4, 10, 2
  game.speedOverride = nil
  check(game:logicSpeed() == 4, "2578_gen3_field_speed")
  local menus = {
    { id = "start", open = function() Start.show({ session = session, game = game }) end, close = Start.close },
    { id = "party", open = function() Party.show(session.party, nil, { session = session }) end, close = Party.close },
    { id = "bag", open = function() Bag.show(session, { session = session }) end, close = Bag.close },
  }
  for _, menu in ipairs(menus) do
    menu.open()
    U.wait(120)
    check(Stack.has(menu.id) and game:logicSpeed() == 2, "2578_gen3_field_" .. menu.id .. "_menu_speed")
    check(U.still(game, DIR .. "/2578_gen3_field_" .. menu.id .. ".png"), "2578_gen3_" .. menu.id .. "_shot")
    menu.close()
    check(game:logicSpeed() == 4, "2578_gen3_" .. menu.id .. "_pop_restores_field")
  end
  local Battle = require("src.core.game3.battle")
  local Bridge = require("src.core.game3.battle_bridge")
  local started, err = Bridge.startWild(Runtime._mod, game, { species = 16, level = 3 }, { fade = false })
  assert(started, tostring(err))
  game.speedOverride = 200
  for _ = 1, 1800 do
    if Battle._phase == "command" then break end
    U.tap(game, "a")
    U.wait(2)
  end
  game.speedOverride = nil
  check(Battle.isActive() and game:logicSpeed() == 10, "2578_gen3_actual_battle_speed")
  Party.show(session.party, nil, { session = session, battle = true, mode = "battle_switch" })
  U.wait(120)
  check(game:logicSpeed() == 2, "2578_gen3_battle_party_menu_speed")
  check(U.still(game, DIR .. "/2578_gen3_battle_party.png"), "2578_gen3_battle_party_shot")
  Party.close()
  check(game:logicSpeed() == 10, "2578_gen3_battle_party_pop_restores_battle")
  Bag.show(session, { session = session, battle = true })
  U.wait(120)
  check(game:logicSpeed() == 2 and Stack.top().fullscreen == false, "2578_gen3_nonfullscreen_battle_bag_menu_speed")
  check(U.still(game, DIR .. "/2578_gen3_battle_bag.png"), "2578_gen3_battle_bag_shot")
  Bag.close()
  check(game:logicSpeed() == 10, "2578_gen3_battle_bag_pop_restores_battle")
end

return function(game)
  local ok, err = xpcall(function()
    if game.phase ~= nil then gen3(game) else gen1(game) end
  end, debug.traceback)
  if not ok then failed = failed + 1; print("FAIL 2578_driver " .. tostring(err)) end
  print((failed == 0 and "PASS " or "FAIL ") .. "2578_menu_speed failures=" .. failed)
  love.event.quit(failed == 0 and 0 or 1)
end
