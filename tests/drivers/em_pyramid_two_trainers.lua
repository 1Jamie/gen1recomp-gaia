local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

return function(game)
  local d = S.new("em_pyramid_two_trainers", "/tmp/em_pyramid_two_trainers")
  local check, note = d.check, d.note
  local function shot(name) d.shot(game, name) end
  local function finish() return d.finish() end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(240)
  S.settle(game)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Natives = require("src.core.game3.scripting.natives")
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local TrainerSight = require("src.core.game3.trainer_sight")
  local Battle = require("src.core.game3.battle")
  local BattleUi = require("src.core.game3.battle.ui")
  local Encounters = require("src.core.game3.encounters")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field session exists") then return finish() end
  Natives.ensureBound(session)
  require("tests.drivers.em_f4_hooks").install()
  local Py = require("src.core.game3.rse.frontier.pyramid")
  local Util = require("src.core.game3.rse.frontier.util")
  local D = require("src.core.game3.rse.frontier.trainers")
  local C = S.C()
  session.repelSteps = 0
  Encounters.onStep = function() return nil end

  local function tough(name, moves)
    local m = D.createMon(S.species(name), 50, 31, 0, tonumber(session.trainerId) or 0, { otName = session.name })
    local ms = {}
    for i, mv in ipairs(moves) do ms[i] = S.move(mv) end
    D.setMoves(m, ms)
    D.setEvs(m, { 252, 252, 6, 0, 0, 0 })
    m.otId, m.otName, m.ot = session.trainerId, session.name, session.name
    return m
  end
  session.party = {
    tough("SPECIES_METAGROSS", { "MOVE_METEOR_MASH", "MOVE_EARTHQUAKE", "MOVE_PSYCHIC", "MOVE_SHADOW_BALL" }),
    tough("SPECIES_SALAMENCE", { "MOVE_DRAGON_CLAW", "MOVE_EARTHQUAKE", "MOVE_FLAMETHROWER", "MOVE_AERIAL_ACE" }),
    tough("SPECIES_SWAMPERT", { "MOVE_SURF", "MOVE_EARTHQUAKE", "MOVE_ICE_BEAM", "MOVE_BRICK_BREAK" }),
  }

  local function teleport(mapId, x, y, facing)
    S.settle(game)
    local ok, err = pcall(function() Map.load(nil, game, mapId, { x = x, y = y, facing = facing }) end)
    if not ok then note("Map.load " .. mapId .. ": " .. tostring(err)) end
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    U.wait(30)
    S.settle(game)
    return ok
  end

  -- pokeemerald/data/maps/BattleFrontier_BattlePyramidLobby/scripts.inc:106
  S.setVar("VAR_FRONTIER_FACILITY", D.FACILITY.PYRAMID)
  S.setVar("VAR_FRONTIER_BATTLE_MODE", D.MODE.SINGLES)
  local f = Util.frontier(session)
  f.lvlMode = D.LVL.L50
  Py.init(session)
  f.challengeStatus, f.challengePaused = 0, 0
  Py.seedFloor(session)
  if not check(teleport(Py.FLOOR_MAP, 8, 8, "down"), "Pyramid floor loads") then return finish() end
  if not check(S.mapNow() == Py.FLOOR_MAP and Py.inPyramid(session), "standing on a Pyramid floor (" ..
      tostring(S.mapNow()) .. ")") then
    return finish()
  end
  U.wait(60)
  S.settle(game)

  local ball = C:require("event_objects", "OBJ_EVENT_GFX_ITEM_BALL")
  local trainers = {}
  for _, lid in ipairs(Objects._order or {}) do
    local eo = Objects.find(lid)
    if eo and not eo.hidden and tonumber(eo.graphicsId) ~= ball and eo.cellX < 1000 then trainers[#trainers + 1] = eo end
  end
  if not check(#trainers >= 2, "the floor has at least two trainers (" .. #trainers .. ")") then return finish() end

  local L = Map._def and Map._def.midLayout
  local function open(x, y)
    if not L or x < 0 or y < 0 or x >= L.width or y >= L.height then return false end
    return Collision.canEnter(game, x, y, {}) and not Objects.at(x, y)
  end
  local spot
  for y = 2, (L and L.height or 32) - 1 do
    for x = 1, (L and L.width or 32) - 3 do
      if not spot and open(x - 1, y) and open(x, y) and open(x + 1, y) and open(x + 2, y)
          and open(x, y - 1) and open(x, y - 2) then
        spot = { x = x, y = y }
      end
    end
  end
  if not check(spot ~= nil, "found an open cell with room for two watching trainers") then return finish() end

  local A, B = trainers[1], trainers[2]
  for i = 3, #trainers do
    local eo = trainers[i]
    eo.hidden, eo.visible = true, false
  end
  local function place(eo, x, y, mt, facing)
    eo.cellX, eo.cellY = x, y
    eo.px, eo.py = x * 16, y * 16
    eo.targetX, eo.targetY = x, y
    eo.homeX, eo.homeY = x, y
    eo.moving, eo.progress = false, 0
    if eo.def then eo.def.x, eo.def.y = x, y end
    Objects.setMovementType(eo.localId, mt)
    eo.facing = facing
    eo.sight = 2
  end
  -- pokeemerald/include/constants/event_object_movement.h:12
  place(A, spot.x, spot.y - 2, 8, "down")
  place(B, spot.x + 2, spot.y, 9, "left")
  Player.reset(spot.x - 1, spot.y, "right")
  session.x, session.y, session.facing = spot.x - 1, spot.y, "right"
  U.wait(10)
  local tidA, tidB = Py.localIdToTrainerId(session, A.localId), Py.localIdToTrainerId(session, B.localId)
  note(string.format("spot %d,%d trainer A lid %d tid %d, trainer B lid %d tid %d", spot.x, spot.y, A.localId, tidA,
    B.localId, tidB))
  check(tidA ~= tidB and tidA < D.TRAINERS_COUNT and tidB < D.TRAINERS_COUNT, "both objects map to Pyramid trainer ids")
  shot("01_before_step")

  local before = Py.remainingTrainers(session)
  U.hold(game, "right", 20)
  local pairSeen = false
  for _ = 1, 120 do
    if TrainerSight._pair then pairSeen = true break end
    U.wait(1)
  end
  if not check(pairSeen, "both Pyramid trainers spot the player (engagePair)") then return finish() end
  check(TrainerSight._pair.a == tidA and TrainerSight._pair.b == tidB, "the pair carries both Pyramid trainer ids")
  check(session.frontierOpponentA == tidA and session.frontierOpponentB == tidB,
    "gTrainerBattleOpponent_A/B hold the two Pyramid trainers")
  U.wait(10)
  shot("02_first_exclamation")

  local st0
  local shotBattle = false
  local function onBattleStart(st) st0 = st0 or st end
  local function onBattleFrame()
    if not shotBattle and Battle._phase == "command" and BattleUi._mode == "menu" then
      shotBattle = true
      U.wait(10)
      shot("03_pyramid_two_trainer_battle")
    end
  end
  S.settle(game, { limit = 30000, onBattleStart = onBattleStart, onBattleFrame = onBattleFrame })
  if not check(st0 ~= nil, "the two-trainer Pyramid battle starts") then return finish() end
  check(st0.double == true, "battle is double")
  check(st0.kinds and st0.kinds.twoOpponents == true, "battle kind twoOpponents")
  check(st0.kinds and st0.kinds.pyramid == true, "battle kind pyramid")
  check(st0.trainerId == tidA and st0.trainerIdB == tidB, "opponents A and B are the two Pyramid trainers")
  check(st0.foeHalf == 1, "each Pyramid trainer brings one mon (foeHalf 1)")
  check(shotBattle, "the command menu was reached")
  check(st0.result == "win", "player won (" .. tostring(st0.result) .. ")")
  check(Py.trainerFlag(session, A.localId) and Py.trainerFlag(session, B.localId),
    "both trainers are marked battled (battle_pyramid.c:1328)")
  check(Py.remainingTrainers(session) == before - 2, "two fewer trainers remain (" .. Py.remainingTrainers(session) .. ")")
  U.wait(30)
  shot("04_after_battle")
  finish()
end
