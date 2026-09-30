local U = require("tests.drivers.util")

local MAP = os.getenv("PERF_MAP") or "EM_SLATEPORT_CITY"
local FRAMES = math.max(120, tonumber(os.getenv("PERF_FRAMES") or "900") or 900)
local failures = 0

local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " game3_overworld_profile failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

local function waitBoot(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then return true end
    U.wait(1)
  end
  return false
end

local function timeWrap(owner, key, label, data)
  local original = owner[key]
  if type(original) ~= "function" then return nil end
  owner[key] = function(...)
    local start = love.timer.getTime()
    local bx, by, baseBx, baseBy, dirty, resetCause
    if label == "FieldView.draw" then
      bx, by = owner._nativeBx, owner._nativeBy
      baseBx, baseBy, dirty = owner._nativeBaseBx, owner._nativeBaseBy, owner._nativeDirty
      local _, canvasW, canvasH = ...
      local cols, rows = math.ceil((canvasW or 0) / 16) + 3, math.ceil((canvasH or 0) / 16) + 3
      resetCause = {
        dirty = dirty == true,
        slots = (owner._nativeSpriteSlots or 0) > cols * rows * 4,
        dimensions = owner._nativeViewCols ~= cols or owner._nativeViewRows ~= rows,
        noCells = type(owner._nativeVisibleCells) ~= "table",
      }
      if owner._nativeBatches then
        for _, batch in pairs(owner._nativeBatches) do
          if type(batch.set) ~= "function" then resetCause.noSet = true; break end
        end
      end
    end
    local a, b, c, d = original(...)
    if data.active then
      local elapsed = (love.timer.getTime() - start) * 1000
      local samples = data.samples[label]
      samples[#samples + 1] = elapsed
      if elapsed > (data.max[label] or 0) then data.max[label] = elapsed end
      if label == "FieldView.draw" then
        data.nativeMaxSlots = math.max(data.nativeMaxSlots or 0, owner._nativeSpriteSlots or 0)
        if dirty or owner._nativeBaseBx ~= baseBx or owner._nativeBaseBy ~= baseBy then
          data.nativeRebuilds = data.nativeRebuilds + 1
          for reason, active in pairs(resetCause or {}) do
            if active then data.nativeResetReasons[reason] = (data.nativeResetReasons[reason] or 0) + 1 end
          end
        end
        if owner._nativeBx ~= bx or owner._nativeBy ~= by then
          data.nativeScrolls = data.nativeScrolls + 1
        end
      end
    end
    return a, b, c, d
  end
  return original
end

local function stats(samples)
  table.sort(samples)
  local n = #samples
  if n == 0 then return "n=0" end
  local sum = 0
  for i = 1, n do sum = sum + samples[i] end
  local p95 = samples[math.max(1, math.ceil(n * 0.95))]
  local p99 = samples[math.max(1, math.ceil(n * 0.99))]
  return string.format("n=%d mean=%.3f p95=%.3f p99=%.3f max=%.3f", n, sum / n, p95, p99, samples[n])
end

return function(game)
  if not check(waitBoot(game), "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(45)

  local Runtime = require("src.core.game3.runtime")
  local MapModule = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Permissions = require("src.world.gen2.Permissions")
  local session = Runtime.getSession()
  if not check(session ~= nil, "game3 session started") then return finish() end

  local okLoad, loadErr = pcall(MapModule.load, nil, game, MAP, { x = 10, y = 10, facing = "right" })
  if not check(okLoad, "loaded " .. MAP .. (loadErr and (": " .. tostring(loadErr)) or "")) then return finish() end
  U.wait(60)

  local def = game.data and game.data.maps and game.data.maps[MAP]
  local layout = def and def.midLayout
  if not check(layout ~= nil, MAP .. " has a decoded layout") then return finish() end

  local bestLo, bestHi, bestY = nil, nil, nil
  for y = 0, (layout.height or 0) - 1 do
    local lo, hi
    for x = 0, (layout.width or 0) do
      local walkable = x < layout.width and Permissions.isWalkable(layout:collAt(x, y))
      if walkable then
        lo = lo or x
        hi = x
      elseif lo then
        if not bestLo or hi - lo > bestHi - bestLo then bestLo, bestHi, bestY = lo, hi, y end
        lo, hi = nil, nil
      end
    end
  end
  if not bestLo then
    return check(false, MAP .. " has a straight walkable row"), finish()
  end

  local startX = math.floor((bestLo + bestHi) / 2)
  Player.cellX, Player.cellY = startX, bestY
  Player.px, Player.py = startX * 16, bestY * 16
  Player.targetX, Player.targetY = startX, bestY
  Player.facing = "right"
  session.x, session.y, session.facing = startX, bestY, "right"
  print(string.format("PERF_ROUTE map=%s row=%d cells=%d..%d objects=%d world=%d",
    MAP, bestY, bestLo, bestHi, #(def.objects or {}), #(MapModule.world or {})))

  local Zoom = require("src.render.Zoom")
  local Renderer = require("src.render.Renderer")
  local Ghosts = require("src.core.game3.ghosts")
  local Objects = require("src.core.game3.objects")
  local Field = require("src.core.game3.field")
  local FieldView = require("src.core.game3.field_view")
  local data = { active = false, samples = {}, max = {} }
  local originals = {
    gameUpdate = rawget(game, "update"),
    gameDraw = rawget(game, "draw"),
    update = game.update,
    draw = game.draw,
  }
  originals.fieldUpdate = timeWrap(Field, "update", "Field.update", data)
  originals.ghostSync = timeWrap(Ghosts, "sync", "Ghosts.sync", data)
  originals.ghostUpdate = timeWrap(Ghosts, "update", "Ghosts.update", data)
  originals.objectUpdate = timeWrap(Objects, "update", "Objects.update", data)
  originals.tickPool = timeWrap(Objects, "tickPool", "Objects.tickPool", data)
  originals.fieldDraw = timeWrap(FieldView, "draw", "FieldView.draw", data)
  for _, label in ipairs({ "game.update", "game.draw", "Field.update", "Ghosts.sync", "Ghosts.update", "Objects.update", "Objects.tickPool", "FieldView.draw" }) do
    data.samples[label], data.max[label] = {}, 0
  end
  timeWrap(game, "update", "game.update", data)
  timeWrap(game, "draw", "game.draw", data)

  local previousAllowSurvey = Zoom.allowSurvey
  Zoom.allowSurvey = true
  local lo, hi = Zoom.offsetRange(Renderer:fitScale())
  local modes = { { label = "fit", offset = 0 }, { label = "survey", offset = lo } }
  local input = game.input
  local moved
  for _, mode in ipairs(modes) do
    Zoom.offset = Zoom.clampOffset(mode.offset, Renderer:fitScale())
    game.options.zoom = Zoom.offset
    MapModule.load(nil, game, MAP, { x = startX, y = bestY, facing = "right" })
    U.wait(60)
    collectgarbage("collect")
    for _, samples in pairs(data.samples) do for i = #samples, 1, -1 do samples[i] = nil end end
    data.nativeRebuilds = 0
    data.nativeScrolls = 0
    data.nativeResetReasons = {}
    data.nativeMaxSlots = 0
    data.active = true
    local dir = "right"
    local left = 0
    local right = 0
    local beforeX = Player.cellX
    local start = love.timer.getTime()
    for _ = 1, FRAMES do
      if Player.cellX >= bestHi then dir = "left" end
      if Player.cellX <= bestLo then dir = "right" end
      input.state.right = dir == "right"
      input.state.left = dir == "left"
      input.pressQueue[#input.pressQueue + 1] = dir
      if dir == "right" then right = right + 1 else left = left + 1 end
      U.wait(1)
    end
    input.state.right, input.state.left = false, false
    data.active = false
    local elapsed = love.timer.getTime() - start
    local endX = Player.cellX or beforeX
    moved = math.abs(endX - beforeX)
    local view = string.format("%sx%s", tostring(FieldView._viewW), tostring(FieldView._viewH))
    local gc = collectgarbage("count")
    local objectCount, poolCount = 0, 0
    for _, pool in pairs(Ghosts._pools or {}) do
      poolCount = poolCount + 1
      objectCount = objectCount + #(pool.order or {})
    end
    print(string.format("PERF %s zoom=%d range=%d..%d frames=%d elapsed=%.3f fps=%.1f x=%d..%d moved=%d input_r=%d input_l=%d view=%s world=%d ghost_pools=%d ghost_objects=%d native_rebuilds=%d native_scrolls=%d native_slots_max=%d lua_kb=%.1f",
      mode.label, Zoom.offset, lo, hi, FRAMES, elapsed, FRAMES / math.max(elapsed, 0.001), beforeX, endX, moved,
      right, left, view, #(MapModule.world or {}), poolCount, objectCount, data.nativeRebuilds, data.nativeScrolls, data.nativeMaxSlots, gc))
    for reason, count in pairs(data.nativeResetReasons) do print("PERF " .. mode.label .. " native_reset_reason=" .. reason .. " count=" .. count) end
    for _, label in ipairs({ "game.update", "Field.update", "Ghosts.sync", "Ghosts.update", "Objects.update", "Objects.tickPool", "game.draw", "FieldView.draw" }) do
      print("PERF " .. mode.label .. " " .. label .. " " .. stats(data.samples[label]) .. " measured_max=" .. string.format("%.3f", data.max[label] or 0))
    end
  end

  game.update, game.draw = originals.gameUpdate, originals.gameDraw
  Field.update, Ghosts.sync, Ghosts.update = originals.fieldUpdate, originals.ghostSync, originals.ghostUpdate
  Objects.update, Objects.tickPool, FieldView.draw = originals.objectUpdate, originals.tickPool, originals.fieldDraw
  Zoom.allowSurvey = previousAllowSurvey
  check(moved and moved > 0, "player moved along the selected town route")
  return finish()
end
