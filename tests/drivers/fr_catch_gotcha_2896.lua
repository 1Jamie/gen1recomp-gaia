local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("fr_catch_gotcha_2896", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/fr_catch_gotcha_2896")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Battle = require("src.core.game3.battle")
  local Bridge = require("src.core.game3.battle_bridge")
  local Ui = require("src.core.game3.battle.ui")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local CatchSeq = require("src.core.game3.battle.catch_seq")
  local Anim = require("src.core.game3.battle.anim")
  local session = Runtime.getSession()
  local version = session.version
  local C = require("src.core.game3.constants").of(version)
  local master = C:require("items", "ITEM_MASTER_BALL")
  local target = C:require("species", version == "emerald" and "SPECIES_WURMPLE" or "SPECIES_PIDGEY")
  session.party = {}
  Party.giveMon(session, C:require("species", version == "emerald" and "SPECIES_TREECKO" or "SPECIES_CHARMANDER"), 12)
  Bag.add(session.bag, master, 1)
  S.check(F.goTo(game, version == "emerald" and "EM_ROUTE101" or "FR_ROUTE_1", 10, 10, "down"), "route loaded")
  S.check(Bridge.startWild(Runtime._mod, game, { species = target, level = 3 }, { fade = false }) == true,
    "wild battle started")
  for _ = 1, 600 do
    if Battle.isActive() then break end
    U.wait(1)
  end

  local seen = {}
  local thrown = false
  for frame = 1, 9000 do
    if not Battle.isActive() then break end
    local bs = Anim.stage().ball
    local ball = CatchSeq._ball
    if Battle._phase == "command" and Ui._mode == "menu" and not thrown then
      thrown = true
      Ui._pendingCommand = { kind = "bag", itemId = master, user = "player" }
      Ui._mode = "none"
    end
    local page = Message.isOpen() and Message.currentPage() or ""
    if ball and ball.data and ball.data[0] ~= 34 and not ball.released and not seen.usedDuringThrow
        and page:find("used", 1, true) then
      seen.usedDuringThrow = not Ui.dialogPending()
      U.wait(6)
      S.check(S.still(game, "2896_01_used_text_stays_during_throw.png"), "used text during throw shot")
    end
    if page:find("Gotcha", 1, true) and not seen.gotcha then
      seen.gotcha = true
      seen.ballAtGotcha = bs.visible
      seen.releasedAtGotcha = ball and ball.released and not ball.finished
      U.wait(40)
      seen.stayDuringFanfare = Message._stay == true
      U.tap(game, "a")
      U.wait(2)
      seen.aIgnored = Message.isOpen() and Message.currentPage():find("Gotcha", 1, true) ~= nil
      S.check(S.still(game, "2896_02_gotcha_with_ball_during_fanfare.png"), "gotcha during fanfare shot")
    elseif seen.gotcha and not seen.prompt and page:find("Gotcha", 1, true) and Message._stay == false
        and Message.isWaiting() then
      seen.prompt = true
      U.wait(20)
      S.check(S.still(game, "2896_03_gotcha_prompt_after_fanfare.png"), "gotcha prompt shot")
      U.tap(game, "a")
    elseif Choice.isOpen and Choice.isOpen() then
      U.tap(game, "b")
      U.wait(10)
    elseif Message.isOpen() and Message.isWaiting() and not page:find("Gotcha", 1, true) and frame % 20 == 0 then
      U.tap(game, "a")
    elseif Battle._phase == "pokedex_reg" and frame % 20 == 0 then
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end
  S.check(seen.usedDuringThrow, "used text stays without an A prompt while the ball flies")
  S.check(seen.gotcha and seen.ballAtGotcha and seen.releasedAtGotcha,
    "gotcha prints when MUS_CAUGHT_INTRO starts, ball still on screen")
  S.check(seen.stayDuringFanfare and seen.aIgnored, "A cannot skip the gotcha text during the fanfare")
  S.check(seen.prompt, "prompt arrow appears after the fanfare")
  S.check(not Battle.isActive(), "battle ended")
  S.finish()
end
