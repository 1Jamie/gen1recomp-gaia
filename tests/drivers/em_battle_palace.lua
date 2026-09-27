local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local F = require("tests.drivers.em_frontier_f2_util")

return function(game)
  local d = S.new("em_battle_palace", "/tmp/em_battle_palace")
  local check, note = d.check, d.note
  local function shot(name) d.shot(game, name) end
  local function finish() return d.finish() end

  local session = F.boot(game, d)
  if not session then return finish() end
  local Natives = require("src.core.game3.scripting.natives")
  check(Natives.handlerFor("CallBattlePalaceFunction") ~= nil, "CallBattlePalaceFunction bound on Emerald")
  local Util = require("src.core.game3.rse.frontier.util")
  local Battle = require("src.core.game3.battle")
  local BUi = require("src.core.game3.battle.ui")

  -- pokeemerald/include/constants/pokemon.h:139
  local ADAMANT, MODEST, JOLLY, BOLD = 3, 15, 13, 5
  session.party = {
    F.mon(session, "SPECIES_METAGROSS", { "MOVE_METEOR_MASH", "MOVE_EARTHQUAKE", "MOVE_PSYCHIC", "MOVE_BRICK_BREAK" }, ADAMANT),
    F.mon(session, "SPECIES_SALAMENCE", { "MOVE_DRAGON_CLAW", "MOVE_EARTHQUAKE", "MOVE_FLAMETHROWER", "MOVE_AERIAL_ACE" }, JOLLY),
    F.mon(session, "SPECIES_SWAMPERT", { "MOVE_SURF", "MOVE_EARTHQUAKE", "MOVE_ICE_BEAM", "MOVE_BRICK_BREAK" }, MODEST),
    F.mon(session, "SPECIES_LATIOS", { "MOVE_PSYCHIC", "MOVE_DRAGON_CLAW", "MOVE_THUNDERBOLT", "MOVE_ICE_BEAM" }, BOLD),
  }
  local originalSpecies = {}
  for i, m in ipairs(session.party) do originalSpecies[i] = m.species end

  if not check(F.teleport(game, d, "EM_BATTLE_FRONTIER_OUTSIDE_EAST", 45, 58, "up"), "Battle Frontier east loads") then
    return finish()
  end
  S.travel(game, { "EM_BATTLE_FRONTIER_BATTLE_PALACE_LOBBY" }, { repel = false, settle = { limit = 20000 } })
  if not check(S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_PALACE_LOBBY", "walked into the Battle Palace lobby ("
    .. tostring(S.mapNow()) .. ")") then return finish() end
  U.wait(10)
  shot("01_palace_lobby")

  local f = Util.frontier(session)
  local picker = F.partyPicker(d, game, { 1, 2, 3 }, "02_choose_three")
  local battles, retired = 0, false
  local sawMoveMenu, palaceBattle, flavor = false, false, 0
  local choicesSeen = {}
  local attendant = S.objectByScript("BattleFrontier_BattlePalaceLobby_EventScript_SinglesAttendant")
  if not check(attendant ~= nil, "singles attendant present") then return finish() end
  S.talkTo(game, attendant)
  local shotBattle, shotRoom = false, false
  S.settle(game, {
    limit = 400000,
    until_ = function()
      return retired and S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_PALACE_LOBBY" and not S.busy()
        and tonumber(f.challengeStatus) == 0
    end,
    choice = function(ch)
      local opts = F.optionTexts(ch)
      choicesSeen[#choicesSeen + 1] = table.concat(opts, "/")
      local r = F.pick(ch, "RETIRE")
      if r then
        if not shotRoom then
          shotRoom = true
          shot("05_ready_for_next")
        end
        retired = true
        return r
      end
      return F.yesNo(ch) or "yes"
    end,
    onIdleUi = picker.idle,
    onBattleStart = function(st)
      battles = battles + 1
      palaceBattle = st.facility ~= nil and st.facility.kind == "palace"
      note(string.format("battle %d vs %s foe lv %s facility=%s", battles, tostring(st.trainerName),
        tostring(st.enemy and st.enemy.mon and st.enemy.mon.level), tostring(st.facility and st.facility.kind)))
      if not shotBattle then
        shotBattle = true
        S.pendingBattleShot = "03_palace_battle"
      end
    end,
    onBattleFrame = function(st, phase)
      if BUi._mode == "moves" then sawMoveMenu = true end
      if phase == "facility" and st.facility and st.facility.kind == "palace" then flavor = flavor + 1 end
    end,
    onBattleEnd = function(result, st)
      note("battle " .. battles .. " -> " .. tostring(result) .. " palace choices=" .. tostring(st.facility and st.facility.choices))
      U.wait(20)
      shot("04_after_battle")
    end,
  })
  check(picker.opened >= 1, "ChoosePartyForBattleFrontier opened the party menu for three mons")
  check(picker.saved >= 1, "the challenge saves the game before the corridor")
  check(battles == 1, "one palace battle fought (" .. battles .. ")")
  check(palaceBattle, "the battle runs with the palace facility hooks (battle_tower.c:2071)")
  check(not sawMoveMenu, "the player never picks a move: FIGHT goes straight to the nature choice (battle_controller_player.c:2631)")
  check(retired, "RETIRE offered after the first win")
  check(Util.get2(f.palaceWinStreaks, 0, 0) == 1, "palace win streak is 1 (" .. Util.get2(f.palaceWinStreaks, 0, 0) .. ")")
  check(S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_PALACE_LOBBY", "back in the palace lobby")
  check(tonumber(f.challengeStatus) == 0, "challenge status cleared by palace_save 0")
  local same = #session.party == #originalSpecies
  for i, m in ipairs(session.party) do if m.species ~= originalSpecies[i] then same = false end end
  check(same, "LoadPlayerParty restored the full party in order")
  note("choices: " .. table.concat(choicesSeen, " | "))
  note("flavor frames: " .. flavor)
  shot("06_back_in_lobby")
  note("logs outside f2 scope: " .. F.vmLogsExcept(d, { "CallApprenticeFunction", "SetCameraPanning" }))
  finish()
end
