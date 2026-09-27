local U = require("tests.drivers.util")

local F = {}

function F.new(name)
  local self = { name = name, failures = 0, dir = os.getenv("POKEPORT_SHOT_DIR") or ("/tmp/" .. name) }

  function self.check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then self.failures = self.failures + 1 end
    return ok
  end

  function self.finish()
    print((self.failures == 0 and "PASS" or "FAIL") .. " " .. name .. " failures=" .. self.failures)
    love.event.quit(self.failures == 0 and 0 or 1)
  end

  function self.try(label, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
    return ok
  end

  function self.shot(game, file, still)
    if still then return U.still(game, self.dir .. "/" .. file) end
    return U.shot(game, self.dir .. "/" .. file)
  end

  function self.boot(game)
    for _ = 1, 900 do
      if game.phase == "boot" and game.boot then break end
      U.wait(1)
    end
    if not self.check(game.boot ~= nil, "boot reached") then return false end
    local ok = self.try("new_game", function()
      game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
    end)
    U.wait(30)
    local Runtime = require("src.core.game3.runtime")
    return self.check(ok and Runtime.getSession() ~= nil, "new game session is live")
  end

  function self.givePartyAndRepel(speciesName, level)
    local Runtime = require("src.core.game3.runtime")
    local Party = require("src.core.game3.party")
    local C = require("src.core.game3.constants").of("emerald")
    local s = Runtime.getSession()
    if s and #(s.party or {}) == 0 then
      Party.giveMonToPlayer(s, C:require("species", speciesName or "SPECIES_TORCHIC"), level or 100)
    end
    self.flags().setVar("VAR_REPEL_STEP_COUNT", 250)
  end

  function self.settle(game, frames)
    local Warp = require("src.core.game3.warp")
    local Message = require("src.ui.game3.message")
    for _ = 1, frames or 600 do
      local busy = Warp.isBusy() or (Message.isOpen and Message.isOpen())
      if not busy then break end
      if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
      U.wait(1)
    end
  end

  function self.haltVm()
    local Space = require("src.core.game3.scripting.space")
    if Space.vm and Space.vm:isRunning() then Space.vm:halt(true) end
    require("src.core.game3.field").unlock()
  end

  function self.goTo(game, mapId, x, y, facing, opts)
    self.settle(game)
    local Map = require("src.core.game3.map")
    local Player = require("src.core.game3.player")
    local Runtime = require("src.core.game3.runtime")
    local ok = self.try("Map.load " .. mapId, function()
      Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    end)
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    Player.cellX, Player.cellY = x, y
    Player.prevCellX, Player.prevCellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    U.wait((opts and opts.wait) or 40)
    if not (opts and opts.keepScripts) then self.haltVm() end
    return ok and s and s.map == mapId
  end

  function self.flags()
    local Flags = require("src.core.game3.scripting.flags")
    local Space = require("src.core.game3.scripting.space")
    local t = Flags.forVersion("emerald")
    return {
      set = function(name, on) Flags.setFlag(Space.store, nil, assert(t.IDS[name], name), on ~= false) end,
      get = function(name) return Flags.getFlag(Space.store, nil, assert(t.IDS[name], name)) == true end,
      setVar = function(name, v) Flags.setVar(Space.store, nil, assert(t.VAR_IDS[name], name), v) end,
      var = function(name) return tonumber(Flags.getVar(Space.store, nil, assert(t.VAR_IDS[name], name))) or 0 end,
    }
  end

  function self.findCell(pred, x0, y0, x1, y1)
    for y = y0, y1 do
      for x = x0, x1 do
        if pred(x, y) then return x, y end
      end
    end
    return nil
  end

  function self.behaviorIs(x, y, name)
    local Collision = require("src.core.game3.collision")
    local MB = require("src.core.game3.mb")
    return Collision.inBounds(x, y) and Collision.behavior(x, y) == MB.id(name)
  end

  function self.walk(game, dir, frames)
    U.hold(game, dir, frames or 16)
    local Player = require("src.core.game3.player")
    for _ = 1, 60 do
      if not Player.moving then break end
      U.wait(1)
    end
  end

  return self
end

return F
