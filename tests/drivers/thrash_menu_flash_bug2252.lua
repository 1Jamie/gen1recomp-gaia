-- engine/battle/core.asm:293
--   POKEPORT_IDENTITY=red-sep04 POKEPORT_SHOT_DIR=/tmp/shots POKEPORT_DRIVER=tests/drivers/thrash_menu_flash_bug2252.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local fails = 0
  local function ok(cond, line)
    print((cond and "PASS " or "FAIL ") .. line)
    if not cond then fails = fails + 1 end
  end

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld

  local function startBattle()
    love.math.setRandomSeed(2252)
    local king = Pokemon.new(game.data, "NIDOKING", 60)
    king.moves = { { id = "THRASH", pp = 20 } }
    king.stats.hp, king.hp = 999, 999
    game.save.party = { king }
    local battle = BattleState.newWild(game, "MAGIKARP", 60)
    battle.onFinish = function() end
    battle.enemy.mon.stats.hp, battle.enemy.mon.hp = 999, 999
    ow:pushBattle(battle)
    for _ = 1, 200 do
      if battle.phase == "menu" then break end
      U.tap(game, "a")
      U.wait(4)
    end
    return battle
  end

  local function selectThrash(battle)
    U.tap(game, "a"); U.wait(12)
    U.tap(game, "a")
  end

  local function locked(battle)
    return (battle.player.thrashTurns or 0) > 0
  end

  local battle = startBattle()
  ok(battle.phase == "menu", "2252 pass 1 reached the command menu")
  local startTurn = battle.turnCount or 0
  selectThrash(battle)
  local f, drainFrame, flashes, sawLocked = 0, nil, 0, false
  local lastSig, logged = nil, 0
  for _ = 1, 2400 do
    f = f + 1
    if f % 20 == 0 then U.tap(game, "a") else U.wait(1) end
    local sig = tostring(battle.phase) .. " thrash=" .. tostring(battle.player.thrashTurns)
      .. " turn=" .. tostring(battle.turnCount) .. " top=" .. tostring(game.stack:top() == battle)
    if sig ~= lastSig and logged < 80 then
      U.log("f", f, sig)
      lastSig, logged = sig, logged + 1
    end
    if locked(battle) then sawLocked = true end
    if not drainFrame and (battle.turnCount or 0) >= startTurn + 2 then drainFrame = f end
    if battle.phase == "menu" and locked(battle) then flashes = flashes + 1 end
    if battle.phase == "menu" and not locked(battle) and f > 30 then break end
  end
  U.log("turns", (battle.turnCount or 0) - startTurn, "drainFrame", drainFrame,
    "status", battle.player.mon.status, "confused", battle.player.confusedTurns)
  ok(sawLocked, "2252 player locked into thrash")
  ok(drainFrame ~= nil, "2252 locked turn resolved without input")
  ok(flashes == 0, "2252 no command menu frame while locked (" .. flashes .. ")")
  if game.stack:top() == battle then game.stack:pop() end

  if drainFrame then
    battle = startBattle()
    local replayStartTurn = battle.turnCount or 0
    selectThrash(battle)
    local g, shotBefore, shotDrain, shotAfter = 0, false, false, false
    local beforeSeen, drainSeen, afterSeen = false, false, false
    local phaseAtDrain
    local function fullyTyped(fragment)
      if game.stack:top() ~= battle or battle.phase ~= "messages"
         or not battle.current or (battle.total or 0) <= 0
         or (battle.charIndex or 0) < battle.total
         or (battle.scrollPx or 0) > 0 then return false end
      local text = table.concat(battle:visibleText() or {}, " "):gsub("%s+", " ")
      if not text:find(fragment, 1, true) then return false end
      U.log("2252 fully typed capture", text, "frame", g,
            "turn", battle.turnCount, "thrash", battle.player.thrashTurns)
      return true
    end
    while g < 2400 do
      if not beforeSeen and g < drainFrame
         and (battle.turnCount or 0) == replayStartTurn + 1
         and fullyTyped("used THRASH!") then
        beforeSeen = true
        ok(locked(battle), "2252 used THRASH page is fully typed while locked")
        shotBefore = U.still(game, DIR .. "/2252_01_thrash_text_before_drain.png")
      end
      if not drainSeen and g >= drainFrame then
        drainSeen = true
        phaseAtDrain = battle.phase
        shotDrain = U.still(game, DIR .. "/2252_02_drain_frame_no_menu.png")
      end
      if not afterSeen and (battle.turnCount or 0) >= replayStartTurn + 2
         and fullyTyped("thrashing about!") then
        afterSeen = true
        ok(locked(battle), "2252 thrashing about page is fully typed while locked")
        shotAfter = U.still(game, DIR .. "/2252_03_thrashing_about_text.png")
      end
      if beforeSeen and drainSeen and afterSeen then break end
      g = g + 1
      if g % 20 == 0 then U.tap(game, "a") else U.wait(1) end
    end
    ok(beforeSeen, "2252 fully typed used THRASH page reached before the locked turn")
    ok(afterSeen, "2252 fully typed thrashing about page reached on the locked turn")
    ok(phaseAtDrain ~= "menu", "2252 pass 2 drain frame is not the command menu")
    ok(shotBefore and shotDrain and shotAfter, "2252 shots written")
  end

  love.event.quit(fails == 0 and 0 or 1)
end
