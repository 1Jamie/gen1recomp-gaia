local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

return function(game)
  local d = S.new("em_idle", "/tmp/em_idle")
  local check = d.check
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return d.finish() end
  local SaveData = require("src.core.SaveData")
  local Schema = require("src.core.game3.save_schema_firered")
  local raw = love.filesystem.read("saves/emerald/slot1.lua")
  if not check(type(raw) == "string", "identity has a save") then return d.finish() end
  local session = Schema.fromSaveTable(SaveData.decode(raw))
  require("src.core.game3.options").bind(session, game.options)
  game:adoptSave(session, true)
  game:_enterField(session, "continue")
  U.wait(30)
  S.settle(game)
  require("src.core.game3.encounters").onStep = function() return nil end
  local Map = require("src.core.game3.map")
  local Runtime = require("src.core.game3.runtime")

  local frames = 0
  local peak = 0
  local function sample(tag)
    print(string.format("SOAK %-22s nocollect lua=%7.1fMB peak=%7.1fMB", tag, collectgarbage("count") / 1024, peak / 1024))
    collectgarbage("collect")
    local st = love.graphics.getStats()
    print(string.format("SOAK %-22s f=%6d lua=%7.1fMB tex=%7.1fMB images=%5d canvases=%4d fonts=%d",
      tag, frames, collectgarbage("count") / 1024, st.texturememory / 1048576, st.images, st.canvases, st.fonts))
  end
  local function walk(dir, n)
    for _ = 1, n / 8 do
      U.hold(game, dir, 8)
      local c = collectgarbage("count")
      if c > peak then peak = c end
    end
    frames = frames + n
  end

  pcall(function() Map.load(nil, game, "EM_OLDALE_TOWN_POKEMON_CENTER_1F", { x = 7, y = 6, facing = "up" }) end)
  U.wait(60)
  local counts = {}
  local orig = love.graphics.newImage
  love.graphics.newImage = function(...)
    local tb = debug.traceback("", 2):gsub("\n%s*%[C%][^\n]*", "")
    local key = table.concat({ tb:match("\n%s*([^\n]+)\n%s*([^\n]+)\n%s*([^\n]+)\n%s*([^\n]+)") }, " <- ")
    counts[key] = (counts[key] or 0) + 1
    return orig(...)
  end
  U.wait(120)
  love.graphics.newImage = orig
  local rows = {}
  for k, v in pairs(counts) do rows[#rows + 1] = { k, v } end
  table.sort(rows, function(a, b) return a[2] > b[2] end)
  for i = 1, math.min(8, #rows) do print(string.format("NEWIMG %5d %s", rows[i][2], rows[i][1])) end
  local n = tonumber(os.getenv("EM_IDLE_SECONDS") or "30")
  local firstImages
  for sec = 1, n do
    U.wait(60)
    frames = frames + 60
    if sec % 10 == 0 then
      local st = love.graphics.getStats()
      print(string.format("IDLE t=%4ds lua=%7.1fMB tex=%6.1fMB images=%d canvases=%d drawcalls=%d", sec,
        collectgarbage("count") / 1024, st.texturememory / 1048576, st.images, st.canvases, st.drawcalls))
      firstImages = firstImages or st.images
    end
  end
  check(love.graphics.getStats().images <= (firstImages or 0) + 8, "idle field does not keep creating images")
  return d.finish()
end
