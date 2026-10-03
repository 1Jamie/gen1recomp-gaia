local U = require("tests.drivers.util")
return function(game)
  U.wait(20)
  package.path = package.path .. ";./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
  local App, Paint, Kit, path, tmp, oldPaint, oldField
  local dim, safe, osName, keyboard
  local ok, err = xpcall(function()
    App = require("tools.save-editor.App")
    local Gen, Ops = require("Gen"), require("Ops")
    local Touch, History = require("TouchEditor"), require("History")
    local Serializer = require("src.core.SaveSerializer")
    local Copy = require("src.mods.Merge").deepCopy
    local version = require("src.core.GameVersion").get()
    assert(version == "crystal" or version == "gold" or version == "silver", "run on Crystal, Gold or Silver")
    local eligible = version == "crystal"
    local dir = assert(os.getenv("POKEPORT_SHOT_DIR"))
    Kit, Paint = require("Kit"), require("src.ui.kit.Button")
    dim, safe, osName, keyboard = love.graphics.getDimensions, love.window.getSafeArea,
      love.system.getOS, love.keyboard.setTextInput
    local controls, keyboardActive = {}, false
    oldPaint, oldField = Paint.draw, Kit.textfield
    love.keyboard.setTextInput = function(active, ...)
      keyboardActive = active
      return keyboard(active, ...)
    end
    Paint.draw = function(owner, x, y, w, h, label, opts, hot, focused)
      if owner == Kit then
        controls[opts.id or label] = { x = x, y = y, w = w, h = h }
        if opts.id and opts.id:find("buenaPoints", 1, true) then
          assert(opts.fullLabel and opts.labelLayout, "Buena label must be complete")
          assert(opts.labelLayout.height <= h - 4 * Kit.scale + 1, "Buena label fits")
          assert(h >= Kit.tapMin(), "Buena field meets touch target")
        end
      end
      return oldPaint(owner, x, y, w, h, label, opts, hot, focused)
    end
    Kit.textfield = function(id, x, y, w, h, value, placeholder, opts)
      controls["field-" .. id] = { x = x, y = y, w = w, h = h }
      return oldField(id, x, y, w, h, value, placeholder, opts)
    end
    tmp = os.tmpname()
    path = tmp .. "-buena-2640.lua"
    local seed = Gen.newGame(version)
    if eligible then
      seed.crystal = seed.crystal or {}
      seed.crystal.buenaPassword = { balance = 7, word = 0x21, day = 4, prizesToday = 0, streak = 0 }
    end
    local file = assert(io.open(path, "wb"))
    file:write(Serializer.encode(seed)); file:close()
    App.load(path, { version = version, embedded = true })
    local S = App.getState()
    assert(S.save and not S.loadError and not S.missingCache, S.status)
    local W, H, platform = 390, 844, "Android"
    local function frame(name)
      controls = {}
      love.graphics.getDimensions = function() return W, H end
      love.window.getSafeArea = function() return 0, 0, W, H end
      love.system.getOS = function() return platform end
      local canvas = love.graphics.newCanvas(W, H, { msaa = 0 })
      love.graphics.push("all")
      love.graphics.setCanvas(canvas)
      love.graphics.origin()
      love.graphics.setScissor()
      love.graphics.setShader()
      require("src.render.GameViewport").reset()
      love.graphics.clear(0, 0, 0, 1)
      App.draw()
      love.graphics.setCanvas()
      love.graphics.pop()
      if name then
        local pixels = canvas:newImageData()
        local bytes = pixels:encode("png"):getString()
        pixels:release()
        local out = assert(io.open(dir .. "/" .. version .. "-" .. name .. ".png", "wb"))
        out:write(bytes); out:close()
        print("PASS captured " .. name)
      end
      canvas:release()
      love.graphics.getDimensions, love.window.getSafeArea, love.system.getOS = dim, safe, osName
    end
    local function tap(id)
      local r = assert(controls[id], "missing control " .. id)
      assert(r.y >= 0 and r.y + r.h <= H, "control must be visible " .. id)
      App.mousepressed(r.x + r.w / 2, r.y + r.h / 2, 1)
      frame()
      frame()
    end
    local function view(tab, name)
      Touch.close(S, Kit)
      S.tab, S.itemView, S.pageScroll = tab, "wallet", {}
      S.trainerScroll, S.walletScroll = 0, 0
      frame()
      if tab == "trainer" then S.trainerScroll = 10000 else S.walletScroll = 10000 end
      frame()
      frame(name)
      local id = "value-" .. (tab == "trainer" and "trainer-" or "wallet-") .. "buenaPoints"
      assert((controls[id] ~= nil) == eligible, "edition currency visibility")
      if eligible then
        local r = controls[id]
        assert(r.y >= 0 and r.y + r.h <= H, "Buena field reachable after scrolling")
      end
      return id
    end
    local trainer = view("trainer", "trainer-buena-points-phone")
    view("items", "wallet-buena-points-phone")
    W, H = 320, 568
    view("trainer", "trainer-buena-points-small-phone")
    view("items", "wallet-buena-points-small-phone")
    W, H, platform = 1000, 650, "Linux"
    view("trainer", "trainer-buena-points-desktop")
    view("items", "wallet-buena-points-desktop")
    if eligible then
      W, H, platform = 390, 844, "Android"
      trainer = view("trainer")
      local before = Copy(S.save)
      tap(trainer)
      assert(S.editPopup and S.editPopup.id == "trainer-buenaPoints", "Trainer opens Buena popup")
      assert(S.editPopup.limits.lo == 0 and S.editPopup.limits.hi == 30, "popup uses 0 to 30")
      frame("buena-points-popup-range")
      S.editPopup.scroll = 10000
      frame(); frame()
      tap("Max")
      assert(S.editPopup.value == 30 and Gen.buenaPoints(S.save) == 7 and not S.dirty, "Max affects draft only")
      S.editPopup.scroll = 0
      frame(); frame("buena-points-max-draft")
      S.editPopup.scroll = 10000
      frame(); frame()
      tap("Type a value")
      frame()
      tap("field-touch-exact")
      assert(Kit.focus == "touch-exact" and keyboardActive, "exact entry focuses keyboard")
      for _ = 1, 4 do App.keypressed("backspace") end
      App.textinput("31")
      frame()
      tap("Apply")
      assert(S.editPopup and S.editPopup.error == "Choose a whole number from 0 to 30", "invalid draft stays visible")
      assert(Gen.buenaPoints(S.save) == 7 and not S.dirty, "invalid draft does not edit save")
      S.editPopup.scroll = 10000
      frame(); frame("buena-points-invalid-31")
      tap("field-touch-exact")
      for _ = 1, 4 do App.keypressed("backspace") end
      App.textinput("15")
      frame()
      tap("Apply")
      assert(not S.editPopup and not Kit.focus and not keyboardActive, "Apply closes popup and keyboard")
      assert(Gen.buenaPoints(S.save) == 15 and S.dirty, "popup edits canonical points")
      before.crystal.buenaPassword.balance = 15
      assert(Serializer.encode(S.save) == Serializer.encode(before), "password, flags and other save state preserved")
      frame("trainer-buena-points-edited-15")
      assert(History.undo(S) and Gen.buenaPoints(S.save) == 7 and not S.dirty, "undo restores clean balance")
      assert(History.redo(S) and Gen.buenaPoints(S.save) == 15, "redo restores edited balance")
      local wallet = view("items", "wallet-buena-points-edited-15")
      tap(wallet)
      S.editPopup.scroll = 10000
      frame(); frame()
      tap("Min")
      tap("Apply")
      assert(Gen.buenaPoints(S.save) == 0, "Wallet Min writes zero")
      assert(History.undo(S) and Gen.buenaPoints(S.save) == 15, "Wallet edit can undo")
      assert(App.save() and not S.dirty, "native save succeeds and clears dirty")
      App.unload()
      App.load(path, { version = version, embedded = true })
      S = App.getState()
      assert(S.save and not S.loadError and Gen.buenaPoints(S.save) == 15, "native reopen preserves edited points")
      assert(S.save.crystal.buenaPassword.word == 0x21 and S.save.crystal.buenaPassword.day == 4, "native reopen preserves password state")
      view("items", "wallet-buena-points-saved-reopened")
      print("PASS Crystal Buena points: canonical field, popup validation, focus, undo/redo, save/reopen")
    else
      local before = Serializer.encode(S.save)
      assert(not Ops.setTrainerProperty(S, "buenaPoints", 7), "non-Crystal mutation refused")
      assert(Serializer.encode(S.save) == before and not S.dirty, "edition refusal preserves save")
      print("PASS " .. version .. " has no Buena currency or mutation")
    end
  end, debug.traceback)
  if App then App.unload() end
  if Paint and oldPaint then Paint.draw = oldPaint end
  if Kit and oldField then Kit.textfield = oldField end
  if dim then love.graphics.getDimensions, love.window.getSafeArea, love.system.getOS = dim, safe, osName end
  if keyboard then love.keyboard.setTextInput = keyboard end
  if path then
    os.remove(path)
    for _, backup in ipairs(require("tests.fs_io").globPrefix(path .. ".bak-")) do os.remove(backup) end
  end
  if tmp then os.remove(tmp) end
  if not ok then print("FAIL save_editor_buena_points_2640: " .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
