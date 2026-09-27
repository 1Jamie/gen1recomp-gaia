local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_ingame_trade", "/tmp/em_ingame_trade")

local function mod(name) return require(name) end

local function firstWarp(game, mapId)
  local def = game.data and game.data.maps and game.data.maps[mapId]
  local w = def and def.warps and def.warps[1]
  return w and tonumber(w.x), w and tonumber(w.y)
end

return function(game)
  local session = M.boot(game, d)
  if not session then return d.finish() end
  local PartyMenu = mod("src.ui.game3.party_menu")
  local Stack = mod("src.ui.game3.stack")
  local Scene = mod("src.core.game3.trade_scene")
  local Trade = mod("src.core.game3.scripting.natives_trade")

  local partyPick = 1
  local sawScene, sawSummary, sawRelearner = false, false, false
  local n = 0
  local function ui()
    local top = Stack.top()
    if PartyMenu.isOpen and PartyMenu.isOpen() then
      U.wait(10)
      PartyMenu.cursor = partyPick
      U.tap(game, "a")
      U.wait(10)
      return true
    end
    if Scene.isOpen() then
      if not sawScene then
        sawScene = true
        U.wait(240)
        d.shot(game, "00_trade_scene")
      end
    end
    if top and top.id == "summary" then sawSummary = true end
    if top and top.id == "move_relearner" then sawRelearner = true end
    if top then
      n = n + 1
      if n % 8 == 0 then U.tap(game, "a") else U.wait(1) end
      return true
    end
    return false
  end

  local function visit(mapId, label)
    local x, y = firstWarp(game, mapId)
    M.goTo(game, mapId, x, y - 1, "up")
    local eo = S.objectByScript(label)
    if not d.check(eo ~= nil, label .. " is in " .. mapId) then return false end
    if not d.check(S.talkTo(game, eo), "talked to " .. label) then return false end
    return true
  end

  -- pokeemerald/data/maps/RustboroCity_House1/scripts.inc:4
  local entry = Trade.entry(0)
  d.check(entry and entry.nickname == "DOTS", "INGAME_TRADE_SEEDOT is DOTS from the Emerald cache")
  session.party = {}
  mod("src.core.game3.party").giveMon(session, entry.requestedSpecies, 12, "")
  S.giveMon("SPECIES_MUDKIP", 12)
  if visit("EM_RUSTBORO_CITY_HOUSE1", "RustboroCity_House1_EventScript_Trader") then
    partyPick = 1
    S.settle(game, { limit = 6000, onIdleUi = ui })
    d.shot(game, "01_after_trade")
    local got = session.party[1]
    d.check(sawScene, "DoInGameTradeScene played the trade scene")
    d.check(got and tonumber(got.species) == entry.species, "party slot 1 now holds the traded mon (" .. tostring(got and got.species) .. ")")
    d.check(got and got.nickname == "DOTS", "the traded mon is nicknamed DOTS")
    d.check(got and got.otName == "KOBE" and got.otId == entry.otId, "OT KOBE and the trader's OT ID")
    d.check(got and got.contest and got.contest.cool == entry.conditions[1] and got.contest.sheen == entry.sheen,
      "contest conditions and sheen copied (trade.c:4571)")
    d.check(S.flag("FLAG_RUSTBORO_NPC_TRADE_COMPLETED"), "FLAG_RUSTBORO_NPC_TRADE_COMPLETED")
  end

  -- pokeemerald/data/maps/LilycoveCity_MoveDeletersHouse/scripts.inc:4
  local mon = session.party[2]
  S.setMoves(mon, { "MOVE_TACKLE", "MOVE_GROWL", "MOVE_WATER_GUN" })
  if visit("EM_LILYCOVE_CITY_MOVE_DELETERS_HOUSE", "LilycoveCity_MoveDeletersHouse_EventScript_MoveDeleter") then
    partyPick = 2
    S.settle(game, { limit = 6000, onIdleUi = ui })
    d.check(sawSummary, "MoveDeleterChooseMoveToForget opened the move-select summary")
    local moves = {}
    for i = 1, 4 do moves[i] = tonumber(mon.moves[i]) or 0 end
    d.check(moves[1] == S.move("MOVE_GROWL") and moves[2] == S.move("MOVE_WATER_GUN") and moves[3] == 0,
      "MoveDeleterForgetMove removed TACKLE and shifted the rest (" .. table.concat(moves, ",") .. ")")
  end

  -- pokeemerald/data/maps/FallarborTown_MoveRelearnersHouse/scripts.inc:4
  S.giveItem("ITEM_HEART_SCALE", 1)
  if visit("EM_FALLARBOR_TOWN_MOVE_RELEARNERS_HOUSE", "FallarborTown_MoveRelearnersHouse_EventScript_MoveRelearner") then
    partyPick = 2
    S.settle(game, { limit = 6000, onIdleUi = ui })
    d.check(sawRelearner, "TeachMoveRelearnerMove opened the move relearner")
    local count = 0
    for i = 1, 4 do if (tonumber(mon.moves[i]) or 0) ~= 0 then count = count + 1 end end
    d.check(count == 3, "the relearned move filled the free slot (" .. count .. " moves)")
    d.check(not S.hasItem("ITEM_HEART_SCALE"), "the HEART SCALE was handed over")
  end
  d.finish()
end
