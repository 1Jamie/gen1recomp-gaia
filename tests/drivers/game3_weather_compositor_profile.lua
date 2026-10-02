local U = require("tests.drivers.util")
local function stats(v)
  table.sort(v)
  local sum = 0; for _, n in ipairs(v) do sum = sum + n end
  return string.format("n=%d mean=%.3f p99=%.3f max=%.3f", #v, sum / #v, v[math.ceil(#v * .99)], v[#v])
end
return function(game)
  for _ = 1, 900 do if game.boot then break end U.wait(1) end
  game:_handleBootAction({ action = "new_game", name = "WEATHER", gender = 0 })
  U.wait(60)
  local Map = require("src.core.game3.map")
  Map.load(nil, game, "EM_PETALBURG_CITY", { x = 17, y = 13 })
  U.wait(90)
  local R = require("src.core.game3.field_weather_rse")
  local baselinePath = os.getenv("WEATHER_BASELINE")
  local baseline = baselinePath and assert(love.filesystem.load(baselinePath))() or nil
  local Field = require("src.core.game3.field_view")
  local Renderer = require("src.render.Renderer")
  local Rng = require("src.core.game3.rng")
  local Oam = require("src.core.game3.oam")
  local failures = 0
  local function check(ok, label) print((ok and "PASS " or "FAIL ") .. label); if not ok then failures = failures + 1 end end
  local saveUpdate, saveDraw = game.update, game.draw
  game.update, game.draw = function() end, function() end
  local function weather(engine, id, frames)
    engine.restart(); Rng._value = 42
    engine.setCurrentAndNextWeatherNoDelay(id)
    for _ = 1, frames do engine.update() end
  end
  local function render(engine, w, h, swap)
    package.loaded["src.core.game3.field_weather_rse"] = engine
    Oam.resetFrame()
    local canvas = Renderer.worldCanvas
    if not canvas or canvas:getWidth() ~= w or canvas:getHeight() ~= h then
      canvas = love.graphics.newCanvas(w, h, { dpiscale = 1 })
    end
    Renderer.worldCanvas, Renderer.worldActive = canvas, true
    love.graphics.setCanvas(canvas); love.graphics.clear(.2, .3, .4, 1)
    local switches, oldSet = 0, love.graphics.setCanvas
    love.graphics.setCanvas = function(...) switches = switches + 1; return oldSet(...) end
    local t = love.timer.getTime()
    Field.draw(game, w, h, { exchangeCanvas = swap and function(cur, next) return Renderer:exchangeWorldCanvas(cur, next) end or nil })
    love.graphics.setCanvas = oldSet
    local cpu = (love.timer.getTime() - t) * 1000
    oldSet()
    local image = Renderer.worldCanvas:newImageData()
    local sync = (love.timer.getTime() - t) * 1000
    return image, cpu, sync, switches
  end
  for _, size in ipairs({ { "fit", 240, 160 }, { "survey", 960, 640 } }) do
    for _, spec in ipairs({ { "clear", 2, 180 }, { "shade", 11, 180 }, { "rain", 3, 180 },
        { "drought", 12, 180 }, { "fog", 6, 180 }, { "sandstorm", 8, 180 }, { "sandstorm_blend", 8, 2 } }) do
      weather(R, spec[2], spec[3])
      local copy = render(R, size[2], size[3], false)
      local swapped = render(R, size[2], size[3], true)
      check(copy:getString() == swapped:getString(), size[1] .. " " .. spec[1] .. " copy vs exchange pixels")
      if baseline then
        weather(baseline, spec[2], spec[3])
        render(baseline, size[2], size[3], false)
        local original = render(baseline, size[2], size[3], false)
        if original:getString() ~= swapped:getString() then
          local a, b, count, max = original:getString(), swapped:getString(), 0, 0
          for i = 1, #a do local d = math.abs(a:byte(i) - b:byte(i)); if d > 0 then count = count + 1; max = math.max(max, d) end end
          print(string.format("WEATHER_DIFF %s %s channels=%d max=%d eva=%d evb=%d", size[1], spec[1], count, max, R.state.currBlendEVA, R.state.currBlendEVB))
        end
        check(original:getString() == swapped:getString(), size[1] .. " " .. spec[1] .. " original vs batched exchange pixels")
      end
      for _, mode in ipairs({ { "copy", baseline or R, false }, { "exchange", R, true } }) do
        weather(mode[2], spec[2], spec[3])
        local cpus, synced, switches = {}, {}, {}
        for _ = 1, 60 do
          local _, cpu, sync, count = render(mode[2], size[2], size[3], mode[3])
          cpus[#cpus + 1], synced[#synced + 1], switches[#switches + 1] = cpu, sync, count
        end
        print(string.format("WEATHER_PROFILE %s %s %s cpu %s completion_with_readback %s switches=%d", size[1], spec[1], mode[1],
          stats(cpus), stats(synced), switches[#switches]))
      end
      if os.getenv("POKEPORT_SHOT_DIR") then
        swapped:encode("png", "weather-preview.png")
        local bytes = love.filesystem.read("weather-preview.png")
        local f = assert(io.open(os.getenv("POKEPORT_SHOT_DIR") .. "/" .. size[1] .. "_" .. spec[1] .. ".png", "wb")); f:write(bytes); f:close()
        love.filesystem.remove("weather-preview.png")
      end
    end
  end
  -- Exercise Display's actual target exchange, upright actors, and UI planes.
  local Zoom, Tilt = require("src.render.Zoom"), require("src.render.Tilt")
  local uprightCalls, beginUpright = 0, Renderer.beginUprightPass
  Renderer.beginUprightPass = function(self, ...)
    uprightCalls = uprightCalls + 1
    return beginUpright(self, ...)
  end
  Zoom.allowSurvey = true
  if baseline then
    for _, zoom in ipairs({ 0, Zoom.offsetRange(Renderer:fitScale()) }) do
      game.options.zoom = zoom; Zoom.offset = zoom
      for _, tilt in ipairs({ 0, 2 }) do
        game.options.tilt = tilt; Tilt.setLevel(tilt); Tilt.update(1)
        for _, id in ipairs({ 2, 3, 6, 11, 12, 8 }) do
          local function planes(engine)
            package.loaded["src.core.game3.field_weather_rse"] = engine
            weather(engine, id, 180)
            local before = uprightCalls
            saveDraw(game); saveDraw(game)
            if tilt > 0 then check(uprightCalls == before + 2, "upright pass rendered") end
            local out = {}
            for _, key in ipairs({ "worldCanvas", "uprightCanvas", "canvas" }) do
              local target = Renderer[key]
              if target then out[key] = target:newImageData():getString() end
            end
            return out
          end
          local a, b = planes(baseline), planes(R)
          for key, bytes in pairs(a) do
            check(bytes == b[key], string.format("display zoom=%d tilt=%d weather=%d %s pixels", zoom, tilt, id, key))
          end
        end
        if os.getenv("POKEPORT_SHOT_DIR") then
          game.draw = saveDraw
          U.still(game, os.getenv("POKEPORT_SHOT_DIR") .. string.format("/display_zoom%d_tilt%d.png", zoom, tilt))
          game.draw = function() end
        end
      end
    end
  end
  Renderer.beginUprightPass = beginUpright
  package.loaded["src.core.game3.field_weather_rse"] = R
  game.update, game.draw = saveUpdate, saveDraw
  love.graphics.setCanvas()
  print((failures == 0 and "PASS" or "FAIL") .. " game3_weather_compositor_profile failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end
