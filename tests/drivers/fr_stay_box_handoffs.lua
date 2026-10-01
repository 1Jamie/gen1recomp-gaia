local U = require("tests.drivers.util")
local L = require("tests.drivers.em_battle_loop")

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " fr_stay_box_handoffs failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  U.wait(10)
end

return function(game)
  io.stdout:setvbuf("line")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Party = require("src.core.game3.party")
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Field = require("src.core.game3.field")
  local Battle = require("src.core.game3.battle")
  local Encounters = require("src.core.game3.encounters")
  local C = require("src.core.game3.constants").of("firered")
  local session = Runtime.getSession()
  if not result(session ~= nil, "field session exists") then return finish() end
  Encounters.onStep = function() return nil end
  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_BLASTOISE, 40, "")

  local function running() return Space.vm and Space.vm:isRunning() end
  local function untilTrue(fn, frames, step)
    for _ = 1, frames do
      if fn() then return true end
      U.wait(step or 2)
    end
    return fn() and true or false
  end
  local function answerYes()
    local opened = untilTrue(function()
      if Choice.isOpen and Choice.isOpen() then return true end
      if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
      return false
    end, 900, 4)
    if opened then U.wait(6); U.tap(game, "a") end
    return opened
  end
  local function load(id, x, y, facing)
    local ok, err = pcall(function() Map.load(nil, game, id, { x = x, y = y, facing = facing }) end)
    result(ok, "load " .. id .. " " .. tostring(err or ""))
    session.map = id
    U.wait(60)
  end

  -- pokefirered/data/maps/CinnabarIsland_PokemonLab_Lounge/scripts.inc:52 special ChoosePartyMon
  local Stack = require("src.ui.game3.stack")
  load("FR_CINNABAR_ISLAND_POKEMON_LAB_LOUNGE", 6, 6, "up")
  local key = Space.scriptKey("g3:0816e33e") or Space.scriptKey("g3:0816e3b6")
  result(key and Space.startScript(key, 1) and true or false, "Norma trade script starts")
  if answerYes() then
    local party = untilTrue(function() return Stack.has("party") or not running() end, 900, 4)
    result(party and Stack.has("party"), "trade: party menu opened")
    result(not Message.isOpen(), "trade: stay box closed at party menu")
    U.tap(game, "b"); U.wait(20)
    untilTrue(function()
      if Message.isOpen() and not Choice.isOpen() then U.tap(game, "a") end
      return not running()
    end, 900, 4)
    result(not running() and not Message.isOpen(), "trade: idle afterwards")
    result(not Field.locked, "trade: field unlocked")
  else
    result(false, "trade: prompt opened")
  end

  load("FR_ROUTE1", 10, 10, "down")
  local synth = "synthetic_stay_wild"
  Space.vm.scripts[synth] = {
    { op = "lockall" },
    { op = "message", ptr = "SafariZone_Text_WouldYouLikeToExit" },
    { op = "setwildbattle", C.species.byName.SPECIES_RATTATA, 3 },
    { op = "dowildbattle" },
    { op = "releaseall" },
    { op = "end" },
  }
  result(Space.startScript(synth) and true or false, "synthetic stay+wild battle starts")
  local inBattle = untilTrue(function() return Battle.isActive() end, 1500, 2)
  result(inBattle, "wild battle started")
  if inBattle then
    result(not Message.isOpen(), "stay+wild: stay box closed once battle is up")
    local over = L.run(game, { turnCap = 60, guard = 60000 })
    result(over, "wild battle ended")
    U.wait(60)
    untilTrue(function()
      if Message.isOpen() then U.tap(game, "a") end
      return not running()
    end, 900, 4)
  end
  result(not Message.isOpen(), "stay+wild: stay box closed after battle")
  result(not Field.locked, "stay+wild: field unlocked")
  finish()
end
