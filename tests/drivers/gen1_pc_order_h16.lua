local U = require("tests.drivers.util")
local PlayerPC = require("src.ui.PlayerPC")
local ListMenu = require("src.ui.ListMenu")
local QuantityBox = require("src.ui.QuantityBox")
local ChoiceBox = require("src.ui.ChoiceBox")
local SaveData = require("src.core.SaveData")

return function(game)
  local deadline = love.timer.getTime() + 25
  local oldWrite, oldOptions, oldPersist = rawget(game, "writeSave"), rawget(game, "writeOptions"), rawget(game, "persistOptions")
  local oldSave, oldSaveOptions = SaveData.save, SaveData.saveOptions
  local oldVolume = love.audio.getVolume()
  local ok, err = xpcall(function()
    local identity = os.getenv("POKEPORT_IDENTITY") or ""
    assert(identity ~= "" and identity ~= "pokemon-love2d", "isolated READY identity required")
    local out = assert(os.getenv("POKEPORT_SHOT_DIR"), "shot directory required")
    local version = require("src.core.GameVersion").get()
    assert(version == "red" or version == "blue" or version == "yellow", "Gen1 edition required")
    local function forbidden() error("H16 unexpected persistent write") end
    game.writeSave, game.writeOptions, game.persistOptions = forbidden, forbidden, forbidden
    SaveData.save, SaveData.saveOptions = forbidden, forbidden
    love.audio.setVolume(0)
    local function wait(n)
      for _ = 1, n do assert(love.timer.getTime() < deadline, "H16 deadline"); U.wait(1) end
    end
    local function settled(fn, label)
      for _ = 1, 1800 do if fn() then return end; wait(1) end
      error("H16 did not settle " .. label)
    end
    U.teleport(game, "REDS_HOUSE_2F", 3, 4, "up")
    settled(function() return game.overworld and game.stack:top() == game.overworld and not game.overworld.player.moving end, "actual bedroom field")
    game.save.pcItems = {REPEL = 1, POTION = 1, ANTIDOTE = 1}
    game.save.pcOrder = {"REPEL", "POTION", "ANTIDOTE"}
    game.save.cartPc = nil
    game.save.inventory, game.save.bagOrder, game.save.cartBag = {}, {}, nil
    local order = game.save.pcOrder
    local pc = PlayerPC.new(game, {direct = true})
    game.stack:push(pc);wait(4)
    local function topIs(mt) return getmetatable(game.stack:top()) == mt end
    local function ids(list)
      local a = {}
      for _, item in ipairs(list.items) do if item.value then a[#a + 1] = item.value end end
      return table.concat(a, ",")
    end
    local function open(index)
      assert(game.stack:top() == pc, "parent PC required")
      for _ = 1, 5 do
        if pc.index == index then break end
        U.tap(game, pc.index < index and "down" or "up");wait(3)
      end
      assert(pc.index == index, "PC row input failed")
      U.tap(game, "a")
      settled(function() return topIs(ListMenu) end, "actual item list")
      return game.stack:top()
    end
    local function select(list, id)
      for _ = 1, 8 do
        if list.items[list.index].value == id then break end
        U.tap(game, "down");wait(3)
      end
      assert(list.items[list.index].value == id, "actual item row input failed")
      U.tap(game, "a")
      settled(function() return topIs(QuantityBox) end, "quantity selector")
      U.tap(game, "a");wait(3)
    end
    local function complete(list)
      settled(function() return list.pcCompletion end, "completion message")
      U.tap(game, "a");wait(4)
      assert(not list.pcCompletion, "completion did not return to list")
    end
    local function close(list)
      assert(game.stack:top() == list, "current item list required")
      U.tap(game, "b");wait(4)
      assert(game.stack:top() == pc, "B did not return to PC")
    end
    local function shot(list, name)
      assert(game.stack:top() == list and not list.pcCompletion, "intended settled PC list required")
      wait(4)
      assert(U.still(game, out .. "/h16-" .. version .. "-" .. name .. ".png"), "capture failed")
      assert(love.timer.getTime() < deadline, "H16 capture deadline")
    end
    local withdraw = open(1)
    assert(ids(withdraw) == "REPEL,POTION,ANTIDOTE", "actual initial list ignored acquisition order")
    shot(withdraw, "01-imported-order")
    select(withdraw, "POTION");complete(withdraw)
    assert(game.save.inventory.POTION == 1 and not game.save.pcItems.POTION, "normal withdrawal failed")
    assert(game.save.pcOrder == order and table.concat(order, ",") == "REPEL,ANTIDOTE", "normal withdrawal failed ordered removal")
    assert(ids(withdraw) == "REPEL,ANTIDOTE", "actual withdrawal list did not repaint survivors")
    close(withdraw)
    local deposit = open(2)
    select(deposit, "POTION");complete(deposit);close(deposit)
    assert(game.save.pcItems.POTION == 1 and not game.save.inventory.POTION, "normal redeposit failed")
    withdraw = open(1)
    assert(ids(withdraw) == "REPEL,ANTIDOTE,POTION" and table.concat(order, ",") == "REPEL,ANTIDOTE,POTION", "normal redeposit did not append after survivors")
    shot(withdraw, "02-redeposit-appended");close(withdraw)
    local toss = open(3)
    select(toss, "REPEL")
    settled(function() return topIs(ChoiceBox) end, "actual toss confirmation")
    U.tap(game, "a");wait(3);complete(toss)
    assert(not game.save.pcItems.REPEL and table.concat(order, ",") == "ANTIDOTE,POTION", "normal toss failed ordered removal")
    assert(ids(toss) == "ANTIDOTE,POTION", "actual toss list did not repaint survivors")
    shot(toss, "03-toss-survivors");close(toss)
    U.tap(game, "b");wait(4)
    assert(game.stack:top() == game.overworld, "normal PC close did not restore bedroom field")
    print("PASS H16 actual PC input, ordered withdrawal, redeposit append, toss survivors, original order identity and no persistent writes", version)
  end, debug.traceback)
  game.writeSave, game.writeOptions, game.persistOptions = oldWrite, oldOptions, oldPersist
  SaveData.save, SaveData.saveOptions = oldSave, oldSaveOptions
  love.audio.setVolume(oldVolume)
  if not ok then print("FAIL H16 " .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
