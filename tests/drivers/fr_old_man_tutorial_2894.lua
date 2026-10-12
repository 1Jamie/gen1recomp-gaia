local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("fr_old_man_tutorial_2894", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/fr_old_man_tutorial_2894")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Battle = require("src.core.game3.battle")
  local Bridge = require("src.core.game3.battle_bridge")
  local Ui = require("src.core.game3.battle.ui")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local BagMenu = require("src.ui.game3.bag_menu")
  local ItemsData = require("src.core.game3.items_data")
  local Message = require("src.ui.game3.message")
  local CatchSeq = require("src.core.game3.battle.catch_seq")
  local Anim = require("src.core.game3.battle.anim")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 4, 8)
  Bag.add(session.bag, 17, 3)
  Bag.add(session.bag, 3, 7)
  S.check(F.goTo(game, "FR_VIRIDIAN_CITY", 20, 10, "down"), "viridian loaded")

  local function pocket_ids(pocket)
    local out = {}
    for _, s in ipairs(session.bag.pockets[pocket] or {}) do
      out[#out + 1] = tostring(ItemsData.toNumericId(s.id))
    end
    return table.concat(out, ",")
  end

  S.check(Bridge.startWild(Runtime._mod, game, { species = 13, level = 5, gender = "M", oldManTutorial = true },
    { oldManTutorial = true, fade = false }) == true, "old man battle started")
  for _ = 1, 600 do
    if Battle.isActive() then break end
    U.wait(1)
  end
  S.check(Battle.isActive(), "old man battle active")

  local seen = {}
  local pockets = {}
  local bagFrames, bagOpenFrame, cmdSeenBeforeBag = 0, nil, false
  for frame = 1, 6000 do
    if not Battle.isActive() then break end
    if Ui._mode == "menu" and Ui._menuIndex == 2 and not seen.cursor then
      seen.cursor = true
      U.wait(8)
      S.check(S.still(game, "2894_01_cursor_on_bag.png"), "cursor on BAG shot")
    end
    if BagMenu.isOpen() and BagMenu.isPokedude() then
      if not bagOpenFrame then
        bagOpenFrame = frame
        S.check(pocket_ids("ITEMS") == "13" and pocket_ids("POKE_BALLS") == "4",
          "old man bag holds POTION and POKe BALL only")
      end
      bagFrames = bagFrames + 1
      local p = BagMenu.currentPocket()
      if pockets[#pockets] ~= p then pockets[#pockets + 1] = p end
      if p == "ITEMS" and bagFrames == 60 then
        S.check(S.still(game, "2894_02_bag_items_pocket.png"), "items pocket shot")
      elseif p == "KEY_ITEMS" and not seen.key then
        seen.key = true
        U.wait(40)
        S.check(S.still(game, "2894_03_bag_key_items_pocket.png"), "key items pocket shot")
      elseif p == "POKE_BALLS" and not seen.balls and BagMenu.mode == "list" then
        seen.balls = true
        U.wait(40)
        S.check(S.still(game, "2894_04_bag_poke_balls_pocket.png"), "poke balls pocket shot")
      elseif BagMenu.mode == "action" and not seen.action then
        seen.action = true
        U.wait(20)
        S.check(S.still(game, "2894_05_poke_ball_use_cancel.png"), "USE CANCEL shot")
      end
    elseif bagOpenFrame and not seen.back and not BagMenu.isOpen() then
      seen.back = true
      S.check(pocket_ids("ITEMS") == "17" and pocket_ids("POKE_BALLS") == "3", "player bag restored after old man bag")
    end
    local ball = CatchSeq._ball
    local tr = Anim.stage().trainer.player
    local bs = Anim.stage().ball
    if ball and ball.trainerThrow and tr.frame == 1 and not seen.windup then
      seen.windup = true
      U.wait(12)
      S.check(bs.visible and bs.x == 60 and bs.y == 91, "ball held at (60,91) during the wind-up")
      S.check(S.still(game, "2893_01_old_man_windup_ball_in_hand.png"), "wind-up shot")
    elseif seen.windup and tr.frame == 3 and not seen.release then
      seen.release = true
      U.wait(4)
      S.check(S.still(game, "2893_02_old_man_throw_follow_through.png"), "throw follow-through shot")
    end
    if seen.release and ball and not ball.released and not ball.trainerThrow and not seen.wobbleText
        and Message.isOpen() and Message.currentPage():find("used", 1, true) then
      seen.wobbleText = true
      S.check(S.still(game, "2893_03_used_text_stays_during_capture.png"), "used text during capture shot")
    end
    if Message.isOpen() and Message.currentPage():find("Gotcha", 1, true) and not seen.gotcha then
      seen.gotcha = true
      S.check(bs.visible, "gotcha text appears while the ball is still on screen")
      U.wait(30)
      S.check(S.still(game, "2896_01_old_man_gotcha_with_ball.png"), "gotcha with ball shot")
    end
    if Battle._phase == "catching" and not bagOpenFrame then cmdSeenBeforeBag = true end
    if Message.isOpen() and not Message.isTyping() and Message.isWaiting and Message.isWaiting() and frame % 30 == 0 then
      U.tap(game, "a")
    end
    U.wait(1)
  end
  S.check(seen.cursor, "cursor moved to BAG")
  S.check(bagOpenFrame ~= nil and not cmdSeenBeforeBag, "bag opened before the ball was thrown")
  S.check(table.concat(pockets, ">") == "ITEMS>KEY_ITEMS>POKE_BALLS", "pocket order " .. table.concat(pockets, ">"))
  S.check(seen.action, "USE CANCEL context menu shown")
  S.check(seen.back, "returned to battle")
  S.check(seen.windup and seen.release, "old man back pic plays the throw anim")
  S.check(seen.wobbleText, "used text stays up during the capture")
  S.check(seen.gotcha, "gotcha text seen")
  S.check(not Battle.isActive(), "battle ended")
  S.finish()
end
