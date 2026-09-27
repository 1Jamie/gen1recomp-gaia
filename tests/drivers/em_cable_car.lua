local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("em_cable_car", "/tmp/em_cable_car")

local function ride(game, fromMap, toMap, goingDown, tag)
  local Core = require("src.core.game3.rse.cable_car")
  Core.last = nil
  d.check(X.goTo(d, game, fromMap, 6, 9, "up"), tag .. ": station loads (" .. fromMap .. ")")
  U.wait(20)
  local att = require("src.core.game3.objects").find(1)
  local ax, ay = att and att.cellX or 6, att and att.cellY or 6
  d.note(string.format("%s attendant at (%s,%s)", tag, tostring(ax), tostring(ay)))
  X.goTo(d, game, fromMap, ax, ay + 1, "up")
  U.wait(20)
  local reached = X.mash(game, function() return Core.last ~= nil and Core.last.phase ~= "fade" end, 1500)
  if not d.check(reached, tag .. ": attendant YES runs CableCarWarp + CableCar (" .. tostring(Core.last and Core.last.phase) .. ")") then
    return false
  end
  d.check(Core.last.goingDown == goingDown, tag .. ": VAR_0x8004 direction reaches the scene (goingDown=" .. tostring(Core.last.goingDown) .. ")")
  local sess = X.session()
  local w = sess and sess.warpDestination
  d.check(w and w.map == toMap and w.x == 6 and w.y == 4,
    tag .. ": CableCarWarp targets " .. toMap .. " (6,4) (" .. tostring(w and w.map) .. ")")
  local scene = Core.last.screen
  if not d.check(scene ~= nil, tag .. ": cable car scene opened") then return false end
  local dumpAt = {}
  for f in (os.getenv("XA_DUMP_FRAMES") or ""):gmatch("%d+") do dumpAt[tonumber(f)] = true end
  if next(dumpAt) then
    local orig = scene.frame
    scene.frame = function(self, inp)
      orig(self, inp)
      if dumpAt[self.frames] then
        local data = self.m.ppu:snapshot():encode("png"):getString()
        os.execute('mkdir -p "' .. d.dir .. '/raw" 2>/dev/null')
        local h = io.open(string.format("%s/raw/%s_f%04d.png", d.dir, tag, self.frames), "wb")
        if h then h:write(data) h:close() end
      end
    end
  end
  local shots = { { 40, "fade_in" }, { 200, "riding" }, { 380, "weather_change" }, { 560, "arriving" } }
  local carX0, lastCarX
  for _, s in ipairs(shots) do
    X.waitFor(function() return scene.frames >= s[1] or scene.done end, 20000)
    if scene.done then break end
    local car = scene.car
    if car then
      carX0 = carX0 or car.x
      lastCarX = car.x
      d.note(string.format("%s frame %d car=(%d,%d) timer=%d weather=%d->%d ash=%s", tag, scene.frames, car.x, car.y,
        scene.c.timer, scene.w.currWeather, scene.w.nextWeather, tostring(scene.w.ashSpritesCreated)))
    end
    d.still(game, tag .. "_" .. string.format("%02d", math.floor(s[1] / 10)) .. "_" .. s[2] .. ".png")
  end
  d.check(scene.player ~= nil and scene.player.inUse, tag .. ": player sprite rides in the car")
  if goingDown then
    d.check(carX0 and lastCarX and lastCarX > carX0, tag .. ": the car travels right and down (x " .. tostring(carX0) .. " -> " .. tostring(lastCarX) .. ")")
    d.check(scene.w.currWeather == 2, tag .. ": ash clears to WEATHER_SUNNY by the bottom (" .. tostring(scene.w.currWeather) .. ")")
  else
    d.check(carX0 and lastCarX and lastCarX < carX0, tag .. ": the car travels left and up (x " .. tostring(carX0) .. " -> " .. tostring(lastCarX) .. ")")
    d.check(scene.w.ashSpritesCreated, tag .. ": volcanic ash starts falling near the summit")
  end
  local done = X.waitFor(function() return Core.last.phase == "done" end, 30000)
  d.check(done, tag .. ": scene fades out and warps (" .. tostring(Core.last.phase) .. ")")
  X.settle(game, 900)
  local s = X.session()
  d.check(s and s.map == toMap, tag .. ": arrives at " .. toMap .. " (" .. tostring(s and s.map) .. ")")
  local exited = X.waitFor(function() return X.var("VAR_CABLE_CAR_STATION_STATE") == 0 and not X.scriptRunning() end, 2400)
  d.check(exited, tag .. ": station ON_FRAME walks the player out and resets VAR_CABLE_CAR_STATION_STATE (" ..
    X.var("VAR_CABLE_CAR_STATION_STATE") .. ")")
  d.shot(game, tag .. "_99_arrival.png")
  return true
end

return function(game)
  local sess = X.newGame(d, game, 0)
  if not sess then return d.finish() end
  local okUp = ride(game, "EM_ROUTE112_CABLE_CAR_STATION", "EM_MT_CHIMNEY_CABLE_CAR_STATION", false, "up")
  if okUp then
    ride(game, "EM_MT_CHIMNEY_CABLE_CAR_STATION", "EM_ROUTE112_CABLE_CAR_STATION", true, "down")
  end
  d.finish()
end
