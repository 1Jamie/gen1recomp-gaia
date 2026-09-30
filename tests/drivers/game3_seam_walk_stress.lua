local U = require("tests.drivers.util")

local TARGET_SEAMS = math.max(4, math.min(8, tonumber(os.getenv("SEAM_STRESS_CROSSES") or "4") or 4))
local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR")
local failures = 0
local patches = {}

local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function patch(owner, key, value)
  patches[#patches + 1] = { owner = owner, key = key, value = owner[key] }
  owner[key] = value
end

local function restorePatches()
  for i = #patches, 1, -1 do
    local p = patches[i]
    p.owner[p.key] = p.value
  end
  patches = {}
end

local function finish()
  restorePatches()
  print((failures == 0 and "PASS" or "FAIL") .. " game3_seam_walk_stress failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function waitBoot(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then return true end
    U.wait(1)
  end
  return false
end

local CARDINAL_TO_MOVE = { north = "up", south = "down", west = "left", east = "right" }
local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

local function centerOut(lo, hi)
  local out = {}
  local mid = math.floor((lo + hi) / 2)
  out[#out + 1] = mid
  for offset = 1, math.max(mid - lo, hi - mid) do
    if mid - offset >= lo then out[#out + 1] = mid - offset end
    if mid + offset <= hi then out[#out + 1] = mid + offset end
  end
  return out
end

local function edgeCells(dir, width, height)
  local out = {}
  if dir == "up" then
    for _, x in ipairs(centerOut(0, width - 1)) do out[#out + 1] = { x, 0 } end
  elseif dir == "down" then
    for _, x in ipairs(centerOut(0, width - 1)) do out[#out + 1] = { x, height - 1 } end
  elseif dir == "left" then
    for _, y in ipairs(centerOut(0, height - 1)) do out[#out + 1] = { 0, y } end
  else
    for _, y in ipairs(centerOut(0, height - 1)) do out[#out + 1] = { width - 1, y } end
  end
  return out
end

local function sameConnection(a, b)
  return a and b and a.map == b.map and a.dir == b.dir
    and (tonumber(a.offset) or 0) == (tonumber(b.offset) or 0)
end

local function crossingFor(game, Connections, Collision, Permissions, sourceId, sourceDef, conn)
  local destDef = game.data.maps[conn.map]
  if not destDef then return nil end
  local Map = require("src.core.game3.map")
  Map.ensureMidLayout(game, sourceId, sourceDef)
  Map.ensureMidLayout(game, conn.map, destDef)
  local w, h = Connections.sizeOf(sourceDef)
  local dir = CARDINAL_TO_MOVE[conn.dir]
  if not dir or w < 1 or h < 1 then return nil end

  for _, pos in ipairs(edgeCells(dir, w, h)) do
    local x, y = pos[1], pos[2]
    local got = Connections.incoming(sourceDef, conn.dir, x, y, function(id)
      local def = game.data.maps[id]
      if def then Map.ensureMidLayout(game, id, def) end
      return def
    end)
    if sameConnection(got, conn) then
      local lx, ly = Collision.connectionLanding(destDef, conn, dir, x, y)
      if lx and ly then
        local layout = destDef.midLayout
        local coll = layout and layout.collAt and layout:collAt(lx, ly)
        local water = Collision.isWaterOn(destDef, lx, ly, coll)
        local walkable = Permissions.isWalkable(coll) or Permissions.isWater(coll)
        local leave = Collision.behaviorOn(sourceDef, x, y)
        local enter = Collision.behaviorOn(destDef, lx, ly)
        local leaveBlocked, enterBlocked
        if dir == "up" then leaveBlocked, enterBlocked = Collision.isNorthBlocked(leave), Collision.isSouthBlocked(enter)
        elseif dir == "down" then leaveBlocked, enterBlocked = Collision.isSouthBlocked(leave), Collision.isNorthBlocked(enter)
        elseif dir == "left" then leaveBlocked, enterBlocked = Collision.isWestBlocked(leave), Collision.isEastBlocked(enter)
        else leaveBlocked, enterBlocked = Collision.isEastBlocked(leave), Collision.isWestBlocked(enter) end
        local blocks = leaveBlocked or enterBlocked
        if walkable and not water and not blocks then
          return {
            src = sourceId, dst = conn.map, dir = dir,
            fromX = x, fromY = y, landX = lx, landY = ly,
            offset = tonumber(conn.offset) or 0,
          }
        end
      end
    end
  end
  return nil
end

local function buildGraph(game, family, Connections, Collision, Permissions)
  local Dataset = require("src.core.game3.dataset")
  local maps = game.data and game.data.maps or {}
  local ids = {}
  for id in pairs(maps) do
    local familyId
    if family == "rse" then familyId = id:match("^EM_")
    else familyId = id:match("^FR_") end
    if familyId then ids[#ids + 1] = id end
  end
  table.sort(ids)

  local graph = {}
  for _, id in ipairs(ids) do
    local def = maps[id]
    if def and Dataset.isOutdoorMapType(def.mapType) then
      local edges = {}
      for _, conn in ipairs(Connections.each(def)) do
        local edge = crossingFor(game, Connections, Collision, Permissions, id, def, conn)
        if edge then edges[#edges + 1] = edge end
      end
      table.sort(edges, function(a, b)
        if a.dst ~= b.dst then return a.dst < b.dst end
        if a.dir ~= b.dir then return a.dir < b.dir end
        return a.offset < b.offset
      end)
      if #edges > 0 then graph[id] = edges end
    end
  end

  local path, best, seen = {}, {}, {}
  local visits = 0
  local function search(id)
    visits = visits + 1
    if #path > #best then
      best = {}
      for i = 1, #path do best[i] = path[i] end
    end
    if #path >= TARGET_SEAMS or visits > 250000 then return #path >= TARGET_SEAMS end
    for _, edge in ipairs(graph[id] or {}) do
      if not seen[edge.dst] then
        seen[edge.dst] = true
        path[#path + 1] = edge
        if search(edge.dst) then return true end
        path[#path] = nil
        seen[edge.dst] = nil
      end
    end
    return false
  end

  for _, id in ipairs(ids) do
    if graph[id] then
      seen[id] = true
      if search(id) then break end
      seen[id] = nil
    end
  end
  return best, graph, visits
end

local function stepOnce(Player, game, dir, expectedMap)
  local action
  for _ = 1, 4 do
    action = Player.tryMove(dir, game, false)
    if action ~= "turned" then break end
    for _ = 1, 90 do
      U.wait(1)
      if not Player.moving and (tonumber(Player.turnTimer) or 0) <= 0 then break end
    end
  end
  if action ~= "step" and action ~= "connection" then
    return false, "Player.tryMove returned " .. tostring(action)
  end
  for _ = 1, 90 do
    U.wait(1)
    if not Player.moving then break end
  end
  if Player.moving then return false, "movement did not settle" end
  if expectedMap and require("src.core.game3.map").current ~= expectedMap then
    return false, "map changed to " .. tostring(require("src.core.game3.map").current)
  end
  return true, action
end

local function walkTo(Player, game, x, y, mapId)
  while Player.cellX ~= x do
    local dir = Player.cellX < x and "right" or "left"
    local ok, why = stepOnce(Player, game, dir, mapId)
    if not ok then return false, why end
  end
  while Player.cellY ~= y do
    local dir = Player.cellY < y and "down" or "up"
    local ok, why = stepOnce(Player, game, dir, mapId)
    if not ok then return false, why end
  end
  return true
end

local function visibleTileMatches(FieldView, Map, NativeTileset, mapDef, primaryPair, x, y)
  local row = FieldView._nativeVisibleCells and FieldView._nativeVisibleCells[y]
  local info = row and row[x]
  if not info then return nil, "not visible" end
  local mid, pair, isVoid = Map.worldMidAt(x, y, mapDef)
  if isVoid then return nil, "void" end
  pair = pair or primaryPair
  local actualPair = pair
  if not NativeTileset.ready(actualPair) then actualPair = primaryPair end
  local ts = NativeTileset.get(actualPair)
  local quad = ts and NativeTileset.quad(ts, NativeTileset.slotFor(ts, mid))
  if not info.draw then return false, "cell marked undrawn" end
  if info.pair ~= actualPair then return false, "pair " .. tostring(info.pair) .. " != " .. tostring(actualPair) end
  if not quad or not info.under or info.under.quad ~= quad then
    return false, string.format("under quad mismatch at %d,%d mid=%s source=%s", x, y, tostring(mid), tostring(pair))
  end
  if ts.layered and ts.overImage then
    local over = NativeTileset.overQuad(ts, NativeTileset.slotFor(ts, mid))
    if over and (not info.over or info.over.quad ~= over) then
      return false, string.format("over quad mismatch at %d,%d mid=%s source=%s", x, y, tostring(mid), tostring(pair))
    end
  end
  return true
end

local function inspectSeam(FieldView, Map, NativeTileset, game, edge, crossingIndex)
  local mapId = Map.current
  local def = game.data.maps[mapId]
  local layout = def and def.midLayout
  if not (def and layout) then return check(false, "seam " .. crossingIndex .. " destination layout loaded") end

  local reverse = OPPOSITE[edge.dir]
  local baseX, baseY = edge.landX, edge.landY
  local width, height = layout.width, layout.height
  local visible = FieldView._nativeVisibleCells or {}
  local tested, failuresHere = 0, 0
  local maxAcross = 6
  for distance = 1, maxAcross do
    for along = -5, 5 do
      local x, y
      if reverse == "left" then x, y = -distance, baseY + along
      elseif reverse == "right" then x, y = width - 1 + distance, baseY + along
      elseif reverse == "up" then x, y = baseX + along, -distance
      else x, y = baseX + along, height - 1 + distance end
      local matched, why = visibleTileMatches(FieldView, Map, NativeTileset, def,
        def.pair or layout.pair, x, y)
      if matched then
        tested = tested + 1
      elseif matched == false then
        failuresHere = failuresHere + 1
        check(false, "seam " .. crossingIndex .. " rendered tile " .. x .. "," .. y .. ": " .. why)
      elseif why == "void" and visible[y] and visible[y][x] then
      end
    end
  end
  check(tested > 0, string.format("seam %d has visible connected-neighbor tiles", crossingIndex))
  if tested > 0 then
    print(string.format("SEAM_CHECK %d from=%s to=%s direction=%s checked=%d bad=%d",
      crossingIndex, edge.src, edge.dst, edge.dir, tested, failuresHere))
  end
  local slots = tonumber(FieldView._nativeSpriteSlots) or 0
  local cols, rows = tonumber(FieldView._nativeViewCols) or 0, tonumber(FieldView._nativeViewRows) or 0
  if cols > 0 and rows > 0 then
    local freeSlots = 0
    for _, store in ipairs({ FieldView._nativeFreeUnder or {}, FieldView._nativeFreeOver or {} }) do
      for _, free in pairs(store) do freeSlots = freeSlots + #free end
    end
    local cap = cols * rows * 4
    check(slots <= cap, string.format("seam %d recycled sprite slots stay under cap (%d/%d)", crossingIndex, slots, cap))
    print(string.format("NATIVE_POOL %d slots=%d hidden=%d cap=%d", crossingIndex, slots, freeSlots, cap))
  end
  return failuresHere == 0 and tested > 0
end

return function(game)
  if not check(waitBoot(game), "boot reached") then return finish() end
  local version = (os.getenv("POKEPORT_VERSION") or ""):lower()
  local isEmerald = version:find("emerald", 1, true) or version:find("ruby", 1, true) or version:find("sapphire", 1, true)
  game:_handleBootAction({ action = "new_game", name = isEmerald and "BRENDAN" or "RED", gender = 0 })
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local Profile = require("src.core.game3.profile")
  local session = Runtime.getSession()
  if not check(session ~= nil, "Game3 session started") then return finish() end

  local family = Profile.family(session)
  if not check(family == "rse" or family == "frlg", "family=" .. tostring(family)) then return finish() end
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Connections = require("src.core.game3.connections")
  local Permissions = require("src.world.gen2.Permissions")
  local FieldView = require("src.core.game3.field_view")
  local NativeTileset = require("src.core.game3.tileset_native")
  local Field = require("src.core.game3.field")
  local Encounters = require("src.core.game3.encounters")
  local TrainerSight = require("src.core.game3.trainer_sight")
  local ForcedMovement = require("src.core.game3.forced_movement")
  local StepEvents = require("src.core.game3.step_events")
  local Ghosts = require("src.core.game3.ghosts")
  local Space = require("src.core.game3.scripting.space")
  local Warp = require("src.core.game3.warp")
  local MapNamePopup = require("src.ui.game3.map_name_popup")

  patch(Collision, "canEnter", function(_, x, y)
    if Collision.inBounds(x, y) then return true end
    return false, "bounds"
  end)
  patch(Ghosts, "blocksOn", function() return false end)
  patch(Collision, "ledgeLanding", function() return nil end)
  for _, name in ipairs({ "isStairWarp", "isDoorWarp", "isExitWarp", "isEscalatorWarp", "isArrowWarp" }) do
    if type(Collision[name]) == "function" then patch(Collision, name, function() return nil end) end
  end
  patch(Collision, "tryWarpAt", function() return false end)
  patch(Field, "tryCoordEvents", function() return false end)
  patch(Field, "tryWalkIntoSign", function() return false end)
  patch(TrainerSight, "check", function() return false end)
  patch(ForcedMovement, "onStepFinished", function() return false end)
  patch(StepEvents, "onStepTaken", function() return false end)
  patch(Encounters, "onStep", function() return nil end)
  patch(Encounters, "noteGrass", function() return nil end)
  patch(Space, "runEnterScripts", function() return nil end)
  patch(Space, "runOnWarpIntoMap", function() return nil end)
  patch(Space, "runOnFrame", function() return nil end)
  patch(Space, "scheduleOnFrame", function() return nil end)
  if MapNamePopup.dismiss then MapNamePopup.dismiss() end
  patch(MapNamePopup, "show", function() return false end)
  local RseInit = require("src.core.game3.rse.init")
  if RseInit and type(RseInit.call) == "function" then
    local originalCall = RseInit.call
    patch(RseInit, "call", function(component, name, ...)
      if component == "secretBase" and name == "tryDoorWarp" then return false end
      return originalCall(component, name, ...)
    end)
  end
  if Space.vm and Space.vm.isRunning and Space.vm:isRunning() and Space.vm.halt then
    Space.vm:halt(true)
  end

  local route, graph, visits = buildGraph(game, family, Connections, Collision, Permissions)
  check(#route >= 4, string.format("found %d traversable outdoor seams (target %d, search nodes %d)",
    #route, TARGET_SEAMS, visits))
  if #route < 4 then
    local count = 0
    for _ in pairs(graph) do count = count + 1 end
    print("SEAM_GRAPH connectedOutdoorMaps=" .. count)
    return finish()
  end
  if #route < TARGET_SEAMS then
    print(string.format("NOTE using longest real path (%d seams; requested %d)", #route, TARGET_SEAMS))
  end
  for i, edge in ipairs(route) do
    print(string.format("SEAM_ROUTE %d %s (%d,%d) --%s--> %s landing=(%d,%d)",
      i, edge.src, edge.fromX, edge.fromY, edge.dir, edge.dst, edge.landX, edge.landY))
  end

  local first = route[1]
  local startX, startY = first.fromX, first.fromY
  if first.dir == "up" then startY = math.min(1, first.fromY)
  elseif first.dir == "down" then startY = math.max(0, first.fromY - 1)
  elseif first.dir == "left" then startX = math.min(1, first.fromX)
  elseif first.dir == "right" then startX = math.max(0, first.fromX - 1) end
  local okLoad, loadErr = pcall(Map.load, Runtime._mod, game, first.src,
    { x = startX, y = startY, facing = first.dir })
  if not check(okLoad, "loaded route start " .. first.src .. (loadErr and (": " .. tostring(loadErr)) or "")) then
    return finish()
  end
  U.wait(45)
  check(Map.current == first.src and Player.cellX == startX and Player.cellY == startY,
    "spawned on the real connection route")

  for index, edge in ipairs(route) do
    if Map.current ~= edge.src then
      check(false, string.format("route %d starts on %s, currently on %s", index, edge.src, tostring(Map.current)))
      return finish()
    end
    local okWalk, walkErr = walkTo(Player, game, edge.fromX, edge.fromY, edge.src)
    if not check(okWalk, string.format("walk to seam %d at %s (%d,%d)%s", index, edge.src,
      edge.fromX, edge.fromY, walkErr and (": " .. walkErr) or "")) then return finish() end

    local okCross, crossResult = stepOnce(Player, game, edge.dir, edge.dst)
    if not check(okCross and crossResult == "connection", string.format("cross seam %d %s -> %s via %s%s",
      index, edge.src, edge.dst, edge.dir, crossResult and (": " .. tostring(crossResult)) or "")) then
      return finish()
    end
    local settled = false
    for _ = 1, 90 do
      U.wait(1)
      if not Player.moving then settled = true; break end
    end
    if not check(settled and Map.current == edge.dst and Player.cellX == edge.landX and Player.cellY == edge.landY,
        string.format("seam %d landed at %s (%d,%d)", index, edge.dst, edge.landX, edge.landY)) then
      return finish()
    end
    U.wait(4)
    if SHOT_DIR then
      local path = string.format("%s/%02d_%s_to_%s.png", SHOT_DIR, index, edge.src, edge.dst)
      check(U.shot(game, path), "captured seam " .. index .. " at " .. path)
    end
    inspectSeam(FieldView, Map, NativeTileset, game, edge, index)
  end

  check(Map.current == route[#route].dst, "finished on final connected map")
  finish()
end
