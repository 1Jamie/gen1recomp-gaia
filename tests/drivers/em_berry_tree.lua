local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("em_berry_tree")

return function(game)
  if not F.boot(game) then return F.finish() end
  F.givePartyAndRepel()
  local Objects = require("src.core.game3.objects")
  local BerryTrees = require("src.core.game3.rse.berry_trees")
  local Rtc = require("src.core.game3.rtc")
  local TimeEvents = require("src.core.game3.time_events")
  local Runtime = require("src.core.game3.runtime")
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Bag = require("src.core.game3.bag")
  local Rse = require("src.core.game3.rse.init")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()

  Rtc.setFixed("2005-06-01T09:30:00")
  TimeEvents.init(session)
  F.check(F.flags().get("FLAG_SYS_CLOCK_SET"), "clock set so time-based events run")

  local planted = 0
  for i = 0, BerryTrees.COUNT - 1 do
    local t = BerryTrees.peek(session, i)
    if t and t.stage == BerryTrees.STAGE_BERRIES then planted = planted + 1 end
  end
  F.check(planted >= 8, "new game plants the fixed berry trees (" .. planted .. ")")

  F.check(F.goTo(game, "EM_ROUTE104", 10, 10, "down"), "Route 104 loads")
  local tree
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    local t = eo and eo.berryTree and BerryTrees.peek(session, eo.berryTree.id)
    if t and t.stage == BerryTrees.STAGE_BERRIES and not tree then
      local bx, by = eo.cellX, eo.cellY + 1
      if Collision.isWalkable(bx, by) then tree = eo end
    end
  end
  if not F.check(tree ~= nil, "found a fruiting berry tree with a walkable cell below") then return F.finish() end
  local id = tree.berryTree.id
  local lid = tree.localId
  F.goTo(game, "EM_ROUTE104", tree.cellX, tree.cellY + 1, "up")
  tree = Objects.find(lid)
  U.wait(4)
  F.check(tree.berryTree.visible and tree.berryTree.tree ~= nil, "berry tree draws its berry-stage sprite")
  F.check(tree.invisible == true, "the tree object hides its OW sprite (drawn from the berry tree sheet)")
  F.shot(game, "01_tree_with_berries.png", true)

  local function waitPrompt(frames)
    for _ = 1, frames or 300 do
      if Message.isOpen and Message.isOpen() then return true end
      if not (Space.vm and Space.vm:isRunning()) then return false end
      U.wait(1)
    end
    return false
  end

  local function talkThrough(taps)
    for _ = 1, taps or 40 do
      U.tap(game, "a")
      U.wait(6)
      if not (Space.vm and Space.vm:isRunning()) then return true end
    end
    return not (Space.vm and Space.vm:isRunning())
  end

  local berryItem = BerryTrees.berryToItem(BerryTrees.peek(session, id).berry)
  local before = Bag.get(session.bag, berryItem)
  U.tap(game, "a")
  waitPrompt()
  F.check(Space.vm:isRunning(), "A on the tree runs BerryTreeScript")
  F.shot(game, "02_want_to_pick.png", true)
  talkThrough(60)
  F.settle(game)
  local after = Bag.get(session.bag, berryItem)
  F.check(after > before, "picking adds berries to the bag (" .. before .. " -> " .. after .. ")")
  F.check(BerryTrees.peek(session, id).stage == 0, "the picked tree is removed to soft soil")
  U.wait(4)
  F.check(not tree.berryTree.visible, "empty soil draws no tree")

  Bag.add(session.bag, C:require("items", "ITEM_CHERI_BERRY"), 3)
  Bag.add(session.bag, C:require("items", "ITEM_WAILMER_PAIL"), 1)
  local BagMenu = require("src.ui.game3.bag_menu")
  local bagShown = false
  U.tap(game, "a")
  waitPrompt()
  for _ = 1, 600 do
    if BagMenu.open and BagMenu._location == "berry_tree" then
      if not bagShown then
        bagShown = true
        U.wait(30)
        F.shot(game, "02b_choose_berry.png", true)
      end
      U.tap(game, "a")
      U.wait(4)
    elseif not Space.vm:isRunning() then
      break
    else
      U.tap(game, "a")
      U.wait(4)
    end
  end
  F.check(bagShown, "Bag_ChooseBerry opens the bag on the BERRIES pocket")
  F.settle(game)
  local t = BerryTrees.peek(session, id)
  F.check(t and t.stage == BerryTrees.STAGE_PLANTED and t.berry == 1, "a Cheri berry is planted (stage 1)")
  U.wait(4)
  F.shot(game, "03_planted.png", true)

  U.tap(game, "a")
  waitPrompt()
  local watered = false
  for _ = 1, 80 do
    U.tap(game, "a")
    U.wait(6)
    if Player.watering then watered = true end
    if not (Space.vm and Space.vm:isRunning()) then break end
  end
  F.settle(game)
  F.check(watered, "the Wailmer Pail watering anim plays")
  F.check(BerryTrees.peek(session, id).watered1, "watering marks stage 1 watered")

  local stages = {}
  for stage = 2, 5 do
    Rtc.advance(3 * 60)
    TimeEvents.run(session)
    U.wait(2)
    local sparkled = false
    for _ = 1, 140 do
      if tree.berryTree.func == "sparkle" then sparkled = true end
      if sparkled and tree.berryTree.func == "normal" then break end
      U.wait(1)
    end
    stages[#stages + 1] = BerryTrees.peek(session, id).stage
    F.check(BerryTrees.peek(session, id).stage == stage, "three hours later the tree reaches stage " .. stage)
    F.check(sparkled, "stage " .. stage .. " growth sparkles")
    F.shot(game, string.format("%02d_stage_%d.png", 2 + stage, stage), true)
  end
  F.check(BerryTrees.peek(session, id).berryYield >= 2, "a watered Cheri tree yields berries ("
    .. tostring(BerryTrees.peek(session, id).berryYield) .. ")")
  F.finish()
end
