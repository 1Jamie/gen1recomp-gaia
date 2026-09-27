package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Game2 = require("src.core.Game2")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")
local Performance = require("src.core.Performance")
local FrameCap = require("src.core.FrameCap")
local Tilt = require("src.render.Tilt")
local ShaderFX = require("src.render.ShaderFX")
local Zoom = require("src.render.Zoom")

local performanceRow
for _, row in ipairs(OptionsMenu.ROWS) do
  if row.id == "performance" then performanceRow = row end
end
check(performanceRow ~= nil, "Gen 2 OPTIONS exposes PERFORMANCE")

do
  local options = { performance = "auto" }
  local fullApply, scopedApply = 0, 0
  local game = {
    options = options,
    applyOptions = function() fullApply = fullApply + 1 end,
    applyPerformanceOptions = function() scopedApply = scopedApply + 1 end,
  }
  performanceRow.step(game, 1)
  eq(options.performance, "high", "the row still cycles AUTO to HIGH")
  eq(scopedApply, 1, "the row applies only the performance scope")
  eq(fullApply, 0, "the row does not re-enter the full display apply")
end

do
  local oldLevel = Tilt.level
  local oldOffset, oldSurvey = Zoom.offset, Zoom.allowSurvey
  local oldCap = FrameCap.current
  local oldSetLevel, oldDeactivate = Tilt.setLevel, ShaderFX.deactivate
  local tiltSeen, deactivated = nil, false
  Tilt.setLevel = function(level) tiltSeen = level Tilt.level = level end
  ShaderFX.deactivate = function() deactivated = true end
  FrameCap.current = 144
  Zoom.offset, Zoom.allowSurvey = -1, true

  local game = setmetatable({ options = { performance = "low" } }, Game2)
  local caps = game:applyPerformanceOptions()
  eq(caps.fpsMax, 60, "LOW keeps its 60 FPS cap")
  eq(tiltSeen, 0, "LOW disables tilt live")
  check(deactivated, "LOW disables shader FX live")
  check(not Zoom.allowSurvey and Zoom.offset == 0,
    "LOW removes survey zoom live")
  eq(FrameCap.current, 60, "LOW clamps the live frame cap")

  Tilt.setLevel, ShaderFX.deactivate = oldSetLevel, oldDeactivate
  Tilt.level = oldLevel
  Zoom.offset, Zoom.allowSurvey = oldOffset, oldSurvey
  FrameCap.current = oldCap
end

T.finish("game2 performance options #2493")
