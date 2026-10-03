local U = require("tests.drivers.util")

return function(game)
  local deadline = love.timer.getTime() + 25
  local ok, err = xpcall(function()
    local identity = os.getenv("POKEPORT_IDENTITY") or ""
    assert(identity ~= "" and identity ~= "pokemon-love2d", "isolated native identity required")
    local out = assert(os.getenv("POKEPORT_SHOT_DIR"), "shot directory required")
    local function wait(n)
      for _ = 1, n do assert(love.timer.getTime() < deadline, "#2643 watchdog"); U.wait(1) end
    end
    local function settle(fn, name)
      for _ = 1, 1800 do if fn() then return end; wait(1) end
      error("#2643 did not settle: " .. name)
    end
    settle(function() return game.phase == "boot" and game.boot end, "native boot")
    game:_handleBootAction({ action = "new_game", name = "BRENDAN" })
    local Runtime = require("src.core.game3.runtime")
    local Space = require("src.core.game3.scripting.space")
    local Map = require("src.core.game3.map")
    local Catalog = require("src.import.gba.map_catalog")
    local Version = require("src.core.GameVersion")
    local C = require("src.core.game3.constants").of("emerald")
    local D = require("src.core.game3.rse.frontier.trainers")
    local Util = require("src.core.game3.rse.frontier.util")
    local Rse = require("src.core.game3.rse.init")
    local Message = require("src.ui.game3.message")
    local Stack = require("src.ui.game3.stack")
    assert(Version.get() == "emerald", "READY Emerald cache required")
    settle(function() return Runtime.getSession() and game.phase == "field" end, "native field")
    local Fade = require("src.ui.game3.fade")
    local function uncovered() return not Fade.isActive() and Fade.t == 0 and not Fade.lockInput end
    settle(uncovered, "uncovered new field")
    local session = Runtime.getSession()
    local function fieldReady()
      return Space.vm and not Space.vm:isRunning() and not Message.isOpen() and not Stack.top() and uncovered()
    end
    if os.getenv("H2643_VISUAL_PIKE") == "1" then
      local Pike = require("src.core.game3.rse.frontier.pike")
      local Objects = require("src.core.game3.objects")
      local Field = require("src.core.game3.field")
      local Ow = require("src.core.game3.ow_sprites")
      session.party = {}
      for i = 1, 3 do
        session.party[i] = D.createMon(C:require("species", "SPECIES_SWAMPERT"), 50, 20, i, session.trainerId,
          { otName = session.name })
      end
      local target = Catalog.pretToEngine("BattleFrontier_BattlePikeRoomNormal")
      for _, kind in ipairs({ "STATUS", "DOUBLE_BATTLE" }) do
        Map.load(nil, game, Catalog.pretToEngine("InsideOfTruck"), { x = 2, y = 2, facing = "down" })
        settle(fieldReady, "leave previous Pike callback")
        Pike.rt(session).roomType = Pike.ROOM[kind]
        Pike.rt(session).statusMon = Pike.STATUSMON.DUSCLOPS
        Map.load(nil, game, target, { x = 4, y = 8, facing = "up" })
        session.x, session.y, session.facing = 4, 8, "up"
        local expected = kind == "STATUS" and {48, 226} or {
          D.gfxId(session, session.frontierOpponentA, D.FACILITY.PIKE),
          D.gfxId(session, session.frontierOpponentB, D.FACILITY.PIKE) }
        settle(function()
          return Map.current == target and Space.mapId == target and Objects._mapId == target
            and not Space._inTransition and not Field.callbackPending() and not Space._pendingOnFrame
            and Message.isWaiting() and not Message.isTyping() and not Objects.hasActiveTracks() and uncovered()
        end, "fully typed actual Pike " .. kind .. " introduction")
        for id = 1, 2 do
          local obj = assert(Objects._byId[id], "actual Pike object missing")
          print("STATE #2643 Pike " .. kind .. " object=" .. id .. " cached=" .. tostring(obj.graphicsId)
            .. " resolved=" .. tostring(Space.resolveObjectGraphicsId(obj.def)) .. " expected=" .. expected[id])
          assert(obj.graphicsId == expected[id], "source-spawned Pike graphics " .. kind)
          assert(Space.resolveObjectGraphicsId(obj.def) == 28, "source ON_WARP template reset missing")
        end
        local draw, drawn = Ow.draw, {}
        Ow.draw = function(id, ...)
          drawn[id] = true
          return draw(id, ...)
        end
        local captured = U.still(game, out .. "/pike-" .. kind:lower() .. ".png")
        Ow.draw = draw
        assert(captured, "Pike capture failed")
        assert(drawn[expected[1]] and drawn[expected[2]], "actual Pike renderer must draw source-cached IDs")
        print("PASS #2643 Pike " .. kind .. " actual OwSprites IDs=" .. expected[1] .. "/" .. expected[2]
          .. "; fully typed imported dialogue; visual review remains required")
        if kind == "STATUS" then
          for _ = 1, 1800 do
            if fieldReady() and not Space._pendingOnFrame then break end
            if Message.isWaiting() then U.tap(game, "a") else wait(1) end
          end
          assert(fieldReady() and not Space._pendingOnFrame, "Pike STATUS callbacks did not finish normally")
        end
      end
      return
    end
    session.party = {}
    for i, row in ipairs({
      { "SPECIES_SWAMPERT", { "MOVE_TACKLE", "MOVE_GROWL", "MOVE_PROTECT", "MOVE_COUNTER" } },
      { "SPECIES_METAGROSS", { "MOVE_METEOR_MASH", "MOVE_EARTHQUAKE", "MOVE_PSYCHIC", "MOVE_BRICK_BREAK" } },
      { "SPECIES_SALAMENCE", { "MOVE_DRAGON_CLAW", "MOVE_EARTHQUAKE", "MOVE_FLAMETHROWER", "MOVE_AERIAL_ACE" } },
    }) do
      local mon = D.createMon(C:require("species", row[1]), 50, 20, 99, session.trainerId,
        { otName = session.name })
      local moves = {}
      for slot, name in ipairs(row[2]) do
        moves[slot] = C:require("moves", name)
      end
      D.setMoves(mon, moves)
      session.party[i] = mon
    end
    local Summary = require("src.ui.game3.summary_menu")
    Summary.openMenu(session.party, 1, { page = 2 })
    settle(function() return Summary.isOpen() and not Summary._slide.active end, "four valid moves")
    wait(8)
    settle(uncovered, "uncovered valid Counter moves")
    assert(U.still(game, out .. "/01-valid-counter-moves.png"), "valid Counter team capture failed")
    Summary.close(); wait(8)
    local target = Catalog.pretToEngine("BattleFrontier_BattlePalaceLobby")
    Map.load(nil, game, target, { x = 6, y = 7, facing = "up" })
    session.x, session.y, session.facing = 6, 7, "up"
    settle(fieldReady, "Palace field")
    local Palace = require("src.core.game3.rse.frontier.palace")
    Rse.setVar("VAR_FRONTIER_FACILITY", D.FACILITY.PALACE, session)
    Rse.setVar("VAR_FRONTIER_BATTLE_MODE", 0, session)
    Util.frontier(session).lvlMode = D.LVL.L50
    Palace.init(session)
    Palace.doSpecialBattle(Space.vm.ctx, Space.vm.adapters, session)
    local Battle = require("src.core.game3.battle")
    local Ui = require("src.core.game3.battle.ui")
    local Anim = require("src.core.game3.battle.anim")
    local introState
    for _ = 1, 1800 do
      if Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" then break end
      local state = Battle.getState()
      assert(not state or state.turn == 0, "Palace intro advanced past initial turn")
      local diagnosis = tostring(Battle._phase) .. "/" .. tostring(Ui._mode)
      if diagnosis ~= introState then
        print("STATE #2643 Palace intro " .. diagnosis .. " turn=" .. tostring(state and state.turn))
        introState = diagnosis
      end
      if (Battle._phase == "intro" or Battle._phase == "startfx") and Ui.dialogPending() then
        U.tap(game, "a")
      else wait(1) end
    end
    assert(Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu",
      "Palace first command missing: " .. tostring(Battle._phase) .. "/" .. tostring(Ui._mode))
    local st = assert(Battle.getState())
    assert(st.facility and st.facility.kind == "palace" and st.turn == 0, "actual Palace first-turn facility missing")
    assert(not st.player.lastMove and not st.enemy.lastMove, "initial last-move sentinel missing")
    settle(uncovered, "uncovered Palace turn zero")
    assert(U.still(game, out .. "/02-palace-turn-zero.png"), "Palace initial capture failed")
    local movesMenu = false
    for _ = 1, 10000 do
      assert(Battle.isActive(), "first Palace turn ended the battle unexpectedly")
      st = Battle.getState()
      if st.turn >= 1 and Battle._phase == "command" and Ui._mode == "menu" then break end
      if Ui._mode == "moves" then movesMenu = true end
      for _, action in ipairs(Battle._actions or {}) do
        if action.kind == "move" then assert(action.move and action.move ~= 0, "MOVE_NONE became an action") end
      end
      if Anim.vm() and Anim.vm():busy() then wait(1) else U.tap(game, "a"); wait(3) end
    end
    assert(st.turn >= 1 and Battle._phase == "command" and Ui._mode == "menu", "Palace first turn did not finish")
    assert((st.facility.choices or 0) >= 2 and not movesMenu, "Palace automatic real choices not exercised")
    settle(uncovered, "uncovered Palace first turn")
    assert(U.still(game, out .. "/03-palace-first-turn-complete.png"), "Palace first-turn capture failed")
    print("PASS #2643 actual Palace first turn with compact valid Counter team, imported AI, automatic choices and strict real actions")
  end, debug.traceback)
  if not ok then print("FAIL #2643 " .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
  while true do coroutine.yield() end
end
