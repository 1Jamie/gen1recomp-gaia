local U = require("tests.drivers.util")

local MAGIKARP, GYARADOS = 129, 130
local SWIFT_SWIM, INTIMIDATE = 33, 22

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print(failures == 0 and "PASS evolve_ability_battle_2603" or ("FAIL evolve_ability_battle_2603 failures=" .. failures))
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

  local session = Runtime.getSession()
  if not result(session ~= nil, "field reached (" .. tostring(session and session.version) .. ")") then return finish() end
  session.party = {}
  Party.giveMon(session, MAGIKARP, 19)
  local mine = session.party[1]
  mine.moves = { 33, 0, 0, 0 }
  mine.pp = { 35, 0, 0, 0 }
  mine.maxPp = { 35, 0, 0, 0 }
  mine.exp = SummaryData.expForLevel(Pokemon.growthRate(MAGIKARP), 20) - 1
  result(mine.ability == SWIFT_SWIM, "Magikarp starts with Swift Swim (" .. tostring(mine.ability) .. ")")

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = MAGIKARP, level = 30 }, { fade = false })
  if not result(ok == true, "battle started " .. tostring(err or "")) then return finish() end

  local lastTap, f = 0, 0
  for _ = 1, 20000 do
    f = f + 1
    local evoOpen = EvolutionScene.isOpen()
    if not Battle.isActive() and not evoOpen then break end
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
  result(Pokemon.speciesOf(mon) == GYARADOS, "post-battle evolution to Gyarados (" .. tostring(Pokemon.speciesOf(mon)) .. ")")
  result(mon.ability == INTIMIDATE and mon.abilityId == INTIMIDATE,
    "Gyarados has Intimidate (" .. tostring(mon.ability) .. "/" .. tostring(mon.abilityId) .. ")")
  finish()
end
