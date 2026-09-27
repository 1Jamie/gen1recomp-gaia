local U = require("tests.drivers.util")
local L = require("tests.drivers.em_battle_loop")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_legendaries"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_legendaries failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not result(session ~= nil, "field session exists") then return finish() end
  Encounters.onStep = function() return nil end

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_SWAMPERT, 90, "")
  Party.giveMon(session, C.species.byName.SPECIES_METAGROSS, 90, "")

  local function sp(n) return C.species.byName["SPECIES_" .. n] end

  local function run(case)
    Rse.setFlag(case.defeated, false)
    for _, f in ipairs(case.clear or {}) do Rse.setFlag(f, false) end
    for k, v in pairs(case.vars or {}) do Rse.setVar(k, v) end
    local ok, err = pcall(function()
      Map.load(nil, game, case.map, { x = case.x, y = case.y, facing = case.facing })
    end)
    if not result(ok, case.name .. ": " .. case.map .. " loads " .. tostring(err or "")) then return end
    local s = Runtime.getSession()
    s.x, s.y, s.facing = case.x, case.y, case.facing
    U.wait(40)
    for _ = 1, 300 do
      if not (Space.vm and Space.vm:isRunning()) then break end
      U.wait(1)
    end
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
    if case.talk then
      Player.facing = case.facing
      for _ = 1, 10 do
        U.tap(game, "a")
        U.wait(10)
        if (Space.vm and Space.vm:isRunning()) or Battle.isActive() then break end
        U.wait(20)
      end
    else
      U.hold(game, case.facing, 8)
    end
    local shotT = false
    for _ = 1, 40000 do
      if Battle.isActive() then break end
      if transitionId and not shotT then
        shotT = true
        U.wait(30)
        U.still(game, DIR .. "/" .. case.name .. "_1_transition.png")
      end
      if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
      U.wait(2)
    end
    Audio.playSong = prevPlay
    BattleTransition.start = prevStart
    if not result(Battle.isActive(), case.name .. ": the map script starts the legendary battle") then
      local Objects = require("src.core.game3.objects")
      print(string.format("[driver] %s player %d,%d facing %s map %s vm %s", case.name, Player.cellX, Player.cellY,
        tostring(Player.facing), tostring(Runtime.getSession().map), tostring(Space.vm and Space.vm._scriptKey)))
      for _, lid in ipairs(Objects.listActive()) do
        local eo = Objects.find(lid)
        print(string.format("[driver]   obj %s at %s,%s hidden=%s script=%s", tostring(lid), tostring(eo.cellX), tostring(eo.cellY),
          tostring(eo.hidden), tostring(eo.def and eo.def.scriptKey)))
      end
      return
    end
    local st = Battle._st
    result(transitionId == C.battle.byName[case.transition],
      case.name .. ": " .. case.transition .. " (" .. tostring(transitionId) .. ")")
    local heard = false
    for _, id in ipairs(songs) do if id == C.songs.byName[case.song] then heard = true end end
    result(heard, case.name .. ": " .. case.song .. " plays")
    result(st.legendary == true, case.name .. ": BATTLE_TYPE_LEGENDARY")
    if case.kind then result(st.kinds and st.kinds[case.kind], case.name .. ": " .. case.kind .. " battle kind") end
    if case.scene then
      result(BattleBg.env().SCENE_SHEET[BattleBg.terrainId()] == case.scene, case.name .. ": " .. case.scene .. " scene")
    end
    result(st.enemy.mon.species == sp(case.species) and st.enemy.mon.level == case.level,
      case.name .. ": wild " .. case.species .. " lv" .. case.level)
    local shot = false
    L.run(game, {
      turnCap = 2,
      onFrame = function(_, phase)
        if phase == "command" and not shot and Ui._mode == "menu" then
          shot = true
          U.wait(10)
          U.still(game, DIR .. "/" .. case.name .. "_2_battle.png")
        end
      end,
    })
    if case.weather then
      result(st.weather ~= nil and tostring(st.weather):upper():find(case.weather) ~= nil,
        case.name .. ": weather " .. case.weather .. " (" .. tostring(st.weather) .. ")")
    end
    if Battle.isActive() then
      Battle.abort("run")
      U.wait(10)
    end
    for _ = 1, 600 do
      if not (Space.vm and Space.vm:isRunning()) and not Battle.isActive() then break end
      if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
      U.wait(2)
    end
    result(not Battle.isActive(), case.name .. ": battle closed")
  end

  -- pokeemerald/data/maps/MarineCave_End/scripts.inc:25
  run({ name = "kyogre", map = "EM_MARINE_CAVE_END", x = 9, y = 27, facing = "up", defeated = "FLAG_DEFEATED_KYOGRE",
    species = "KYOGRE", level = 70, transition = "B_TRANSITION_KYOGRE", song = "MUS_VS_KYOGRE_GROUDON", kind = "kyogre",
    scene = "kyogre", weather = "RAIN" })
  -- pokeemerald/data/maps/SkyPillar_Top/scripts.inc:44
  run({ name = "rayquaza", map = "EM_SKY_PILLAR_TOP", x = 14, y = 7, facing = "up", talk = true,
    defeated = "FLAG_DEFEATED_RAYQUAZA", vars = { VAR_SKY_PILLAR_STATE = 2, VAR_SKY_PILLAR_RAYQUAZA_CRY_DONE = 1 },
    species = "RAYQUAZA", level = 70, transition = "B_TRANSITION_RAYQUAZA", song = "MUS_VS_RAYQUAZA", kind = "rayquaza",
    scene = "rayquaza" })
  -- pokeemerald/src/battle_setup.c:569
  for _, r in ipairs({ { "regirock", "EM_DESERT_RUINS" }, { "regice", "EM_ISLAND_CAVE" }, { "registeel", "EM_ANCIENT_TOMB" } }) do
    local up = r[1]:upper()
    run({ name = r[1], map = r[2], x = 8, y = 8, facing = "up", talk = true, defeated = "FLAG_DEFEATED_" .. up,
      clear = { "FLAG_HIDE_" .. up }, species = up, level = 40, transition = "B_TRANSITION_" .. up,
      song = "MUS_VS_REGI", kind = "regi" })
  end
  return finish()
end
