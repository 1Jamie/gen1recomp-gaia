-- Tests for Game 3 Old Man catching tutorial battle (pokefirered special StartOldManTutorialBattle)
require("tests.game3_cache").mountOrSkip("game3_old_man_tutorial_battle_test")
require("tests.fixture_data.game3_items").install()
local function check(cond, msg)
  if not cond then error(msg or "check failed", 2) end
  print("[ok] " .. tostring(msg or "check passed"))
end

local function eq(a, b, msg)
  if a ~= b then
    error(string.format("%s: expected %s, got %s", msg or "eq failed", tostring(b), tostring(a)), 2)
  end
  print("[ok] " .. tostring(msg or "eq passed"))
end

print("[test] 1. TrainerPic.back supports back pic 5 (Old Man)")
local TrainerPic = require("src.core.game3.trainer_pic")
TrainerPic._back[0] = { image = "red", w = 64, h = 320 }
TrainerPic._back[5] = { image = "old_man", w = 64, h = 256, frames = 4 }
local oldManPic = TrainerPic.back(5)
check(oldManPic ~= nil and oldManPic.image == "old_man", "TrainerPic.back(5) returns Old Man back pic entry")
local clampedPic = TrainerPic.back(99)
check(clampedPic ~= nil and clampedPic.image == "red", "TrainerPic.back(99) clamps to index 0")

print("[test] 2. Intro sequence configures Old Man back sprite and omits player mon sendout")
local Battle = require("src.core.game3.battle.init")
local IntroSeq = require("src.core.game3.battle.intro_seq")
local Ui = require("src.core.game3.battle.ui")
local CatchSeq = require("src.core.game3.battle.catch_seq")
local Catching = require("src.core.game3.battle.catching")
local Anim = require("src.core.game3.battle.anim")

local foe = {
  species = 13, -- WEEDLE
  name = "WEEDLE",
  level = 5,
  gender = "M",
  oldManTutorial = true,
}

if Battle.isActive() then Battle.abort("win") end
local ok = Battle.start({
  wild = true,
  headless = true,
  foe = foe,
  oldManTutorial = true,
  playerParty = {
    { species = 1, level = 5, hp = 20, maxHp = 20, moves = { 33, 45 }, pp = { 35, 20 }, maxPp = { 35, 20 } }
  }
})
check(ok, "battle started")
local st = Battle.getState()
eq(st.oldManTutorial, true, "st.oldManTutorial is true")

IntroSeq.begin(st, { playerGender = 0 })

local stage = Anim.stage()
eq(stage.trainer.player.gender, 5, "player trainer back sprite gender set to 5 (OLD MAN)")

local hasSendout = false
local hasPlayerHealthbox = false
for _, step in ipairs(IntroSeq._steps or {}) do
  if step.kind == "player_throw" then hasSendout = true end
  if step.kind == "healthbox" and step.data and step.data.side == "player" then
    hasPlayerHealthbox = true
  end
end
check(not hasSendout, "player mon sendout / throw step omitted")
check(not hasPlayerHealthbox, "player healthbox omitted")

print("[test] 3. Action selection UI: prompt text and automated input")
-- Test non-headless step timing
local Bag = require("src.core.game3.bag")
local BagMenu = require("src.ui.game3.bag_menu")
local Fade = require("src.ui.game3.fade")
local Stack = require("src.ui.game3.stack")
local prevPush, prevPop = Stack.push, Stack.pop
Stack.push = function() end
Stack.pop = function() end
Fade.clear()
Ui.reset({ headless = false })
Ui._session = { name = "RED", bag = Bag.new(), party = {}, modData = {} }
Ui.bindState(st)
Ui.openMenu()
eq(Ui._menuIndex, 1, "menu starts on FIGHT (index 1)")

-- 63 ticks on FIGHT
for _ = 1, 63 do
  Ui.tick()
end
eq(Ui._menuIndex, 1, "still on FIGHT after 63 ticks")

-- 64th tick moves to BAG
Ui.tick()
eq(Ui._menuIndex, 2, "moves to BAG (index 2) on 64th tick")

-- 63 ticks on BAG
for _ = 1, 63 do
  Ui.tick()
end
check(Ui.takeCommand() == nil, "no command produced before 64 ticks on BAG")

Ui.tick()
check(Ui.takeCommand() == nil and Fade.isActive(), "BAG fades the battle to black (battle_controller_oak_old_man.c:1876)")
for _ = 1, 16 do
  Fade.tick(1 / 60)
  Ui.tick()
end
check(BagMenu.isOpen() and BagMenu.isPokedude(), "old man bag opens after the fade (item_menu.c:2098)")
local NO = { wasPressed = function() return false end, isDown = function() return false end }
local cmd
for _ = 1, 900 do
  BagMenu.handleInput(NO)
  cmd = Ui.takeCommand()
  if cmd then break end
end
check(cmd ~= nil, "command emitted when the scripted bag closes (item_menu.c:2133)")
eq(cmd.kind, "bag", "command is bag")
eq(cmd.itemId, 4, "itemId is Poké Ball (4)")
Stack.push, Stack.pop = prevPush, prevPop

-- Input lock test
Ui.openMenu()
local fakeInput = { wasPressed = function() return true end }
local handled = Ui.handleInput(fakeInput)
eq(handled, true, "player gamepad input is consumed/locked during tutorial")

print("[test] 4. Catch mechanics and messaging for Old Man tutorial")
local session = {
  name = "RED",
  party = { { species = 1, level = 5, hp = 20, maxHp = 20 } },
  box = { {}, {} },
  bag = {}, -- empty bag
  pokedex = {},
}

-- tryCatch always succeeds in tutorial
local caught, shakes = Catching.tryCatch(4, st.enemy, st, session, function() return 999999 end)
eq(caught, true, "Catching.tryCatch succeeds")
eq(shakes, 4, "Catching.tryCatch yields 4 shakes")

-- CatchSeq messages
local msgs = {}
CatchSeq.begin(st, 4, true, 4, {
  headless = true,
  session = session,
  pushMsg = function(t) msgs[#msgs + 1] = t end,
})

check(#msgs >= 2, "messages were emitted")
eq(msgs[1], "The old man used\nPOKé BALL!", "throw msg is sText_OldManUsedItem")
eq(msgs[2], "Gotcha!\nWEEDLE was caught!", "catch msg is 'Gotcha! WEEDLE was caught!'")

-- Weedle not added to player party or dex
eq(#session.party, 1, "player party unchanged (weedle not added)")
check(session.pokedex[13] == nil, "pokedex unchanged")

-- Non-headless post-catch flow must skip nickname prompt
Battle._headless = false
Battle.startPostCatchFlow(nil)
eq(Battle._phase, "ending", "startPostCatchFlow goes straight to ending phase (no nickname prompt)")
eq(Battle._pendingEnd, "catch", "pendingEnd is catch")

print("[test] 5. Full battle headless execution runs to catch completion")
if Battle.isActive() then Battle.abort("win") end
local ok2 = Battle.start({
  wild = true,
  headless = true,
  foe = foe,
  oldManTutorial = true,
  playerParty = {
    { species = 1, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 }, maxPp = { 35 } }
  }
})
check(ok2, "second battle started")
local res = Battle.runToEnd()
eq(res, "catch", "battle concluded with catch outcome")

print("[PASS] game3 old man tutorial battle tests")
