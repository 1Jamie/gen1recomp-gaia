local U = require("tests.drivers.util")

local OUT = os.getenv("SHOT_DIR") or "battle-hud-layout-lock"
local BEFORE = OUT .. "/battle_hud_wide_extended.png"
local AFTER = OUT .. "/battle_hud_og_locked_standard.png"

return function(game)
  os.remove(BEFORE)
  os.remove(AFTER)

  local options = game.save.options
  options.battleLayout = "wide"
  options.battleHud = "extended"

  local menu = require("src.ui.Screens").push(game, "OptionsMenu")
  local layoutRow, hudRow
  for _, row in ipairs(menu.rows) do
    if row.id == "battleLayout" then layoutRow = row end
    if row.id == "battleHud" then hudRow = row end
  end
  assert(layoutRow and hudRow, "battle layout/HUD rows are present")

  menu.index = 6
  menu.scroll = 3
  assert(hudRow.value(game) == "EXTENDED", "WIDE displays EXTENDED")
  assert(U.shot(game, BEFORE), "WIDE/EXTENDED screenshot was written")

  layoutRow.step(game, 1)
  assert(options.battleLayout == "og", "layout switched to OG")
  assert(options.battleHud == "standard", "OG normalized HUD to STANDARD")
  assert(hudRow.value(game) == "STANDARD", "OG displays STANDARD")
  assert(U.shot(game, AFTER), "OG/STANDARD screenshot was written")

  print("[driver] BATTLE_HUD_LAYOUT_LOCK_PASS")
  game.driverDone = true
end
