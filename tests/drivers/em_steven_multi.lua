local U = require("tests.drivers.util")
local L = require("tests.drivers.em_battle_loop")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_steven_multi"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_steven_multi failures=" .. failures)
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
  local Choice = require("src.ui.game3.choice")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Battle = require("src.core.game3.battle")
  local Kinds = require("src.core.game3.battle.kinds")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local Natives = require("src.core.game3.scripting.natives")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not result(session ~= nil, "field session exists") then return finish() end
  Encounters.onStep = function() return nil end
  Natives.ensureBound(session)
  result(Natives.handlerFor("DoSpecialTrainerBattle") ~= nil, "DoSpecialTrainerBattle is bound on Emerald")

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_SWAMPERT, 60, "")
  Party.giveMon(session, C.species.byName.SPECIES_ZIGZAGOON, 5, "")
  Party.giveMon(session, C.species.byName.SPECIES_BLAZIKEN, 60, "")
  Party.giveMon(session, C.species.byName.SPECIES_SCEPTILE, 60, "")
  local zigPersonality = session.party[2].personality
  local swampertExp = session.party[1].exp

  Rse.setVar("VAR_MOSSDEEP_CITY_STATE", 2)
  Rse.setVar("VAR_MOSSDEEP_SPACE_CENTER_STATE", 2)
  Rse.setFlag("FLAG_HIDE_MOSSDEEP_CITY_SPACE_CENTER_2F_STEVEN", false)
  Rse.setFlag("FLAG_HIDE_MOSSDEEP_CITY_SPACE_CENTER_2F_TEAM_MAGMA", false)
  Rse.setFlag("FLAG_INTERACTED_WITH_STEVEN_SPACE_CENTER", false)
  local ok, err = pcall(function()
    Map.load(nil, game, "EM_MOSSDEEP_CITY_SPACE_CENTER_2F", { x = 2, y = 8, facing = "left" })
  end)
  if not result(ok, "Space Center 2F loads " .. tostring(err or "")) then return finish() end
  U.wait(40)
  U.still(game, DIR .. "/01_space_center.png")

  local function pump_field(limit, stop)
    for _ = 1, limit do
      if stop() then return true end
      if Choice.isOpen and Choice.isOpen() then
        U.wait(4)
        U.tap(game, "a")
      elseif Message.isOpen and Message.isOpen() then
        U.tap(game, "a")
      end
      U.wait(2)
    end
    return stop()
  end

  U.tap(game, "a")
  pump_field(1200, function() return not (Space.vm and Space.vm:isRunning()) end)
  result(Rse.flag("FLAG_INTERACTED_WITH_STEVEN_SPACE_CENTER"), "first talk runs Steven's intro scene")
  U.wait(20)
  local sawParty = false
  U.tap(game, "a")
  for _ = 1, 1500 do
    if PartyMenu.isOpen and PartyMenu.isOpen() then sawParty = true break end
    if Choice.isOpen and Choice.isOpen() then
      U.wait(4)
      U.tap(game, "a")
    elseif Message.isOpen and Message.isOpen() then
      U.tap(game, "a")
    end
    U.wait(2)
  end
  if not result(sawParty, "YES opens ChooseHalfPartyForBattle") then return finish() end
  U.wait(20)
  U.still(game, DIR .. "/02_choose_half_party.png")
  for _, slot in ipairs({ 1, 3, 4 }) do
    PartyMenu.enterChosenMon(slot)
    U.wait(6)
  end
  U.still(game, DIR .. "/03_three_entered.png")
  PartyMenu.confirmChosenMons()

  for _ = 1, 1500 do
    if Battle.isActive() then break end
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(2)
  end
  if not result(Battle.isActive(), "DoSpecialTrainerBattle SPECIAL_BATTLE_STEVEN starts the battle") then
    return finish()
  end
  local st = Battle._st
  result(st.double and st.kinds.partner and st.kinds.twoOpponents, "double, partner and two opponents")
  result(st.playerHalf == 3, "player brings the three chosen mons (" .. tostring(st.playerHalf) .. ")")
  result(#st.playerParty == 6, "battle party is 3 chosen + 3 Steven")
  result(st.battlers[2] and st.battlers[2].mon.species == C.species.byName.SPECIES_METANG,
    "Steven leads with Metang on the right")
  result(st.player.mon.species == C.species.byName.SPECIES_SWAMPERT, "player leads with the first chosen mon")
  result(Kinds.controllerOf(st, 2) == "aiPartner", "battler 2 runs the partner controller")
  result(st.trainerId == C.trainers.byName.TRAINER_MAXIE_MOSSDEEP and st.trainerIdB == C.trainers.byName.TRAINER_TABITHA_MOSSDEEP,
    "opponents are Maxie and Tabitha")
  result(st.partner and st.partner.backPic == 7, "Steven back pic (TRAINER_BACK_PIC_STEVEN)")

  local shots = {}
  local done, why = L.run(game, {
    turnCap = 40,
    onFrame = function(s, phase)
      local stage = Anim.stage()
      if phase == "intro" and not shots.intro and stage.trainer.player.visible and (stage.trainer.player.ox or 0) == 0 then
        shots.intro = true
        U.still(game, DIR .. "/04_intro_steven_and_player.png")
      end
      if phase == "command" and not shots.cmd and Ui._mode == "menu" then
        shots.cmd = true
        U.wait(10)
        U.still(game, DIR .. "/05_command.png")
      end
      if phase == "animating" and not shots.anim and s.turn >= 2 then
        shots.anim = true
        U.wait(12)
        U.still(game, DIR .. "/06_mid_turn.png")
      end
    end,
  })
  result(done, "battle finished " .. tostring(why or ""))
  local sentOut = L.logIndex("sent out METANG") or L.logIndex("sent\nout METANG")
  result(sentOut ~= nil, "intro uses sText_InGamePartnerSentOutZGoN (STEVEN sent out METANG)")
  result(L.logHas("want to battle"), "intro uses sText_TwoTrainersWantToBattle")
  result(st.result == "win", "the multi battle is won (" .. tostring(st.result) .. ")")
  local partnerMoves = 0
  for _, t in ipairs(Ui.log and Ui.log() or {}) do
    local s = tostring(t):gsub("\n", " ")
    if s:find("METANG used", 1, true) or s:find("SKARMORY used", 1, true) or s:find("AGGRON used", 1, true) then
      partnerMoves = partnerMoves + 1
    end
  end
  result(partnerMoves > 0, "Steven's mons act on their own (" .. partnerMoves .. " moves)")

  local restored = pump_field(3000, function()
    return not (Space.vm and Space.vm:isRunning()) and #session.party == 4
  end)
  result(restored, "LoadPlayerParty restores the four-mon party")
  local stevenLeft = false
  for _, m in ipairs(session.party) do if m.stevenPartner then stevenLeft = true end end
  result(not stevenLeft, "none of Steven's mons stay in the party")
  result(session.party[2].personality == zigPersonality, "the unchosen Zigzagoon keeps its slot")
  result((session.party[1].exp or 0) > (swampertExp or 0), "the chosen Swampert keeps the exp it earned (frontier_saveparty)")
  result(Rse.var("VAR_MOSSDEEP_SPACE_CENTER_STATE") == 3, "defeat script sets VAR_MOSSDEEP_SPACE_CENTER_STATE = 3")
  result(Rse.flag("FLAG_DEFEATED_MAGMA_SPACE_CENTER"), "FLAG_DEFEATED_MAGMA_SPACE_CENTER set")
  U.wait(30)
  U.still(game, DIR .. "/07_after.png")
  return finish()
end
