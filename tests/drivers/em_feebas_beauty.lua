local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_feebas_beauty"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_feebas_beauty failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  try("new_game", function() game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 }) end)
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local Bag = require("src.core.game3.bag")
  local Pokeblock = require("src.core.game3.rse.pokeblock")
  local PartyMenu = require("src.ui.game3.party_menu")
  local EvolutionScene = require("src.ui.game3.evolution_scene")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session and session.version == "emerald", "emerald session") then return finish() end
  local FEEBAS = C:require("species", "SPECIES_FEEBAS")
  local MILOTIC = C:require("species", "SPECIES_MILOTIC")
  local RARE_CANDY = C:require("items", "ITEM_RARE_CANDY")

  session.party = {}
  Party.giveMonToPlayer(session, FEEBAS, 28)
  Party.giveMonToPlayer(session, FEEBAS, 28)
  local hi, lo = session.party[1], session.party[2]
  if not check(hi and lo, "two Lv28 FEEBAS in the party") then return finish() end
  -- pokeemerald/src/use_pokeblock.c:996
  for _ = 1, 5 do Pokeblock.feed({ dry = 60, feel = 1 }, hi, 0) end
  Pokeblock.feed({ dry = 169, feel = 1 }, lo, 0)
  check(hi.contest and hi.contest.beauty == 255, "slot 1 BEAUTY fed to 255 (" .. tostring(hi.contest and hi.contest.beauty) .. ")")
  check(lo.contest and lo.contest.beauty == 169, "slot 2 BEAUTY fed to 169 (" .. tostring(lo.contest and lo.contest.beauty) .. ")")
  Bag.add(session.bag, RARE_CANDY, 5)

  local function candy(slot, shoot)
    PartyMenu.show(session.party, nil, { session = session, bag = session.bag, item = RARE_CANDY, mode = "use" })
    U.wait(30)
    for _ = 2, slot do U.tap(game, "down") U.wait(8) end
    local mon = session.party[slot]
    local before = tonumber(mon.level)
    local opened, shot = false, false
    for _ = 1, 3000 do
      if EvolutionScene.isOpen() then
        opened = true
        if shoot and not shot and EvolutionScene._state == "intro_msg" then
          shot = true
          U.wait(90)
          U.still(game, DIR .. "/2597_01_feebas_is_evolving.png")
        end
        local st = EvolutionScene._state
        if st == "congrats" or st == "done" or st == "learn" or st == "intro_msg" then U.tap(game, "a") else U.wait(1) end
      elseif opened then
        break
      elseif tonumber(mon.level) ~= before then
        local mode = PartyMenu.mode
        if not PartyMenu.open or (mode == "use" and not PartyMenu._hpAnim) then
          U.wait(30)
          if not EvolutionScene.isOpen() then break end
        elseif mode == "message" or mode == "stat_growth" then
          U.tap(game, "a")
          U.wait(4)
        else
          U.wait(1)
        end
      else
        U.tap(game, "a")
        U.wait(4)
      end
    end
    for _ = 1, 600 do
      if not EvolutionScene.isOpen() then break end
      U.tap(game, "a") U.wait(4)
    end
    return opened, mon
  end

  local opened, mon = candy(1, true)
  check(mon.level == 29, "Rare Candy raised slot 1 to Lv" .. tostring(mon.level))
  check(opened, "BEAUTY 255 FEEBAS starts the evolution scene")
  check(Pokemon.speciesOf(mon) == MILOTIC, "slot 1 is now MILOTIC (" .. tostring(Pokemon.speciesOf(mon)) .. ")")
  U.wait(30)
  if PartyMenu.open then PartyMenu.close() end
  U.wait(20)

  local opened2, mon2 = candy(2, false)
  check(mon2.level == 29, "Rare Candy raised slot 2 to Lv" .. tostring(mon2.level))
  check(not opened2, "BEAUTY 169 FEEBAS does not start the evolution scene")
  check(Pokemon.speciesOf(mon2) == FEEBAS, "slot 2 is still FEEBAS (" .. tostring(Pokemon.speciesOf(mon2)) .. ")")
  if PartyMenu.open then PartyMenu.close() end
  U.wait(20)

  PartyMenu.show(session.party, { session = session })
  U.wait(60)
  check(U.shot(game, DIR .. "/2597_02_party_milotic_and_feebas.png"), "party shot")
  PartyMenu.close()
  U.wait(20)
  local SummaryMenu = require("src.ui.game3.summary_menu")
  SummaryMenu.openMenu(session.party, 1, { session = session })
  U.wait(90)
  check(U.shot(game, DIR .. "/2597_03_summary_milotic_lv29.png"), "summary shot")
  SummaryMenu.close()
  U.wait(10)
  finish()
end
