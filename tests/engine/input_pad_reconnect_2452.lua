package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local Input = require("src.core.Input")

local held = false
local function pad(name)
  return {
    isGamepad = function() return true end,
    isGamepadDown = function(_, button)
      return button == "a" and held
    end,
    getGamepadAxis = function() return 0 end,
    getName = function() return name end,
    isConnected = function() return true end,
  }
end

local oldJoysticks = love.joystick
local first = pad("old Xbox controller")
local current = { first }
love.joystick = {
  getJoystickCount = function() return #current end,
  getJoysticks = function() return current end,
}

Input:init()
Input:pollPads()
check(Input._pollPads and Input._pollPads[1] == first,
  "polling initially caches the connected controller")

local replacement = pad("reconnected Xbox controller")
current = { replacement } -- same count, different joystick userdata
held = true
Input:reset()
Input:reconcile()
Input:step()
check(Input._pollPads and Input._pollPads[1] == replacement,
  "input recovery refreshes a same-count replacement controller")
check(Input:isDown("a"), "the replacement controller's held button survives recovery")

held = false
Input:step()
check(not Input:isDown("a"), "the replacement controller still releases normally")

love.joystick = oldJoysticks
Input:reset()
T.finish("input pad reconnect #2452")
