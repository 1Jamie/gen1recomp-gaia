local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_lottery", "/tmp/em_lottery")

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    local Lottery = require("src.core.game3.rse.lottery")
    local Party = require("src.core.game3.party")
    local Bag = require("src.core.game3.bag")
    local Rtc = require("src.core.game3.rtc")
    local Field = require("src.core.game3.field")
    local C = S.C()
    Party.giveMonToPlayer(session, S.species("SPECIES_TORCHIC"), 20)
    local mon = session.party[1]
    local otId = (tonumber(mon.otId) or 0) % 0x10000
    d.note("party OT id " .. otId)
    d.check(M.goTo(game, "EM_LILYCOVE_CITY_DEPARTMENT_STORE_1F", 9, 6, "up"), "entered Lilycove Department Store 1F")
    d.shot(game, "01_dept_store")

    local function talkClerk(opts)
      if not S.goTo(game, { 10, 4 }) then return false end
      S.face(game, "up")
      U.tap(game, "a")
      U.wait(4)
      return M.pump(game, opts)
    end

    -- pokeemerald/data/maps/LilycoveCity_DepartmentStore_1F/scripts.inc:8
    Lottery.setNumber(otId, session)
    local laptopSeen = false
    local flash = C:require("metatile_labels", "METATILE_Shop_Laptop1_Flash")
    local normal = C:require("metatile_labels", "METATILE_Shop_Laptop1_Normal")
    local function laptop()
      local Collision = package.loaded["src.core.game3.collision"]
      local def = Collision and Collision._mapDef
      local layout = def and def.midLayout
      return layout and layout.midAt and layout:midAt(11, 1)
    end
    d.check(laptop() == normal, "laptop screen starts off (METATILE_Shop_Laptop1_Normal)")
    local mark = #M.msgs
    local items0 = Bag.get(session.bag, C:require("items", "ITEM_MASTER_BALL")) or 0
    local done = talkClerk({
      answers = { "yes" },
      onFrame = function()
        if not laptopSeen and laptop() == flash then
          laptopSeen = true
          d.shot(game, "02_laptop_flash")
        end
      end,
    })
    d.check(done, "lottery clerk script finished")
    d.check(M.saw(string.format("%05d", otId), mark), "ticket number " .. string.format("%05d", otId) .. " read out")
    d.check(laptopSeen, "DoLotteryCornerComputerEffect lit the laptop")
    d.check(laptop() == normal, "EndLotteryCornerComputerEffect turned the laptop off")
    d.check((Bag.get(session.bag, C:require("items", "ITEM_MASTER_BALL")) or 0) == items0 + 1, "5-digit match won the MASTER BALL")
    d.check((session.gameStats and session.gameStats[46] or 0) == 1, "GAME_STAT_WON_POKEMON_LOTTERY incremented")
    d.check(S.flag("FLAG_DAILY_PICKED_LOTO_TICKET"), "FLAG_DAILY_PICKED_LOTO_TICKET set")
    d.check(M.saw("all five digits", mark) or M.saw("five", mark) or M.saw("MASTER BALL", mark), "full-match prize text")
    d.shot(game, "03_prize")

    mark = #M.msgs
    talkClerk({})
    d.check(M.saw("tomorrow", mark), "second visit the same day: come back tomorrow")

    -- pokeemerald/src/lottery_corner.c:32
    local before = Lottery.getNumber(session)
    Rtc.advance(24 * 60)
    mark = #M.msgs
    talkClerk({ answers = { "yes" } })
    local after = Lottery.getNumber(session)
    d.note(string.format("lottery number before %d after one day %d", before, after))
    d.check(after ~= before, "SetRandomLotteryNumber drew a new number on the new day")
    d.check(M.saw(string.format("%05d", after % 0x10000), mark), "next day ticket " .. string.format("%05d", after % 0x10000))
    d.shot(game, "04_next_day")
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
