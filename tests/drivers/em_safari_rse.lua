local U = require("tests.drivers.util")
local L = require("tests.drivers.em_battle_loop")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_safari_rse"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_safari_rse failures=" .. failures)
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
  local Bag = require("src.core.game3.bag")
  local Space = require("src.core.game3.scripting.space")
  local Rse = require("src.core.game3.rse.init")
  local Encounters = require("src.core.game3.encounters")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Battle = require("src.core.game3.battle")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Ui = require("src.core.game3.battle.ui")
  local Safari = require("src.core.game3.safari")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not result(session ~= nil, "field session exists") then return finish() end
  Encounters.onStep = function() return nil end

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_SWAMPERT, 40, "")
  session.money = 3000
  Bag.add(session.bag, C.items.byName.ITEM_POKEBLOCK_CASE, 1)

  local ok, err = pcall(function()
    Map.load(nil, game, "EM_ROUTE121_SAFARI_ZONE_ENTRANCE", { x = 9, y = 4, facing = "left" })
  end)
  if not result(ok, "Safari Zone entrance loads " .. tostring(err or "")) then return finish() end
  U.wait(30)
  U.hold(game, "left", 8)
  local entered = false
  for _ = 1, 3000 do
    if Map.current == "EM_SAFARI_ZONE_SOUTH" and not (Space.vm and Space.vm:isRunning()) then entered = true break end
    if Choice.isOpen and Choice.isOpen() then
      U.wait(4)
      U.tap(game, "a")
    elseif Message.isOpen and Message.isOpen() then
      U.tap(game, "a")
    end
    U.wait(2)
  end
  result(entered, "paying at the counter warps into Safari Zone South (" .. tostring(Map.current) .. ")")
  result(Safari.isActive(session), "EnterSafariMode sets FLAG_SYS_SAFARI_MODE")
  result(Safari.balls(session) == 30 and Safari.steps(session) == 500, "30 SAFARI BALLS, 500 steps (safari_zone.c:60)")
  result(session.money == 2500, "500 paid")
  U.wait(30)
  U.still(game, DIR .. "/01_safari_zone_south.png")
  Safari.takeStep(session, game)
  result(Safari.steps(session) == 499, "a step spends one of the 500")

  local blocks = 0
  Rse.register("pokeblock", {
    chooseForBattle = function(_, done)
      blocks = blocks + 1
      done({ name = "RED POKeBLOCK", flavors = { 30, 0, 0, 0, 0 } })
    end,
  })

  local RomText = require("src.core.game3.rom_text")
  if not RomText.has("gText_HighlightRed_Left") then
    print("[driver] healthbox.lua reads the FR-only gText_HighlightRed_Left (crossfile W3a-B2); shimmed to gText_SafariBallLeft")
    local plain = RomText.plain
    RomText.plain = function(key, ...)
      if key == "gText_HighlightRed_Left" then return plain("gText_SafariBallLeft") end
      return plain(key, ...)
    end
  end

  local started = BattleBridge.startWild(Runtime._mod, game,
    { species = C.species.byName.SPECIES_PIKACHU, level = 25 }, {})
  if not result(started, "wild battle starts in the safari zone") then return finish() end
  for _ = 1, 600 do
    if Battle.isActive() then break end
    U.wait(2)
  end
  local st = Battle._st
  result(st and st.safari and st.safariState and st.safariState.rse, "battle is an RSE safari battle")
  result(st.safariState.escapeFactor == 3, "escape factor starts at 3 (battle_main.c:3116)")
  local catchStart = st.safariState.catchFactor

  local function command(index)
    for _ = 1, 3000 do
      if not Battle.isActive() then return false end
      if Battle._phase == "command" and Ui._mode == "menu" then break end
      if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
    end
    if not Battle.isActive() then return false end
    Ui._menuIndex = index
    U.wait(4)
    U.tap(game, "a")
    return true
  end

  local shots = {}
  for _ = 1, 3000 do
    if Battle._phase == "command" and Ui._mode == "menu" then break end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
  end
  U.wait(10)
  U.still(game, DIR .. "/02_safari_menu.png")

  command(3)
  U.wait(20)
  result(L.logHas("crept closer"), "GO NEAR: sText_CreptCloser")
  result(st.safariState.goNearCounter == 1, "go near counter 1")
  result(st.safariState.catchFactor == math.min(20, catchStart + 4), "catch factor +4 (sGoNearCounterToCatchFactor)")
  result(st.safariState.escapeFactor == 7 or not Battle.isActive(), "escape factor +4")
  U.still(game, DIR .. "/03_crept_closer.png")

  if not (Battle.isActive() and command(2)) then
    print("[driver] the wild mon fled before the POKeBLOCK turn (Random() % 100 < escapeFactor * 5); checks skipped")
  else
    for _ = 1, 600 do
      if L.logHas("POKeBLOCK") or L.logHas("POKéBLOCK") or not Battle.isActive() then break end
      if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
    end
    result(blocks == 1, "POKéBLOCK asks the pokeblock case system")
    result(L.logHas("threw a"), "sText_ThrewPokeblockAtPkmn")
    result(L.logHas("curious about") or L.logHas("enthralled by") or L.logHas("completely ignored"),
      "gSafariPokeblockResultStringIds reaction")
    result(st.safariState.pkblThrowCounter == 1, "pokeblock throw counter 1")
    U.wait(10)
    U.still(game, DIR .. "/04_pokeblock.png")
  end

  local ballsBefore = Safari.balls(session)
  local threw = 0
  while Battle.isActive() and threw < 30 do
    if not command(1) then break end
    threw = threw + 1
    for _ = 1, 3000 do
      if not Battle.isActive() then break end
      if Battle._phase == "command" and Ui._mode == "menu" then break end
      if Battle._phase == "catching" and not shots.ball then
        shots.ball = true
        U.wait(60)
        U.still(game, DIR .. "/05_safari_ball.png")
      end
      if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
      if Ui.choiceActive and Ui.choiceActive() then U.tap(game, "b") end
    end
  end
  local ballsNow = Safari.balls(session)
  threw = 0
  for _, t in ipairs(Ui.log and Ui.log() or {}) do
    if tostring(t):gsub("\n", " "):find("used SAFARI BALL", 1, true) then threw = threw + 1 end
  end
  if not result(ballsNow == ballsBefore - threw,
      string.format("each throw spends a SAFARI BALL (threw %d, %d -> %d)", threw, ballsBefore, ballsNow)) then
    L.dumpLog("[driver log]")
  end
  result(L.logHas("watching") or L.logHas("fled") or L.logHas("caught"), "enemy watches carefully or flees")
  result(st.result == "catch" or st.result == "run" or st.result == "fled" or st.result == "no_safari_balls",
    "safari battle ends (" .. tostring(st.result) .. ")")
  for _ = 1, 600 do
    if not (Space.vm and Space.vm:isRunning()) and not Battle.isActive() then break end
    if Message.isOpen and Message.isOpen() then U.tap(game, "a") end
    U.wait(2)
  end
  U.wait(20)
  U.still(game, DIR .. "/06_after.png")
  return finish()
end
