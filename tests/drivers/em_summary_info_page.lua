local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_summary_info_page"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_summary_info_page failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function body(game)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_TORCHIC"), 9)
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_TORCHIC"), 12)
  session.party[2].status = "PSN"
  U.wait(60)

  local function settle()
    for _ = 1, 120 do
      if not (SummaryMenu._slide and SummaryMenu._slide.active) then break end
      U.wait(1)
    end
    U.wait(8)
  end

  for mi = 1, 2 do
    SummaryMenu.openMenu(session.party, mi, {})
    settle()
    U.still(game, DIR .. "/m" .. mi .. "_p0_info.png")
    U.tap(game, "right") settle()
    U.still(game, DIR .. "/m" .. mi .. "_p1_skills.png")
    U.tap(game, "right") settle()
    U.still(game, DIR .. "/m" .. mi .. "_p2_moves.png")
    U.tap(game, "right") settle()
    U.still(game, DIR .. "/m" .. mi .. "_p3_contest.png")
    U.tap(game, "a") settle()
    U.still(game, DIR .. "/m" .. mi .. "_p3_detail.png")
    U.tap(game, "b") settle()
    U.tap(game, "left") settle()
    U.tap(game, "a") settle()
    U.still(game, DIR .. "/m" .. mi .. "_p2_detail.png")
    for _ = 1, 4 do U.tap(game, "b") settle() end
    check(true, "mon " .. mi .. " pages shot")
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(30)
  local ok, err = xpcall(function() body(game) end, debug.traceback)
  if not ok then print("[driver] error " .. tostring(err)) failures = failures + 1 end
  return finish()
end
