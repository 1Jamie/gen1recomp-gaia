local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_start_menu_exit_90001"

return function(game)
  local failures = 0
  local overallDeadline = love.timer.getTime() + 25
  local SaveData, originalSave
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function waitUntil(pred, seconds)
    local deadline = math.min(overallDeadline, love.timer.getTime() + seconds)
    while love.timer.getTime() < deadline do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end
  local ok, err = xpcall(function()
    local identity = os.getenv("POKEPORT_IDENTITY") or ""
    if not check(identity:match("^bsa0930%-") ~= nil, "isolated campaign identity") then return end
    if not check(waitUntil(function() return game.boot ~= nil end, 5), "Emerald boot ready") then return end
    local Boot = require("src.ui.game3.boot")
    local StartMenu = require("src.ui.game3.start_menu")
    local Runtime = require("src.core.game3.runtime")
    SaveData = require("src.core.SaveData")
    if not check(not SaveData.isPortable(), "save fixtures use isolated identity storage") then return end
    originalSave = SaveData.save
    local saves = 0
    SaveData.save = function(...) saves = saves + 1; return originalSave(...) end
    local Message = require("src.ui.game3.message")
    local Field = require("src.core.game3.field")
    local Fade = require("src.ui.game3.fade")
    local Hud = require("src.ui.game3.hud")
    local Space = require("src.core.game3.scripting.space")
    local Warp = require("src.core.game3.warp")
    local Forced = require("src.core.game3.forced_movement")
    local Player = require("src.core.game3.player")
    local function idle()
      if Message.isOpen() then U.tap(game, "b") end
      local running = Space.vm and Space.vm.isRunning and Space.vm:isRunning()
      return game.phase == "field" and not Hud.busy() and not Fade.isActive() and not Fade.lockInput
        and not Field.locked and not running and not Warp.isBusy() and not Forced.isForced()
        and not Player.moving and Player.boulderPush == nil
    end
    for caseIndex, saved in ipairs({ false, true }) do
      local prefix = saved and "saved" or "unsaved"
      local slot = SaveData.createSlot("emerald")
      if not check(slot and SaveData.setActiveSlot("emerald", slot) == slot, prefix .. " fresh save slot selected") then return end
      game:_handleBootAction({ action = "new_game", name = "BRENDAN",
        start = { map = "EM_LITTLEROOT_TOWN", x = 5, y = 9, facing = "down" } })
      print("INFO " .. prefix .. " initial fade=" .. tostring(Fade.isActive()) .. " hudBusy=" .. tostring(Hud.busy()))
      if not check(waitUntil(idle, 4), prefix .. " field ready after fade and script completion") then return end
      if saved then
        if not check(game:saveGame(), "saved fixture writes a real Emerald save") then return end
      end
      if not check(game:_hasContinueSave() == saved, prefix .. " expected continue availability before EXIT") then return end
      local session, saveCount = game.session, saves
      local rawBefore = SaveData.readSlotSource("emerald", slot)
      U.tap(game, "start")
      if not check(StartMenu.isOpen(), prefix .. " START opens Emerald menu") then return end
      local exitIndex
      for i, entry in ipairs(StartMenu.ENTRIES) do if entry.id == "exit" then exitIndex = i end end
      if not check(exitIndex ~= nil, prefix .. " Emerald EXIT present") then return end
      for _ = 1, #StartMenu.ENTRIES do
        if StartMenu.cursor == exitIndex then break end
        U.tap(game, "down")
      end
      U.tap(game, "a")
      check(StartMenu._confirmExit and StartMenu._confirmCursor == 2, prefix .. " EXIT confirmation defaults NO")
      check(U.still(game, DIR .. "/" .. string.format("%02d", (caseIndex - 1) * 3 + 1) .. "_" .. prefix .. "_exit_default_no.png"), prefix .. " default NO screenshot")
      U.tap(game, "b")
      check(StartMenu.isOpen() and game.session == session, prefix .. " EXIT B preserves field session")
      U.tap(game, "a")
      U.tap(game, "a")
      check(StartMenu.isOpen() and game.session == session, prefix .. " EXIT NO preserves field session")
      U.tap(game, "a")
      U.tap(game, "up")
      U.tap(game, "a")
      local direct = game.boot and game.boot.phase == Boot.PHASE.TITLE and game.boot.custom.title
        and not game.boot.custom.intro
      if not check(direct, prefix .. " EXIT YES enters title directly") then return end
      check(game.session == nil and not Runtime.isActive(), prefix .. " EXIT YES stops field runtime")
      check(saves == saveCount and SaveData.readSlotSource("emerald", slot) == rawBefore, prefix .. " EXIT does not implicitly save")
      check(game.boot.hasContinue == saved, prefix .. " EXIT preserves existing continue availability")
      check(game.boot.custom.coldBoot == false, prefix .. " EXIT consumes cold boot")
      if not check(waitUntil(function()
        local title = game.boot.custom.title
        if not title or title.phase ~= "phase3" then return false end
        for _, sprite in pairs(title.m.ppu.sprites.sprites) do
          if sprite.inUse and sprite.y == 108 and sprite.data[0] == 1 and not sprite.invisible then return true end
        end
        return false
      end, 5), prefix .. " Emerald title settled") then return end
      check(U.still(game, DIR .. "/" .. string.format("%02d", (caseIndex - 1) * 3 + 2) .. "_" .. prefix .. "_exit_title.png"), prefix .. " settled title screenshot")
      U.tap(game, "start")
      if not check(waitUntil(function()
        local menu = game.boot.custom.menu
        return game.boot.phase == Boot.PHASE.MENU and menu and menu.state == "input"
      end, 4), prefix .. " title START reaches settled main menu") then return end
      local menu = game.boot.custom.menu
      check(menu.hasContinue == saved and menu.items[1] == (saved and "CONTINUE" or "NEW_GAME"), prefix .. " main menu offers correct first action")
      if saved then check(menu.info and menu.info.name == "BRENDAN", "saved main menu retains trainer metadata") end
      check(U.still(game, DIR .. "/" .. string.format("%02d", (caseIndex - 1) * 3 + 3) .. "_" .. prefix .. "_main_menu.png"), prefix .. " main menu screenshot")
    end
  end, debug.traceback)
  if SaveData and originalSave then SaveData.save = originalSave end
  if not ok then check(false, tostring(err)) end
  print((failures == 0 and "PASS" or "FAIL") .. " em_start_menu_exit_90001 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end
