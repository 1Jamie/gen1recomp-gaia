return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local TextBox = require("src.render.TextBox")
  local failed = false

  local function check(label, ok)
    if ok then print("PASS " .. label) else print("FAIL " .. label) failed = true end
  end

  local function finish()
    love.event.quit(failed and 1 or 0)
  end

  U.newGame(game)
  U.teleport(game, "OAKS_LAB", 5, 6, "up")

  local text = game.data.text._OaksLabGivePokeballsExplanationText
  check("text present", text ~= nil)
  if not text then return finish() end

  local box = TextBox.new(game, text)
  game.stack:push(box)
  check("page 2 has two rows", #box.pages[2] == 2)
  check("page 2 row 2 overwritten", box.pages[2][2] == "to catch it!nd try")

  for _ = 1, 3000 do
    if box.waiting then break end
    U.wait(1)
  end
  check("waits at first para", box.waiting)
  for _ = 1, 3000 do
    if box.pageIndex == 2 and not box.waiting and box.charIndex >= 1 then break end
    if box.waiting and box.pageIndex == 1 then
      U.wait(10)
      U.tap(game, "a")
    end
    U.wait(1)
  end

  local scrolledAuto = false
  for _ = 1, 600 do
    U.wait(1)
    if box.waiting and box.pageIndex == 2 then break end
    if box.lineIndex > 2 then scrolledAuto = true end
  end
  check("page 2 never auto-scrolled a third line", not scrolledAuto)
  check("page 2 stops for a press", box.waiting and box.pageIndex == 2)
  U.still(game, DIR .. "/page2_end_waiting_arrow.png")

  U.wait(10)
  U.tap(game, "a")
  U.wait(60)
  check("press advances to page 3", box.pageIndex == 3)
  finish()
end
