local U = require("tests.drivers.util")
local L = require("tests.drivers.em_battle_loop")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_two_trainers"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_two_trainers failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local MAPS = { "EM_ROUTE110", "EM_ROUTE117", "EM_ROUTE111", "EM_ROUTE113", "EM_ROUTE114", "EM_ROUTE116",
  "EM_ROUTE118", "EM_ROUTE119", "EM_ROUTE120", "EM_ROUTE121", "EM_ROUTE123", "EM_ROUTE104", "EM_ROUTE103",
  "EM_ROUTE102", "EM_ROUTE115", "EM_ROUTE112" }
local STEP = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Party = require("src.core.game3.party")
  local Objects = require("src.core.game3.objects")
  local Collision = require("src.core.game3.collision")
  local Player = require("src.core.game3.player")
  local TrainerSight = require("src.core.game3.trainer_sight")
  local Trainers = require("src.core.game3.scripting.trainers")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Encounters = require("src.core.game3.encounters")
  local Message = require("src.ui.game3.message")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Prize = require("src.core.game3.battle.prize")
  local Audio = require("src.core.game3.audio")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not result(session ~= nil, "field session exists") then return finish() end
  Encounters.onStep = function() return nil end
  result(TrainerSight.twoTrainerApproach(), "Emerald battle profile enables two-trainer approach")

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_SWAMPERT, 60, "SWAMPERT")
  Party.giveMon(session, C.species.byName.SPECIES_BLAZIKEN, 60, "BLAZIKEN")
  Party.giveMon(session, C.species.byName.SPECIES_SCEPTILE, 60, "SCEPTILE")

  local store, ctx = Space.store, Space.vm and Space.vm.ctx
  local function candidates()
    local out = {}
    for _, lid in ipairs(Objects._order or {}) do
      local eo = Objects.find(lid)
      local sight = eo and tonumber(eo.sight or (eo.def and (eo.def.sight or eo.def.trainerRange))) or 0
      if eo and eo.visible and not eo.hidden and sight > 0 and TrainerSight.isTrainerType(eo)
          and TrainerSight.getTrainerId(eo) and TrainerSight.battleType(eo) == 0
          and not TrainerSight.isDefeated(eo, store, ctx) then
        out[#out + 1] = eo
      end
    end
    return out
  end
  local function sees(eo, x, y)
    local ok, spotted = pcall(TrainerSight.checkLineOfSight, eo, { cellX = x, cellY = y,
      currentElevation = eo.currentElevation }, game)
    return ok and spotted
  end

  local pick
  for _, mapId in ipairs(MAPS) do
    local ok = pcall(function() Map.load(nil, game, mapId, { x = 5, y = 5, facing = "down" }) end)
    U.wait(4)
    if ok then
      local list = candidates()
      local cells = {}
      for _, eo in ipairs(list) do
        local d = STEP[eo.facing or "down"]
        local sight = tonumber(eo.sight or (eo.def and (eo.def.sight or eo.def.trainerRange))) or 0
        for k = 1, sight do cells[#cells + 1] = { eo.cellX + d[1] * k, eo.cellY + d[2] * k } end
      end
      for _, c in ipairs(cells) do
        if pick then break end
        local x, y = c[1], c[2]
        local seen = {}
        for _, eo in ipairs(list) do
          if sees(eo, x, y) then seen[#seen + 1] = eo end
        end
        if #seen == 2 and not Objects.at(x, y) then
          for dir, d in pairs(STEP) do
            local nx, ny = x - d[1], y - d[2]
            if not pick and Collision.canEnter(game, nx, ny, {}) and not Objects.at(nx, ny)
                and Collision.canEnter(game, x, y, { fromX = nx, fromY = ny, dir = dir })
                and not sees(seen[1], nx, ny) and not sees(seen[2], nx, ny) then
              local unseenByOthers = true
              for _, eo in ipairs(list) do
                if sees(eo, nx, ny) then unseenByOthers = false end
              end
              if unseenByOthers then
                pick = { map = mapId, x = nx, y = ny, dir = dir, a = seen[1], b = seen[2] }
              end
            end
          end
        end
      end
    end
    if pick then break end
  end
  if not result(pick ~= nil, "found a cell two single trainers see at once") then return finish() end
  local tidA, tidB = TrainerSight.getTrainerId(pick.a), TrainerSight.getTrainerId(pick.b)
  print(string.format("[driver] %s step %s from (%d,%d): %s (lid %d) + %s (lid %d)", pick.map, pick.dir, pick.x,
    pick.y, C:name("trainers", tidA, "TRAINER_") or tidA, pick.a.localId, C:name("trainers", tidB, "TRAINER_") or tidB,
    pick.b.localId))

  Map.load(nil, game, pick.map, { x = pick.x, y = pick.y, facing = pick.dir })
  U.wait(60)
  local moneyBefore = tonumber(session.money) or 0
  local want = Prize.rewardRse(tidA, { twoOpponents = true, trainerIdB = tidB, double = true })

  U.hold(game, pick.dir, 20)
  local pairSeen = false
  for _ = 1, 120 do
    if TrainerSight._pair then pairSeen = true break end
    U.wait(1)
  end
  result(pairSeen, "both trainers spot the player (engagePair)")
  U.wait(10)
  U.still(game, DIR .. "/01_first_exclamation.png")

  local intros, shotIntro = 0, 0
  local wasOpen = false
  for _ = 1, 3000 do
    if Battle.isActive() then break end
    local open = Message.isOpen and Message.isOpen()
    if open and not wasOpen then
      intros = intros + 1
      U.wait(40)
      shotIntro = shotIntro + 1
      U.still(game, DIR .. string.format("/0%d_intro_%d.png", shotIntro + 1, shotIntro))
    end
    wasOpen = open
    if open then U.tap(game, "a") end
    U.wait(3)
  end
  result(intros >= 2, "both trainers give their intro speech (" .. intros .. ")")
  if not result(Battle.isActive(), "the two-trainer battle starts") then return finish() end
  local st = Battle._st
  result(st.double == true, "battle is double")
  result(st.kinds and st.kinds.twoOpponents == true, "battle kind twoOpponents")
  result(st.trainerId == tidA and st.trainerIdB == tidB, "opponents A and B are the two trainers")
  result(st.foeHalf ~= nil and st.battlers[3] and st.battlers[3].partyIndex == st.foeHalf + 1,
    "right opponent leads with trainer B's first mon")
  local song = Audio._currentSong and Audio._currentSong.id
  print("[driver] battle song " .. tostring(song))

  local shots = {}
  local done = L.run(game, {
    onFrame = function(s, phase)
      if phase == "intro" and not shots.intro and Ui.dialogPending and Ui.dialogPending()
          and L.logHas("want to battle") then
        shots.intro = true
        U.wait(20)
        U.still(game, DIR .. "/04_two_trainers_want_to_battle.png")
      end
      if phase == "command" and not shots.cmd and Ui._mode == "menu" then
        shots.cmd = true
        U.wait(10)
        U.still(game, DIR .. "/05_command.png")
      end
      if Battle._pendingEnd == "win" and not shots.win and Ui.dialogPending and Ui.dialogPending() then
        shots.win = true
        U.wait(30)
        U.still(game, DIR .. "/06_two_enemies_defeated.png")
      end
    end,
  })
  result(done, "battle finished")
  result(st.result == "win", "player won (" .. tostring(st.result) .. ")")
  local infoA, infoB = Trainers.info(tidA), Trainers.info(tidB)
  local iWant = L.logIndex(infoA.name .. " and") or L.logIndex(infoA.name)
  result(L.logHas("want to battle"), "intro uses sText_TwoTrainersWantToBattle")
  result(L.logHas(infoB.name), "trainer B is named in the battle text")
  L.dumpLog()
  local iDef = L.logIndex("were defeated")
  local loseA = Trainers.dialogs(tidA).defeat
  local loseB = Trainers.dialogs(tidB).defeat
  local iA = loseA and L.logIndex(loseA:sub(1, 10))
  local iB = loseB and L.logIndex(loseB:sub(1, 10))
  local iMoney = L.logIndex("got $") or L.logIndex(tostring(want))
  print(string.format("[driver] log order defeated=%s loseA=%s loseB=%s money=%s", tostring(iDef), tostring(iA),
    tostring(iB), tostring(iMoney)))
  result(iDef and iA and iB and iMoney and iDef < iA and iA < iB and iB < iMoney,
    "LocalTwoTrainersDefeated order: defeated, A lose text, B lose text, money")
  local gained = (tonumber(session.money) or 0) - moneyBefore
  result(gained == want, string.format("prize money A + B without the double x2 (gained %d want %d)", gained, want))
  for _ = 1, 600 do
    if not (Message.isOpen and Message.isOpen()) and not Battle.isActive() and not (TrainerSight._pair) then break end
    U.tap(game, "a")
    U.wait(3)
  end
  U.wait(30)
  result(Flags.getFlag(Space.store, Space.vm and Space.vm.ctx, Flags.trainerFlagId(tidA)), "trainer A flag set")
  result(Flags.getFlag(Space.store, Space.vm and Space.vm.ctx, Flags.trainerFlagId(tidB)), "trainer B flag set")
  result(Map.current == pick.map, "back on " .. pick.map)
  U.still(game, DIR .. "/07_after.png")
  U.hold(game, pick.dir == "up" and "down" or "up", 20)
  U.wait(30)
  result(not Battle.isActive() and TrainerSight._pair == nil, "defeated trainers do not re-engage")
  return finish()
end
