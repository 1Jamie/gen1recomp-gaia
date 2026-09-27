local U = require("tests.drivers.util")

local F = {}

function F.new(name, dir)
  local S = { name = name, dir = dir, failures = 0, logs = {} }

  function S.check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then S.failures = S.failures + 1 end
    return ok
  end

  function S.note(msg)
    print("[driver] " .. msg)
  end

  local origPrint = print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    local msg = table.concat(parts, "\t")
    if msg:find("not ported", 1, true) or msg:find("skip unknown", 1, true) or msg:find("unbound special", 1, true)
        or msg:find("no handler", 1, true) or msg:find("warphole unknown", 1, true) then
      S.logs[#S.logs + 1] = msg
    end
    return origPrint(...)
  end

  function S.finish()
    for i = 1, math.min(#S.logs, 12) do S.note("VM LOG " .. S.logs[i]) end
    print((S.failures == 0 and "PASS" or "FAIL") .. " " .. name .. " failures=" .. S.failures)
    love.event.quit(S.failures == 0 and 0 or 1)
    U.wait(10)
  end

  function S.shot(game, file)
    return U.shot(game, dir .. "/" .. file)
  end

  function S.still(game, file)
    return U.still(game, dir .. "/" .. file)
  end

  return S
end

function F.boot(game, S)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not S.check(game.boot ~= nil, "boot reached") then return false end
  local ok, err = pcall(function()
    game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  end)
  if not ok then S.note("new_game error: " .. tostring(err)) end
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  return S.check(ok and session ~= nil, "new game session (" .. tostring(session and session.map) .. ")")
end

function F.settle(game, frames)
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Space = require("src.core.game3.scripting.space")
  for _ = 1, frames or 600 do
    local busy = Warp.isBusy() or (Message.isOpen and Message.isOpen())
      or (Space.vm and Space.vm:isRunning())
    if not busy then break end
    if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
    U.wait(1)
  end
end

function F.goTo(game, mapId, x, y, facing)
  F.settle(game, 300)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local ok, err = pcall(function()
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
  end)
  if not ok then print("[driver] Map.load " .. mapId .. " error: " .. tostring(err)) end
  local s = Runtime.getSession()
  if s then s.x, s.y, s.facing = x, y, facing end
  Player.cellX, Player.cellY = x, y
  Player.px, Player.py = x * 16, y * 16
  Player.targetX, Player.targetY = x, y
  Player.facing = facing
  Player.moveDir = facing
  U.wait(40)
  F.settle(game, 300)
  return ok and Runtime.getSession().map == mapId
end

function F.release(game)
  for _, k in ipairs({ "up", "down", "left", "right", "a", "b", "start", "select" }) do
    game.input.state[k] = false
  end
end

function F.holdKeys(game, keys, n, each)
  for i = 1, n do
    for _, k in ipairs(keys) do
      if i == 1 then table.insert(game.input.pressQueue, k) end
      game.input.state[k] = true
    end
    coroutine.yield()
    if each and each(i) then break end
  end
  F.release(game)
end

function F.give(item, qty)
  local Runtime = require("src.core.game3.runtime")
  local s = Runtime.getSession()
  local id = require("src.core.game3.constants").active(s):require("items", item)
  require("src.core.game3.bag").add(s.bag, id, qty or 1)
  return id
end

function F.setVar(name, value)
  local Rse = require("src.core.game3.rse.init")
  Rse.setVar(name, value)
end

function F.var(name)
  return require("src.core.game3.rse.init").var(name)
end

function F.setFlag(name, on)
  require("src.core.game3.rse.init").setFlag(name, on)
end

function F.useRegistered(game, id)
  local Runtime = require("src.core.game3.runtime")
  Runtime.getSession().registeredItem = id
  U.tap(game, "select")
  U.wait(4)
end

function F.songId()
  local Audio = require("src.core.game3.audio")
  return (Audio._fadeOut and Audio._fadeOut.nextSong) or (Audio._currentSong and Audio._currentSong.id)
end

function F.noTrainerSight()
  local TrainerSight = require("src.core.game3.trainer_sight")
  TrainerSight.check = function() return false end
end

function F.map()
  local s = require("src.core.game3.runtime").getSession()
  return s and s.map
end

return F
