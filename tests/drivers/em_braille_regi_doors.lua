local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("em_braille_regi_doors")
local S = require("tests.drivers.em_story_util")

return function(game)
  local deadline = love.timer.getTime() + 24
  local wait = U.wait
  U.wait = function(n)
    for _ = 1, n do
      assert(love.timer.getTime() < deadline, "Regi door driver exceeded its 24 second budget")
      wait(1)
    end
  end
  local ok, err = xpcall(function()
    if not F.boot(game) then return end
    local Runtime = require("src.core.game3.runtime")
    local Party = require("src.core.game3.party")
    local PartyMenu = require("src.ui.game3.party_menu")
    local Field = require("src.core.game3.field")
    local FieldMoves = require("src.core.game3.field_moves")
    local Collision = require("src.core.game3.collision")
    local Player = require("src.core.game3.player")
    local Objects = require("src.core.game3.objects")
    local ShowMon = require("src.core.game3.field_move_show_mon")
    local Warp = require("src.core.game3.warp")
    local Fade = require("src.ui.game3.fade")
    local Message = require("src.ui.game3.message")
    local Flags = require("src.core.game3.scripting.flags")
    local Space = require("src.core.game3.scripting.space")
    local C = require("src.core.game3.constants").of("emerald")
    local fl, session = F.flags(), Runtime.getSession()
    if not F.check(session.version == "emerald", "Emerald puzzle session") then return end
    session.party = {}
    Party.giveMonToPlayer(session, C:require("species", "SPECIES_SABLEYE"), 40)
    session.party[1].moves = { C:require("moves", "MOVE_ROCK_SMASH"), C:require("moves", "MOVE_FLASH") }
    session.party[1].pp = { 15, 20 }
    session.party[1].maxPp = { 15, 20 }
    for _, badge in ipairs(Flags.forVersion("emerald").BADGES) do
      if badge.fieldMove == "ROCK_SMASH" or badge.fieldMove == "FLASH" then
        Flags.setFlag(Space.store, nil, badge.flag, true)
      end
    end
    fl.set("FLAG_SYS_REGIROCK_PUZZLE_COMPLETED", false)
    fl.set("FLAG_SYS_REGISTEEL_PUZZLE_COMPLETED", false)

    local function idle()
      for _ = 1, 600 do
        if not S.busy() and not ShowMon.isActive() and not PartyMenu.isOpen()
            and not Fade.isActive() and (Fade.t or 0) == 0 then return true end
        U.wait(1)
      end
      return false
    end

    local function shot(name)
      if not F.check(idle(), name .. " complete field frame") then return false end
      return F.check(F.shot(game, name .. ".png", true), name .. " saved screenshot")
    end

    local function closedDoor(case)
      local layout = game.data.maps[case.map].midLayout
      for y = 19, 20 do
        local label = y == 19 and "METATILE_Cave_EntranceCover" or "METATILE_Cave_SealedChamberBraille_Mid"
        for x = 7, 9 do
          F.check(layout:midAt(x, y) == C:require("metatile_labels", label)
              and layout:collAt(x, y) == 7, case.name .. " closed doorway at " .. x .. "," .. y)
        end
      end
    end

    local function openDoor(case, tag, written)
      local layout = game.data.maps[case.map].midLayout
      for row, vertical in ipairs({ "Top", "Bottom" }) do
        for column, horizontal in ipairs({ "Left", "Mid", "Right" }) do
          local x, y = column + 6, row + 18
          local tile = C:require("metatile_labels", "METATILE_Cave_SealedChamberEntrance_" .. vertical .. horizontal)
          F.check(layout:midAt(x, y) == tile, case.name .. " " .. tag .. " ROM tile " .. vertical .. horizontal)
          if written then
            F.check((layout:collAt(x, y) == 7) == (row == 2 and column ~= 2),
                case.name .. " " .. tag .. " collision " .. vertical .. horizontal)
          else
            local base = layout.cells[y * layout.width + x + 1]
            F.check(base and base.mid == tile and layout:collAt(x, y) == base.coll,
                case.name .. " " .. tag .. " original map collision " .. vertical .. horizontal)
          end
          if written then
            local override = Field.metatileOverrideAt(case.map, x, y)
            F.check(override and override.metatile == tile, case.name .. " " .. tag .. " field effect wrote " .. vertical .. horizontal)
          end
        end
      end
    end

    for _, case in ipairs({
      { name = "regirock", map = "EM_DESERT_RUINS", move = "ROCK_SMASH", x = 6, y = 23,
        flag = "FLAG_SYS_REGIROCK_PUZZLE_COMPLETED", other = "FLAG_SYS_REGISTEEL_PUZZLE_COMPLETED" },
      { name = "registeel", map = "EM_ANCIENT_TOMB", move = "FLASH", x = 8, y = 25,
        flag = "FLAG_SYS_REGISTEEL_PUZZLE_COMPLETED", other = "FLAG_SYS_REGIROCK_PUZZLE_COMPLETED" },
    }) do
      if not F.check(F.goTo(game, case.map, 8, 22, "up", { keepScripts = true }) and idle(),
          case.name .. " map and original on-load script finish") then return end
      closedDoor(case)
      shot(case.name .. "_before_closed_door")
      if not F.check(S.goTo(game, { case.x, case.y }, { tries = 4, settle = { limit = 600 } }),
          case.name .. " walks to exact unopened puzzle coordinates") then return end
      local actors, flashBefore, otherBefore = {}, fl.get("FLAG_SYS_USE_FLASH"), fl.get(case.other)
      for _, id in ipairs(Objects.listActive()) do actors[id] = Objects.find(id) end
      F.check(not fl.get(case.flag), case.name .. " completion flag starts unset")
      PartyMenu.show(session.party, nil, { session = session, slot = 1 })
      PartyMenu.cursor = 1
      U.tap(game, "a")
      local index
      local moveId = C:require("moves", "MOVE_" .. case.move)
      for i, action in ipairs(PartyMenu.ACTIONS or {}) do
        if FieldMoves.normalizeMoveId(action) == moveId then index = i end
      end
      if not F.check(index ~= nil, case.name .. " actual party action menu offers " .. case.move) then return end
      for _ = 1, 16 do
        if PartyMenu.actionCursor == index then break end
        U.tap(game, "down")
      end
      if not F.check(PartyMenu.actionCursor == index, case.name .. " selects " .. case.move) then return end
      U.tap(game, "a")
      local sawMon, finished, frames = false, false, 0
      for _ = 1, 1200 do
        sawMon = sawMon or ShowMon.isActive()
        if sawMon and not ShowMon.isActive() and not Warp.isBusy() and not Field.locked
            and not PartyMenu.isOpen() and not Message.isOpen() then finished = true; break end
        frames = frames + 1
        U.wait(1)
      end
      F.check(sawMon, case.name .. " party action plays the selected mon animation")
      if not F.check(finished, case.name .. " puzzle animation finishes and unlocks controls frames=" .. frames) then return end
      F.check(session.map == case.map and Player.cellX == case.x and Player.cellY == case.y,
          case.name .. " remains at the puzzle after the party move")
      F.check(fl.get(case.flag), case.name .. " real party move sets completion flag")
      F.check(fl.get(case.other) == otherBefore, case.name .. " preserves the sibling completion flag")
      F.check(fl.get("FLAG_SYS_USE_FLASH") == flashBefore, case.name .. " leaves ordinary Flash flag unchanged")
      for id, actor in pairs(actors) do
        F.check(Objects.find(id) == actor, case.name .. " puzzle preserves native actor " .. id)
      end
      openDoor(case, "opened", true)
      if not F.check(S.goTo(game, { 8, 22 }, { tries = 4, settle = { limit = 600 } }),
          case.name .. " walks back to the opened doorway") then return end
      shot(case.name .. "_after_party_move_open_door")
      if not F.check(F.goTo(game, case.map, 8, 22, "up", { keepScripts = true }) and idle(),
          case.name .. " reloads with actual on-load script") then return end
      F.check(fl.get(case.flag), case.name .. " completion flag survives reload")
      openDoor(case, "reloaded", false)
      F.check(Collision.isWalkable(8, 20), case.name .. " reloaded bottom-center doorway is walkable")
      local warp = Collision.warpAt(8, 20)
      local arrival = warp and game.data.maps[case.map].warps[warp.destWarp]
      if not F.check(warp and warp.destMap == case.map and arrival and arrival.x == 8 and arrival.y == 11,
          case.name .. " original same-map doorway warp leads to inner room at 8,11") then return end
      shot(case.name .. "_reloaded_open_door")
      if not F.check(S.goTo(game, { 8, 21 }, { tries = 4, settle = { limit = 600 } }),
          case.name .. " walks up to the original doorway warp") then return end
      S.step(game, "up")
      if not F.check(idle() and session.map == case.map and Player.cellX == arrival.x and Player.cellY == arrival.y,
          case.name .. " actually walks through the center doorway") then return end
      shot(case.name .. "_walked_through_door")
    end
  end, debug.traceback)
  U.wait = wait
  if not ok then F.check(false, "driver error: " .. tostring(err)) end
  F.finish()
end
