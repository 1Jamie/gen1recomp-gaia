package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local GameVersion = require("src.core.GameVersion")

local MB_WARP_DOOR = 0x69

package.loaded["src.core.game3.audio"] = { playSe = function() end, fadeOutBgm = function() end }

local Player = { facing = "down", cellX = 6, cellY = 6, visible = true, spriteYOffset = 0, steps = {} }
function Player.setVisible(v) Player.visible = v and true or false end
function Player.forceStep(dir, cb)
  Player.facing = dir
  Player.steps[#Player.steps + 1] = { dir = dir, cb = cb, left = 16 }
  return true
end
package.loaded["src.core.game3.player"] = Player

local Fade = require("src.ui.game3.fade")
local frameNo, loadFrame, lastStepEnd = 0, nil, nil
local Map = {}
function Map.load(_, _, _, opts)
  loadFrame = frameNo
  Player.cellX, Player.cellY, Player.facing = opts.x, opts.y, opts.facing
end
package.loaded["src.core.game3.map"] = Map
package.loaded["src.ui.game3.map_preview_screen"] = {
  has = function() return false end, isForestActive = function() return false end, dismiss = function() end,
}
package.loaded["src.import.gba.map_preview_extract"] = { TYPE_CAVE = 1 }

local doorCalls = {}
local Doors = { SOUND_EXIT = 9 }
local function rec(kind) doorCalls[#doorCalls + 1] = { kind = kind, frame = frameNo, visible = Player.visible } end
function Doors.open(_, _, _, _, cb) rec("open"); if cb then cb() end end
function Doors.close(_, _, _, _, cb) rec("close"); if cb then cb() end end
function Doors.holdOpen() rec("hold") end
function Doors.closeAfterDelay(_, _, _, delay, _, cb)
  local left = tonumber(delay) or 0
  require("src.core.game3.task").spawn(function()
    left = left - 1
    if left > 0 then return false end
    rec("close")
    if cb then cb() end
    return true
  end)
end
function Doors.getSoundForWarp() return 0 end
function Doors.reset() end
package.loaded["src.core.game3.doors"] = Doors

local Flags = require("src.core.game3.scripting.flags")
package.loaded["src.core.game3.scripting.space"] = { store = Flags.newStore() }
local Field = { _fieldCallback = false }
function Field.lock() end
function Field.unlock() end
package.loaded["src.core.game3.field"] = Field

local Collision = require("src.core.game3.collision")
Collision.behavior = function() return MB_WARP_DOOR end

local Task = require("src.core.game3.task")
local Warp = require("src.core.game3.warp")

local game = { data = { maps = {
  A = { mapType = 8, regionMapSectionId = 1, music = 100 },
  C = { mapType = 3, regionMapSectionId = 1, music = 100 },
} } }

local function frame()
  frameNo = frameNo + 1
  Fade.tick(1 / 60)
  Task.update(1 / 60)
  for i = #Player.steps, 1, -1 do
    local s = Player.steps[i]
    s.left = s.left - 1
    if s.left <= 0 then
      table.remove(Player.steps, i)
      lastStepEnd = frameNo
      if s.cb then s.cb() end
    end
  end
end

local function run(version)
  GameVersion.set(version)
  doorCalls, frameNo, loadFrame = {}, 0, nil
  Fade.clear()
  Fade._wipe = nil
  Task.clear()
  Warp.clear()
  Player.steps, Player.visible = {}, true
  local out = { widths = {}, fadeInEnd = nil, wipeEnd = nil, wipeAtLoad = nil }
  local done = false
  Warp.scripted(nil, game, "warp", "C", 6, 6, nil, function()
    done = true
    out.doneAt = frameNo
  end)
  while not done and frameNo < 600 do
    frame()
    if loadFrame then
      if out.wipeAtLoad == nil then
        local w = Fade._wipe
        out.wipeAtLoad = w and { lhs = w.lhs, rhs = w.rhs } or false
        out.fadeModeAtLoad = Fade.mode
      end
      local w = Fade._wipe
      if w then
        out.widths[#out.widths + 1] = w.rhs - w.lhs
      elseif not out.wipeEnd and out.wipeAtLoad then
        out.wipeEnd = frameNo - loadFrame
      end
      if not out.fadeInEnd and not Fade.active and (Fade.t or 0) == 0 then
        out.fadeInEnd = frameNo - loadFrame
      end
    end
  end
  out.done = done
  return out
end

local function find(kind)
  for _, c in ipairs(doorCalls) do if c.kind == kind then return c end end
end

-- pokefirered/src/field_fadetransition.c:335
local r = run("firered")
T.check(r.done, "FRLG door exit completes")
T.check(r.wipeAtLoad and r.wipeAtLoad.lhs == 120 and r.wipeAtLoad.rhs == 120,
  "FRLG door exit starts an outward barn door wipe with the screen fully masked")
local okSteps, prev = true, -1
for _, w in ipairs(r.widths) do
  if w < prev then okSteps = false end
  if prev >= 0 and w ~= prev and w - prev ~= (prev <= 60 and 4 or 8) then okSteps = false end
  prev = w
end
T.check(okSteps, "FRLG wipe widens 2px per side per frame, then 4px once past x=90")
T.eq(r.widths[#r.widths], 240, "FRLG wipe opens to the full 240px")
T.check(r.wipeEnd and r.wipeEnd >= 39 and r.wipeEnd <= 42, "FRLG wipe lasts the pret ~41 frames (" .. tostring(r.wipeEnd) .. ")")
-- pokefirered/src/palette.c:408
T.check(r.fadeInEnd and r.fadeInEnd >= 38 and r.fadeInEnd <= 46,
  "FRLG delay-3 fade-in takes 5 frames per 2/16 step (" .. tostring(r.fadeInEnd) .. ")")
local open = find("open")
T.check(open and open.frame - loadFrame >= 24 and open.frame - loadFrame <= 26, "FRLG door animates open 25 frames in")
T.check(find("hold") == nil, "FRLG door is not pre-opened")
T.check(r.doneAt and r.wipeEnd and r.doneAt - loadFrame >= r.wipeEnd, "FRLG exit waits for the wipe to finish")

-- pokeemerald/src/field_screen_effect.c:317
for _, v in ipairs({ "emerald", "ruby" }) do
  r = run(v)
  T.check(r.done, v .. " door exit completes")
  T.check(r.wipeAtLoad == false, v .. " door exit has no barn door wipe")
  local hold = find("hold")
  T.check(hold and hold.frame == loadFrame, v .. " door is set open on arrival")
  T.check(find("open") == nil, v .. " door does not animate open")
  T.check(r.fadeInEnd and r.fadeInEnd <= 18, v .. " fades in at delay 0 (" .. tostring(r.fadeInEnd) .. ")")
  local close = find("close")
  T.check(close and close.frame - loadFrame >= r.fadeInEnd + 16, v .. " door closes after the player steps out")
end

-- pokefirered/src/field_fadetransition.c:765
-- pokeemerald/src/field_screen_effect.c:704
-- pokeruby/src/field_fadetransition.c:587
for _, v in ipairs({ "firered", "emerald", "ruby" }) do
  GameVersion.set(v)
  doorCalls, frameNo, loadFrame, lastStepEnd = {}, 0, nil, nil
  Fade.clear()
  Fade._wipe = nil
  Task.clear()
  Warp.clear()
  Player.steps, Player.visible, Player.cellX, Player.cellY = {}, true, 6, 7
  local entered = false
  Warp.startDoorEntrance(nil, { currentMap = "C", data = game.data }, "A", 3, 7, 6, 6)
  while not loadFrame and frameNo < 600 do frame() end
  entered = loadFrame ~= nil
  T.check(entered, v .. " door entry loads the destination")
  local close = find("close")
  T.check(close and lastStepEnd and close.frame == lastStepEnd,
    v .. " entry door closes the frame the player stops (close=" .. tostring(close and close.frame)
      .. " step=" .. tostring(lastStepEnd) .. ")")
  T.check(close and close.visible == false, v .. " player is hidden as the door starts closing")
end

GameVersion.set("firered")
T.finish("game3_door_exit_wipe_2895")
