local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_wally_tutorial"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_wally_tutorial failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

return function(game)
  io.stdout:setvbuf("line")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Party = require("src.core.game3.party")
  local Space = require("src.core.game3.scripting.space")
  local Rse = require("src.core.game3.rse.init")
  local Encounters = require("src.core.game3.encounters")
  local Message = require("src.ui.game3.message")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Anim = require("src.core.game3.battle.anim")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not result(session ~= nil, "field session exists") then return finish() end
  Encounters.onStep = function() return nil end

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_TORCHIC, 12, "")
  local starterPersonality = session.party[1].personality

  -- pokeemerald/data/maps/PetalburgCity_Gym/scripts.inc:181
  Rse.setFlag("FLAG_HIDE_PETALBURG_CITY_WALLYS_MOM", true)
  Rse.setVar("VAR_PETALBURG_GYM_STATE", 1)
  Rse.setVar("VAR_PETALBURG_CITY_STATE", 2)
  Rse.setFlag("FLAG_HIDE_PETALBURG_CITY_WALLY", false)
  local ok, err = pcall(function() Map.load(nil, game, "EM_PETALBURG_CITY", { x = 15, y = 8, facing = "down" }) end)
  if not result(ok, "Petalburg City loads " .. tostring(err or "")) then return finish() end

  local sawIntro = false
  for _ = 1, 1500 do
    if Battle.isActive() then break end
    if Message.isOpen and Message.isOpen() then
      if not sawIntro then
        sawIntro = true
        U.wait(20)
        U.still(game, DIR .. "/01_watch_me_catch.png")
      end
      U.tap(game, "a")
    end
    U.wait(2)
  end
  result(sawIntro, "Wally says he will catch a POKEMON (Route102_Text_WatchMeCatchPokemon)")
  if not result(Battle.isActive(), "StartWallyTutorialBattle starts the battle") then return finish() end
  local st = Battle._st
  result(st.kinds and st.kinds.tutorial == "wally", "battle kind is the Wally tutorial")
  result(st.enemy.mon.species == C.species.byName.SPECIES_RALTS and st.enemy.mon.level == 5, "wild Ralts lv5")
  result(st.player.mon.species == C.species.byName.SPECIES_ZIGZAGOON and st.player.mon.level == 7,
    "Wally battles with the lv7 Zigzagoon (LoadWallyZigzagoon)")
  result(st.backPicOverride == 6, "Wally back pic (TRAINER_BACK_PIC_WALLY)")

  local shots, menus, pressedDuringMenu, seen = {}, 0, 0, {}
  for _ = 1, 30000 do
    if not Battle.isActive() then break end
    local phase = Battle._phase
    if phase == "intro" and not shots.intro and Anim.stage().trainer.player.visible then
      shots.intro = true
      U.wait(30)
      U.still(game, DIR .. "/02_intro_wally_back.png")
    end
    if phase == "command" and Ui._mode == "menu" and Ui._wally and not seen[st.turn] then
      seen[st.turn] = true
      menus = menus + 1
      if menus == 1 then
        U.wait(10)
        U.still(game, DIR .. "/03_what_will_wally_do.png")
      end
    end
    if phase == "command" and Ui._mode == "moves" and not shots.moves then
      shots.moves = true
      U.wait(10)
      U.still(game, DIR .. "/04_wally_move_menu.png")
    end
    if phase == "command" and Ui._mode == "menu" and Ui._menuIndex == 2 and not shots.bag then
      shots.bag = true
      U.still(game, DIR .. "/06_cursor_on_bag.png")
    end
    if phase == "switching" and not shots.slide and Anim.stage().trainer.player.visible then
      shots.slide = true
      U.wait(50)
      U.still(game, DIR .. "/05_wally_slides_back.png")
    end
    if phase == "catching" and not shots.catch then
      shots.catch = true
      U.wait(90)
      U.still(game, DIR .. "/07_ball_shakes.png")
    end
    if phase == "command" and Ui._wally then
      pressedDuringMenu = pressedDuringMenu + 1
      if pressedDuringMenu % 7 == 0 then U.tap(game, "b") end
      U.wait(1)
    elseif Ui.dialogPending and Ui.dialogPending() then
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end
  result(not Battle.isActive(), "the tutorial battle ends by itself")
  result(st.result == "catch", "Wally catches Ralts (" .. tostring(st.result) .. ")")
  result(st.wallyState == 4, "Wally took FIGHT, FIGHT, the return and the BAG turns (" .. tostring(st.wallyState) .. ")")
  result(menus == 4, "the WALLY command menu ran every turn without player input (" .. menus .. ")")
  local Log = Ui.log and Ui.log() or {}
  local function has(needle)
    for _, t in ipairs(Log) do
      if tostring(t):gsub("\n", " "):find(needle, 1, true) then return true end
    end
    return false
  end
  result(has("WALLY used"), "STRINGID_WALLYUSEDITEM shown")
  result(has("RALTS was caught"), "STRINGID_GOTCHAPKMNCAUGHTWALLY shown")
  result(has("right?"), "STRINGID_YOUTHROWABALLNOWRIGHT shown")

  local afterGym = false
  for _ = 1, 3000 do
    if Map.current == "EM_PETALBURG_CITY_GYM" then afterGym = true break end
    if Message.isOpen and Message.isOpen() then
      if not shots.didIt then
        shots.didIt = true
        U.wait(20)
        U.still(game, DIR .. "/08_i_did_it.png")
      end
      U.tap(game, "a")
    end
    U.wait(2)
  end
  result(afterGym, "the script warps back into the gym (" .. tostring(Map.current) .. ")")
  result(Rse.var("VAR_PETALBURG_CITY_STATE") == 3, "VAR_PETALBURG_CITY_STATE = 3")
  result(#session.party == 1 and session.party[1].species == C.species.byName.SPECIES_TORCHIC
    and session.party[1].personality == starterPersonality, "LoadPlayerParty restores the player's own party")
  U.wait(60)
  U.still(game, DIR .. "/09_back_in_gym.png")
  if Space.vm and Space.vm:isRunning() then
    for _ = 1, 300 do
      if not Space.vm:isRunning() then break end
      if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
      U.wait(2)
    end
  end
  return finish()
end
