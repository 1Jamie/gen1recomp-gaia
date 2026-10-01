-- engine/events/vending_machine.asm:2-75
-- home/text_script.asm:92-109
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/shots"
  os.execute('mkdir -p "' .. SHOT_DIR .. '"')

  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")
  local Menu = require("src.ui.Menu")

  local ok = true
  local function check(label, pass)
    if not pass then ok = false end
    U.log(pass and "PASS" or "FAIL", label)
    return pass
  end
  local function finish()
    U.log(ok and "vending_machine_2581: ALL PASS" or "vending_machine_2581: FAILED")
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end
  local function typed(box)
    local n = 0
    for _, line in ipairs(box.shown or {}) do n = n + #line end
    return n
  end
  local function waitFor(pred, limit)
    for _ = 1, limit or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end
  local function top() return game.stack:top() end
  local function depth() return #game.stack.states end

  game.save.party = { Pokemon.new(game.data, "BULBASAUR", 5) }
  game.save.money = 3000
  game.save.inventory.FRESH_WATER = nil

  U.teleport(game, "CELADON_MART_ROOF", 10, 2, "up")
  U.wait(20)
  local ow = game.overworld
  local sign
  for _, s in ipairs((ow.map.def and ow.map.def.signs) or {}) do
    if tostring(s.text or s.id or ""):find("VENDING_MACHINE") then
      sign = s
      break
    end
  end
  if not check("the roof has a vending machine sign", sign ~= nil) then
    finish()
  end
  U.teleport(game, "CELADON_MART_ROOF", sign.x, sign.y + 1, "up")
  U.wait(20)
  local base = depth()

  U.tap(game, "a")
  local intro
  check("A on the machine starts the greeting typing", waitFor(function()
    local t = top()
    if getmetatable(t) == TextBox and typed(t) > 0 and not t.done then
      intro = t
      return true
    end
  end, 120))
  if not intro then finish() end
  check("no money box while the greeting types", not intro:moneyVisible())
  U.still(game, SHOT_DIR .. "/2581_01_greeting_typing_no_money.png")

  waitFor(function() return intro.done end, 600)
  U.wait(2)
  check("the greeting waits on its prompt arrow",
        intro.done and not intro.stayShown and intro:arrowVisible())
  check("still no money box at the prompt arrow", not intro:moneyVisible())
  U.still(game, SHOT_DIR .. "/2581_02_greeting_prompt_no_money.png")

  U.tap(game, "a")
  local menu = top()
  check("the drink list opens on the A press", getmetatable(menu) == Menu)
  check("the money box goes up on the same frame", intro:moneyVisible())
  if getmetatable(menu) ~= Menu then finish() end
  U.wait(2)
  U.still(game, SHOT_DIR .. "/2581_03_menu_and_money_after_A.png")

  local before = game.save.money
  U.tap(game, "a")
  local result
  check("FRESH WATER rumbles, then popped out! types", waitFor(function()
    local t = top()
    if getmetatable(t) == TextBox and t ~= intro and typed(t) > 0
       and not t.done then
      result = t
      return true
    end
  end, 400))
  if not result then finish() end
  check("the menu is still up under popped out!",
        game.stack.states[depth() - 1] == menu
        and game.stack.states[depth() - 2] == intro)
  check("the money box still shows the old balance mid-typing",
        intro:moneyVisible() and game.save.money == before)
  U.still(game, SHOT_DIR .. "/2581_04_popped_out_typing_old_money.png")

  waitFor(function() return result.done end, 600)
  U.wait(1)
  check("the price comes off once popped out! has typed",
        game.save.money == before - 200)
  check("the menu is still up after typing ends",
        game.stack.states[depth() - 1] == menu)
  U.wait(2)
  U.still(game, SHOT_DIR .. "/2581_05_popped_out_done_new_money.png")

  U.tap(game, "a")
  check("one A closes text, menu and money box together",
        depth() == base and top() == ow)
  U.wait(2)
  U.still(game, SHOT_DIR .. "/2581_06_all_closed_after_last_A.png")

  U.wait(20)
  U.tap(game, "a")
  waitFor(function() return top() ~= ow and getmetatable(top()) == TextBox
    and top().done end, 600)
  intro = top()
  U.tap(game, "a")
  menu = top()
  if not check("the second visit opens the list", getmetatable(menu) == Menu) then
    finish()
  end
  for _ = 1, 3 do
    U.tap(game, "down")
    U.wait(2)
  end
  U.tap(game, "a")
  result = top()
  check("CANCEL prints Not thirsty! over the list",
        getmetatable(result) == TextBox and result ~= intro
        and game.stack.states[depth() - 1] == menu)
  waitFor(function() return result.done end, 600)
  U.wait(2)
  check("the list stays up through Not thirsty!",
        game.stack.states[depth() - 1] == menu)
  U.still(game, SHOT_DIR .. "/2581_07_cancel_not_thirsty_menu_up.png")
  U.tap(game, "a")
  check("Not thirsty! closes everything on one press",
        depth() == base and top() == ow)

  U.wait(20)
  U.tap(game, "a")
  waitFor(function() return top() ~= ow and getmetatable(top()) == TextBox
    and top().done end, 600)
  U.tap(game, "a")
  menu = top()
  U.tap(game, "b")
  result = top()
  check("B prints Not thirsty! with the list still up",
        getmetatable(result) == TextBox
        and game.stack.states[depth() - 1] == menu)
  waitFor(function() return result.done end, 600)
  U.tap(game, "a")
  check("and closes everything on one press", depth() == base and top() == ow)

  finish()
end
