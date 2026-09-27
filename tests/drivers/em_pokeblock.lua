local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local F = require("tests.drivers.em_fc_util").new("em_pokeblock")

local d = S.new("em_pokeblock", "/tmp/em_pokeblock")

local function topId()
  local top = require("src.ui.game3.stack").top()
  return top and top.id or nil
end

local function waitFor(pred, frames)
  for _ = 1, frames or 300 do
    if pred() then return true end
    U.wait(1)
  end
  return pred() and true or false
end

local function tapWait(game, btn, frames)
  U.tap(game, btn)
  U.wait(frames or 4)
end

local function settleSafe(game, opts)
  local ok = F.try("settle", function() S.settle(game, opts) end)
  return ok
end

return function(game)
  local Case = require("src.ui.game3.rse.pokeblock_case")
  local Use = require("src.ui.game3.rse.use_pokeblock")
  local Feed = require("src.ui.game3.rse.pokeblock_feed")
  local Tag = require("src.ui.game3.rse.berry_tag")
  local Pokeblock = require("src.core.game3.rse.pokeblock")
  local Bag = require("src.core.game3.bag")
  local Message = require("src.ui.game3.message")
  local Collision = require("src.core.game3.collision")
  local Player = require("src.core.game3.player")

  if not F.boot(game) then return d.finish() end
  local s = S.session()
  s.party = {}
  local mon = S.giveMon("SPECIES_TORCHIC", 30)
  -- pokeemerald/src/pokemon.c:6590
  mon.personality = mon.personality - (mon.personality % 25) + 1
  mon.contest = nil
  d.check(Pokeblock.natureOf(mon) == 1, "lead mon has a Lonely nature (likes spicy)")
  F.flags().setVar("VAR_REPEL_STEP_COUNT", 250)
  F.flags().set("FLAG_SYS_POKEDEX_GET", true)

  -- pokeemerald/data/scripts/contest_hall.inc:15
  F.goTo(game, "EM_LILYCOVE_CITY_CONTEST_LOBBY", 14, 4, "up")
  d.check(not S.hasItem("ITEM_POKEBLOCK_CASE"), "no POKeBLOCK CASE before the contest lobby")
  U.tap(game, "a")
  waitFor(function() return S.vmRunning() end, 60)
  d.check(S.vmRunning(), "talking to the contest receptionist runs her script")
  local sawCaseText = false
  settleSafe(game, {
    limit = 4000,
    watch = function()
      local page = Message.isOpen() and Message.currentPage() or ""
      if page:find("POK", 1, true) and page:find("CASE", 1, true) then sawCaseText = true end
    end,
    choice = function() return "b" end,
  })
  d.check(S.flag("FLAG_RECEIVED_POKEBLOCK_CASE"), "the receptionist sets FLAG_RECEIVED_POKEBLOCK_CASE")
  d.check(S.hasItem("ITEM_POKEBLOCK_CASE"), "the POKeBLOCK CASE is in the bag")
  d.check(sawCaseText, "her message mentions the POKeBLOCK CASE")
  d.shot(game, "00_contest_lobby")
  local keep, others = {}, {}
  for _, msg in ipairs(d.vmLogs) do
    if msg:find("Contest", 1, true) then others[msg:match("%(([%w_]+)%)") or msg] = true else keep[#keep + 1] = msg end
  end
  d.vmLogs = keep
  local names = {}
  for k in pairs(others) do names[#names + 1] = k end
  table.sort(names)
  if #names > 0 then d.note("NOTE contest lobby specials owned by the contest unit: " .. table.concat(names, ", ")) end
  for _ = 1, 30 do
    if not S.busy() then break end
    d.note("lobby script still running: " .. S.vmWhere() .. " msg=" .. tostring(Message.isOpen()))
    tapWait(game, "b", 12)
  end
  settleSafe(game, { limit = 600 })

  Pokeblock.clearAll(s)
  Pokeblock.add(s, { color = Pokeblock.COLOR.PINK, sweet = 12, feel = 23 })
  Pokeblock.openCase(s, { caseId = Pokeblock.CASE.FIELD, onClose = function() end })
  waitFor(function() return Case.isOpen() and Case._st.fade == 0 end, 120)
  U.wait(20)
  d.shot(game, "01a_case_ref_pink")
  tapWait(game, "a", 10)
  d.shot(game, "01b_case_ref_actions")
  tapWait(game, "b", 4)
  tapWait(game, "b", 4)
  waitFor(function() return not Case.isOpen() end, 120)
  Pokeblock.clearAll(s)
  Pokeblock.add(s, { color = Pokeblock.COLOR.RED, spicy = 30, sour = 10, feel = 20 })
  Pokeblock.add(s, { color = Pokeblock.COLOR.YELLOW, sour = 25, feel = 15 })
  Pokeblock.add(s, { color = Pokeblock.COLOR.BLUE, dry = 15, feel = 10 })
  d.check(Pokeblock.count(s) == 3, "three POKeBLOCKS in the case")

  local openedFromBag = false
  tapWait(game, "start", 30)
  if topId() ~= "start" then
    d.note("start menu did not open: top=" .. tostring(topId()) .. " busy=" .. tostring(S.busy()) .. " vm=" .. S.vmWhere())
    settleSafe(game, { limit = 600 })
    tapWait(game, "start", 30)
  end
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  if topId() == "start" then
    for i, e in ipairs(StartMenu.ENTRIES or {}) do
      if e.id == "bag" then
        for _ = 1, 10 do
          if StartMenu.cursor == i then break end
          tapWait(game, "down", 6)
        end
        tapWait(game, "a", 60)
      end
    end
  end
  if d.check(topId() == "bag", "START -> BAG opens the bag") then
    for _ = 1, 6 do
      if BagMenu.currentPocket() == "KEY_ITEMS" then break end
      tapWait(game, "right", 20)
    end
    local want = S.item("ITEM_POKEBLOCK_CASE")
    local rows = BagMenu.list()
    local idx
    for i, r in ipairs(rows) do
      if require("src.core.game3.items_data").toNumericId(r.id) == want then idx = i end
    end
    d.check(idx ~= nil, "the POKeBLOCK CASE is listed in KEY ITEMS")
    while idx and BagMenu.cursor < idx do tapWait(game, "down", 6) end
    d.shot(game, "01_bag_case")
    tapWait(game, "a", 10)
    tapWait(game, "a", 60)
    openedFromBag = waitFor(function() return Case.isOpen() end, 120)
    if not openedFromBag then
      d.note("NOTE bag USE on the POKeBLOCK CASE did not open the case (item_use hook in crossfile); opening it the way "
        .. "ItemUseOutOfBattle_PokeblockCase does")
      for _ = 1, 20 do
        if topId() == nil and not Message.isOpen() then break end
        tapWait(game, "b", 20)
      end
    end
  end
  if not openedFromBag then
    Pokeblock.openCase(s, { caseId = Pokeblock.CASE.FIELD, onClose = function() end })
  end
  waitFor(function() return Case.isOpen() and Case._st.fade == 0 end, 120)
  d.check(Case.isOpen(), "the POKeBLOCK CASE screen is open")
  d.check(Case._st.itemsNo == 4, "case list has 3 blocks + STOW CASE (" .. tostring(Case._st.itemsNo) .. ")")
  d.shot(game, "02_case_list")
  tapWait(game, "down", 6)
  d.check(Case.saved.row == 1 and Case._st.shake ~= nil, "down moves the cursor and shakes the case")
  tapWait(game, "up", 20)
  d.check(Case.saved.row == 0, "back on the RED block")
  tapWait(game, "a", 6)
  d.check(Case._st.phase == "actions", "A opens USE/TOSS/CANCEL")
  d.shot(game, "03_case_actions")
  tapWait(game, "a", 4)
  d.check(waitFor(function() return Use.isOpen() end, 120), "USE opens the condition screen")
  waitFor(function() return Use._st.state == "input" end, 200)
  d.check(Use._st.state == "input", "condition screen ready for input")
  d.check(Use._st.nameInfo ~= nil and Use._st.natureText ~= nil, "mon name and nature shown")
  U.wait(30)
  d.shot(game, "04_use_condition")
  tapWait(game, "down", 2)
  waitFor(function() return Use._st.state == "input" end, 120)
  d.check(Use._st.sel == 1, "down moves to CANCEL")
  U.wait(10)
  d.shot(game, "05_use_cancel_row")
  tapWait(game, "up", 2)
  waitFor(function() return Use._st.state == "input" end, 120)
  d.check(Use._st.sel == 0, "up returns to the mon")
  tapWait(game, "a", 6)
  d.check(Use._st.state == "confirm", "A asks whether the mon gets a POKeBLOCK")
  d.shot(game, "06_use_confirm")
  tapWait(game, "a", 4)
  d.check(waitFor(function() return Feed.isOpen() end, 120), "YES opens the feeding scene")
  waitFor(function() return Feed._st.fade == 0 end, 60)
  U.wait(20)
  d.shot(game, "07_feed_anim")
  waitFor(function() return Feed._st.block ~= nil end, 600)
  d.check(Feed._st.block ~= nil, "the case throws the POKeBLOCK")
  U.wait(4)
  d.shot(game, "08_feed_throw")
  waitFor(function() return Feed._st.phase == "message" end, 300)
  waitFor(function() return Feed._st.printer and Feed._st.printer.state == "wait" end, 400)
  d.check(Feed._st.gain == 20, "Lonely nature: gain 20 (happily ate) (" .. tostring(Feed._st.gain) .. ")")
  d.check(Feed._st.printer and Feed._st.printer.state == "wait", "gText_Var1HappilyAteVar2 waits for a press")
  d.shot(game, "09_feed_message")
  tapWait(game, "a", 4)
  d.check(waitFor(function() return Use.isOpen() and Use._st.state == "results_wait" end, 300),
    "back on the condition screen for the results")
  local before = Pokeblock.conditions(mon)
  tapWait(game, "a", 4)
  waitFor(function() return Use._st.state == "results_text" end, 200)
  d.check(Use._st.state == "results_text", "graph animates and the enhancement text shows")
  d.check((mon.contest.cool or 0) == 33 and before[1] == 0, "Coolness 0 -> 33 (30 spicy + liked bonus)")
  d.check((mon.contest.tough or 0) == 10, "Toughness 0 -> 10 (sour, no bonus)")
  d.check((mon.contest.sheen or 0) == 20, "sheen 0 -> 20 (feel)")
  d.check((Use._st.message or ""):find("enhanced", 1, true) ~= nil, "message: " .. tostring(Use._st.message))
  d.shot(game, "10_use_results")
  for _ = 1, 6 do
    if not Use.isOpen() then break end
    tapWait(game, "a", 20)
  end
  d.check(waitFor(function() return Case.isOpen() end, 120), "results close back to the POKeBLOCK CASE")
  waitFor(function() return Case._st.fade == 0 end, 60)
  d.check(Pokeblock.count(s) == 2, "the eaten block is gone (" .. Pokeblock.count(s) .. " left)")
  d.shot(game, "11_case_after_feed")

  tapWait(game, "down", 8)
  tapWait(game, "a", 6)
  tapWait(game, "down", 4)
  tapWait(game, "a", 6)
  waitFor(function() return Case._st.phase == "toss_yesno" end, 200)
  d.check(Case._st.phase == "toss_yesno", "TOSS asks to throw the block away")
  d.shot(game, "12_case_toss")
  tapWait(game, "a", 6)
  waitFor(function() return Case._st.phase == "tossed" and not Case._st.printer:isActive() end, 200)
  tapWait(game, "a", 6)
  d.check(Pokeblock.count(s) == 1 and Pokeblock.get(s, 0).color == Pokeblock.COLOR.YELLOW, "the BLUE block was tossed")

  Pokeblock.add(s, { color = Pokeblock.COLOR.GREEN, bitter = 12, feel = 3 })
  Case._st.phase = "list"
  Case.show(Case._st.opts)
  waitFor(function() return Case._st.fade == 0 end, 60)
  tapWait(game, "up", 8)
  tapWait(game, "up", 8)
  d.check(Case.saved.row == 0 and Case.saved.scroll == 0, "cursor on the first block")
  tapWait(game, "select", 4)
  d.check(Case._st.phase == "swap", "SELECT starts a swap")
  tapWait(game, "down", 4)
  d.shot(game, "13_case_swap")
  tapWait(game, "down", 4)
  tapWait(game, "select", 6)
  d.check(Pokeblock.get(s, 0).color == Pokeblock.COLOR.GREEN and Pokeblock.get(s, 1).color == Pokeblock.COLOR.YELLOW,
    "swap moved YELLOW below GREEN")
  tapWait(game, "b", 4)
  d.check(waitFor(function() return not Case.isOpen() end, 120), "B stows the case")
  for _ = 1, 20 do
    if topId() == nil and not Message.isOpen() then break end
    tapWait(game, "b", 20)
  end

  S.giveItem("ITEM_CHERI_BERRY", 3)
  S.giveItem("ITEM_ORAN_BERRY", 2)
  local berries = {}
  local pocket = require("src.core.game3.items_data").pocketOf(S.item("ITEM_CHERI_BERRY"))
  for _, r in ipairs(Bag.listPocket(s.bag, pocket) or {}) do
    berries[#berries + 1] = require("src.core.game3.items_data").toNumericId(r.id or r.item or r[1])
  end
  local tagFromBag = false
  tapWait(game, "start", 30)
  if topId() == "start" then
    for i, e in ipairs(StartMenu.ENTRIES or {}) do
      if e.id == "bag" then
        for _ = 1, 10 do
          if StartMenu.cursor == i then break end
          tapWait(game, "down", 6)
        end
        tapWait(game, "a", 60)
      end
    end
  end
  if topId() == "bag" then
    for _ = 1, 6 do
      local p = BagMenu.currentPocket()
      if p == "BERRIES" or p == "BERRY_POUCH" then break end
      tapWait(game, "right", 20)
    end
    tapWait(game, "a", 10)
    local acts = table.concat(BagMenu.ACTIONS or {}, ",")
    d.shot(game, "14_bag_berry_actions")
    if acts:find("CHECK_TAG", 1, true) then
      for i, a in ipairs(BagMenu.ACTIONS) do
        if a == "CHECK_TAG" then BagMenu.actionCursor = i end
      end
      tapWait(game, "a", 60)
      tagFromBag = waitFor(function() return Tag.isOpen() end, 120)
    else
      d.note("NOTE the Emerald bag has no CHECK TAG action on berries yet (" .. acts .. "); crossfile bag owner")
    end
    if not tagFromBag then
      for _ = 1, 20 do
        if topId() == nil and not Message.isOpen() then break end
        tapWait(game, "b", 20)
      end
    end
  end
  if not tagFromBag then
    Tag.show({ session = s, list = berries, pos = 0, onClose = function() end })
  end
  waitFor(function() return Tag.isOpen() and Tag._st.fade == 0 end, 120)
  d.check(Tag.isOpen() and Tag.current() == 1, "berry tag shows No.01 CHERI (" .. tostring(Tag.current()) .. ")")
  d.check(Tag._st.text.size ~= nil and Tag._st.text.firm ~= nil, "size and firmness lines printed")
  d.shot(game, "15_berry_tag_cheri")
  tapWait(game, "down", 8)
  U.wait(4)
  d.shot(game, "16_berry_tag_scroll")
  waitFor(function() return Tag._st.phase == "input" end, 60)
  d.check(Tag.current() == 7, "down scrolls to No.07 ORAN (" .. tostring(Tag.current()) .. ")")
  d.shot(game, "17_berry_tag_oran")
  tapWait(game, "b", 4)
  d.check(waitFor(function() return not Tag.isOpen() end, 60), "B closes the berry tag")
  for _ = 1, 20 do
    if topId() == nil and not Message.isOpen() then break end
    tapWait(game, "b", 20)
  end

  local Safari = require("src.core.game3.safari")
  F.goTo(game, "EM_SAFARI_ZONE_SOUTH", 20, 20, "down")
  Safari.enter(s)
  local fx, fy
  for y = 0, 60 do
    for x = 0, 60 do
      if not fx and F.behaviorIs(x, y, "MB_POKEBLOCK_FEEDER") then fx, fy = x, y end
    end
  end
  if not fx then
    F.goTo(game, "EM_SAFARI_ZONE_SOUTHWEST", 20, 20, "down")
    for y = 0, 60 do
      for x = 0, 60 do
        if not fx and F.behaviorIs(x, y, "MB_POKEBLOCK_FEEDER") then fx, fy = x, y end
      end
    end
  end
  if d.check(fx ~= nil, "found a POKeBLOCK feeder metatile (" .. tostring(fx) .. "," .. tostring(fy) .. ")") then
    local placed = false
    for dir, v in pairs({ down = { 0, -1 }, up = { 0, 1 }, left = { 1, 0 }, right = { -1, 0 } }) do
      local px, py = fx + v[1], fy + v[2]
      if not placed and Collision.isWalkable(px, py) then
        F.goTo(game, S.mapNow(), px, py, dir)
        placed = true
      end
    end
    Safari.enter(s)
    d.check(Player.facing and placed, "standing in front of the feeder")
    U.tap(game, "a")
    waitFor(function() return Message.isOpen() or require("src.ui.game3.choice").isOpen() end, 120)
    d.shot(game, "18_feeder_prompt")
    local caseOpened = false
    settleSafe(game, {
      limit = 3000,
      until_ = function() return Case.isOpen() end,
      choice = function() return "yes" end,
    })
    caseOpened = waitFor(function() return Case.isOpen() and Case._st.fade == 0 end, 200)
    d.check(caseOpened and Case._st.caseId == Pokeblock.CASE.FEEDER, "YES opens the case in feeder mode")
    d.shot(game, "19_feeder_case")
    local selId = Case.selected()
    local placedColor = selId and Pokeblock.get(s, selId).color
    tapWait(game, "a", 6)
    d.check(Case._st.phase == "actions" and #Case.ACTIONS[Pokeblock.CASE.FEEDER] == 2, "feeder actions are USE/CANCEL")
    tapWait(game, "a", 6)
    local sawPlaced = false
    settleSafe(game, {
      limit = 3000,
      watch = function()
        local page = Message.isOpen() and Message.currentPage() or ""
        if page:find("placed", 1, true) then
          if not sawPlaced then d.shot(game, "20_feeder_placed") end
          sawPlaced = true
        end
      end,
    })
    d.check(sawPlaced, "SafariZone_Text_PokeblockWasPlaced")
    local fi = Pokeblock.feederInFront(s)
    d.check(fi == 0, "GetPokeblockFeederInFront finds the placed feeder (" .. tostring(fi) .. ")")
    local row = Pokeblock.feeders(s)[1]
    d.check(row.pokeblock.color == placedColor and row.stepCounter == 100, "feeder holds a copy for 100 steps (color "
      .. tostring(row.pokeblock.color) .. "/" .. tostring(placedColor) .. ", steps " .. tostring(row.stepCounter) .. ")")
    d.check(s.safari.activePokeblock ~= nil and s.safari.activePokeblock.color == placedColor,
      "wild nature pick sees the feeder block within range")
    U.tap(game, "a")
    local sawStill = false
    settleSafe(game, {
      limit = 3000,
      watch = function()
        local page = Message.isOpen() and Message.currentPage() or ""
        if page:find("still", 1, true) then sawStill = true end
      end,
    })
    d.check(sawStill, "SafariZone_Text_PokeblockStillHere on the occupied feeder")
    Safari.exit(s)
  end

  F.goTo(game, "EM_MOSSDEEP_CITY_HOUSE1", 3, 6, "up", { keepScripts = false })
  local bb = S.objectByScript("MossdeepCity_House1_EventScript_BlackBelt")
  if d.check(bb ~= nil, "the Black Belt is in Mossdeep House 1") then
    local pages = {}
    S.talkTo(game, bb)
    settleSafe(game, {
      limit = 3000,
      watch = function()
        local page = Message.isOpen() and Message.currentPage() or ""
        if page ~= "" and pages[#pages] ~= page then pages[#pages + 1] = page end
      end,
    })
    local all = table.concat(pages, " / ")
    d.check(all:find(Pokeblock.colorName(Pokeblock.COLOR.RED), 1, true) ~= nil,
      "GetPokeblockNameByMonNature: a Lonely mon likes RED POKeBLOCKS (" .. all:gsub("\n", " ") .. ")")
  end

  s.berryPowder = 1000
  F.flags().set("FLAG_RECEIVED_POWDER_JAR", true)
  F.goTo(game, "EM_SLATEPORT_CITY", 10, 37, "right")
  local clerk = S.objectByScript("SlateportCity_EventScript_BerryPowderClerk")
  if d.check(clerk ~= nil, "the berry powder clerk is in Slateport") then
    S.talkTo(game, clerk)
    local sawBox = false
    local yesNo = 0
    settleSafe(game, {
      limit = 4000,
      watch = function()
        if require("src.ui.game3.berry_powder_box").visible then
          if not sawBox then d.shot(game, "21_powder_vendor") end
          sawBox = true
        end
      end,
      choice = function(ch)
        if ch and ch.options and #ch.options > 2 then return 1 end
        yesNo = yesNo + 1
        return yesNo == 1 and "yes" or "no"
      end,
    })
    d.check(sawBox, "DisplayBerryPowderVendorMenu shows the powder box")
    d.check((s.berryPowder or 0) < 1000 and (s.berryPowder or 0) > 0, "TakeBerryPowder spent powder once (" .. tostring(s.berryPowder) .. ")")
    d.check(not require("src.ui.game3.berry_powder_box").visible, "RemoveBerryPowderVendorMenu hides it")
  end

  d.finish()
end
