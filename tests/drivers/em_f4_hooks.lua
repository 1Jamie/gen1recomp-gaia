local H = {}

local function source(path)
  local f = io.open(path, "rb")
  if not f then return "" end
  local s = f:read("*a")
  f:close()
  return s
end

local function has(path, needle)
  return source(path):find(needle, 1, true) ~= nil
end

function H.install()
  local notes = {}
  local Rse = require("src.core.game3.rse.init")
  local Py = require("src.core.game3.rse.frontier.pyramid")
  local Hill = require("src.core.game3.rse.trainer_hill")
  local EI = require("src.core.game3.rse.event_islands")

  if not has("src/core/game3/map.lua", '"pyramid", "onMapLoad"') then
    local Map = require("src.core.game3.map")
    local orig = Map.load
    Map.load = function(mod, game, mapId, opts)
      opts = opts or {}
      local def = game and game.data and game.data.maps and game.data.maps[mapId]
      if def then
        Map.ensureMidLayout(game, mapId, def)
        Py.onMapLoad(nil, mapId, def, opts)
        Hill.onMapLoad(nil, mapId, def, opts)
      end
      return orig(mod, game, mapId, opts)
    end
    notes[#notes + 1] = "map.lua pyramid/trainerHill onMapLoad"
  end

  if not has("src/core/game3/step_events.lua", '"incrementStepCount"') then
    local StepEvents = require("src.core.game3.step_events")
    local orig = StepEvents.onStepTaken
    StepEvents.onStepTaken = function(session, game)
      local r = orig(session, game)
      if session and Rse.isRse(session) then
        local P = require("src.core.game3.player")
        EI.incrementStepCount(session)
        Py.onStep(session, P.cellX, P.cellY)
      end
      return r
    end
    notes[#notes + 1] = "step_events.lua incrementStepCount/onStep"
  end

  if not has("src/core/game3/bag.lua", "bagActive") then
    local Bag = require("src.core.game3.bag")
    local function redirect(bag)
      local s = Rse.session()
      return s and bag ~= nil and bag == s.bag and Py.bagActive(s) and s or nil
    end
    local add, remove, get, canAdd = Bag.add, Bag.remove, Bag.get, Bag.canAdd
    Bag.add = function(bag, id, qty)
      local s = redirect(bag)
      if s then
        local ok = Py.bagAdd(s, id, qty or 1)
        return ok, ok and (qty or 1) or 0
      end
      return add(bag, id, qty)
    end
    Bag.remove = function(bag, id, qty)
      local s = redirect(bag)
      if s then return Py.bagRemove(s, id, qty or 1) end
      return remove(bag, id, qty)
    end
    Bag.get = function(bag, id)
      local s = redirect(bag)
      if s then return Py.bagCount(s, id) end
      return get(bag, id)
    end
    Bag.canAdd = function(bag, id, qty)
      local s = redirect(bag)
      if s then return Py.bagHasSpace(s, id, qty or 1) end
      return canAdd(bag, id, qty)
    end
    notes[#notes + 1] = "bag.lua pyramid bag redirect"
  end

  for _, n in ipairs(notes) do print("NOTE crossfile hook shim active: " .. n) end
  return notes
end

return H
