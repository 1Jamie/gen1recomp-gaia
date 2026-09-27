local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_weather_sweep"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_weather_sweep failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Weather = require("src.core.game3.weather")
  local E = require("src.core.game3.field_weather_rse")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field session exists") then return finish() end

  local function settle(frames)
    for _ = 1, frames or 600 do
      local busy = Warp.isBusy() or (Message.isOpen and Message.isOpen())
        or (Space.vm and Space.vm:isRunning())
      if not busy then break end
      if Message.isOpen and Message.isOpen() then U.tap(game, "b") end
      U.wait(1)
    end
  end

  local function place(mapId, x, y, facing)
    settle()
    local ok, err = pcall(function() Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" }) end)
    if not ok then print("[driver] Map.load " .. mapId .. " error " .. tostring(err)) end
    local s = Runtime.getSession()
    if s then s.x, s.y, s.facing = x, y, facing or "down" end
    require("src.core.game3.field").unlock()
    U.wait(2)
    settle()
    return ok
  end

  local function walkableNear(mapId, x, y)
    place(mapId, x, y)
    for r = 0, 12 do
      for dy = -r, r do
        for dx = -r, r do
          if math.max(math.abs(dx), math.abs(dy)) == r then
            local cx, cy = x + dx, y + dy
            if Collision.inBounds(cx, cy) and Collision.isWalkable(cx, cy)
                and not (Collision.isWater and Collision.isWater(cx, cy)) then
              return cx, cy
            end
          end
        end
      end
    end
    return x, y
  end

  local function goTo(mapId, x, y, facing)
    local cx, cy = walkableNear(mapId, x, y)
    place(mapId, cx, cy, facing)
    return cx, cy
  end

  local function snap()
    return E.snapshot()
  end

  local function waitFor(pred, frames)
    for _ = 1, frames or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end

  local x, y = goTo("EM_ROUTE120", 5, 30, "down")
  U.wait(30)
  local s = snap()
  check(s.curr == Weather.RAIN, string.format("Route 120 (%d,%d) ON_TRANSITION sets rain (curr=%s)", x, y, tostring(s.curr)))
  check(s.colorMapIndex == 3, "rain darkens with color map 3 (" .. tostring(s.colorMapIndex) .. ")")
  check(s.rain == 24, "24 rain sprites created (" .. tostring(s.rain) .. ")")
  check(s.rainVisible == 10, "10 rain sprites visible (" .. tostring(s.rainVisible) .. ")")
  U.wait(60)
  U.shot(game, DIR .. "/01_route120_rain.png")

  session.weatherCycleStage = 2
  goTo("EM_ROUTE119", 29, 14, "up")
  local before = Weather.get()
  local sx, sy = Player.cellX, Player.cellY
  print(string.format("[driver] route119 start (%d,%d) weather=%s", sx, sy, tostring(before)))
  place("EM_ROUTE119", 29, 14, "up")
  U.hold(game, "up", 16)
  U.wait(20)
  local ok119 = waitFor(function() return snap().next == Weather.RAIN_THUNDERSTORM end, 60)
  check(ok119, string.format("stepping on Route 119 (29,13) runs the cycle coord event -> thunderstorm (next=%s at %d,%d)",
    tostring(snap().next), Player.cellX, Player.cellY))
  local switched = waitFor(function() return snap().curr == Weather.RAIN_THUNDERSTORM end, 400)
  check(switched, "sunny -> thunderstorm transition completes (curr=" .. tostring(snap().curr) .. ")")
  U.wait(120)
  U.shot(game, DIR .. "/02_route119_thunderstorm.png")
  local flash = waitFor(function() return snap().colorMapIndex == 19 end, 1500)
  check(flash, "thunderstorm lightning applies color map 19")
  if flash then U.still(game, DIR .. "/03_route119_lightning.png") end

  goTo("EM_ROUTE111", 20, 85, "down")
  U.wait(40)
  s = snap()
  check(s.curr == Weather.SANDSTORM and s.sandstorm, "Route 111 desert ON_TRANSITION sets sandstorm (" .. tostring(s.curr) .. ")")
  check(s.eva == 16 and s.evb == 0, string.format("sandstorm blend reaches 16/0 (%s/%s)", tostring(s.eva), tostring(s.evb)))
  U.wait(200)
  U.shot(game, DIR .. "/04_route111_sandstorm.png")

  goTo("EM_ROUTE113", 20, 11, "left")
  place("EM_ROUTE113", 20, 11, "left")
  local okAshStep = Player.cellX == 20 and Player.cellY == 11
  U.hold(game, "left", 16)
  U.wait(10)
  check(okAshStep and snap().next == Weather.VOLCANIC_ASH,
    string.format("Route 113 (19,11) coord event sets volcanic ash (next=%s at %d,%d)", tostring(snap().next),
      Player.cellX, Player.cellY))
  waitFor(function() local q = snap(); return q.curr == Weather.VOLCANIC_ASH and q.eva == 16 end, 400)
  s = snap()
  check(s.ash and s.eva == 16 and s.evb == 0, string.format("ash fades in to 16/0 (%s/%s)", tostring(s.eva), tostring(s.evb)))
  U.shot(game, DIR .. "/05_route113_ash.png")

  goTo("EM_MT_PYRE_SUMMIT", 22, 20, "up")
  U.wait(30)
  s = snap()
  check(s.curr == Weather.FOG_HORIZONTAL and s.fogH, "Mt. Pyre summit header fog (" .. tostring(s.curr) .. ")")
  check(s.eva == 12 and s.evb == 8, string.format("fog blend 12/8 (%s/%s)", tostring(s.eva), tostring(s.evb)))
  U.shot(game, DIR .. "/06_mt_pyre_fog.png")

  goTo("EM_PETALBURG_WOODS", 14, 32, "up")
  U.wait(30)
  s = snap()
  check(s.curr == Weather.SHADE and s.colorMapIndex == 3, "Petalburg Woods shade -> color map 3 (" .. tostring(s.colorMapIndex) .. ")")
  U.shot(game, DIR .. "/07_petalburg_woods_shade.png")

  goTo("EM_SOOTOPOLIS_CITY", 31, 34, "down")
  Weather.set(Weather.ABNORMAL)
  Weather.doWeather()
  U.wait(10)
  check(snap().next == Weather.DOWNPOUR, "abnormal weather starts with a downpour (" .. tostring(snap().next) .. ")")
  waitFor(function() return snap().curr == Weather.DOWNPOUR end, 600)
  U.wait(60)
  U.shot(game, DIR .. "/08_sootopolis_downpour.png")
  local toDrought = waitFor(function() return snap().next == Weather.DROUGHT end, 700)
  check(toDrought, "abnormal weather alternates to drought after 600 frames")
  local droughtOn = waitFor(function() local q = snap(); return q.curr == Weather.DROUGHT and q.colorMapIndex < 0 end, 900)
  check(droughtOn, "drought applies the drought color tables (idx=" .. tostring(snap().colorMapIndex) .. ")")
  U.wait(40)
  U.shot(game, DIR .. "/09_sootopolis_drought.png")

  goTo("EM_UNDERWATER_ROUTE124", 16, 4, "down")
  Player.underwater = true
  U.wait(200)
  s = snap()
  check(s.curr == Weather.UNDERWATER_BUBBLES and s.fogH, "underwater bubbles weather (" .. tostring(s.curr) .. ")")
  check(s.bubbles > 0, "bubble sprites spawn (" .. tostring(s.bubbles) .. ")")
  check(s.eva == 4 and s.evb == 16, string.format("underwater fog blend 4/16 (%s/%s)", tostring(s.eva), tostring(s.evb)))
  U.shot(game, DIR .. "/10_underwater_bubbles.png")
  Player.underwater = false

  goTo("EM_ROUTE120", 8, 72, "down")
  U.wait(60)
  s = snap()
  check(s.curr == Weather.SUNNY_CLOUDS and s.clouds == 3, "Route 120 south clouds (" .. tostring(s.curr) .. ")")
  U.shot(game, DIR .. "/11_route120_clouds.png")

  place("EM_ROUTE117", 51, 6, "down")
  U.wait(60)
  U.still(game, DIR .. "/12_route117_none.png")
  Weather.setWeather(Weather.RAIN)
  U.wait(400)
  check(snap().curr == Weather.RAIN and snap().colorMapIndex == 3, "Route 117 rain reaches color map 3")
  U.still(game, DIR .. "/13_route117_rain.png")
  Weather.setWeather(Weather.FOG_HORIZONTAL)
  U.wait(400)
  check(snap().curr == Weather.FOG_HORIZONTAL and snap().eva == 12, "Route 117 fog reaches blend 12/8")
  U.still(game, DIR .. "/14_route117_fog.png")
  Weather.setWeather(Weather.SHADE)
  U.wait(300)
  U.still(game, DIR .. "/15_route117_shade.png")

  session.weatherCycleStage = 3
  local TimeEvents = require("src.core.game3.time_events")
  local perDay = TimeEvents.handlers()
  if perDay.UpdateWeatherPerDay then perDay.UpdateWeatherPerDay(session, 2) end
  check(session.weatherCycleStage == 1, "UpdateWeatherPerDay advances the cycle stage mod 4 (" .. tostring(session.weatherCycleStage) .. ")")

  finish()
end
