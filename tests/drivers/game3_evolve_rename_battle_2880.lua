local U = require("tests.drivers.util")

local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_evolve_rename_battle_2880"
local BULBASAUR, IVYSAUR = 1, 2

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print(failures == 0 and "PASS evolve_rename_battle_2880" or ("FAIL evolve_rename_battle_2880 failures=" .. failures))
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local SummaryData = require("src.core.game3.summary_data")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local Choice = require("src.ui.game3.choice")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local EvolutionScene = require("src.ui.game3.evolution_scene")
  local PartyMenu = require("src.ui.game3.party_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "field reached (" .. tostring(session and session.version) .. ")") then return finish() end
  session.party = {}
  Party.giveMon(session, BULBASAUR, 15, Pokemon.name(BULBASAUR))
  local mine = session.party[1]
  mine.moves = { 33, 0, 0, 0 }
  mine.pp = { 35, 0, 0, 0 }
  mine.maxPp = { 35, 0, 0, 0 }
  mine.exp = SummaryData.expForLevel(Pokemon.growthRate(BULBASAUR), 16) - 1
  result(Pokemon.displayMonName(mine) == Pokemon.name(BULBASAUR), "starts named " .. tostring(Pokemon.displayMonName(mine)))

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 30 }, { fade = false })
  if not result(ok == true, "battle started " .. tostring(err or "")) then return finish() end

  local lastTap, f, shotEvo = 0, 0, false
  for _ = 1, 20000 do
    f = f + 1
    local evoOpen = EvolutionScene.isOpen()
    if not Battle.isActive() and not evoOpen then break end
    if evoOpen and not shotEvo and EvolutionScene._state == "congrats" then
      shotEvo = true
      U.wait(40)
      U.still(game, DIR .. "/2880_01_congrats_evolved.png")
    end
    if Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" then
      local est = Battle.getState() and Battle.getState().enemy
      if est and est.mon then
        est.mon.moves = { 150, 0, 0, 0 }
        est.mon.pp = { 40, 0, 0, 0 }
        est.mon.hp = 1
        local ep = Anim.present("enemy")
        if ep then ep.displayHp = 1 end
      end
      Ui._pendingCommand = { kind = "move", move = 33, slot = 1, user = "player" }
      Ui._mode = "none"
      U.wait(2)
    elseif Choice.active or SummaryMenu.isOpen() then
      U.tap(game, "a")
      U.wait(6)
    elseif Anim.vm() and Anim.vm():busy() then
      U.wait(1)
    elseif f - lastTap >= 12 then
      lastTap = f
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end
  U.wait(30)
  local mon = session.party[1]
  result(Pokemon.speciesOf(mon) == IVYSAUR, "evolved to IVYSAUR (" .. tostring(Pokemon.speciesOf(mon)) .. ")")
  result(mon.nickname == Pokemon.name(IVYSAUR), "nickname is " .. tostring(mon.nickname))
  result(Pokemon.displayMonName(mon) == Pokemon.name(IVYSAUR), "party name is " .. tostring(Pokemon.displayMonName(mon)))

  PartyMenu.show(session.party, session.move_overlay, {})
  U.wait(40)
  U.still(game, DIR .. "/2880_02_party_shows_ivysaur.png")
  finish()
end
