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
  local SB = require("src.core.game3.rse.secret_base")

  if not has("src/core/game3/field.lua", '"interactBg"') then
    local Field = require("src.core.game3.field")
    local orig = Field.interact
    Field.interact = function(game)
      local Runtime = package.loaded["src.core.game3.runtime"]
      local Space = package.loaded["src.core.game3.scripting.space"]
      local P = require("src.core.game3.player")
      local vmBusy = Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning()
      if Field.running and not Field.locked and not vmBusy and not P.moving
          and not (Runtime and Runtime.uiBusy and Runtime.uiBusy()) then
        local x, y = SB.frontOfPlayer()
        if SB.interactBg(x, y, P.facing, nil) then return true end
      end
      return orig(game)
    end
    notes[#notes + 1] = "field.lua interactBg"
  end

  if not has("src/core/game3/player.lua", '"tryDoorWarp"') then
    local Player = require("src.core.game3.player")
    local orig = Player.tryMove
    Player.tryMove = function(dir, game, run)
      if dir == "up" and Player.facing == "up" and not Player.moving and (Player.turnTimer or 0) <= 0 then
        if SB.tryDoorWarp(game, Player.cellX, Player.cellY - 1) then return "secret_base_door" end
      end
      return orig(dir, game, run)
    end
    notes[#notes + 1] = "player.lua tryDoorWarp"
  end

  if not has("src/core/game3/scripting/space.lua", '"onMapLoad"') then
    local Space = require("src.core.game3.scripting.space")
    local enter, onLoad = Space.runEnterScripts, Space.runOnLoad
    local enterVia
    Space.runEnterScripts = function(mod, mapId, game, world, opts)
      enterVia = opts and opts.enterVia
      return enter(mod, mapId, game, world, opts)
    end
    Space.runOnLoad = function(mapId)
      local Runtime = package.loaded["src.core.game3.runtime"]
      local sess = Runtime and Runtime.getSession and Runtime.getSession()
      if sess then SB.onMapLoad(sess, nil, enterVia) end
      return onLoad(mapId)
    end
    notes[#notes + 1] = "space.lua onMapLoad"
  end

  local save = require("src.core.game3.profile").of("emerald").save
  local listed = false
  for _, e in ipairs(save.sections or {}) do
    if e == "secretBases" or (type(e) == "table" and e.name == "secretBases") then listed = true end
  end
  if not listed then
    save.sections[#save.sections + 1] = { name = "secretBases", module = "src.core.game3.rse.secret_base" }
    notes[#notes + 1] = "profiles/emerald/save.lua secretBases"
  end

  for _, n in ipairs(notes) do print("NOTE crossfile hook shim active: " .. n) end
  return notes
end

return H
