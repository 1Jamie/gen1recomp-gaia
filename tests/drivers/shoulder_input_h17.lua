local U = require("tests.drivers.util")

return function(game)
  local deadline = love.timer.getTime() + 25
  local originalOptions, originalSaveOptions, originalWrite
  local originalSessionOptions, originalSessionEngine
  local Input = require("src.core.Input")
  local Controls = require("src.ui.game3.controls_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local Stack = require("src.ui.game3.stack")
  local Options = require("src.core.game3.options")
  local ok, err = xpcall(function()
    local identity = os.getenv("POKEPORT_IDENTITY") or ""
    assert(identity ~= "" and identity ~= "pokemon-love2d", "isolated READY identity required")
    local out = assert(os.getenv("POKEPORT_SHOT_DIR"), "shot directory required")
    local function wait(n)
      for _ = 1, n do assert(love.timer.getTime() < deadline, "H17 watchdog"); U.wait(1) end
    end
    local function untilReady(fn, label)
      for _ = 1, 1600 do if fn() then return end; wait(1) end
      error("H17 did not settle: " .. label)
    end
    untilReady(function() return game.phase == "boot" and game.boot end, "native boot")
    game:_handleBootAction({action = "new_game", name = "MAY", gender = 1})
    untilReady(function() return game.session and game.phase == "field" end, "native field")
    local Fade = require("src.ui.game3.fade")
    local function uncovered() return not Fade.isActive() and Fade.t == 0 and not Fade.lockInput end
    untilReady(uncovered, "uncovered new field")
    local version = require("src.core.GameVersion").get()
    assert(version == "emerald" or version == "firered" or version == "leafgreen", "native RSE/FRLG route required")
    originalOptions, originalSaveOptions = game.options, game.save and game.save.options
    originalWrite = rawget(game, "writeOptions")
    originalSessionOptions, originalSessionEngine = game.session.options, game.session.engineOptions
    local detached = {}
    for k, v in pairs(game.options or {}) do if k ~= "bindings" then detached[k] = v end end
    local blockId = Options.blockId(game.session)
    detached[blockId] = {}
    for k, v in pairs(originalSessionOptions) do detached[blockId][k] = v end
    game.options = detached
    Options.bind(game.session, detached)
    if version ~= "emerald" then assert(Options.ensure(game.session).buttonMode == 0, "first FRLG capture must exercise default Help mode") end
    if game.save then game.save.options = detached end
    local writes = 0
    game.writeOptions = function() writes = writes + 1 end
    Input:applyBindings(nil); Input:reset()
    Stack.clear()
    local function shot(name, id)
      wait(8)
      untilReady(uncovered, "uncovered " .. name)
      assert(Stack.top() and Stack.top().id == id, "intended screenshot screen missing")
      assert(U.still(game, out .. "/" .. name .. ".png"), "capture did not reach disk")
      assert(love.timer.getTime() < deadline, "capture deadline")
    end
    local function tap(btn)
      Input:overlayPressed(btn); wait(1); Input:overlayReleased(btn); wait(1)
    end
    local function bind(id)
      Controls.show({game = game}); wait(4)
      local bm = assert(Controls._bm)
      for i, row in ipairs(bm.items) do if row.button.id == id then bm.index = i end end
      tap("a"); assert(bm.capture and not bm.pending, "actual Controls did not arm")
      game:gamepadpressed(nil, "leftshoulder"); wait(1)
      assert(bm.pending and bm.pending.value == "leftshoulder", "candidate must wait for release")
      game:gamepadreleased(nil, "leftshoulder"); wait(1)
      assert(not bm.capture and game.options.bindings[id].pad == "leftshoulder", "actual released binding was not stored")
      assert(not Input:isDown("a") and not Input:isDown("l"), "capture release left gameplay hold")
    end
    bind("a")
    assert(detached.bindings.l.pad == "a" and writes == 1, "actual A/L swap or deferred write failed")
    shot("01-controls-A-on-LB", "controls")
    tap("b"); assert(not Controls.open, "Controls close failed")
    assert(Input.padBindings.leftshoulder == "a" and Input.padBindings.a == "l", "closed menu did not apply actual swap")
    local Bag = require("src.core.game3.bag")
    local Items = require("src.core.game3.items_data")
    Options.set(game.session, "buttonMode", 1)
    local session = {version = version, party = game.session.party, bag = Bag.new()}
    Options.bind(session, detached)
    assert(session.options == game.session.options and Options.lrMode(game.session), "actual game and Bag must share canonical LR options")
    local keyItem
    for id = 1, 376 do if Items.pocketOf(id) == "KEY_ITEMS" then keyItem = id; break end end
    assert(keyItem, "required real ROM key item missing")
    session.bag.pockets.KEY_ITEMS = {{id = keyItem, qty = 1}}
    BagMenu.show(session, {pocket = "KEY_ITEMS"}); BagMenu.settle(); wait(4)
    assert(BagMenu.currentPocket() == "KEY_ITEMS" and BagMenu.mode == "list", "real LR bag did not settle")
    game:gamepadpressed(nil, "leftshoulder"); wait(1)
    game:gamepadreleased(nil, "leftshoulder"); wait(4)
    assert(BagMenu.currentPocket() == "KEY_ITEMS" and BagMenu.mode == "action", "configured LB A was consumed as pocket L")
    shot("02-LR-key-item-action-with-LB", "bag")
    BagMenu.close(); Input:reset()
    detached.bindings = nil; Input:applyBindings(nil)
    bind("speedUp")
    assert(detached.bindings.l.pad == "triggerright", "actual SPEED+/L swap missing")
    tap("b")
    local Speed = require("src.core.GameSpeed")
    local key = Speed.optionKey(game:speedCategory())
    local expected = Speed.cycle(detached[key], 1)
    game:gamepadpressed(nil, "leftshoulder"); wait(1)
    game:gamepadreleased(nil, "leftshoulder"); wait(1)
    assert(detached[key] == expected and not Input:isDown("l"), "explicit native shoulder speed action failed")
    Controls.show({game = game}); wait(4)
    for i, row in ipairs(Controls._bm.items) do if row.button.id == "speedUp" then Controls._bm.index = i end end
    shot("03-controls-SPEED-plus-on-LB", "controls")
    tap("b")
    BagMenu.show(session, {pocket = "KEY_ITEMS"}); BagMenu.settle(); wait(4)
    game:gamepadaxis(nil, "triggerright", 1); wait(1)
    game:gamepadaxis(nil, "triggerright", 0); wait(8)
    local priorPocket = version == "emerald" and "BERRY_POUCH" or "ITEMS"
    assert(BagMenu.currentPocket() == priorPocket, "moved L on old R2 did not reach edition-specific actual LR bag consumer")
    print("PASS H17 real Controls capture/release/swap, LR Bag A consumer, native explicit SPEED+ and moved L")
  end, debug.traceback)
  BagMenu.close(); Controls.close()
  if originalOptions then
    game.options = originalOptions
    if game.save then game.save.options = originalSaveOptions end
    game.writeOptions = originalWrite
    game.session.options, game.session.engineOptions = originalSessionOptions, originalSessionEngine
    Input:applyBindings(originalOptions.bindings); Input:reset()
  end
  if not ok then print("FAIL H17 " .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
