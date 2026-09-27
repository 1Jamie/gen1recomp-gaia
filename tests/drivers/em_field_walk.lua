local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_field_walk"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_field_walk failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function try(label, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print("[driver] " .. label .. " error: " .. tostring(err)) end
  return ok
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end

  local okNew = try("new_game", function()
    game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  end)
  U.wait(30)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local session = Runtime.getSession()
  check(okNew and session ~= nil and session.map == "EM_INSIDE_OF_TRUCK",
    "new game lands in the truck (" .. tostring(session and session.map) .. ")")
  if not session then return finish() end
  U.shot(game, DIR .. "/01_new_game_truck.png")

  local function mapNow()
    local s = Runtime.getSession()
    return s and s.map
  end

  local function settle(frames)
    for _ = 1, frames or 600 do
      local busy = Warp.isBusy() or (Message.isOpen and Message.isOpen())
      if not busy then break end
      if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
      U.wait(1)
    end
  end

  local function goTo(mapId, x, y, facing)
    settle()
    local ok = try("Map.load " .. mapId, function()
      Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    end)
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    U.wait(40)
    return ok
  end

  local function walkUntil(dir, pred, maxSteps)
    for _ = 1, maxSteps or 12 do
      U.hold(game, dir, 16)
      for _ = 1, 400 do
        if not Warp.isBusy() then break end
        U.wait(1)
      end
      if pred() then return true end
    end
    return pred()
  end

  check(goTo("EM_LITTLEROOT_TOWN", 5, 9, "up"), "Littleroot Town loads")
  check(mapNow() == "EM_LITTLEROOT_TOWN", "session is on EM_LITTLEROOT_TOWN")
  U.shot(game, DIR .. "/02_littleroot.png")

  local okDoors, Doors = pcall(require, "src.core.game3.doors")
  local entry = okDoors and Doors.getDoorEntryAt and Doors.getDoorEntryAt("EM_LITTLEROOT_TOWN", 5, 8)
  print("[driver] INFO door entry at (5,8): " .. tostring(entry and entry.tile) .. " (doors runtime is R5)")
  local inHouse = walkUntil("up", function() return mapNow() == "EM_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F" end, 3)
  check(inHouse, "door at (5,8) warps into Brendan's house (" .. tostring(mapNow()) .. ")")
  settle()
  U.wait(30)
  local s = Runtime.getSession()
  print(string.format("[driver] inside at %s,%s", tostring(s and s.x), tostring(s and s.y)))
  U.shot(game, DIR .. "/03_brendans_house_1f.png")

  local out = walkUntil("down", function() return mapNow() == "EM_LITTLEROOT_TOWN" end, 4)
  settle()
  U.wait(30)
  s = Runtime.getSession()
  check(out, "exit mat returns to Littleroot (" .. tostring(mapNow()) .. ")")
  check(s and s.x == 5 and s.y == 9, string.format("exit lands below the door (%s,%s)", tostring(s and s.x), tostring(s and s.y)))
  U.shot(game, DIR .. "/04_littleroot_after_exit.png")

  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local VARS = Flags.forVersion("emerald").VAR_IDS
  local IDS = Flags.forVersion("emerald").IDS

  local function runningKey()
    return Space.vm and Space.vm:isRunning() and Space.vm._scriptKey or nil
  end

  local function haltStuck(label)
    if not runningKey() then return end
    local pc = Space.vm.ctx.pc
    local list = pc and Space.vm.scripts[pc.listKey]
    local row = list and list[pc.index]
    print(string.format("[driver] NOTE %s still running at %s#%s op=%s status=%s; halting it", label,
      tostring(pc and pc.listKey), tostring(pc and pc.index), tostring(row and row.op), tostring(Space.vm.ctx.status)))
    local Objects = require("src.core.game3.objects")
    for lid, tr in pairs(Objects._tracks) do
      print(string.format("[driver] NOTE track lid=%s i=%s/%s done=%s", tostring(lid), tostring(tr.i),
        tostring(tr.actions and #tr.actions), tostring(tr.done)))
    end
    Space.vm:halt(true)
    require("src.core.game3.field").unlock()
  end

  Flags.setVar(Space.store, nil, VARS.VAR_LITTLEROOT_TOWN_STATE, 4)
  Flags.setVar(Space.store, nil, VARS.VAR_ROUTE101_STATE, 3)
  Flags.setFlag(Space.store, nil, IDS.FLAG_RESCUED_BIRCH, true)
  goTo("EM_LITTLEROOT_TOWN", 10, 3, "up")
  local TilesetAnim = require("src.core.game3.tileset_anim")
  local seen, last = {}, nil
  for _ = 1, 160 do
    local e = TilesetAnim._pairs["general__petalburg"]
    local b = e and e.rse and e.banks[1]
    if b and b.frame ~= last then last = b.frame; seen[#seen + 1] = b.frame end
    U.wait(1)
  end
  check(#seen >= 3, "general flower bank advances on the RSE primary counter (" .. table.concat(seen, ",") .. ")")
  U.still(game, DIR .. "/05_littleroot_flowers_a.png")
  U.wait(16)
  U.still(game, DIR .. "/05_littleroot_flowers_b.png")

  local onRoute = walkUntil("up", function() return mapNow() == "EM_ROUTE101" end, 6)
  s = Runtime.getSession()
  check(onRoute, "walking north crosses into Route 101 (" .. tostring(mapNow()) .. ")")
  check(s and s.x == 10 and s.y >= 17, string.format("Route 101 entry cell (%s,%s)", tostring(s and s.x), tostring(s and s.y)))
  U.wait(10)
  U.shot(game, DIR .. "/06_route101_seam.png")

  local back = walkUntil("down", function() return mapNow() == "EM_LITTLEROOT_TOWN" end, 4)
  s = Runtime.getSession()
  check(back, string.format("walking south returns to Littleroot (%s %s,%s)", tostring(mapNow()),
    tostring(s and s.x), tostring(s and s.y)))

  goTo("EM_ROUTE101", 10, 2, "up")
  local oldale = walkUntil("up", function() return mapNow() == "EM_OLDALE_TOWN" end, 6)
  check(oldale, "Route 101 north crosses into Oldale Town (" .. tostring(mapNow()) .. ")")
  U.wait(10)
  U.shot(game, DIR .. "/07_oldale.png")

  Flags.setVar(Space.store, nil, VARS.VAR_ROUTE101_STATE, 0)
  goTo("EM_ROUTE101", 11, 17, "down")
  local rescue = Space.scriptKey("Route101_EventScript_StartBirchRescue")
  local started = nil
  for _ = 1, 3 do
    U.hold(game, "down", 16)
    for _ = 1, 30 do
      started = started or runningKey()
      U.wait(1)
    end
    if started then break end
  end
  check(rescue ~= nil and started == rescue, string.format(
    "Route 101 (11,19) coord event starts Route101_EventScript_StartBirchRescue via labels.lua (%s want %s, state %s)",
    tostring(started), tostring(rescue), tostring(Flags.getVar(Space.store, nil, VARS.VAR_ROUTE101_STATE))))
  U.shot(game, DIR .. "/08_route101_birch_rescue.png")
  haltStuck("Birch rescue")

  Flags.setVar(Space.store, nil, VARS.VAR_LITTLEROOT_TOWN_STATE, 0)
  Flags.setFlag(Space.store, nil, IDS.FLAG_RESCUED_BIRCH, false)
  goTo("EM_LITTLEROOT_TOWN", 10, 3, "up")
  started = nil
  for _ = 1, 3 do
    U.hold(game, "up", 16)
    for _ = 1, 30 do
      started = started or runningKey()
      U.wait(1)
    end
    if started then break end
  end
  local twinKey = Space.scriptKey("LittlerootTown_EventScript_NeedPokemonTriggerLeft")
  s = Runtime.getSession()
  check(started ~= nil and started == twinKey and mapNow() == "EM_LITTLEROOT_TOWN",
    string.format("twin coord event at (10,1) starts NeedPokemonTriggerLeft at VAR_LITTLEROOT_TOWN_STATE 0 (%s want %s)",
      tostring(started), tostring(twinKey)))
  settle(1200)
  U.wait(60)
  haltStuck("twin")

  finish()
end
