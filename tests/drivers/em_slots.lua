local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("em_slots", "/tmp/em_slots")

local GC = function() return require("src.core.game3.scripting.natives_game_corner_rse") end

local function hookSnapshots(screen, wants)
  local orig = screen.frame
  screen.frame = function(self, inp)
    orig(self, inp)
    for _, w in ipairs(wants) do
      if not w.taken and w.when(self) then
        w.taken = true
        if self.m.ppu.render then
          local ok, data = pcall(function() return self.m.ppu:snapshot():encode("png"):getString() end)
          if ok then
            os.execute('mkdir -p "' .. d.dir .. '" 2>/dev/null')
            local h = io.open(d.dir .. "/" .. w.name, "wb")
            if h then h:write(data) h:close() end
          end
        end
      end
    end
  end
end

return function(game)
  local sess = X.newGame(d, game, 0)
  if not sess then return d.finish() end
  local Constants = require("src.core.game3.constants")
  local C = Constants.of("emerald")
  local Bag = require("src.core.game3.bag")
  Bag.add(sess.bag, C:require("items", "ITEM_COIN_CASE"), 1)
  Bag.Coins.set(sess, 120)
  X.setVar("VAR_DAILY_SLOTS", 0)

  d.check(X.goTo(d, game, "EM_MAUVILLE_CITY_GAME_CORNER", 4, 7, "left"), "Mauville Game Corner loads")
  U.wait(20)
  d.shot(game, "00_game_corner.png")
  GC().last = nil
  U.tap(game, "a")
  local opened = X.waitFor(function() return GC().last and GC().last.screen ~= nil end, 600)
  if not d.check(opened, "slot machine 3 script opens the RSE slot machine (" .. tostring(GC().last and GC().last.phase) .. ")") then
    return d.finish()
  end
  local ui = GC().last.screen
  d.check(ui.machineId >= 0 and ui.machineId <= 5 and ui.machineId == GC().last.machineId,
    "GetSlotMachineId picks machine " .. tostring(ui.machineId) .. " for VAR_0x8004=3")
  local snaps = {
    { name = "01_bet_prompt.png", when = function(s) return s.core.state == 5 and s.frames > 40 end },
    { name = "02_reels_spinning.png", when = function(s) return s.core.state == 12 end },
    { name = "03_stopped.png", when = function(s) return s.core.state == 14 or s.core.state == 15 or s.core.state == 20 end },
    { name = "05_reel_time_window.png", when = function(s) return s.reelTimeTaskId and s.m.tasks:get(s.reelTimeTaskId).isActive and s.m.tasks:get(s.reelTimeTaskId).data[0] == 4 end },
    { name = "06_reel_time_outcome.png", when = function(s) return s.reelTimeTaskId and s.m.tasks:get(s.reelTimeTaskId).isActive and (s.m.tasks:get(s.reelTimeTaskId).data[0] == 9 or s.m.tasks:get(s.reelTimeTaskId).data[0] == 16) end },
  }
  hookSnapshots(ui, snaps)
  X.waitFor(function() return ui.core.state == 5 end, 600)
  d.check(ui.core.state == 5, "bet prompt reached (state " .. ui.core.state .. ")")
  d.check(ui.core.coins == 120, "machine starts with the coin case's 120 coins")
  U.wait(10)
  d.still(game, "01b_bet_screen.png")

  local spins, won = 0, 0
  local function spin(maxBet)
    local before = ui.core.coins
    if maxBet then
      U.tap(game, "r")
    else
      U.tap(game, "down")
      U.wait(2)
      U.tap(game, "a")
    end
    local started = X.waitFor(function() return ui.core.state == 12 end, 900)
    if not started then return false end
    spins = spins + 1
    for _ = 1, 3 do
      X.waitFor(function() return ui.core.state == 12 end, 900)
      U.tap(game, "a")
      U.wait(3)
    end
    local back = X.waitFor(function() return ui.core.state == 5 or ui.core.state == 12 end, 3000)
    if ui.core.state == 12 then return "replay" end
    if ui.core.coins >= before then won = won + 1 end
    return back
  end
  local r = spin(true)
  d.check(r, "max bet spins and stops all three reels")
  d.check(ui.core.bet == 0 or ui.core.state == 12, "round resolves back to the bet prompt")
  d.still(game, "03b_after_spin.png")
  for _ = 1, 6 do
    local rr = spin(false)
    while rr == "replay" do
      for _ = 1, 3 do
        X.waitFor(function() return ui.core.state == 12 end, 900)
        U.tap(game, "a")
        U.wait(3)
      end
      X.waitFor(function() return ui.core.state == 5 or ui.core.state == 12 end, 3000)
      rr = ui.core.state == 12 and "replay" or true
    end
  end
  d.note(string.format("played %d spins, %d without a net loss, coins now %d, bolts %d", spins, won, ui.core.coins, ui.core.pikaPowerBolts))

  U.tap(game, "select")
  local function infoState()
    for i = 0, 15 do
      local t = ui.m.tasks:get(i)
      if t.isActive and t.func == ui.infoBoxFn then return t.data[0] end
    end
    return -1
  end
  local boxOpen = X.waitFor(function() return infoState() == 6 end, 600)
  d.check(boxOpen and ui.infoWindow and ui.infoWindow.text, "SELECT opens the Reel Time info box")
  d.still(game, "04_info_box.png")
  U.tap(game, "b")
  local boxClosed = X.waitFor(function() return ui:isInfoBoxClosed() and ui.core.state == 5 end, 600)
  d.check(boxClosed, "B closes the info box back to the bet prompt")

  ui.core.machineBias = bit.bor(ui.core.machineBias, require("src.core.game3.rse.slot_machine").BIAS.REELTIME)
  local rtStart = ui.core.coins
  U.tap(game, "r")
  local rtRan = X.waitFor(function() return ui.reelTimeTaskId ~= nil end, 600)
  d.check(rtRan, "a Reel Time bias starts the Reel Time lottery")
  local rtDone = X.waitFor(function() return ui:isReelTimeTaskDone() and ui.core.state == 12 end, 6000)
  d.check(rtDone, "Reel Time lottery resolves (draw=" .. ui.core.reelTimeDraw .. ", spins left=" .. ui.core.reelTimeSpinsLeft .. ")")
  for _ = 1, 3 do
    X.waitFor(function() return ui.core.state == 12 end, 900)
    U.tap(game, "a")
    U.wait(3)
  end
  X.waitFor(function() return ui.core.state == 5 end, 3000)
  d.note("after Reel Time round coins " .. rtStart .. " -> " .. ui.core.coins)

  local daily = spins + 1
  X.waitFor(function() return ui.core.state == 5 and not ui.m.ppu.palette.active end, 600)
  U.tap(game, "b")
  local asked = X.waitFor(function() return ui.message ~= nil and ui.yesNo ~= nil end, 600)
  d.check(asked, "B asks to quit")
  U.wait(10)
  d.still(game, "07_quit_prompt.png")
  local final = ui.core.coins
  U.tap(game, "a")
  local closed = X.waitFor(function() return GC().last.phase == "done" end, 1200)
  d.check(closed, "YES fades out and returns to the field")
  X.settle(game, 600)
  X.waitFor(function() return not X.scriptRunning() end, 600)
  U.wait(30)
  local s = X.session()
  d.check(s.map == "EM_MAUVILLE_CITY_GAME_CORNER", "back in the Game Corner (" .. tostring(s.map) .. ")")
  d.check(Bag.Coins.get(s) == final, "coin case holds the machine's coins (" .. Bag.Coins.get(s) .. " == " .. final .. ")")
  d.check(X.var("VAR_DAILY_SLOTS") >= daily - 1 and X.var("VAR_DAILY_SLOTS") > 0,
    "IncrementDailySlotsUses counted the spins (" .. X.var("VAR_DAILY_SLOTS") .. ")")
  d.check(not X.scriptRunning(), "slot machine script released")
  d.shot(game, "08_back_in_field.png")
  for _, w in ipairs(snaps) do d.note("snapshot " .. w.name .. " " .. tostring(w.taken)) end
  d.finish()
end
