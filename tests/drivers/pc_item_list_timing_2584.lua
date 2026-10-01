-- engine/menus/players_pc.asm:129-138, 183-192, 239-241
-- engine/items/inventory.asm:131
-- engine/items/item_effects.asm:2267
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Bag = require("src.inventory.Bag")
  local PlayerPC = require("src.ui.PlayerPC")
  local BagMenu = require("src.ui.BagMenu")
  local ListMenu = require("src.ui.ListMenu")
  local QuantityBox = require("src.ui.QuantityBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local TextBox = require("src.render.TextBox")

  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end
  local function finish()
    U.log(ok and "PASS pc_item_list_timing_2584" or "FAIL pc_item_list_timing_2584")
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end
  local function topIs(mt) return getmetatable(game.stack:top()) == mt end
  local function waitFor(pred, n)
    for _ = 1, n or 300 do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end
  local function rowOf(list, id)
    for i, it in ipairs(list.items) do
      if it.value == id then return i, it end
    end
  end
  local function moveTo(list, id)
    for _ = 1, 20 do
      local it = list.items[list.index]
      if it and it.value == id then return true end
      U.tap(game, "down"); U.wait(4)
    end
    return false
  end

  U.newGame(game)
  if not check("new game reached the overworld", game.overworld ~= nil) then finish() end
  U.teleport(game, "VIRIDIAN_POKECENTER", 13, 4, "up")
  U.wait(20)
  for _, id in ipairs({ "DOME_FOSSIL", "NUGGET", "POTION", "RARE_CANDY", "REPEL",
                        "MOON_STONE", "ESCAPE_ROPE", "HM_FLY" }) do
    if not check("item " .. id .. " exists", game.data.items[id] ~= nil) then finish() end
  end
  game.save.pcItems = { DOME_FOSSIL = 1, NUGGET = 1, POTION = 5, RARE_CANDY = 3, REPEL = 2 }
  game.save.inventory = {}
  Bag.add(game.save, "HM_FLY", 1)
  Bag.add(game.save, "MOON_STONE", 1)
  Bag.add(game.save, "ESCAPE_ROPE", 2)

  local pc = PlayerPC.new(game)
  game.stack:push(pc)
  U.wait(6)

  local function openSub(row)
    for _ = 1, 10 do
      if game.stack:top() == pc and pc.index == row then break end
      U.tap(game, pc.index < row and "down" or "up"); U.wait(4)
    end
    U.tap(game, "a")
    waitFor(function() return topIs(ListMenu) and game.stack:top() ~= pc end)
    return game.stack:top()
  end

  local function confirmQty(whole)
    waitFor(function() return topIs(QuantityBox) end, 60)
    if whole then U.tap(game, "down"); U.wait(4) end
    U.tap(game, "a"); U.wait(4)
  end

  local function during(list, id, tag, count, index, shot)
    waitFor(function() return list.pcCompletion end, 120)
    check(tag .. ": completion message is up", list.pcCompletion == true)
    local i, it = rowOf(list, id)
    check(tag .. ": " .. id .. " row still listed during message", i ~= nil)
    if count then
      check(tag .. ": count still " .. count .. " during message", it and it.count == count)
    end
    check(tag .. ": cursor stays on row " .. index .. " during message", list.index == index)
    if shot then U.still(game, DIR .. "/" .. shot) end
  end

  local function after(list, id, tag, count, index, shot)
    U.tap(game, "a"); U.wait(6)
    check(tag .. ": message dismissed", not list.pcCompletion)
    local i, it = rowOf(list, id)
    if count then
      check(tag .. ": count repaints to " .. count .. " after message", it and it.count == count)
    else
      check(tag .. ": " .. id .. " row removed after message", i == nil)
      check(tag .. ": scroll back to top", list.scroll == 0)
    end
    check(tag .. ": cursor on row " .. index .. " after message", list.index == index)
    if shot then U.still(game, DIR .. "/" .. shot) end
  end

  local wd = openSub(1)
  check("withdraw list opened", wd.kind == "pc_item_withdraw")
  local n = #wd.items

  moveTo(wd, "POTION")
  local potionRow = wd.index
  U.tap(game, "a"); confirmQty(false)
  during(wd, "POTION", "withdraw 1 of POTION x5", 5, potionRow, "2584_01_withdraw_partial_during_message.png")
  after(wd, "POTION", "withdraw 1 of POTION x5", 4, potionRow, "2584_02_withdraw_partial_after_message.png")
  check("partial withdraw keeps list length", #wd.items == n)

  moveTo(wd, "RARE_CANDY")
  local candyRow = wd.index
  U.tap(game, "a"); confirmQty(true)
  during(wd, "RARE_CANDY", "withdraw RARE_CANDY stack", 3, candyRow, "2584_03_withdraw_stack_during_message.png")
  after(wd, "RARE_CANDY", "withdraw RARE_CANDY stack", nil, 1, "2584_04_withdraw_stack_after_message.png")

  moveTo(wd, "NUGGET")
  local nuggetRow = wd.index
  U.tap(game, "a"); confirmQty(false)
  during(wd, "NUGGET", "withdraw single NUGGET", nil, nuggetRow, "2584_05_withdraw_single_during_message.png")
  after(wd, "NUGGET", "withdraw single NUGGET", nil, 1, "2584_06_withdraw_single_after_message.png")
  check("withdraw list lost two rows", #wd.items == n - 2)

  U.tap(game, "b")
  waitFor(function() return game.stack:top() == pc end, 60)
  local dp = openSub(2)
  check("deposit list opened", dp.kind == "pc_item_deposit")
  moveTo(dp, "MOON_STONE")
  local moonRow = dp.index
  U.tap(game, "a"); confirmQty(false)
  during(dp, "MOON_STONE", "deposit MOON_STONE", nil, moonRow, "2584_07_deposit_during_message.png")
  after(dp, "MOON_STONE", "deposit MOON_STONE", nil, 1, "2584_08_deposit_after_message.png")

  U.tap(game, "b")
  waitFor(function() return game.stack:top() == pc end, 60)
  local ts = openSub(3)
  check("toss list opened", ts.kind == "pc_item_toss")
  moveTo(ts, "REPEL")
  local repelRow = ts.index
  U.tap(game, "a"); confirmQty(true)
  waitFor(function() return topIs(ChoiceBox) end, 60)
  U.tap(game, "a"); U.wait(4)
  during(ts, "REPEL", "toss REPEL x2", 2, repelRow, "2584_09_toss_during_message.png")
  after(ts, "REPEL", "toss REPEL x2", nil, 1, "2584_10_toss_after_message.png")

  U.tap(game, "b")
  waitFor(function() return game.stack:top() == pc end, 60)
  U.tap(game, "b"); U.wait(10)
  waitFor(function() return game.stack:top() == game.overworld or not topIs(ListMenu) end, 60)

  game.save.inventory = {}
  Bag.add(game.save, "POTION", 3)
  Bag.add(game.save, "REPEL", 1)
  Bag.add(game.save, "ESCAPE_ROPE", 2)
  Bag.add(game.save, "NUGGET", 1)
  game.bagSavedMenuItem, game.bagListScrollOffset = 0, 0
  local bag = BagMenu.new(game)
  game.stack:push(bag)
  U.wait(6)

  moveTo(bag, "REPEL")
  local bagRepelRow = bag.index
  U.tap(game, "a"); U.wait(6)
  U.tap(game, "a")
  local box
  waitFor(function()
    local top = game.stack:top()
    if getmetatable(top) == TextBox and top.done then box = top return true end
  end, 300)
  check("bag REPEL: used message is up", box ~= nil)
  check("bag REPEL: row still listed during message", rowOf(bag, "REPEL") == bagRepelRow)
  check("bag REPEL: save keeps the REPEL until the message ends", game.save.inventory.REPEL == 1)
  check("bag REPEL: cursor stays on REPEL during message", bag.index == bagRepelRow)
  U.still(game, DIR .. "/2584_11_bag_repel_during_message.png")
  for _ = 1, 30 do
    if game.stack:top() == bag then break end
    U.tap(game, "a"); U.wait(10)
  end
  U.wait(6)
  check("bag REPEL: row removed after message", rowOf(bag, "REPEL") == nil)
  check("bag REPEL: cursor back to top after message", bag.index == 1 and bag.scroll == 0)
  U.still(game, DIR .. "/2584_12_bag_repel_after_message.png")

  moveTo(bag, "ESCAPE_ROPE")
  U.tap(game, "a"); U.wait(6)
  U.tap(game, "down"); U.wait(4)
  U.tap(game, "a")
  confirmQty(true)
  waitFor(function() return topIs(ChoiceBox) end, 120)
  for _ = 1, 30 do
    if not topIs(ChoiceBox) then break end
    U.tap(game, "a"); U.wait(10)
  end
  box = nil
  waitFor(function()
    local top = game.stack:top()
    if getmetatable(top) == TextBox and top.done then box = top return true end
  end, 300)
  check("bag toss: threw away message is up", box ~= nil)
  check("bag toss: ESCAPE_ROPE row still listed during message", rowOf(bag, "ESCAPE_ROPE") ~= nil)
  U.still(game, DIR .. "/2584_13_bag_toss_stack_during_message.png")
  for _ = 1, 30 do
    if game.stack:top() == bag then break end
    U.tap(game, "a"); U.wait(10)
  end
  U.wait(6)
  check("bag toss: ESCAPE_ROPE row removed", rowOf(bag, "ESCAPE_ROPE") == nil)
  check("bag toss: whole stack sends cursor to top", bag.index == 1 and bag.scroll == 0)
  check("bag toss: saved bag cursor reset", game.bagSavedMenuItem == 0 and game.bagListScrollOffset == 0)
  U.still(game, DIR .. "/2584_14_bag_toss_stack_after_message.png")

  finish()
end
