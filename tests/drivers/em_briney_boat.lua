local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("em_briney_boat", "/tmp/em_briney_boat")

return function(game)
  if not X.newGame(d, game, 0) then return d.finish() end
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  local Ghosts = require("src.core.game3.ghosts")
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")
  local Fade = require("src.ui.game3.fade")
  local state
  local function monitor()
    if not state then return end
    local s = X.session()
    if s and not state.maps[s.map] then
      state.maps[s.map] = true
      d.note(state.name .. " map " .. s.map .. " VM " .. X.vmWhere())
    end
    local boat, lid
    for id, eo in pairs(Objects._byId) do
      if eo.originMapId == state.origin and eo.originLocalId == state.localId then
        boat, lid = eo, id
        break
      end
    end
    if not boat then return end
    for _, pool in pairs(Ghosts._pools) do
      for _, ghost in pairs(pool.byId) do
        if ghost == boat then state.aliases = state.aliases + 1 end
      end
    end
    local bt = Objects._tracks[lid]
    local pt = Objects._tracks[Objects.PLAYER_LOCAL_ID]
    if Player.visible == false and bt and pt and not bt.done and not pt.done then
      local dx, dy = boat.px - Player.px, boat.py - Player.py
      if state.dx == nil then state.dx, state.dy = dx, dy end
      state.samples = state.samples + 1
      if dx ~= state.dx or dy ~= state.dy then
        state.drift = state.drift + 1
        if state.drift == 1 then
          d.note(string.format("%s drift at %s: expected %s,%s actual %s,%s",
            state.name, s.map, state.dx, state.dy, dx, dy))
        end
      end
    end
  end
  local function waitFor(pred, frames)
    for i = 1, frames do
      if pred() then return true end
      if i % 6 == 0 then table.insert(game.input.pressQueue, "a") end
      U.wait(1)
      game.input.state.a = false
      monitor()
    end
    return pred()
  end
  local function begin(name, origin, localId)
    state = { name = name, origin = origin, localId = localId, maps = {},
      samples = 0, drift = 0, aliases = 0 }
  end
  local function moment(label, file, pred, frames)
    if not d.check(waitFor(pred, frames or 18000), label .. " (VM " .. X.vmWhere() .. ")") then
      return false
    end
    d.check(d.still(game, file), label .. " screenshot")
    return true
  end
  local function finishTrip(mapId, file)
    moment(state.name .. " landing", file, function()
      return not X.scriptRunning() and X.session().map == mapId and Player.visible ~= false
        and not Fade.isActive() and not Fade.lockInput and (Fade.t or 0) <= 0
    end)
    d.check(state.samples > 0, state.name .. " samples sailing every simulation frame (" .. state.samples .. ")")
    d.check(state.drift == 0, state.name .. " boat/player relative pixels remain constant (" .. state.drift .. ")")
    d.check(state.aliases == 0, state.name .. " carried boat absent from every ghost pool (" .. state.aliases .. ")")
    d.check(Player.visible ~= false, state.name .. " player visible after landing")
    state = nil
  end
  local function start(label, localId, facing)
    local key = Space.bundle.labels[label]
    return d.check(key and Space.startScript(key, localId, facing), "cached " .. label .. " starts")
  end
  X.setFlag("FLAG_MR_BRINEY_SAILING_INTRO", true)
  X.setFlag("FLAG_ENABLE_NORMAN_MATCH_CALL", false)
  X.setFlag("FLAG_HIDE_BRINEYS_HOUSE_MR_BRINEY", false)
  X.setFlag("FLAG_HIDE_BRINEYS_HOUSE_PEEKO", false)
  X.setVar("VAR_BRINEY_HOUSE_STATE", 0)
  d.check(X.goTo(d, game, "EM_ROUTE104_MR_BRINEYS_HOUSE", 5, 6, "up"), "Mr. Briney's house loads")
  local briney = Objects.find(1)
  local bx, by = briney and briney.cellX or 5, briney and briney.cellY or 3
  X.goTo(d, game, "EM_ROUTE104_MR_BRINEYS_HOUSE", bx, by + 1, "up")
  begin("Route104 Dad call", "EM_ROUTE104", 7)
  table.insert(game.input.pressQueue, "a")
  moment("Route104 boarded", "90002_route104_boarded.png", function()
    return X.session().map == "EM_ROUTE104" and Player.visible == false
  end)
  moment("Route105 first seam", "90002_route105_first_seam.png", function()
    return X.session().map == "EM_ROUTE105"
  end)
  moment("Dad call fully revealed", "90002_dad_call.png", function()
    return Player.visible == false and Message.isOpen() and not Message.isTyping()
  end)
  moment("Route106 second seam", "90002_route106_second_seam.png", function()
    return X.session().map == "EM_ROUTE106"
  end)
  finishTrip("EM_DEWFORD_TOWN", "90002_dewford_landed.png")
  d.check(X.flag("FLAG_ENABLE_NORMAN_MATCH_CALL"), "first sailing trip enables Dad match call")
  d.check(X.flag("FLAG_HIDE_MR_BRINEY_DEWFORD_TOWN") == false, "Dewford Briney shown after landing")
  for _, trip in ipairs({
    { name = "Dewford Petalburg", label = "DewfordTown_EventScript_SailToPetalburg",
      seam = "EM_ROUTE106", landing = "EM_ROUTE104_MR_BRINEYS_HOUSE", prefix = "90002_petalburg" },
    { name = "Dewford Slateport", label = "DewfordTown_EventScript_SailToSlateport",
      seam = "EM_ROUTE107", landing = "EM_ROUTE109", prefix = "90002_slateport" },
  }) do
    X.setFlag("FLAG_HIDE_MR_BRINEY_DEWFORD_TOWN", false)
    X.setFlag("FLAG_HIDE_MR_BRINEY_BOAT_DEWFORD_TOWN", false)
    d.check(X.goTo(d, game, "EM_DEWFORD_TOWN", 11, 9, "right"), trip.name .. " departure loads")
    begin(trip.name, "EM_DEWFORD_TOWN", 4)
    if start(trip.label, 2, 4) then
      moment(trip.name .. " first seam", trip.prefix .. "_first_seam.png", function()
        return X.session().map == trip.seam and Player.visible == false
      end)
      finishTrip(trip.landing, trip.prefix .. "_landed.png")
    end
  end
  for _, approach in ipairs({
    { name = "south", x = 21, y = 23, facing = "down", dir = 1 },
    { name = "east", x = 20, y = 24, facing = "right", dir = 4 },
    { name = "west", x = 22, y = 24, facing = "left", dir = 3 },
  }) do
    X.setFlag("FLAG_HIDE_ROUTE_109_MR_BRINEY", false)
    X.setFlag("FLAG_HIDE_ROUTE_109_MR_BRINEY_BOAT", false)
    d.check(X.goTo(d, game, "EM_ROUTE109", approach.x, approach.y, approach.facing),
      "Route109 " .. approach.name .. " departure loads")
    begin("Route109 " .. approach.name, "EM_ROUTE109", 1)
    if start("Route109_EventScript_StartDepartForDewford", 2, approach.dir) then
      moment(state.name .. " first seam", "90002_return_" .. approach.name .. "_first_seam.png", function()
        return X.session().map == "EM_ROUTE108" and Player.visible == false
      end)
      finishTrip("EM_DEWFORD_TOWN", "90002_return_" .. approach.name .. "_landed.png")
    end
  end
  d.finish()
end
