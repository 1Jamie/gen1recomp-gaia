local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local F = require("tests.drivers.em_fc_util").new("em_berry_blender")

local d = S.new("em_berry_blender", "/tmp/em_berry_blender")

local function waitFor(pred, frames)
  for _ = 1, frames or 300 do
    if pred() then return true end
    U.wait(1)
  end
  return pred() and true or false
end

local function settleSafe(game, opts)
  return F.try("settle", function() S.settle(game, opts) end)
end

local function lcg(seed)
  local Rng = require("src.core.game3.rng")
  local st = seed
  return function()
    st = (Rng.mulU32(st, 1103515245) + 24691) % 4294967296
    return math.floor(st / 65536) % 65536
  end
end

local function wrap(ui, plan)
  local B = require("src.core.game3.rse.berry_blender")
  local orig = ui.frame
  local press = {}
  for _, p in ipairs(plan.press or {}) do press[p] = true end
  plan.playN = -1
  plan.holds = {}
  local function holdOnce(name)
    if not plan.holds[name] then
      plan.holds[name] = true
      ui._hold = name
    end
  end
  ui.frame = function(self, inp)
    if self._hold then return end
    if self.cb == "load" and self.state == 0 then
      plan.playN = -1
      plan.holds = {}
    end
    inp = inp or { new = {}, held = {} }
    if self.cb == "play" then
      if plan.playN < 0 then
        plan.playN = 0
        if plan.seed then
          self.random = lcg(plan.seed)
          self.vblankRandom = true
        end
      end
      local new = {}
      for k, v in pairs(inp.new or {}) do if k ~= "a" then new[k] = v end end
      if plan.seed then
        new.a = press[plan.playN] or nil
      else
        local g = self.game
        local nxt = (g.arrowPos + g.speed) % 65536
        if g:arrowProximity(nxt, 0) == B.PROXIMITY.BEST and (plan.cool or 0) == 0 then
          new.a = true
          plan.cool = 12
        end
        plan.cool = math.max(0, (plan.cool or 0) - 1)
      end
      inp = { new = new, held = inp.held or {} }
      plan.playN = plan.playN + 1
    end
    orig(self, inp)
    if self.cb == "load" and self.state == 4 and self.printer and self.printer.state == "clear" then holdOnce("load") end
    if self.cb == "play" and plan.shotAt and plan.shotAt[plan.playN] then holdOnce("play_" .. plan.playN) end
    local g = self.game
    if self.cb == "end" and g then
      if g.gameEndState == 5 and self.rankState == 5 then holdOnce("ranking") end
      if g.gameEndState == 6 and self.resState == 4 then holdOnce("results") end
      if g.gameEndState == 6 and self.resState == 6 and self.printer and self.printer.state == "clear" and self.printer.arrowFrame then holdOnce("made") end
      if g.gameEndState == 10 then holdOnce("yesno") end
    end
  end
end

local function runScreen(game, UI, plan)
  local ui = UI.active()
  wrap(ui, plan)
  local seen = {}
  local answered = 0
  local BagMenu = require("src.ui.game3.bag_menu")
  for _ = 1, 60000 do
    if ui.done or not UI.isOpen() then break end
    if BagMenu.open and BagMenu._location == "blender" then
      if not seen.bag then
        seen.bag = true
        U.wait(30)
        d.shot(game, "01b_choose_berry")
      end
      if BagMenu.mode == "action" then
        for i, a in ipairs(BagMenu.ACTIONS or {}) do if a == "CONFIRM" then BagMenu.actionCursor = i end end
      end
      U.tap(game, "a")
      U.wait(6)
    elseif ui._hold then
      local name = ui._hold
      seen[name] = true
      if plan.shots and plan.shots[name] then d.shot(game, plan.shots[name]) end
      if plan.onHold then plan.onHold(name, ui) end
      ui._hold = nil
      if name == "yesno" then
        answered = answered + 1
        local yes = plan.answer and plan.answer(answered)
        if not yes then U.tap(game, "down"); U.wait(4) end
        U.tap(game, "a")
      elseif name ~= "load" and not name:find("^play_") then
        U.wait(2)
        U.tap(game, "a")
      end
    elseif ui.cb == "load" or (ui.cb == "end" and ui.game and ui.game.gameEndState >= 5) or ui.cb == "again" then
      if ui.printer and ui.printer.state == "clear" then U.tap(game, "a") else U.wait(1) end
    else
      U.wait(1)
    end
  end
  return ui, seen
end

return function(game)
  local UI = require("src.ui.game3.rse.berry_blender")
  local B = require("src.core.game3.rse.berry_blender")
  local Pokeblock = require("src.core.game3.rse.pokeblock")
  local Records = require("src.ui.game3.rse.frontier_records")
  local Message = require("src.ui.game3.message")
  local Bag = require("src.core.game3.bag")
  local golden = dofile("tests/data/emerald_blender/golden.lua").mister2

  if not F.boot(game) then return d.finish() end
  local s = S.session()
  s.name = "NICK"
  s.playerName = "NICK"
  local Options = require("src.core.game3.options")
  local o = Options.block(s.options or {})
  if type(s.options) == "table" then
    o.textSpeed, o.frameType = 2, 4
  end
  pcall(function() require("src.ui.game3.chrome").setFrameType(4) end)
  s.party = {}
  S.giveMon("SPECIES_TORCHIC", 30)
  F.flags().setVar("VAR_REPEL_STEP_COUNT", 250)
  F.flags().set("FLAG_RECEIVED_POKEBLOCK_CASE", true)
  S.giveItem("ITEM_POKEBLOCK_CASE", 1)
  S.giveItem("ITEM_CHERI_BERRY", 4)
  Pokeblock.clearAll(s)
  Pokeblock.add(s, { color = Pokeblock.COLOR.PINK, sweet = 12, feel = 23 })
  s.berryBlenderRecords = { 11052, 0, 0 }
  s.gameStats = s.gameStats or {}
  local cheri = S.item("ITEM_CHERI_BERRY")

  -- pokeemerald/data/maps/LilycoveCity_ContestLobby/scripts.inc:528
  F.goTo(game, "EM_LILYCOVE_CITY_CONTEST_LOBBY", 30, 2, "up", { keepScripts = true })
  settleSafe(game, { limit = 600 })
  local opened = false
  for _ = 1, 5 do
    U.tap(game, "a")
    opened = waitFor(function() return Records.isOpen() end, 60)
    if opened then break end
  end
  d.check(opened, "ShowBerryBlenderRecordWindow opens the speed record window")
  if opened then
    local texts = {}
    for _, p in ipairs(Records._window.prints) do texts[#texts + 1] = p.s end
    local all = table.concat(texts, " | ")
    d.check(all:find("MAXIMUM SPEED RECORD!", 1, true) ~= nil and all:find("110.52 RPM", 1, true) ~= nil
      and all:find("{UNK_SPACER}{UNK_SPACER}0.00 RPM", 1, true) ~= nil, "records window: " .. all)
    d.shot(game, "00_speed_records")
    for _ = 1, 30 do
      if not Records.isOpen() then break end
      U.wait(8)
      U.tap(game, "a")
    end
    d.check(not Records.isOpen(), "a button press closes the record window")
    for _ = 1, 30 do
      if not S.vmRunning() then break end
      U.wait(8)
      U.tap(game, "a")
    end
    if not d.check(not S.vmRunning(), "waitbuttonpress + RemoveRecordsWindow + releaseall finish the sign script") then
      local Hud = require("src.ui.game3.hud")
      local top = require("src.ui.game3.stack").top()
      d.note("vm=" .. S.vmWhere() .. " wait=" .. tostring(Hud._waitButton ~= nil) .. " top=" .. tostring(top and top.id)
        .. " msg=" .. tostring(Message.isOpen()) .. " rec=" .. tostring(Records.isOpen()))
    end
  end
  settleSafe(game, { limit = 600 })

  -- pokeemerald/data/scripts/berry_blender.inc:229
  F.goTo(game, "EM_LILYCOVE_CITY_CONTEST_LOBBY", 27, 6, "up", { keepScripts = true })
  settleSafe(game, { limit = 600 })
  d.shot(game, "01_lobby_blender")
  local pages = {}
  U.tap(game, "a")
  settleSafe(game, {
    limit = 6000,
    until_ = function() return UI.isOpen() end,
    watch = function()
      local page = Message.isOpen() and Message.currentPage() or ""
      if page ~= "" and pages[#pages] ~= page then pages[#pages + 1] = page end
    end,
    choice = function() return "yes" end,
  })
  local talk = table.concat(pages, " / "):gsub("\n", " ")
  d.check(talk:find("make some", 1, true) ~= nil and talk:find("old-timer", 1, true) ~= nil,
    "BerryBlender_Text_WantToMakePokeblocks (" .. talk .. ")")
  d.check(talk:find("Let's BERRY BLENDER!", 1, true) ~= nil, "BerryBlender_Text_LetsBerryBlender")
  if not d.check(UI.isOpen(), "special DoBerryBlending opens the BERRY BLENDER") then return d.finish() end
  local ui = UI.active()
  d.check(ui.var8004 == 1, "VAR_0x8004 = 1 NPC opponent")
  local okBag = require("src.core.game3.rse.init").system("bag")
  if not (okBag and okBag.chooseBerry) then
    d.note("NOTE Rse bag system has no chooseBerry (ChooseBerryForMachine, crossfile bag owner); the blender takes the first berry in the BERRIES pocket")
    d.dropChooser = true
  end

  local plan = {
    seed = golden.rng0,
    press = golden.press,
    shotAt = { [1] = true, [100] = true, [300] = true, [600] = true, [1000] = true },
    shots = {
      load = "02_load_msg", play_1 = "07_play_0001", play_100 = "07_play_0100", play_300 = "07_play_0300",
      play_600 = "07_play_0600", play_1000 = "07_play_1000", ranking = "10_ranking", results = "11_results",
      made = "12_made", yesno = "13_yesno",
    },
    answer = function() return false end,
    onHold = function(name, u)
      if name == "load" then
        local page = u.printer and table.concat(u.printer.lines, "\n") or ""
        d.check(page:find("Starting up the BERRY BLENDER.", 1, true) ~= nil, "sText_BerryBlenderStart printed")
      elseif name == "play_1" then
        local g = u.game
        d.check(g.playerNames[1] == "MISTER", "the NPC is MISTER (blend master away)")
        d.check(g.chosenItemId[0] == cheri and g.chosenItemId[1] == S.item("ITEM_ASPEAR_BERRY"),
          "CHERI vs MISTER's ASPEAR in the blender")
        d.check(g.playerIdToArrowId[0] == 1 and g.playerIdToArrowId[1] == 2, "player arrow top right, MISTER bottom left")
      elseif name == "ranking" then
        local g = u.game
        local sc = {}
        for p = 0, 3 do for k = 0, 2 do sc[#sc + 1] = g.scores[p][k] end end
        d.check(table.concat(sc, ",") == table.concat(golden.final.scores, ","),
          "scores equal the pygba run (" .. table.concat(sc, ",") .. ")")
        d.check(g.maxRPM == golden.final.maxRPM, "max RPM equals the pygba run (" .. g.maxRPM .. ")")
        d.check(g.gameFrameTime == golden.final.frameTime, "blend time equals the pygba run (" .. g.gameFrameTime .. ")")
      elseif name == "made" then
        local page = u.printer and table.concat(u.printer.lines, "\n") or ""
        d.check(page:find("RED ", 1, true) ~= nil and page:find("The level is 12, and the feel is 23.", 1, true) ~= nil,
          "made message: " .. page:gsub("\n", " "))
      end
    end,
  }
  local berriesBefore = Bag.get(s.bag, cheri)
  local dailyBefore = F.flags().var("VAR_DAILY_BLENDER")
  ui = runScreen(game, UI, plan)
  d.check(plan.playN == golden.frames, "play lasted " .. tostring(plan.playN) .. " frames (pygba " .. golden.frames .. ")")
  waitFor(function() return not UI.isOpen() end, 300)
  d.check(not UI.isOpen(), "NO returns to the field")
  settleSafe(game, { limit = 1200 })
  d.check(S.mapNow() == "EM_LILYCOVE_CITY_CONTEST_LOBBY", "back in the contest lobby")
  local b = s.pokeblocks[2]
  local P = golden.pokeblock
  d.check(b and b.color == P.color and b.spicy == P.spicy and b.feel == P.feel,
    string.format("RED POKeBLOCK lv%d feel %d added to the case (pygba %d/%d)", b and b.spicy or -1, b and b.feel or -1, P.spicy, P.feel))
  d.check(Bag.get(s.bag, cheri) == berriesBefore - 1, "one CHERI BERRY used")
  d.check(F.flags().var("VAR_DAILY_BLENDER") == dailyBefore + 1, "IncrementDailyBerryBlender")
  d.check((s.gameStats[B.GAME_STAT_POKEBLOCKS] or 0) == 1, "GAME_STAT_POKEBLOCKS counted")
  d.check(s.berryBlenderRecords[1] == 11052, "2-player record kept (110.52 > " .. golden.final.maxRPM / 100 .. ")")
  d.shot(game, "14_back")

  -- pokeemerald/data/scripts/berry_blender.inc:329
  F.goTo(game, "EM_LILYCOVE_CITY_CONTEST_LOBBY", 23, 10, "up", { keepScripts = true })
  settleSafe(game, { limit = 600 })
  pages = {}
  U.tap(game, "a")
  settleSafe(game, {
    limit = 6000,
    until_ = function() return UI.isOpen() end,
    watch = function()
      local page = Message.isOpen() and Message.currentPage() or ""
      if page ~= "" and pages[#pages] ~= page then pages[#pages + 1] = page end
    end,
    choice = function() return "yes" end,
  })
  talk = table.concat(pages, " / "):gsub("\n", " ")
  d.check(talk:find("good at blending", 1, true) ~= nil, "BerryBlender_Text_LookGoodAtBlendingJoinUs")
  if d.check(UI.isOpen(), "the three-NPC blender opens") then
    ui = UI.active()
    d.check(ui.var8004 == 3, "three NPC opponents")
    local rounds = 0
    local plan3 = {
      shotAt = { [300] = true },
      shots = { play_300 = "20_three_play", ranking = "21_three_ranking" },
      answer = function(n) return n == 1 end,
      onHold = function(name, u)
        if name == "play_300" then
          rounds = rounds + 1
          local g = u.game
          d.check(g.playerNames[1] == "MISS" and g.playerNames[2] == "LADDIE" and g.playerNames[3] == "LASSIE",
            "MISS, LADDIE and LASSIE join (round " .. rounds .. ")")
        end
      end,
    }
    local before = Pokeblock.count(s)
    ui = runScreen(game, UI, plan3)
    d.check(rounds == 2, "YES blends another BERRY (" .. rounds .. " rounds)")
    waitFor(function() return not UI.isOpen() end, 300)
    settleSafe(game, { limit = 1200 })
    d.check(Pokeblock.count(s) == before + 2, "two more POKeBLOCKS (" .. Pokeblock.count(s) .. ")")
    d.check(s.berryBlenderRecords[3] > 0, "4-player speed record set (" .. s.berryBlenderRecords[3] .. ")")
    d.check(Bag.get(s.bag, cheri) == berriesBefore - 3, "three CHERI BERRIES used in all")
  end

  if d.dropChooser then
    local keep = {}
    for _, m in ipairs(d.vmLogs) do if not m:find("ChooseBerryForMachine", 1, true) then keep[#keep + 1] = m end end
    d.vmLogs = keep
  end
  d.finish()
end
