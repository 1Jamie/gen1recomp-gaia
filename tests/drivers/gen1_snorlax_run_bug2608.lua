-- pokered/scripts/Route12.asm:45
-- pokered/scripts/Route16.asm:46
-- pokered/engine/battle/core.asm:1584
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Commands = require("src.script.Commands")
  local BattleState = require("src.battle.BattleState")
  local scripts = require("data.scripts.init")
  local dir = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local fails, activeOw, texts = 0, nil, {}
  local showText = Commands.show_text
  Commands.show_text = function(ctx, textId, ...)
    if ctx.overworld == activeOw then texts[#texts + 1] = textId end
    return showText(ctx, textId, ...)
  end
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function shot(name)
    check(name .. "_capture", U.still(game, dir .. "/2608_" .. name .. ".png"))
  end
  local function npcNamed(ow, name)
    for _, npc in ipairs(ow.npcs) do
      if npc.def.name == name then return npc end
    end
  end
  local function setup(route)
    local mapId = "ROUTE_" .. route
    local wake = scripts.get(mapId).snorlaxWake
    local mon = Pokemon.new(game.data, "MEWTWO", 100, function(_, high) return high end)
    mon.moves = { { id = "SWIFT", pp = game.data.moves.SWIFT.pp } }
    game.save.party = { mon }
    game.save.flags[wake.beatFlag] = nil
    game.save.objectToggles[mapId] = { [wake.objName] = true }
    activeOw = nil
    U.teleport(game, mapId, 10, 10, "left")
    local npc = npcNamed(game.overworld, wake.objName)
    if not check("route" .. route .. "_snorlax_exists", npc ~= nil) then return end
    U.teleport(game, mapId, npc.cellX + 1, npc.cellY, "left")
    U.wait(20)
    local ow = game.overworld
    npc = npcNamed(ow, wake.objName)
    if not check("route" .. route .. "_snorlax_adjacent", npc and
      math.abs(npc.cellX - ow.player.cellX) + math.abs(npc.cellY - ow.player.cellY) == 1)
      then return end
    activeOw, texts = ow, {}
    ow.runner:run(wake.script, { npc = npc })
    return ow, wake, npc.cellX, npc.cellY
  end
  local function menu(label)
    for _ = 1, 1800 do
      local top = game.stack:top()
      if getmetatable(top) == BattleState and top.phase == "menu" then return top end
      if top and (top.isTextBox or getmetatable(top) == BattleState) then
        U.tap(game, "a")
        U.wait(2)
      else
        U.wait(1)
      end
    end
    check(label .. "_battle_menu_reached", false)
  end
  local function settle(ow, label)
    for _ = 1, 1800 do
      if game.stack:top() == ow and not ow.runner:isRunning() then return true end
      local top = game.stack:top()
      if top and (top.isTextBox or getmetatable(top) == BattleState) then
        U.tap(game, "a")
        U.wait(2)
      else
        U.wait(1)
      end
    end
    check(label .. "_wake_script_completed", false)
    return false
  end

  game.save.flags = game.save.flags or {}
  game.save.objectToggles = game.save.objectToggles or {}
  game.save.player.name = "RED"
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
  game.save.flags.EVENT_GOT_POKEDEX = true

  for _, route in ipairs({ "12", "16" }) do
    local label = "route" .. route
    local ow, wake, clearedX, clearedY = setup(route)
    if ow then
      local battle = menu(label)
      if battle then
        check(label .. "_real_snorlax_battle", battle.kind == "wild"
          and battle.enemy.mon.species == "SNORLAX" and battle.enemy.mon.level == 30)
        check(label .. "_healthy_fast_party", battle.player.mon.hp > 0
          and battle.player.mon.stats.speed > battle.enemy.mon.stats.speed)
        U.tap(game, "up")
        U.tap(game, "left")
        U.tap(game, "down")
        U.tap(game, "right")
        check(label .. "_run_cursor_selected", battle.menuIndex == 4)
        U.tap(game, "a")
        check(label .. "_actual_escape_result", battle.result == "run" and battle.playerRan == true)
        if settle(ow, label) then
          check(label .. "_wake_script_completed", not ow.runner:isRunning())
          check(label .. "_run_suppresses_farewell", #texts == 1 and texts[1] == wake.script[1][2])
          check(label .. "_run_sets_beat_flag", game.save.flags[wake.beatFlag] == true)
          check(label .. "_run_keeps_snorlax_hidden",
            game.save.objectToggles[ow.map.id][wake.objName] == false
            and npcNamed(ow, wake.objName) == nil)
          check(label .. "_post_run_overworld", game.stack:top() == ow)
          shot(label .. "_post_run_no_farewell")
          U.tap(game, "left")
          U.wait(30)
          check(label .. "_walks_into_cleared_snorlax_cell", game.stack:top() == ow
            and ow.player.cellX == clearedX and ow.player.cellY == clearedY)
        end
      end
    end
  end

  local ow, wake = setup("16")
  if ow then
    local battle = menu("route16_defeat")
    if battle then
      local farewell
      local moves = 0
      for _ = 1, 3600 do
        local top = game.stack:top()
        if top and top.isTextBox and texts[#texts] == wake.script[6][2] then
          farewell = top
          break
        end
        if top == battle and battle.phase == "menu" then
          U.tap(game, "up")
          U.tap(game, "left")
          U.tap(game, "a")
        elseif top == battle and battle.phase == "moveSelect" then
          moves = moves + 1
          if moves > 6 then break end
          U.tap(game, "a")
        elseif top and (top.isTextBox or top == battle) then
          U.tap(game, "a")
          U.wait(2)
        else
          U.wait(1)
        end
      end
      check("route16_defeat_actual_win", battle.result == "win")
      if check("route16_defeat_farewell_opened", farewell ~= nil) then
        for _ = 1, 900 do
          if farewell.done and farewell.pageIndex == #farewell.pages then break end
          if farewell.waiting or farewell.done then U.tap(game, "a") else U.wait(1) end
        end
        local typed = game.stack:top() == farewell and farewell.done
                      and farewell.pageIndex == #farewell.pages
        if check("route16_defeat_farewell_fully_typed", typed) then
          local visible = farewell:visibleText() or {}
          U.log("farewell visible:", table.concat(visible, " / "))
          shot("route16_defeat_farewell_fully_typed")
        end
        check("route16_defeat_two_script_texts", #texts == 2
          and texts[1] == wake.script[1][2] and texts[2] == wake.script[6][2])
        if settle(ow, "route16_defeat") then
          check("route16_defeat_sets_beat_flag", game.save.flags[wake.beatFlag] == true)
          check("route16_defeat_snorlax_hidden", npcNamed(ow, wake.objName) == nil)
        end
      end
    end
  end

  Commands.show_text = showText
  U.log("RESULT", fails == 0 and "PASS" or "FAIL", "gen1_snorlax_run_bug2608", "failures=" .. fails)
  love.event.quit(fails == 0 and 0 or 1)
end
