local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_contest_engine", "/tmp/em_contest_engine")

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    local Party = require("src.core.game3.party")
    local Contest = require("src.core.game3.rse.contest")
    local Util = require("src.core.game3.rse.contest_util")
    local Ribbons = require("src.core.game3.rse.ribbons")
    local Pokeblock = require("src.core.game3.rse.pokeblock")
    Party.giveMonToPlayer(session, S.species("SPECIES_SALAMENCE"), 60)
    local mon = session.party[1]
    local cond = Pokeblock.contest(mon)
    cond.cool, cond.tough, cond.beauty, cond.sheen = 180, 90, 60, 40
    d.check(M.goTo(game, "EM_LILYCOVE_CITY_CONTEST_LOBBY", 14, 4, "up"), "entered the Lilycove Contest Lobby")
    d.shot(game, "01_lobby")

    local data = Contest.data()
    d.check(data.opponentCount == 96, "rse/contest manifest loads from the cache (96 opponents)")
    d.check(data.moves[1] ~= nil and data.effects[0] ~= nil, "contest move/effect tables load from the cache")

    local won = false
    for attempt = 1, 12 do
      local e = Util.tryEnterContestMon(session, 0, Contest.CATEGORY.COOL, Contest.RANK.NORMAL, { gameClear = false })
      if attempt == 1 then
        d.check(e == Util.ELIGIBILITY.EQUAL_RANK, "ribbonless mon may enter Normal rank (eligibility " .. tostring(e) .. ")")
      end
      local c = Util.current()
      if attempt == 1 then
        d.check(c ~= nil and c.mons[3].species == mon.species, "player's mon is contestant 4")
        d.check(c.round1[3] == 180 + math.floor((90 + 60 + 40) / 2), "round 1 = cool + (tough + beauty + sheen) / 2")
        for i = 0, 2 do
          d.check(c.mons[i].whichRank == 0 and c.mons[i].aiPool.cool, "opponent " .. i .. " is a Normal-rank Cool entrant")
        end
      end
      c:init()
      local rounds = c:run({ 2, 0, 2, 3, 1 })
      if attempt == 1 then
        d.check(#rounds == 5, "five appeal rounds")
        local seen = {}
        for i = 0, 3 do seen[c.standings[i]] = true end
        d.check(seen[0] and seen[1] and seen[2] and seen[3], "final standings are a permutation")
        for i = 0, 3 do
          d.check(c.totals[i] == c.round1[i] + 2 * c.appealTotals[i], "total " .. i .. " = round1 + 2 x appeals")
        end
        local bars = Util.resultsData(c)
        d.check(bars[0].barLengthPreliminary ~= nil and bars[3].numStars >= 1, "results-screen bars and stars computed")
        d.note(string.format("attempt 1 totals %d %d %d %d, player place %d", c.totals[0], c.totals[1], c.totals[2],
          c.totals[3], c:playerPlace() + 1))
      end
      if c:playerPlace() == 0 then
        won = true
        local before = Ribbons.get(mon, "cool")
        d.check(Util.giveMonContestRibbon(session), "GiveMonContestRibbon gave the ribbon")
        d.check(Ribbons.get(mon, "cool") == before + 1, "Cool ribbon rank went up")
        d.check(not Util.giveMonContestRibbon(session) or Ribbons.get(mon, "cool") == before + 1,
          "a second call cannot skip a rank")
        Util.clearAllWinners(session)
        d.check(Util.saveContestWinner(session, Contest.RANK.NORMAL), "contest hall winner saved")
        d.check(session.contestWinners[1].species == mon.species, "winner painting shows the player's mon")
        d.note("won on attempt " .. attempt)
        break
      end
    end
    d.check(won, "the conditioned mon won a Normal Cool contest within 12 tries")
    d.check(Util.eligibility(mon, Contest.CATEGORY.COOL, Contest.RANK.SUPER) == Util.ELIGIBILITY.EQUAL_RANK,
      "Normal ribbon unlocks Super rank")
    d.check(Util.hasMonWonThisContestBefore(mon, Contest.CATEGORY.COOL, Contest.RANK.NORMAL),
      "HasMonWonThisContestBefore is true for Normal after the ribbon")
    d.shot(game, "02_after")
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
