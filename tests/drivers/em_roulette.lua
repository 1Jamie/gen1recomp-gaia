local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("em_roulette", "/tmp/em_roulette")

local GC = function() return require("src.core.game3.scripting.natives_game_corner_rse") end

local function snapshotHook(screen, wants)
  local orig = screen.frame
  screen.frame = function(self, inp)
    orig(self, inp)
    for _, w in ipairs(wants) do
      if not w.taken and w.when(self) then
        w.taken = true
        local ok, bytes = pcall(function() return self.m.ppu:snapshot():encode("png"):getString() end)
        if ok then
          os.execute('mkdir -p "' .. d.dir .. '" 2>/dev/null')
          local h = io.open(d.dir .. "/" .. w.name, "wb")
          if h then h:write(bytes) h:close() end
        end
      end
    end
  end
end

local function taskName(ui)
  local t = ui.m.tasks:get(ui.st.playTaskId)
  if not t.isActive then return "none" end
  for k, v in pairs(ui.fn) do if v == t.func then return k end end
  return "?"
end

return function(game)
  local sess = X.newGame(d, game, 1)
  if not sess then return d.finish() end
  local C = require("src.core.game3.constants").of("emerald")
  local Bag = require("src.core.game3.bag")
  Bag.add(sess.bag, C:require("items", "ITEM_COIN_CASE"), 1)
  Bag.Coins.set(sess, 100)
  X.setVar("VAR_DAILY_ROULETTE", 0)

  d.check(X.goTo(d, game, "EM_MAUVILLE_CITY_GAME_CORNER", 13, 7, "right"), "Mauville Game Corner loads")
  U.wait(20)
  GC().last = nil
  U.tap(game, "a")
  local entry = X.waitFor(function() return GC().last and GC().last.entry and GC().last.entry.state == "yesNo" end, 900)
  if not d.check(entry, "left table script runs PlayRoulette to the minimum-wager prompt") then return d.finish() end
  local e = GC().last.entry
  d.check(e.minBet == 1, "left table minimum wager is 1 (" .. tostring(e.minBet) .. ")")
  d.check(e.text and e.text:find("1", 1, true) ~= nil, "prompt names the wager: " .. tostring(e.text))
  d.check(require("src.ui.game3.coins_box").isVisible(), "coins window shows during the prompt")
  d.shot(game, "00_min_wager_prompt.png")
  U.tap(game, "a")
  local opened = X.waitFor(function() return GC().last.screen ~= nil end, 900)
  if not d.check(opened, "YES fades into the roulette table") then return d.finish() end
  local ui = GC().last.screen
  local snaps = {
    { name = "01_board.png", when = function(s) return s.st and s.frames > 30 and s.hw == nil and s.st.playTaskId and taskName(s) == "taskWaitForNextTask" end },
    { name = "02_select_grid.png", when = function(s) return s.st and s.st.playTaskId and taskName(s) == "taskHandleBetGridInput" end },
    { name = "03_ball_rolling.png", when = function(s) return s.st and s.st.ballRolling and s.st.ballState == 0 and s.st.ballDistToCenter and s.st.ballDistToCenter < 50 end },
    { name = "04_ball_landed.png", when = function(s) return s.st and s.st.playTaskId and taskName(s) == "taskSlideGridOnscreen" end },
    { name = "05_result.png", when = function(s) return s.st and s.st.playTaskId and taskName(s) == "taskTryIncrementWins" end },
  }
  snapshotHook(ui, snaps)
  local started = X.waitFor(function() return ui.st and ui.st.playTaskId and taskName(ui) == "taskWaitForNextTask" and ui.hw == nil end, 900)
  d.check(started, "board fades in with the controls instruction")
  d.check(ui.st.minBet == 1 and ui.st.tableId == 0, "table 0, min bet 1")
  U.wait(4)
  d.still(game, "01b_controls_instruction.png")

  local coins = 100
  for ball = 1, 3 do
    U.tap(game, "a")
    local grid = X.waitFor(function() return taskName(ui) == "taskHandleBetGridInput" end, 900)
    d.check(grid, "ball " .. ball .. ": bet grid opens on the first empty square (" .. ui:task(ui.st.playTaskId).data[4] .. ")")
    if ball == 2 then
      U.tap(game, "up")
      X.waitFor(function() return ui:task(ui.st.playTaskId).data[4] <= 4 end, 60)
      d.check(ui:task(ui.st.playTaskId).data[4] <= 4, "UP moves the selection to a column header")
    elseif ball == 3 then
      U.tap(game, "left")
      U.wait(2)
      U.tap(game, "left")
    end
    U.wait(10)
    if ball == 1 then d.still(game, "02b_grid_selection.png") end
    local sel = ui:task(ui.st.playTaskId).data[4]
    U.tap(game, "a")
    local rolled = X.waitFor(function() return ui.st.ballRolling end, 900)
    d.check(rolled, "ball " .. ball .. ": bet on " .. sel .. " slides the grid away and rolls the ball")
    local landed = X.waitFor(function() return taskName(ui) == "taskSlideGridOnscreen" or taskName(ui) == "taskFlashBallOnWinningSquare" end, 3000)
    d.check(landed, "ball " .. ball .. ": ball lands in slot " .. tostring(ui.st.hitSlot) .. " (stuck=" .. tostring(ui.st.ballStuck) .. ")")
    local asked = false
    for _ = 1, 40 do
      if not X.waitFor(function()
        return taskName(ui) == "taskCallYesOrNo" or (taskName(ui) == "taskWaitForNextTask" and (ui.st.taskWaitKey or 0) ~= 0)
      end, 30000) then break end
      if taskName(ui) == "taskCallYesOrNo" then asked = true break end
      local next = ui.st.nextTask
      U.tap(game, "a")
      X.waitFor(function() return taskName(ui) ~= "taskWaitForNextTask" or ui.st.nextTask ~= next end, 120)
    end
    if not asked then d.note("stuck in " .. taskName(ui) .. " sePlaying=" .. tostring(ui.sound:sePlaying())) end
    local dd = ui:task(ui.st.playTaskId).data
    d.check(asked, string.format("ball %d: result %s, credit %d -> %d, asks to keep playing", ball,
      dd[5] == 1 and "hit" or "miss", coins, dd[13]))
    if dd[5] == 1 then
      d.check(dd[13] == coins - 1 + dd[2], "payout is min bet x multiplier (" .. dd[2] .. ")")
    else
      d.check(dd[13] == coins - 1, "a miss costs the min bet")
    end
    coins = dd[13]
    if ball < 3 then
      U.tap(game, "a")
      X.waitFor(function() return taskName(ui) ~= "taskCallYesOrNo" end, 200)
    end
  end
  d.still(game, "06_keep_playing.png")
  U.tap(game, "down")
  U.wait(2)
  U.tap(game, "a")
  local closed = X.waitFor(function() return GC().last.phase == "done" end, 1500)
  d.check(closed, "NO fades back to the field")
  X.settle(game, 600)
  X.waitFor(function() return not X.scriptRunning() end, 600)
  U.wait(30)
  local s = X.session()
  d.check(s.map == "EM_MAUVILLE_CITY_GAME_CORNER", "back in the Game Corner")
  d.check(Bag.Coins.get(s) == coins, "coin case holds the table's credit (" .. Bag.Coins.get(s) .. " == " .. coins .. ")")
  d.check(X.var("VAR_DAILY_ROULETTE") == 3, "IncrementDailyRouletteUses counted 3 balls (" .. X.var("VAR_DAILY_ROULETTE") .. ")")
  d.check(not X.scriptRunning(), "roulette script released")
  d.shot(game, "07_back_in_field.png")
  for _, w in ipairs(snaps) do d.note("snapshot " .. w.name .. " " .. tostring(w.taken)) end
  d.finish()
end
