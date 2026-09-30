return function(game)
  local U = require("tests.drivers.util")
  local identity = os.getenv("POKEPORT_IDENTITY")
  if not identity or identity:lower():find("pokemon-love2d", 1, true) then
    print("FAIL launcher_emerald_release_90005 requires an isolated identity")
    love.event.quit(1)
    return
  end

  local SaveData = require("src.core.SaveData")
  local SecretGames = require("src.import.SecretGames")
  local RomImporter = require("src.import.RomImporter")
  local LauncherView = require("src.import.LauncherView")
  local GameVersion = require("src.core.GameVersion")
  local Kit = require("src.ui.kit.Kit")
  local dir = assert(os.getenv("POKEPORT_SHOT_DIR"), "POKEPORT_SHOT_DIR is required")
  local originalSecret = SaveData.loadOptions().secretEmerald == true
  local realTime, now = os.time, 1790855999
  local realSaveOptions = SaveData.saveOptions
  local originalDraw, originalUpdate = rawget(game, "draw"), rawget(game, "update")
  local failures, drawn, writes = 0, 0, 0
  local imp

  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end

  local function finish()
    os.time = realTime
    SaveData.saveOptions = realSaveOptions
    SaveData.saveOptions({ secretEmerald = originalSecret })
    game.draw, game.update = originalDraw, originalUpdate
    print((failures == 0 and "PASS " or "FAIL ") .. "launcher_emerald_release_90005")
    love.event.quit(failures == 0 and 0 or 1)
  end

  os.time = function(t)
    if t then return realTime(t) end
    return now
  end
  SaveData.saveOptions({ secretEmerald = false })
  SecretGames.reload()
  imp = RomImporter.new(function() end, { launcher = true, reduceMotion = true })
  if not check(imp.ready.emerald == true, "existing Emerald cache is ready") then
    finish()
    return
  end

  local flags = { resizable = true, highdpi = true, fullscreen = false }
  if os.getenv("POKEPORT_BACKGROUND") == "1" then
    flags.x, flags.y, flags.borderless = -30000, -30000, true
  end
  love.window.setMode(1280, 720, flags)
  game.draw = function()
    imp:draw()
    drawn = drawn + 1
  end
  game.update = function(_, dt) imp:update(dt) end

  local function drawFrames(n)
    for _ = 1, n do
      local seen = drawn
      for _ = 1, 4000 do
        U.wait(1)
        if drawn > seen then break end
      end
      if not check(drawn > seen, "launcher frame reached the renderer") then return false end
    end
    return true
  end

  local function navHas(id)
    for i = 1, Kit._navPrevN or 0 do
      local slot = Kit._nav[i]
      if slot and slot.id == id then return true end
    end
    return false
  end

  local function shot(name)
    if not drawFrames(2) then return false end
    return check(U.still(game, dir .. "/" .. name .. ".png"), "capture " .. name)
  end

  imp._gamePopup = true
  local lockedTabs = LauncherView.gameTabs(imp)
  check(#lockedTabs == 8 and not SecretGames.visible("emerald"), "before deadline Emerald remains hidden")
  if not shot("90005_before_deadline_choose_game") then finish() return end
  check(not navHas("gamepop-emerald"), "before deadline Choose game has no Emerald row")

  SaveData.saveOptions = function(...)
    writes = writes + 1
    return realSaveOptions(...)
  end
  now = 1790856000
  imp:update(1 / 60)
  local releasedTabs = LauncherView.gameTabs(imp)
  check(#releasedTabs == 9 and releasedTabs ~= lockedTabs, "deadline refreshes the same launcher's cached tabs")
  check(SaveData.loadOptions().secretEmerald == true and writes == 1, "deadline persists once")
  check(imp._secretPopup == nil and imp._logoTaps == nil, "deadline opens no BLITZ popup")
  if not shot("90005_deadline_choose_game_emerald") then finish() return end
  check(navHas("gamepop-emerald") and not navHas("secret-ok"), "deadline Choose game includes Emerald without confirmation")
  for _ = 1, 20 do imp:update(1 / 60) imp:_logoTap() end
  check(writes == 1 and imp._secretPopup == nil, "repeated released updates and taps remain silent")
  check(imp:_versionForSha1(GameVersion.info("emerald").sha1) == "emerald", "deadline recognizes Emerald ROM")

  SaveData.saveOptions = realSaveOptions
  now = 1790855999
  SaveData.saveOptions({ secretEmerald = false })
  SecretGames.reload()
  imp = RomImporter.new(function() end, { launcher = true, reduceMotion = true })
  for _ = 1, SecretGames.TAPS do imp:_logoTap() end
  check(imp._secretPopup == true, "pre-deadline manual BLITZ mechanism is preserved")
  if not shot("90005_before_deadline_manual_blitz") then finish() return end
  check(navHas("secret-ok"), "manual BLITZ confirmation is rendered before release")

  now = 1790856000
  LauncherView.gameTabs(imp)
  imp:update(1 / 60)
  check(imp._secretPopup == nil and imp._logoTaps == nil, "deadline clears an already-open BLITZ even after another reader unlocks")
  if not shot("90005_deadline_manual_blitz_dismissed") then finish() return end
  check(not navHas("secret-ok"), "scheduled release leaves no BLITZ confirmation control")

  imp:_switchTab("emerald")
  check(imp.tab == "emerald", "released launcher selects Emerald normally")
  if not shot("90005_deadline_emerald_panel") then finish() return end
  check(navHas("play-emerald"), "released Emerald panel has its Play control")
  now = 1790855999
  SecretGames.reload()
  check(SecretGames.visible("emerald"), "persisted release survives clock rollback")
  finish()
end
