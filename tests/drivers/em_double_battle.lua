local U = require("tests.drivers.util")
local L = require("tests.drivers.em_battle_loop")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_double_battle"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_double_battle failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

local SIDE = { up = { 0, -1, "down" }, down = { 0, 1, "up" }, left = { -1, 0, "right" }, right = { 1, 0, "left" } }

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
  local Objects = require("src.core.game3.objects")
  local Collision = require("src.core.game3.collision")
  local TrainerSight = require("src.core.game3.trainer_sight")
  local Trainers = require("src.core.game3.scripting.trainers")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Encounters = require("src.core.game3.encounters")
  local Message = require("src.ui.game3.message")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Prize = require("src.core.game3.battle.prize")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not result(session ~= nil, "field session exists") then return finish() end
  Encounters.onStep = function() return nil end

  local tid = C.trainers.byName.TRAINER_GINA_AND_MIA_1
  local info = Trainers.info(tid)
  result(info and info.doubleBattle == true, "TRAINER_GINA_AND_MIA_1 is a doubleBattle row")

  local ok, err = pcall(function() Map.load(nil, game, "EM_ROUTE104", { x = 10, y = 30, facing = "down" }) end)
  if not result(ok, "Route 104 loads " .. tostring(err or "")) then return finish() end
  U.wait(40)

  local twins = {}
  for _, lid in ipairs(Objects.listActive()) do
    local eo = Objects.find(lid)
    if eo and TrainerSight.getTrainerId(eo) == tid then twins[#twins + 1] = eo end
  end
  table.sort(twins, function(a, b) return (a.cellX or 0) < (b.cellX or 0) end)
  if not result(#twins == 2, "two twin objects share the trainer id (" .. #twins .. ")") then return finish() end
  result(TrainerSight.battleType(twins[1]) == 4, "twin script is TRAINER_BATTLE_DOUBLE")

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_SWAMPERT, 45, "SWAMPERT")
  Party.giveMon(session, C.species.byName.SPECIES_BLAZIKEN, 45, "BLAZIKEN")
  Party.giveMon(session, C.species.byName.SPECIES_SCEPTILE, 45, "SCEPTILE")
  result(Party.monsStateToDoubles(session.party) == Party.PLAYER_HAS_TWO_USABLE_MONS, "party can double battle")

  local gina = twins[1]
  local sx, sy, face
  for _, dir in ipairs({ "down", "left", "right", "up" }) do
    local d = SIDE[dir]
    local x, y = gina.cellX + d[1], gina.cellY + d[2]
    if not sx and Collision.canEnter(game, x, y, {}) and not Objects.at(x, y) then
      sx, sy, face = x, y, d[3]
    end
  end
  if not result(sx ~= nil, "found a cell next to the twin") then return finish() end
  Map.load(nil, game, "EM_ROUTE104", { x = sx, y = sy, facing = face })
  U.wait(60)
  local moneyBefore = tonumber(session.money) or 0

  U.tap(game, "a")
  local sawIntro = false
  for _ = 1, 900 do
    if Battle.isActive() then break end
    if Message.isOpen and Message.isOpen() then
      if not sawIntro then
        sawIntro = true
        U.wait(30)
        U.still(game, DIR .. "/01_twin_intro.png")
      end
      U.tap(game, "a")
    end
    U.wait(3)
  end
  result(sawIntro, "the twin's intro speech shows")
  if not result(Battle.isActive(), "trainerbattle double started the battle") then return finish() end
  local st = Battle._st
  result(st.double == true and st.battlersCount == 4, "battle is double with 4 battlers")
  result(not (st.kinds and st.kinds.twoOpponents), "one trainer row: not a two-opponent battle")
  result(st.battlers[3] ~= nil and not st.absent[3], "opponent right flank present")
  local flags = require("src.core.game3.battle.ai").flagsFor(st)
  result(require("bit").band(flags, 0x80) ~= 0, string.format("AI_SCRIPT_DOUBLE_BATTLE ORed in (0x%X)", flags))

  local shots = {}
  local done, why = L.run(game, {
    onFrame = function(s, phase)
      if phase == "command" and not shots.cmd and Ui._mode == "menu" then
        shots.cmd = true
        U.wait(10)
        U.still(game, DIR .. "/02_command.png")
      end
      if phase == "animating" and not shots.anim then
        shots.anim = true
        U.wait(12)
        U.still(game, DIR .. "/03_mid_turn.png")
      end
    end,
  })
  result(done, "battle finished " .. tostring(why or ""))
  result(L.logHas("sent\nout") or L.logHas("sent out"), "intro used the two-mon send-out line")
  result(L.logHas(" and\n") or L.logHas(" and "), "intro names both mons")
  local res = st.result
  result(res == "win", "player won the double battle (" .. tostring(res) .. ")")
  local want = Prize.calcRse(tid, { double = true })
  local gained = (tonumber(session.money) or 0) - moneyBefore
  result(gained == want, string.format("double prize money x2 (gained %d want %d)", gained, want))
  for _ = 1, 600 do
    if not (Space.vm and Space.vm:isRunning()) and not (Message.isOpen and Message.isOpen()) then break end
    U.tap(game, "a")
    U.wait(3)
  end
  result(Flags.getFlag(Space.store, Space.vm and Space.vm.ctx, Flags.trainerFlagId(tid)), "trainer flag set after the win")
  U.wait(30)
  U.still(game, DIR .. "/04_after.png")
  return finish()
end
