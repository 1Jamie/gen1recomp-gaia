local T = require("tests.harness")
local check, eq = T.check, T.eq

local RseSummary = require("src.ui.game3.rse.summary_menu")
check(type(RseSummary.draw) == "function", "RseSummary.draw exists")
check(type(RseSummary.watchMonAnim) == "function", "watchMonAnim exists")

-- Verify detail mode doesn't swap out front portrait
local Sm = {
  open = false,
  _page = 2,
  _mode = "select_move",
}
eq(RseSummary.detail(Sm), true, "detail is true for select_move")
eq(RseSummary.page(Sm), 2, "page is BATTLE_MOVES")

-- Overview mode (detail = false)
local SmOverview = {
  open = false,
  _page = 2,
  _mode = "view",
}
eq(RseSummary.detail(SmOverview), false, "detail is false for view mode")
eq(RseSummary.page(SmOverview), 2, "page is BATTLE_MOVES")

T.finish("game3_summary_move_sprite_test")
