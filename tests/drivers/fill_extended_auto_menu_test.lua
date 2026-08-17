-- Visual and behavioral acceptance for the adaptive BATTLE BG menu rule.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  love.window.setMode(1920, 1080, { resizable = true })
  U.wait(3)

  local options = game.save.options
  options.battleLayout = "wide"
  options.battleFit = "fixed"
  options.battleHud = "extended"
  options.battleBg = "black"

  local menu = require("src.ui.Screens").push(game, "OptionsMenu")
  local fitRow, bgRow
  local bgIndex
  for i, row in ipairs(menu.rows) do
    if row.id == "battleFit" then fitRow = row end
    if row.id == "battleBg" then bgRow, bgIndex = row, i end
  end
  assert(fitRow and bgRow and bgIndex, "battle size/background rows are present")

  fitRow.step(game, 1)
  assert(options.battleFit == "fill", "battle size switched to FILL")
  assert(options.battleBg == "white", "FILL + EXTENDED normalized background to WHITE")
  assert(bgRow.value(game) == "AUTO", "adaptive background is labeled AUTO")
  assert(bgRow.step(game, 1) == false, "AUTO background row is locked")
  assert(options.battleBg == "white", "locked AUTO retains the WHITE value")

  menu.index = bgIndex
  menu.scroll = math.max(0, bgIndex - 5)
  U.wait(2)
  local autoPath = DIR .. "/fill_extended_auto_menu.png"
  os.remove(autoPath)
  local ok = U.shot(game, autoPath)

  fitRow.step(game, -1)
  assert(options.battleFit == "fixed", "battle size switched back to FIXED")
  assert(bgRow.value(game) == "WHITE", "FIXED exposes the stored WHITE choice")
  assert(bgRow.step(game, 1) == true and options.battleBg == "black",
    "FIXED can select BLACK")
  assert(bgRow.step(game, 1) == true and options.battleBg == "world",
    "FIXED can select WORLD")
  U.wait(2)
  local fixedPath = DIR .. "/fixed_extended_background_choices.png"
  os.remove(fixedPath)
  ok = U.shot(game, fixedPath) and ok

  U.log(ok and "FILL_EXTENDED_AUTO_MENU_PASS"
    or "FILL_EXTENDED_AUTO_MENU_FAIL")
  love.event.quit(ok and 0 or 1)
end
