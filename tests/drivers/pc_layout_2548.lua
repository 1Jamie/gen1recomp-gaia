return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Menu = require("src.ui.Menu")
  local Font = require("src.render.Font")
  local Theme = require("src.ui.Theme")
  local Pokemon = require("src.pokemon.Pokemon")
  local Boxes = require("src.pokemon.Boxes")

  local ok = true
  local function check(label, cond)
    if cond then
      U.log("PASS", label)
    else
      ok = false
      U.log("FAIL", label)
    end
  end
  local function isMenu(s) return getmetatable(s) == Menu end
  local function hasLabel(menu, needle)
    for _, it in ipairs(menu.items or {}) do
      if type(it.label) == "string" and it.label:find(needle, 1, true) then return true end
    end
    return false
  end
  local function mainMenu()
    for _, s in ipairs(game.stack.states) do
      if isMenu(s) and hasLabel(s, "LOG OFF") and hasLabel(s, "'s PC") then return s end
    end
  end
  local function mash(cond)
    for _ = 1, 200 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(3)
    end
    return false
  end
  local function drawnY(state)
    local ys = {}
    local real = Font.draw
    Font.draw = function(text, x, y) ys[text] = y return 8 end
    local good, err = pcall(state.draw, state)
    Font.draw = real
    if not good then error(err, 0) end
    return ys
  end
  local function cursorCode(state)
    local seen
    local real = Font.drawCode
    Font.drawCode = function(code, x, y)
      if code == Theme.cursor or code == Theme.cursorHollow then seen = code end
    end
    local good, err = pcall(state.draw, state)
    Font.drawCode = real
    if not good then error(err, 0) end
    return seen
  end
  local function fail()
    U.log("RESULT: FAIL")
    love.event.quit(1)
  end

  game.save.party = { Pokemon.new(game.data, "PIKACHU", 12), Pokemon.new(game.data, "EEVEE", 10) }
  Boxes.ensure(game.save)
  game.save.boxes[1] = { Pokemon.new(game.data, "SPEAROW", 8), Pokemon.new(game.data, "RATTATA", 5) }
  game.save.pcItems = { POTION = 3, ANTIDOTE = 2 }
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_MET_BILL = true
  game.save.flags.EVENT_GOT_POKEDEX = true

  U.teleport(game, "VIRIDIAN_POKECENTER", 13, 4, "up")
  U.tap(game, "a")
  local main
  mash(function()
    local t = game.stack:top()
    main = isMenu(t) and hasLabel(t, "LOG OFF") and t
    return main
  end)
  check("main menu opens", main)
  if not main then return fail() end
  U.wait(8)

  U.tap(game, "a")
  mash(function() local t = game.stack:top() return isMenu(t) and hasLabel(t, "SEE YA") end)
  local bills = game.stack:top()
  check("bills pc: main menu gone from stack", mainMenu() == nil)
  U.still(game, DIR .. "/2548_01_bills_pc_no_main_menu.png")

  U.tap(game, "a")
  U.wait(8)
  local list = game.stack:top()
  check("bills pc: withdraw list open", list.kind == "pc_box_withdraw")
  U.tap(game, "a")
  U.wait(8)
  check("bills pc: withdraw list chosen row hollow", list.hollowIndex == list.index)
  check("bills pc: withdraw list draws hollow arrow", cursorCode(list) == Theme.cursorHollow)
  U.still(game, DIR .. "/2548_02_bills_withdraw_hollow_cursor.png")
  U.tap(game, "b")
  U.wait(6)
  U.tap(game, "b")
  U.wait(6)

  while game.stack:top() ~= main and game.stack:top() ~= game.overworld do
    U.tap(game, "b")
    U.wait(6)
    if U.frame() > 1e7 then break end
  end
  check("main menu rebuilt on return", game.stack:top() == main)
  check("main menu cursor back on row 1", main.index == 1)
  U.still(game, DIR .. "/2548_03_main_menu_rebuilt.png")

  U.tap(game, "down")
  U.wait(3)
  U.tap(game, "a")
  local ppc
  mash(function()
    local t = game.stack:top()
    ppc = isMenu(t) and hasLabel(t, "WITHDRAW ITEM") and t
    return ppc
  end)
  check("player pc: opens", ppc)
  if not ppc then return fail() end
  check("player pc: main menu gone from stack", mainMenu() == nil)
  check("player pc: no title", ppc.title == nil)
  local ys = drawnY(ppc)
  check("player pc: prompt line 1 in bottom box", ys["What do you want"] == 112)
  check("player pc: prompt line 2 in bottom box", ys["to do?"] == 128)
  U.still(game, DIR .. "/2548_04_players_pc_prompt_bottom.png")

  U.tap(game, "a")
  U.wait(8)
  local items = game.stack:top()
  check("player pc: item list open", items.kind == "pc_item_withdraw")
  check("player pc: parent cursor hollow under list", ppc.hollowIndex == ppc.index)
  check("player pc: parent draws hollow arrow", cursorCode(ppc) == Theme.cursorHollow)
  U.still(game, DIR .. "/2548_05_players_pc_parent_hollow.png")
  U.tap(game, "a")
  U.wait(8)
  check("player pc: item list row hollow under quantity box", items.hollowIndex == items.index)
  U.still(game, DIR .. "/2548_06_players_pc_list_hollow.png")

  U.log(ok and "RESULT: ALL PASS" or "RESULT: FAIL")
  love.event.quit(ok and 0 or 1)
end
