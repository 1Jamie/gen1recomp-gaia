local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_move_relearner"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_move_relearner failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    print("[driver] " .. label .. " error: " .. tostring(err))
    failures = failures + 1
  end
  return ok
end

local function body(game)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local MoveLearn = require("src.core.game3.move_learn")
  local Stack = require("src.ui.game3.stack")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local MoveTeach = require("src.core.game3.scripting.natives_moveteach")
  local Rse = require("src.ui.game3.rse.move_relearner")
  local C = require("src.core.game3.constants").of("emerald")

  local session = Runtime.getSession()
  if not check(session and session.version == "emerald", "emerald session") then return end

  session.party = {}
  Party.giveMonToPlayer(session, C:require("species", "SPECIES_TORCHIC"), 40)
  local mon = session.party[1]
  local start = {}
  for i = 1, 4 do start[i] = Pokemon.moveIdAt(mon, i) end
  print("[driver] start moves: " .. table.concat({ Pokemon.moveName(start[1]), Pokemon.moveName(start[2]),
    Pokemon.moveName(start[3]), Pokemon.moveName(start[4]) }, ", "))
  local offers = MoveLearn.relearnableMoves(mon)
  check(#offers >= 6, "relearnable list scrolls, count=" .. #offers)

  local ctx = { specialVars = { [0x8004] = 0 } }
  local yielded = MoveTeach.BY_NAME.TeachMoveRelearnerMove(ctx, {})
  check(yielded == true, "TeachMoveRelearnerMove yields to the host")
  U.wait(10)
  local top = Stack.top()
  check(top and top.id == "move_relearner" and top.mod == Rse, "native opened the Emerald relearner screen")
  check(Rse.isOpen() and not require("src.ui.game3.move_relearner").isOpen(), "FRLG screen stayed closed")
  check(Rse.prompt and Rse.prompt:find("Teach which move", 1, true) ~= nil, "prompt: " .. tostring(Rse.prompt))
  U.still(game, DIR .. "/01_list_battle.png")

  for _ = 1, 6 do U.tap(game, "down"); U.wait(6) end
  check(Rse.cursor == 7 and Rse.scroll == 1, "cursor on CANCEL, list scrolled (cursor=" .. Rse.cursor .. " scroll=" .. Rse.scroll .. ")")
  U.still(game, DIR .. "/02_list_scrolled_cancel.png")

  local want = C:require("moves", "MOVE_EMBER")
  local row
  for i, id in ipairs(Rse.moves()) do if id == want then row = i end end
  if not check(row ~= nil, "EMBER is relearnable") then return end
  for _ = 1, 10 do
    if Rse.cursor == row then break end
    U.tap(game, "up"); U.wait(6)
  end
  check(Rse.cursor == row, "cursor on EMBER")
  U.tap(game, "right"); U.wait(8)
  check(Rse.contest == true, "RIGHT switched to CONTEST MOVES")
  U.still(game, DIR .. "/03_contest_ember.png")
  U.tap(game, "left"); U.wait(8)
  check(Rse.contest == false, "LEFT switched back to BATTLE MOVES")
  U.still(game, DIR .. "/04_battle_ember.png")

  U.tap(game, "a"); U.wait(10)
  check(Rse.state == "yesno" and Rse.prompt:find("Teach", 1, true) ~= nil, "teach confirm: " .. tostring(Rse.prompt))
  U.still(game, DIR .. "/05_teach_confirm.png")
  U.tap(game, "a"); U.wait(10)
  check(Rse.state == "message" and Rse.prompt:find("trying to learn", 1, true) ~= nil, "trying-to-learn page 1: " .. tostring(Rse.prompt))
  U.still(game, DIR .. "/06_trying_to_learn.png")
  U.tap(game, "a"); U.wait(10)
  check(Rse.state == "message" and Rse.prompt:find("four moves", 1, true) ~= nil, "page 2: " .. tostring(Rse.prompt))
  U.tap(game, "a"); U.wait(10)
  check(Rse.state == "yesno" and Rse.prompt:find("Delete an older move", 1, true) ~= nil, "delete prompt: " .. tostring(Rse.prompt))
  U.still(game, DIR .. "/07_delete_prompt.png")
  U.tap(game, "a"); U.wait(10)
  check(Rse.state == "message" and Rse.prompt:find("forgotten", 1, true) ~= nil and not Rse.prompt:find("\\", 1, true),
    "which-move prompt: " .. tostring(Rse.prompt))
  U.still(game, DIR .. "/08_which_move.png")
  U.tap(game, "a")
  for _ = 1, 120 do
    if SummaryMenu.isOpen() then break end
    U.wait(2)
  end
  if not check(SummaryMenu.isOpen() and SummaryMenu._mode == "select_move", "summary opened in select_move") then return end
  U.wait(60)
  U.still(game, DIR .. "/09_summary_select.png")
  U.tap(game, "a")
  for _ = 1, 120 do
    if not SummaryMenu.isOpen() then break end
    U.wait(2)
  end
  U.wait(10)
  check(Rse.state == "message" and Rse.prompt:find("Poof", 1, true) ~= nil, "poof: " .. tostring(Rse.prompt))
  U.still(game, DIR .. "/10_poof.png")
  local pages = {}
  for _ = 1, 8 do
    if not Rse.isOpen() then break end
    pages[#pages + 1] = Rse.prompt
    if #pages == 4 then U.still(game, DIR .. "/11_learned.png") end
    U.tap(game, "a"); U.wait(10)
  end
  print("[driver] pages: " .. table.concat(pages, " | "):gsub("\n", " "))
  check(pages[2] and pages[2]:find("forgot", 1, true) ~= nil, "forgot page")
  check(pages[4] and pages[4]:find("learned", 1, true) ~= nil, "learned page")
  check(not Rse.isOpen(), "relearner closed")
  check(ctx.specialVars[0x8004] == 1, "VAR_0x8004 = 1 after teach, got " .. tostring(ctx.specialVars[0x8004]))
  check(Pokemon.knowsMove(mon, want), "mon knows EMBER")
  check(not Pokemon.knowsMove(mon, start[1]), "mon forgot " .. tostring(Pokemon.moveName(start[1])))

  ctx.specialVars[0x8004] = 0
  MoveTeach.BY_NAME.TeachMoveRelearnerMove(ctx, {})
  U.wait(10)
  U.tap(game, "b"); U.wait(10)
  check(Rse.state == "yesno" and Rse.prompt:find("Give up", 1, true) ~= nil, "give-up prompt: " .. tostring(Rse.prompt))
  U.still(game, DIR .. "/12_give_up.png")
  U.tap(game, "a"); U.wait(10)
  check(not Rse.isOpen() and ctx.specialVars[0x8004] == 0, "give up closes with VAR_0x8004 = 0")
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  check(game.boot ~= nil, "boot reached")
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(30)
  try("body", function() body(game) end)
  return finish()
end
