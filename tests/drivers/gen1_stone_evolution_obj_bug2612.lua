return function(game)
  local U = require("tests.drivers.util")
  local Pokemon = require("src.pokemon.Pokemon")
  local PaletteFX = require("src.render.PaletteFX")
  local Screens = require("src.ui.Screens")
  local shots = assert(os.getenv("POKEPORT_SHOT_DIR"))
  local failed = false
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    failed = failed or not ok
    return ok
  end
  local function waitFor(fn, ticks)
    for _ = 1, ticks or 12000 do
      if fn() then return true end
      U.wait(1)
    end
    return fn()
  end
  local function evo()
    for _, state in ipairs(game.stack.states) do
      if state.screenId == "EvolutionState" then return state end
    end
  end
  local function top() return game.stack:top() end
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  game.save.options.textSpeed = 1
  game.save.options.colors = "ogred"
  PaletteFX.setMode("ogred")
  game.save.party = {}
  for _, species in ipairs({ "WEEPINBELL", "PIKACHU", "PIDGEY", "RATTATA", "BULBASAUR", "SQUIRTLE" }) do
    game.save.party[#game.save.party + 1] = Pokemon.new(game.data, species, 30)
  end
  local mon = game.save.party[1]
  game.save.inventory = { LEAF_STONE = 2 }
  game.save.bagOrder = { "LEAF_STONE" }
  game.bagSavedMenuItem, game.bagListScrollOffset, game.partyMenuSavedIndex = 0, 0, 1
  Screens.push(game, "BagMenu")
  U.tap(game, "a")
  U.wait(3)
  U.tap(game, "a")
  if not check(waitFor(function() return top() and top().screenId == "PartyMenu" end, 300),
    "2612_actual_stone_party_picker") then love.event.quit(1) return end
  check(U.still(game, shots .. "/2612_six_party_icons_before_evolution.png"), "2612_party_picker_shot")
  U.tap(game, "a")
  if not check(waitFor(function() local t = top() return t and t.t and t.t < 50 and not evo() end),
    "2612_intro_hold_reached") then love.event.quit(1) return end
  check(U.still(game, shots .. "/2612_intro_text_with_party_icons.png"), "2612_intro_shot")
  if not check(waitFor(function() local e = evo() return e and e.loading end),
    "2612_loading_reached") then love.event.quit(1) return end
  check(U.still(game, shots .. "/2612_loading_no_party_icons.png"), "2612_loading_shot")
  check(#PaletteFX.uiSpriteRedraws() == 0, "2612_loading_no_party_obj_replay")
  if not check(waitFor(function() local e = evo() return e and not e.loading and e.t >= 90 and e.t <= 94 end),
    "2612_old_form_flash_reached") then love.event.quit(1) return end
  check(U.still(game, shots .. "/2612_weepinbell_flash_no_party_icons.png"), "2612_old_flash_shot")
  check(#PaletteFX.uiSpriteRedraws() == 0, "2612_old_flash_no_party_obj_replay")
  if not check(waitFor(function() local e = evo() return e and e.t >= 96 and e.t <= 98 end),
    "2612_new_form_flash_reached") then love.event.quit(1) return end
  check(U.still(game, shots .. "/2612_victreebel_flash_no_party_icons.png"), "2612_new_flash_shot")
  check(#PaletteFX.uiSpriteRedraws() == 0, "2612_new_flash_no_party_obj_replay")
  if not check(waitFor(function()
    local e, box = evo(), top()
    return e and e.done and box and box.pages and box.done
  end), "2612_finished_result_text_reached") then love.event.quit(1) return end
  check(U.still(game, shots .. "/2612_victreebel_result_no_party_icons.png"), "2612_result_shot")
  check(#PaletteFX.uiSpriteRedraws() == 0, "2612_result_no_party_obj_replay")
  check(mon.species == "VICTREEBEL", "2612_evolved_to_victreebel")
  check(game.save.inventory.LEAF_STONE == 1, "2612_one_leaf_stone_consumed")
  for _ = 1, 300 do
    if not evo() and top() and top().kind == "bag" then break end
    U.tap(game, "a")
    U.wait(3)
  end
  check(not evo(), "2612_movie_closed_after_result")
  check(top() and top().kind == "bag", "2612_returned_to_bag")
  check(U.still(game, shots .. "/2612_returned_bag_one_leaf_stone.png"), "2612_returned_bag_shot")
  love.event.quit(failed and 1 or 0)
end
