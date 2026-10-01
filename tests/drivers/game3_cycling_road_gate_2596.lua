local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_cycling_road_gate_2596"
local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  print((failures == 0 and "PASS " or "FAIL ") .. "cycling_road_gate_2596")
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "RED", gender = 0 })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field reached") then return finish() end
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local Message = require("src.ui.game3.message")
  local Fade = require("src.ui.game3.fade")
  local ItemUse = require("src.core.game3.item_use")
  local Bag = require("src.core.game3.bag")
  local Objects = require("src.core.game3.objects")
  local C = require("src.core.game3.constants").of(session.version)
  local defs = Flags.forVersion(session.version)
  local road = assert(defs.IDS.FLAG_SYS_ON_CYCLING_ROAD)
  local scene = assert(defs.VAR_IDS.VAR_MAP_SCENE_ROUTE16)
  local bike = C:require("items", "ITEM_BICYCLE")
  Bag.add(session.bag, bike, 1)
  Flags.setFlag(Space.store, nil, assert(defs.IDS.FLAG_GOT_BICYCLE), true)

  local function waitFor(pred, limit)
    for _ = 1, limit do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end
  local function settle()
    return waitFor(function()
      if Message.isOpen() then
        if Message.isTyping() then Message.skipReveal() end
        table.insert(game.input.pressQueue, "a")
      end
      return not Field.locked and not Fade.active and not Player.moving
        and not Message.isOpen() and not (Space.vm and Space.vm:isRunning())
    end, 600)
  end
  local function holdUntil(dir, pred, limit)
    local reached = false
    for _ = 1, limit do
      if pred() then reached = true break end
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      U.wait(1)
    end
    game.input.state[dir] = false
    return reached or pred()
  end
  local function noSight()
    for _, eo in ipairs(Objects.forDraw()) do eo.sight = 0 end
  end
  local function sessionRoad()
    local f = session.flags or {}
    return f[road] == true or f[tostring(road)] == true
  end

  local function run(tag, route, sx, sy, dir, sceneVal, gate1F, gate2F, stairX, stairY)
    Flags.setVar(Space.store, nil, scene, sceneVal)
    Flags.setFlag(Space.store, nil, road, false)
    Space.persistSession(nil, game)
    Map.load(nil, game, route, { x = sx, y = sy, facing = dir })
    if not check(settle(), tag .. " route arrival settles") then return false end
    noSight()
    if sceneVal == 1 then
      check(Flags.getFlag(Space.store, nil, road), tag .. " route OnTransition arms cycling road flag")
      check(Player.biking, tag .. " ForcePlayerOntoBike on the road")
    else
      if not Player.biking then ItemUse.useBike(session, bike) end
      check(Player.biking, tag .. " rides toward the gate")
    end
    if not check(holdUntil(dir, function() return session.map == gate1F end, 300),
        tag .. " enters gate 1F through the door") then return false end
    if not check(settle(), tag .. " gate 1F settles") then return false end
    check(not Flags.getFlag(Space.store, nil, road), tag .. " gate 1F OnTransition cleared live flag")
    if sceneVal == 1 then
      print("INFO " .. tag .. " session.flags road stale=" .. tostring(sessionRoad()))
    end
    if Player.biking then
      local ok, _, text = ItemUse.useBike(session, bike)
      check(ok == true and text == nil and not Player.biking, tag .. " gate 1F dismount allowed")
    end
    local ok2 = ItemUse.useBike(session, bike)
    check(ok2 == true and Player.biking, tag .. " gate 1F mounts bike")
    Player.reset(stairX - 1, stairY, "right")
    Player.biking = true
    Player.syncSavePosition(game)
    if not check(holdUntil("right", function() return session.map == gate2F end, 300),
        tag .. " climbs stairs to 2F") then return false end
    if not check(settle(), tag .. " 2F settles") then return false end
    check(not Player.biking and not session.biking and not game.save.biking,
      tag .. " 2F arrives on foot in every state mirror")
    U.still(game, DIR .. "/2596_" .. tag .. "_2F_on_foot.png")
    local ok3, _, text3 = ItemUse.useBike(session, bike)
    check(ok3 == false and text3 ~= nil and not Player.biking, tag .. " 2F bike says not the time")
    return true
  end

  run("route16_left", "FR_ROUTE_16", 19, 13, "right", 1,
    "FR_ROUTE_16_NORTH_ENTRANCE_1F", "FR_ROUTE_16_NORTH_ENTRANCE_2F", 9, 16)
  run("route16_right", "FR_ROUTE_16", 28, 13, "left", 0,
    "FR_ROUTE_16_NORTH_ENTRANCE_1F", "FR_ROUTE_16_NORTH_ENTRANCE_2F", 9, 16)
  run("route18_left", "FR_ROUTE_18", 40, 9, "right", 1,
    "FR_ROUTE_18_EAST_ENTRANCE_1F", "FR_ROUTE_18_EAST_ENTRANCE_2F", 9, 10)
  finish()
end
