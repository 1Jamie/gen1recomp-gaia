local U = require("tests.drivers.util")
return function(game)
  for _ = 1, 900 do if game.boot then break end U.wait(1) end
  game:_handleBootAction({ action = "new_game", name = "PREP", gender = 0 })
  U.wait(60)
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local View = require("src.core.game3.field_view")
  local Plan = require("src.core.game3.field_plan")
  local Cells = require("src.core.game3.field_cell_prepare")
  local Stream = require("src.core.game3.asset_stream")
  local Objects = require("src.core.game3.objects")
  local Native = require("src.core.game3.tileset_native")
  local Void = require("src.core.game3.void_fill")
  local Prepare = require("src.core.game3.object_prepare")
  local version = require("src.core.GameVersion").get()
  local id = version == "emerald" and "EM_PETALBURG_CITY" or "FR_PALLET_TOWN"
  Map.load(nil, game, id, { x = 1, y = 1, facing = "down" }); U.wait(60)
  local baselinePath = os.getenv("POKEPORT_OBJECT_BASELINE") or "src/core/game3/objects.lua"
  local baseline = assert(love.filesystem.load(baselinePath))()
  local originalUpdate, originalDraw = game.update, game.draw
  game.update, game.draw = function() end, function() end
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
  end
  local function waitPrepared(test)
    local deadline = love.timer.getTime() + 5
    while not test() and love.timer.getTime() < deadline do Stream.poll(); U.wait(1) end
    return test()
  end
  local function stats(v)
    table.sort(v); return string.format("n=%d p99=%.3f max=%.3f", #v, v[math.ceil(#v * .99)] or 0, v[#v] or 0)
  end
  local def = game.data.maps[id]
  local times = { baseline = {}, worker_adopt = {}, snapshot = {} }
  for _ = 1, 20 do
    baseline._mapId, baseline._perm, baseline._templateMt = id, Objects._perm, Objects._templateMt
    local t = love.timer.getTime(); baseline.loadMap(game, id, def)
    times.baseline[#times.baseline + 1] = (love.timer.getTime() - t) * 1000
    t = love.timer.getTime(); Objects.prefetchMap(id, def, 0)
    times.snapshot[#times.snapshot + 1] = (love.timer.getTime() - t) * 1000
    local deadline = love.timer.getTime() + 5
    repeat
      Stream.poll(); U.wait(1)
    until not Objects._preparationPending(id) or love.timer.getTime() > deadline
    t = love.timer.getTime(); Objects.loadMap(game, id, def)
    times.worker_adopt[#times.worker_adopt + 1] = (love.timer.getTime() - t) * 1000
    check(Objects._lastPreparationRoute == "worker", "object reload used worker")
    local equal = Prepare.matches(Prepare.freeze(baseline._byId), Prepare.freeze(Objects._byId))
    if not equal and #times.baseline == 1 then
      local function differences(a, b, path)
        if type(a) ~= type(b) then print("OBJECT_DIFF " .. path .. " " .. tostring(a) .. " / " .. tostring(b)); return end
        if type(a) == "table" then
          for k, v in pairs(a) do differences(v, b[k], path .. "." .. tostring(k)) end
          for k, v in pairs(b) do if a[k] == nil then differences(nil, v, path .. "." .. tostring(k)) end end
        elseif a ~= b then print("OBJECT_DIFF " .. path .. " " .. tostring(a) .. " / " .. tostring(b)) end
      end
      differences(baseline._byId, Objects._byId, "objects")
    end
    check(equal, "worker object pool equals synchronous pool")
  end
  for phase, values in pairs(times) do print("OBJECT_PROFILE " .. phase .. " " .. stats(values)) end
  local savedGet = Plan.get
  local function render(w, h, forceSync)
    local canvas = love.graphics.newCanvas(w, h, { dpiscale = 1 })
    love.graphics.setCanvas(canvas); love.graphics.clear(0, 0, 0, 1)
    View._nativeVisibleCells = nil
    if forceSync then Plan.get = function() return nil end end
    local t = love.timer.getTime(); View.draw(game, w, h)
    local ms = (love.timer.getTime() - t) * 1000
    Plan.get = savedGet
    love.graphics.setCanvas()
    local image = canvas:newImageData()
    canvas:release()
    return image, ms
  end
  for _, size in ipairs({ { "fit", 240, 160 }, { "survey", 960, 640 } }) do
    for _, mode in ipairs(Void.MODES) do
      Void.setMode(mode)
      Player.reset(-2, -2, "down")
      render(size[2], size[3], true)
      Plan.prefetch(game)
      local cx = math.floor((Player.px + 8 - size[2] / 2) / 16) - 1
      local cy = math.floor((Player.py + 8 - size[3] / 2) / 16) - 1
      local cols, rows = math.ceil(size[2] / 16) + 3, math.ceil(size[3] / 16) + 3
      check(waitPrepared(function() return Plan.get(def, cx, cy, cols, rows, mode) ~= nil end), size[1] .. " " .. mode .. " cell worker ready")
      local p = Plan.get(def, cx, cy, cols, rows, mode)
      local matches = p ~= nil
      if p then
        for y = cy, cy + rows - 1 do for x = cx, cx + cols - 1 do
          local mid, pair, void = Map.worldMidAt(x, y, def)
          local skip = false
          if void and mode ~= "map" then
            local fill = Void.fillAt(mode, x, y, function(m) return Native.hasMid(def.midLayout.pair, m) end, Void.primaryFor(def.midLayout.pair))
            if fill == false then skip = true elseif fill then mid, pair = fill, def.midLayout.pair end
          end
          local actual, ap, av, as = Cells.cell(p, x, y)
          matches = matches and actual == mid and ap == pair and av == not not void and as == skip
        end end
      end
      check(matches, size[1] .. " " .. mode .. " all planned cells equal original resolver")
      local prepared, preparedMs = render(size[2], size[3], false)
      check(View._cellPreparationRoute == "worker", size[1] .. " " .. mode .. " draw consumes planned cells")
      local original, originalMs = render(size[2], size[3], true)
      check(prepared:getString() == original:getString(), size[1] .. " " .. mode .. " complete field pixels equal")
      local workerTimes, syncTimes = { preparedMs }, { originalMs }
      for i = 2, 20 do
        -- Alternate order and finish each readback before the next sample.
        local a, ams = render(size[2], size[3], i % 2 == 0)
        local b, bms = render(size[2], size[3], i % 2 ~= 0)
        if i % 2 == 0 then syncTimes[i], workerTimes[i] = ams, bms
        else workerTimes[i], syncTimes[i] = ams, bms end
        a:release(); b:release()
      end
      print(string.format("VOID_PROFILE %s %s worker_draw %s sync_draw %s", size[1], mode, stats(workerTimes), stats(syncTimes)))
      if os.getenv("POKEPORT_SHOT_DIR") then
        local bytes = prepared:encode("png")
        local f = assert(io.open(os.getenv("POKEPORT_SHOT_DIR") .. "/" .. size[1] .. "_" .. mode .. ".png", "wb"))
        f:write(bytes:getString()); f:close()
      end
      prepared:release(); original:release()
    end
  end
  Void.setMode("map"); Plan.invalidate()
  game.update, game.draw = originalUpdate, originalDraw
  print((failures == 0 and "PASS" or "FAIL") .. " game3_field_prepare_profile failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end
