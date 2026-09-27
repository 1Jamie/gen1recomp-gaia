local U = require("tests.drivers.util")
local L = require("tests.drivers.em_battle_loop")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_legendary_groudon"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_legendary_groudon failures=" .. failures)
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
  local BattleBg = require("src.core.game3.battle.bg")
  local BattleTransition = require("src.core.game3.battle_transition")
  local Audio = require("src.core.game3.audio")
  local Ui = require("src.core.game3.battle.ui")
  local Objects = require("src.core.game3.objects")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not result(session ~= nil, "field session exists") then return finish() end
  Encounters.onStep = function() return nil end

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_SWAMPERT, 90, "")
  Party.giveMon(session, C.species.byName.SPECIES_KYOGRE, 90, "")
  session.bag = session.bag or {}
  require("src.core.game3.bag").add(session.bag, C.items.byName.ITEM_MASTER_BALL, 1)

  Rse.setFlag("FLAG_DEFEATED_GROUDON", false)
  local ok, err = pcall(function() Map.load(nil, game, "EM_TERRA_CAVE_END", { x = 17, y = 27, facing = "up" }) end)
  if not result(ok, "Terra Cave End loads " .. tostring(err or "")) then return finish() end
  U.wait(40)
  result(Rse.var("VAR_TEMP_1") == 1, "OnTransition arms the Groudon trigger (VAR_TEMP_1 = 1)")
  local groudon = false
  for _, lid in ipairs(Objects.listActive()) do
    local eo = Objects.find(lid)
    if eo and eo.cellX == 17 and eo.cellY == 22 then groudon = true end
  end
  result(groudon, "Groudon object is shown at (17,22)")
  U.still(game, DIR .. "/01_terra_cave_end.png")

  local songs, transitionId = {}, nil
  local prevPlay = Audio.playSong
  Audio.playSong = function(id, ...)
    songs[#songs + 1] = id
    return prevPlay(id, ...)
  end
  local prevStart = BattleTransition.start
  BattleTransition.start = function(tid, ...)
    transitionId = tid
    return prevStart(tid, ...)
  end

  U.hold(game, "up", 8)
  local shotT = false
  for _ = 1, 2000 do
    if Battle.isActive() then break end
    if transitionId and not shotT then
      shotT = true
      U.wait(30)
      U.still(game, DIR .. "/02_groudon_transition.png")
    end
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(2)
  end
  Audio.playSong = prevPlay
  BattleTransition.start = prevStart
  if not result(Battle.isActive(), "the coord event starts BattleSetup_StartLegendaryBattle") then return finish() end
  local st = Battle._st
  result(transitionId == C.battle.byName.B_TRANSITION_GROUDON, "B_TRANSITION_GROUDON (" .. tostring(transitionId) .. ")")
  local want = C.songs.byName.MUS_VS_KYOGRE_GROUDON
  local heard = false
  for _, id in ipairs(songs) do if id == want then heard = true end end
  result(heard, "MUS_VS_KYOGRE_GROUDON plays")
  result(st.legendary and st.kinds.groudon, "legendary + groudon kinds")
  result(BattleBg.env().SCENE_SHEET[BattleBg.terrainId()] == "groudon", "Groudon cave scene (battle_bg.c:760)")
  result(st.enemy.mon.species == C.species.byName.SPECIES_GROUDON and st.enemy.mon.level == 70, "wild Groudon lv70")
  result(st.aiFlags == 0, "no AI script for Emerald wild legendaries")

  local shots = {}
  local done = L.run(game, {
    turnCap = 3,
    onFrame = function(s, phase)
      if phase == "command" and not shots.cmd and Ui._mode == "menu" then
        shots.cmd = true
        U.wait(10)
        U.still(game, DIR .. "/03_groudon_battle.png")
      end
    end,
  })
  result(L.logHas("GROUDON appeared"), "sText_LegendaryPkmnAppeared")
  result(st.weather ~= nil and tostring(st.weather):upper():find("SUN") ~= nil,
    "Drought turns the battle weather to sun (" .. tostring(st.weather) .. ")")
  if Battle.isActive() then
    Battle.abort("run")
    U.wait(10)
  end
  result(done or not Battle.isActive(), "battle closed")
  for _ = 1, 600 do
    if not (Space.vm and Space.vm:isRunning()) then break end
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(2)
  end
  U.wait(30)
  U.still(game, DIR .. "/04_after.png")
  return finish()
end
