local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

return function(game)
  local d = S.new("em_trainer_hill", "/tmp/em_trainer_hill")
  local check, note = d.check, d.note
  local function shot(name) d.shot(game, name) end
  local function finish() return d.finish() end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end

  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local raw = love.filesystem.read("saves/emerald/slot1.lua")
  if not check(type(raw) == "string", "identity has the post-Hall-of-Fame save") then return finish() end
  local session = Schema.fromSaveTable(SaveData.decode(raw))
  require("src.core.game3.options").bind(session, game.options)
  game:adoptSave(session, true)
  game.sessionStartedAt = os.time()
  game:_enterField(session, "continue")
  U.wait(30)
  S.settle(game)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Natives = require("src.core.game3.scripting.natives")
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  local SaveMenu = require("src.ui.game3.save_menu")
  session = Runtime.getSession()
  Natives.ensureBound(session)
  require("tests.drivers.em_f4_hooks").install()
  local Hill = require("src.core.game3.rse.trainer_hill")
  local D = require("src.core.game3.rse.frontier.trainers")
  check(Natives.handlerFor("CallTrainerHillFunction") ~= nil and Natives.handlerFor("ShowTrainerHillRecords") ~= nil,
    "CallTrainerHillFunction / ShowTrainerHillRecords bound on Emerald")
  session.repelSteps = 0
  require("src.core.game3.encounters").onStep = function() return nil end

  local function tough(name, moves)
    local m = D.createMon(S.species(name), 80, 31, 0, tonumber(session.trainerId) or 0, { otName = session.name })
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
    tough("SPECIES_LATIOS", { "MOVE_PSYCHIC", "MOVE_DRAGON_CLAW", "MOVE_THUNDERBOLT", "MOVE_ICE_BEAM" }),
    tough("SPECIES_TYRANITAR", { "MOVE_CRUNCH", "MOVE_ROCK_SLIDE", "MOVE_EARTHQUAKE", "MOVE_FIRE_PUNCH" }),
    tough("SPECIES_BLAZIKEN", { "MOVE_SKY_UPPERCUT", "MOVE_FLAMETHROWER", "MOVE_BRICK_BREAK", "MOVE_ROCK_SLIDE" }),
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

  if not check(teleport("EM_TRAINER_HILL_ENTRANCE", 9, 8, "up"), "Trainer Hill entrance loads") then return finish() end
  shot("01_entrance")
  local rec = { x = 8, y = 10 }
  S.goTo(game, { rec.x, rec.y + 1 })
  S.face(game, "up")
  U.tap(game, "a")
  local Records = require("src.ui.game3.rse.trainer_hill_records")
  for _ = 1, 200 do
    if Records.isOpen() then break end
    U.wait(1)
  end
  U.wait(30)
  check(Records.isOpen(), "the time board opens the Trainer Hill records (battle_records.c:465)")
  shot("02_time_board")
  U.tap(game, "a")
  for _ = 1, 200 do
    if not Records.isOpen() then break end
    U.wait(1)
  end
  S.settle(game)
  check(not Records.isOpen(), "A closes the time board")

  local saved = false
  S.goTo(game, { 9, 7 })
  S.step(game, "up")
  S.settle(game, { limit = 20000,
    until_ = function() return S.var("VAR_TRAINER_HILL_IS_ACTIVE") == 1 and not S.busy() end,
    choice = function(ch)
      local o = ch.options and ch.options[1]
      local t = tostring(type(o) == "table" and (o.text or o.label or o[1]) or o):upper()
      if t:find("NORMAL", 1, true) then shot("03_mode_select") end
      return 1
    end,
    onIdleUi = function()
      if SaveMenu.isOpen() then
        saved = true
        U.tap(game, "a")
        U.wait(8)
        return true
      end
      return false
    end })
  check(saved, "entering saves the game first")
  check(S.var("VAR_TRAINER_HILL_IS_ACTIVE") == 1, "trainerhill_start begins the Normal challenge")
  check(Hill.timerRunning(), "the challenge timer runs")
  local battles = 0
  local function onBattleStart(st)
    battles = battles + 1
    if battles == 1 then S.pendingBattleShot = "05_hill_battle" end
  end
  S.goTo(game, { 9, 1 })
  S.settle(game, { limit = 6000 })
  for floor = 1, 4 do
    local mapId = "EM_TRAINER_HILL_" .. floor .. "F"
    if not check(S.mapNow() == mapId, "reached " .. mapId .. " (" .. tostring(S.mapNow()) .. ")") then break end
    U.wait(30)
    local def = Map._def
    local fl = Hill.floor(session)
    check(def and def.midLayout and def.midLayout:midAt(0, 5) == fl.map.metatiles[1] + 512,
      mapId .. " floor tiles come from the challenge data")
    local trainers = 0
    for _, lid in ipairs(Objects._order or {}) do
      local eo = Objects.find(lid)
      if eo and not eo.hidden then trainers = trainers + 1 end
    end
    check(trainers == 2, mapId .. " spawns its two trainers")
    if floor == 1 then shot("04_floor1") end
    for t = 1, 2 do
      local eo = Objects.find(t)
      if eo and not Hill.trainerFlag(session, t) then
        S.healParty()
        S.talkTo(game, eo, { settle = { onBattleStart = onBattleStart } })
        S.settle(game, { limit = 30000, onBattleStart = onBattleStart })
      end
    end
    check(Hill.trainerFlag(session, 1) and Hill.trainerFlag(session, 2), mapId .. " trainers beaten")
    local nextMap = floor < 4 and ("EM_TRAINER_HILL_" .. (floor + 1) .. "F") or "EM_TRAINER_HILL_ROOF"
    S.goTo(game, { 12, 1 }, { settle = { onBattleStart = onBattleStart } })
    S.settle(game, { limit = 6000, onBattleStart = onBattleStart,
      until_ = function() return S.mapNow() == nextMap and not S.busy() end })
  end
  check(battles >= 8, "eight Trainer Hill battles (" .. battles .. ")")
  if check(S.mapNow() == "EM_TRAINER_HILL_ROOF", "climbed to the roof") then
    Hill.syncTimer(session)
    local timer = Hill.state(session).timer
    check(timer > 0, "the timer counted the climb (" .. timer .. " frames)")
    local owner = S.objectByScript("TrainerHill_Roof_EventScript_Owner") or Objects.find(1)
    local bagBefore = Hill.prizeItemId(session)
    local had = require("src.core.game3.bag").get(session.bag, bagBefore)
    S.talkTo(game, owner)
    local shotPrize = false
    S.settle(game, { limit = 20000, watch = function()
      if not shotPrize and require("src.ui.game3.message").isOpen() then
        shotPrize = true
        U.wait(20)
        shot("06_owner")
      end
    end })
    check((tonumber(Hill.state(session).receivedPrize) or 0) == 1, "the owner gives the prize (trainer_hill.c:427)")
    check(require("src.core.game3.bag").get(session.bag, bagBefore) == had + 1, "prize item " .. tostring(bagBefore) .. " added")
    check((tonumber(Hill.state(session).checkedFinalTime) or 0) == 1, "the final time is checked")
    check(session.trainerHillTimes[1] == Hill.state(session).timer, "a new best time is recorded for Normal")
    check(not Hill.timerRunning(), "talking to the owner stops the timer")
  end
  finish()
end
