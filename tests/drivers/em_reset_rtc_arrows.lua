local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_reset_rtc_arrows"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_reset_rtc_arrows failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end

  local Kit = require("src.ui.game3.rse.scene_kit")
  local fakeSave = {
    engine = "game3",
    flags = {},
    vars = {},
    lastBerryTreeUpdate = { days = 3, hours = 12, minutes = 30, seconds = 0 },
  }
  Kit.loadRawSave = function() return fakeSave end

  local Boot = require("src.ui.game3.boot")
  local BootModules = require("src.ui.game3.boot_modules")
  BootModules.startCombo(Boot, game.boot, "resetRtc")
  U.wait(60)
  local screen = game.boot.custom and game.boot.custom.combo
  if not check(screen ~= nil and screen.state ~= nil, "reset rtc screen created (" .. tostring(screen and screen.state) .. ")") then
    return finish()
  end

  for _ = 1, 400 do
    if screen.state == "prompt" then break end
    U.wait(1)
  end
  check(screen.state == "prompt", "reached the confirm prompt (" .. tostring(screen.state) .. ")")
  U.still(game, DIR .. "/01_prompt.png")

  U.tap(game, "a")
  for _ = 1, 200 do
    if screen.state == "set_time" then break end
    U.wait(1)
  end
  check(screen.state == "set_time" and screen.input ~= nil, "time input open (" .. tostring(screen.state) .. ")")
  U.wait(10)
  U.still(game, DIR .. "/02_hours_up_down_arrows.png")

  local seen = { screen.selection }
  for _ = 1, 6 do
    U.tap(game, "right")
    U.wait(6)
    seen[#seen + 1] = screen.selection
    U.still(game, DIR .. "/03_selection_" .. tostring(screen.selection) .. ".png")
  end
  print("[driver] selections: " .. table.concat(seen, ","))
  check(#seen >= 2, "cursor moved across fields")
  return finish()
end
