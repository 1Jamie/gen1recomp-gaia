local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local F = require("tests.drivers.em_frontier_f2_util")

return function(game)
  local d = S.new("em_battle_arena", "/tmp/em_battle_arena")
  local check, note = d.check, d.note
  local function shot(name) d.shot(game, name) end
  local function finish() return d.finish() end

  local session = F.boot(game, d)
  if not session then return finish() end
  local Natives = require("src.core.game3.scripting.natives")
  check(Natives.handlerFor("CallBattleArenaFunction") ~= nil, "CallBattleArenaFunction bound on Emerald")
  local Util = require("src.core.game3.rse.frontier.util")
  local PartyMenu = require("src.ui.game3.party_menu")

  -- pokeemerald/include/constants/pokemon.h:139
  local BOLD, ADAMANT, JOLLY = 5, 3, 13
  session.party = {
    F.mon(session, "SPECIES_SHUCKLE", { "MOVE_TOXIC", "MOVE_WITHDRAW", "MOVE_HARDEN", "MOVE_DEFENSE_CURL" }, BOLD,
      { 252, 0, 6, 0, 0, 252 }),
    F.mon(session, "SPECIES_METAGROSS", { "MOVE_METEOR_MASH", "MOVE_EARTHQUAKE", "MOVE_PSYCHIC", "MOVE_BRICK_BREAK" }, ADAMANT),
    F.mon(session, "SPECIES_SALAMENCE", { "MOVE_DRAGON_CLAW", "MOVE_EARTHQUAKE", "MOVE_FLAMETHROWER", "MOVE_AERIAL_ACE" }, JOLLY),
    F.mon(session, "SPECIES_SWAMPERT", { "MOVE_SURF", "MOVE_EARTHQUAKE", "MOVE_ICE_BEAM", "MOVE_BRICK_BREAK" }, ADAMANT),
  }

  if not check(F.teleport(game, d, "EM_BATTLE_FRONTIER_OUTSIDE_EAST", 39, 31, "up"), "Battle Frontier east loads") then
    return finish()
  end
  S.travel(game, { "EM_BATTLE_FRONTIER_BATTLE_ARENA_LOBBY" }, { repel = false, settle = { limit = 20000 } })
  if not check(S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_ARENA_LOBBY", "walked into the Battle Arena lobby ("
    .. tostring(S.mapNow()) .. ")") then return finish() end
  U.wait(10)
  shot("01_arena_lobby")

  local f = Util.frontier(session)
  local picker = F.partyPicker(d, game, { 1, 2, 3 }, "02_choose_three")
  local battles, retired, lost = 0, false, false
  local commence, judged, arenaBattle, partyMenuInBattle = 0, 0, false, false
  local shotRef, shotJudge = false, false
  local judgment
  local attendant = S.objectByScript("BattleFrontier_BattleArenaLobby_EventScript_Attendant")
  if not check(attendant ~= nil, "arena attendant present") then return finish() end
  S.talkTo(game, attendant)
  S.settle(game, {
    limit = 500000,
    until_ = function()
      return (retired or lost) and S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_ARENA_LOBBY" and not S.busy()
        and tonumber(f.challengeStatus) == 0
    end,
    choice = function(ch)
      local r = F.pick(ch, "RETIRE")
      if r then
        retired = true
        return r
      end
      return F.yesNo(ch) or "yes"
    end,
    onIdleUi = picker.idle,
    onBattleStart = function(st)
      battles = battles + 1
      arenaBattle = st.facility ~= nil and st.facility.kind == "arena"
      note(string.format("battle %d vs %s foe %s facility=%s", battles, tostring(st.trainerName),
        tostring(st.enemy and st.enemy.mon and st.enemy.mon.species), tostring(st.facility and st.facility.kind)))
    end,
    onBattleFrame = function(st, phase)
      local fac = st.facility
      if not (fac and fac.kind == "arena") then return end
      if PartyMenu.isOpen and PartyMenu.isOpen() then partyMenuInBattle = true end
      if phase == "facility" and fac.ref and fac.ref.shown >= fac.ref.len and not fac.window then
        if not shotRef then
          shotRef = true
          shot("03_referee_commence")
        end
      end
      if fac.window and #fac.window.icons >= 6 and not shotJudge then
        shotJudge = true
        U.wait(2)
        shot("04_judgment_window")
      end
      if fac.lastJudgment and fac.lastJudgment ~= judgment then
        judgment = fac.lastJudgment
        judged = judged + 1
        note(string.format("judgment on turn %d: result %d totals %d-%d", st.turn, judgment.result,
          judgment.total[0], judgment.total[1]))
      end
    end,
    onBattleEnd = function(result, st)
      note("battle " .. battles .. " -> " .. tostring(result))
      if result ~= "win" then lost = true end
      U.wait(20)
      shot("05_after_battle")
    end,
  })
  check(picker.opened >= 1, "ChoosePartyForBattleFrontier opened the party menu")
  check(battles == 1, "one arena battle fought (" .. battles .. ")")
  check(arenaBattle, "the battle runs with the arena facility hooks (battle_tower.c:2083)")
  check(shotRef, "the referee opens the battle in the referee box (battle_scripts_1.s:4448)")
  check(judged >= 1, "a three-turn judgment decided a match-up (battle_util.c:1856, " .. judged .. ")")
  check(shotJudge, "the judgment window showed all six category marks (battle_arena.c:436)")
  check(not partyMenuInBattle, "replacements come out in party order with no party menu (battle_controller_player.c:2672)")
  if retired then
    check(Util.get1(f.arenaWinStreaks, 0) == 1, "arena win streak is 1 after the win")
  else
    note("lost the arena battle; streak " .. Util.get1(f.arenaWinStreaks, 0))
  end
  check(S.mapNow() == "EM_BATTLE_FRONTIER_BATTLE_ARENA_LOBBY", "back in the arena lobby")
  check(tonumber(f.challengeStatus) == 0, "challenge status cleared by arena_save 0")
  shot("06_back_in_lobby")
  note("logs outside f2 scope: " .. F.vmLogsExcept(d, { "CallApprenticeFunction", "SetCameraPanning" }))
  finish()
end
