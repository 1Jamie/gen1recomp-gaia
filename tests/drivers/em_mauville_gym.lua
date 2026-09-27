local U = require("tests.drivers.util")
local X = require("tests.drivers.em_xa_util")

local d = X.new("em_mauville_gym", "/tmp/em_mauville_gym")
local MAP = "EM_MAUVILLE_CITY_GYM"

local function grid()
  local g = {}
  for y = 5, 16 do
    for x = 0, 8 do g[y * 16 + x] = X.metatile(x, y) end
  end
  return g
end

local function sameGrid(a, b)
  local n = 0
  for k, v in pairs(a) do if b[k] ~= v then n = n + 1 end end
  return n
end

local function expectedAfterPress(before, which)
  local Story = require("src.core.game3.rse.story_specials")
  local C = require("src.core.game3.constants").of("emerald")
  local g = {}
  for k, v in pairs(before) do g[k] = v end
  local get = function(x, y) return g[y * 16 + x] end
  local set = function(x, y, mid) g[y * 16 + x] = mid end
  Story.mauvilleSetDefaultBarriers(get, set, C)
  Story.mauvillePressSwitch(which, get, set, C)
  return g
end

local function onBeams()
  local n = 0
  for y = 5, 16 do
    for x = 0, 8 do
      local m = X.metatile(x, y)
      for _, l in ipairs({ "GreenBeamH1_On", "GreenBeamH3_On", "RedBeamH1_On", "RedBeamH3_On", "GreenBeamV1_On", "RedBeamV1_On" }) do
        if m == X.label("METATILE_MauvilleGym_" .. l) then n = n + 1 end
      end
    end
  end
  return n
end

local function switchState()
  local out = {}
  for i, xy in ipairs(require("src.core.game3.rse.story_specials").MAUVILLE_SWITCHES) do
    out[i] = X.metatile(xy[1], xy[2]) == X.label("METATILE_MauvilleGym_PressedSwitch") and "P" or "R"
  end
  return table.concat(out)
end

return function(game)
  if not X.newGame(d, game, 0) then return d.finish() end
  d.check(X.goTo(d, game, MAP, 5, 19, "up"), "Mauville Gym loads")
  X.settle(game)
  local start = grid()
  d.check(X.var("VAR_MAUVILLE_GYM_STATE") == 0 and not X.flag("FLAG_MAUVILLE_GYM_BARRIERS_STATE"),
    "fresh gym: VAR_MAUVILLE_GYM_STATE 0, barriers default")
  d.note("switches " .. switchState() .. " beams on " .. onBeams())
  d.shot(game, "01_gym_default.png")

  local want1 = expectedAfterPress(start, 0)
  d.check(X.stepOnto(d, game, MAP, 0, 15), "player steps onto switch 1 (0,15)")
  X.waitFor(function() return not X.scriptRunning() end, 600)
  d.check(X.var("VAR_MAUVILLE_GYM_STATE") == 1, "switch 1 script sets VAR_MAUVILLE_GYM_STATE=1 (" .. X.var("VAR_MAUVILLE_GYM_STATE") .. ")")
  d.check(switchState() == "PRRR", "MauvilleGymPressSwitch presses switch 1 and raises the rest (" .. switchState() .. ")")
  d.check(X.flag("FLAG_MAUVILLE_GYM_BARRIERS_STATE"), "barriers flip to the alt state flag")
  local after1 = grid()
  d.check(sameGrid(want1, after1) == 0, "MauvilleGymSetDefaultBarriers toggles every beam like field_specials.c (" ..
    sameGrid(want1, after1) .. " cells differ)")
  d.check(sameGrid(start, after1) > 0, "the barrier layout changed (" .. sameGrid(start, after1) .. " cells)")
  do
    local Collision = require("src.core.game3.collision")
    local blocked, total = 0, 0
    for y = 5, 16 do
      for x = 0, 8 do
        local m = X.metatile(x, y)
        if m == X.label("METATILE_MauvilleGym_RedBeamH3_On") or m == X.label("METATILE_MauvilleGym_GreenBeamH3_On") then
          total = total + 1
          if not Collision.canEnter(game, x, y) then blocked = blocked + 1 end
        end
      end
    end
    d.check(total > 0 and blocked == total, string.format("lit beam H3 cells are impassable (%d/%d)", blocked, total))
  end
  d.shot(game, "02_switch1_pressed.png")

  local want2 = expectedAfterPress(after1, 1)
  d.check(X.stepOnto(d, game, MAP, 4, 12), "player steps onto switch 2 (4,12)")
  X.waitFor(function() return not X.scriptRunning() end, 600)
  d.check(X.var("VAR_MAUVILLE_GYM_STATE") == 2 and switchState() == "RPRR",
    "switch 2 pressed, switch 1 raised (" .. X.var("VAR_MAUVILLE_GYM_STATE") .. " " .. switchState() .. ")")
  local after2 = grid()
  d.check(sameGrid(want2, after2) == 0, "second press toggles the beams back (" .. sameGrid(want2, after2) .. " cells differ)")
  d.check(not X.flag("FLAG_MAUVILLE_GYM_BARRIERS_STATE"), "alt barrier flag cleared again")
  d.shot(game, "03_switch2_pressed.png")

  X.goTo(d, game, MAP, 5, 19, "up")
  X.settle(game)
  local reload = grid()
  local wantReload = {}
  for k, v in pairs(start) do wantReload[k] = v end
  do
    local Story = require("src.core.game3.rse.story_specials")
    Story.mauvillePressSwitch(1, function(x, y) return wantReload[y * 16 + x] end,
      function(x, y, mid) wantReload[y * 16 + x] = mid end, require("src.core.game3.constants").of("emerald"))
  end
  d.check(sameGrid(wantReload, reload) == 0, "ON_LOAD rebuilds the map layout with switch 2 pressed (VAR state 2, default barriers) (" ..
    sameGrid(wantReload, reload) .. " cells differ)")
  for k, v in pairs(wantReload) do
    if reload[k] ~= v then d.note(string.format("cell (%d,%d) want %s got %s after2 %s", k % 16, math.floor(k / 16), tostring(v), tostring(reload[k]), tostring(after2[k]))) end
  end
  d.note("in-play double toggle vs fresh layout differ in " .. sameGrid(after2, reload) .. " cells (FloorTile rule reads the row above live)")

  X.goTo(d, game, "EM_MAUVILLE_CITY", 8, 7, "down")
  d.check(X.var("VAR_MAUVILLE_GYM_STATE") == 0, "Mauville City ON_TRANSITION resets VAR_MAUVILLE_GYM_STATE (" ..
    X.var("VAR_MAUVILLE_GYM_STATE") .. ")")
  X.goTo(d, game, MAP, 5, 19, "up")
  X.settle(game)
  d.check(sameGrid(start, grid()) == 0 and switchState() == "RRRR", "re-entering from the city shows the default gym again")

  X.setFlag("FLAG_DEFEATED_MAUVILLE_GYM", true)
  X.goTo(d, game, "EM_MAUVILLE_CITY", 8, 7, "down")
  X.goTo(d, game, MAP, 5, 19, "up")
  X.settle(game)
  d.check(switchState() == "PPPP", "defeated gym: MauvilleGymDeactivatePuzzle presses every switch (" .. switchState() .. ")")
  d.check(onBeams() == 0, "defeated gym: every beam is off (" .. onBeams() .. " on)")
  d.shot(game, "04_puzzle_deactivated.png")
  d.finish()
end
