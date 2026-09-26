-- Startup errors still reach LÖVE's native handler if graphics cannot open.
package.path = "./?.lua;./?/init.lua;" .. package.path
_G.love = require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local shown
love.errhand = function(msg)
  shown = msg
  return "blue handler result"
end

-- Fail the first engine require after main.lua installs the crash handler.
package.preload["src.core.LaunchOptions"] = function()
  error("startup probe", 0)
end
package.loaded["src.core.LaunchOptions"] = nil
local loaded, startupError = pcall(dofile, "main.lua")
check(not loaded and tostring(startupError):find("startup probe", 1, true) ~= nil,
  "startup probe fails after the crash handler is installed")
check(type(love.errorhandler) == "function", "startup crash handler is installed")

love.filesystem.write("mods/sample_mod/manifest.json",
  '{"id":"sample_mod","name":"Sample Mod"}')
eq(love.errorhandler("mods/sample_mod/main.lua:12: crash"),
  "blue handler result", "inactive graphics delegates to LÖVE's blue handler")
check(shown:find('Likely source: mod "Sample Mod" (sample_mod)', 1, true) ~= nil,
  "blue handler names the mod")
check(shown:find("Error log: /tmp/pokeport-stub-save/lua-error.log", 1, true) ~= nil,
  "blue handler shows the exact log path")
check((love.filesystem.read("lua-error.log") or ""):find(
  'Likely source: mod "Sample Mod" (sample_mod)', 1, true) ~= nil,
  "blue handler saves the attributed error")

eq(love.errorhandler("src/core/Game2.lua:42: crash"),
  "blue handler result", "engine errors also use the blue handler")
check(shown:find("Likely source: Game itself (gen1recomp)", 1, true) ~= nil,
  "blue handler identifies engine errors")

-- With an active window, the game's own screen keeps the useful summary and
-- log path visible, with the current traceback inside a scrollable panel.
local drawn = {}
local backgrounds = {}
love.graphics.printf = function(value)
  drawn[#drawn + 1] = tostring(value)
end
love.graphics.clear = function(r, g, b)
  backgrounds[#backgrounds + 1] = { r, g, b }
end
love.graphics.present = function() end
love.graphics.isActive = function() return true end
love.window.isOpen = function() return true end
love.event = {
  pump = function() end,
  poll = function() return function() return nil end end,
}
love.timer.sleep = function() end

local nativeShown = shown
local drawLoop = love.errorhandler("mods/sample_mod/main.lua:12: raw Lua crash")
eq(type(drawLoop), "function", "active window gets the custom crash screen")
drawLoop()
eq(shown, nativeShown, "custom crash screen does not call the native handler")
local display = table.concat(drawn, "\n")
check(display:find("The game ran into a problem", 1, true) ~= nil,
  "screen has a plain-language heading")
check(display:find("Mod: Sample Mod (sample_mod)", 1, true) ~= nil,
  "screen names the mod and its id")
check(display:find("Try disabling this mod", 1, true) ~= nil,
  "screen gives the player a next step")
check(display:find("/tmp/pokeport-stub-save/lua-error.log", 1, true) ~= nil,
  "screen shows the exact log path")
check(display:find("raw Lua crash", 1, true) ~= nil,
  "the terminal panel shows the current error details")
check((love.filesystem.read("lua-error.log") or ""):find("raw Lua crash", 1, true) ~= nil,
  "technical details remain in the saved log")
local red = backgrounds[#backgrounds]

-- If no window exists yet, open one and render the same layout in blue.
local opened = false
love.window.isOpen = function() return opened end
love.window.setMode = function(width, height)
  eq(width, 800, "fallback opens an 800px window")
  eq(height, 600, "fallback opens a 600px window")
  opened = true
  return true
end
drawn, backgrounds = {}, {}
local blueLoop = love.errorhandler("src/core/Game2.lua:42: startup crash")
eq(type(blueLoop), "function", "startup failure gets a custom crash screen")
blueLoop()
display = table.concat(drawn, "\n")
check(display:find("gen1recomp", 1, true) ~= nil,
  "blue variant identifies the engine")
check(display:find("Restart the game", 1, true) ~= nil,
  "blue variant gives a plain-language next step")
check(display:find("startup crash", 1, true) ~= nil,
  "blue variant shows the same technical-details panel")
local blue = backgrounds[#backgrounds]
check(red and blue and red[3] ~= blue[3],
  "active and startup crash screens use distinct palettes")

local CrashScreen = require("src.debug.CrashScreen")
drawn = {}
local unsaved = CrashScreen.new({
  owner = { kind = "engine", name = "gen1recomp" },
  logPath = "/tmp/pokeport-stub-save/lua-error.log",
  saved = false,
}, "blue")
CrashScreen.draw(unsaved)
display = table.concat(drawn, "\n")
check(display:find("ERROR LOG NOT SAVED", 1, true) ~= nil,
  "screen clearly marks a failed log write")
check(display:find("Take a photo", 1, true) ~= nil,
  "failed log write gives an alternative next step")
check(not display:find("Share this file", 1, true),
  "failed log write does not tell the player to share a nonexistent file")
check(display:find("Close game", 1, true) ~= nil,
  "crash screen has a visible close button")
check(CrashScreen.hitClose(unsaved, 515, 430),
  "close button accepts a pointer press")
check(CrashScreen.hitClose(unsaved, 0.81, 0.75),
  "close button accepts normalized touch coordinates")
check(not CrashScreen.hitClose(unsaved, 10, 10),
  "outside presses do not close the game")

local details = { "first detail line" }
for i = 1, 40 do details[#details + 1] = "trace frame " .. i end
details[#details + 1] = "last detail line"
local longScreen = CrashScreen.new({
  owner = { kind = "engine", name = "gen1recomp" },
  logPath = "/tmp/pokeport-stub-save/lua-error.log",
  details = table.concat(details, "\n"), saved = true,
}, "red")
local clips = {}
local originalScissor = love.graphics.setScissor
love.graphics.setScissor = function(x, y, w, h)
  clips[#clips + 1] = { x, y, w, h }
end
drawn = {}
CrashScreen.draw(longScreen)
love.graphics.setScissor = originalScissor
check(longScreen.scrollMax > 0, "long details have a scroll range")
check(#clips >= 2 and clips[1][3] > 0 and clips[1][4] > 0
    and clips[#clips][1] == nil,
  "details are clipped to the panel and graphics clipping is restored")
check(table.concat(drawn, "\n"):find("first detail line", 1, true) ~= nil,
  "the details panel starts at the first line")
CrashScreen.scrollTo(longScreen, true)
drawn = {}
CrashScreen.draw(longScreen)
display = table.concat(drawn, "\n")
check(display:find("last detail line", 1, true) ~= nil
    and not display:find("first detail line", 1, true),
  "scrolling reaches the final line without drawing hidden lines")
eq(longScreen.scroll, longScreen.scrollMax, "End clamps at the bottom")
CrashScreen.scroll(longScreen, -math.huge)
eq(longScreen.scroll, 0, "scrolling up clamps at the top")
local area = longScreen.detailArea
check(CrashScreen.pointerPressed(longScreen, "touch", area.x + 8, area.y + 25),
  "touch can grab the details panel")
CrashScreen.pointerMoved(longScreen, "touch", area.x + 8, area.y + 5)
check(longScreen.scroll > 0, "touch drag scrolls the details")
CrashScreen.pointerReleased(longScreen, "touch")
check(longScreen.drag == nil, "releasing touch ends the drag")

local copiedPath
love.system.setClipboardText = function(value) copiedPath = value end
love.keyboard = { isDown = function() return true end }
love.window.isOpen = function() return true end
love.event.poll = function()
  local sent = false
  return function()
    if not sent then
      sent = true
      return "keypressed", "c"
    end
  end
end
drawn = {}
local copyLoop = love.errorhandler("src/core/Game2.lua:42: crash")
copyLoop()
eq(copiedPath, "/tmp/pokeport-stub-save/lua-error.log",
  "Ctrl+C copies the exact log path")
display = table.concat(drawn, "\n")
check(display:find("copied to clipboard", 1, true) ~= nil,
  "screen confirms the copied path")

love.event.poll = function()
  local sent = false
  return function()
    if not sent then
      sent = true
      return "mousepressed", 515, 430, 1
    end
  end
end
local clickLoop = love.errorhandler("src/core/Game2.lua:42: crash")
eq(clickLoop(), 1, "clicking Close game exits the crash screen")

love.event.poll = function()
  local sent = false
  return function()
    if not sent then
      sent = true
      return "gamepadpressed", {}, "start"
    end
  end
end
local padLoop = love.errorhandler("src/core/Game2.lua:42: crash")
eq(padLoop(), 1, "pressing Start exits the crash screen")

local originalScroll = CrashScreen.scroll
local scrollCalls = 0
CrashScreen.scroll = function(screen, amount)
  scrollCalls = scrollCalls + 1
  originalScroll(screen, amount)
end
love.event.poll = function()
  local sent = false
  return function()
    if not sent then
      sent = true
      return "wheelmoved", 0, -1
    end
  end
end
local wheelLoop = love.errorhandler("src/core/Game2.lua:42: crash")
wheelLoop()
CrashScreen.scroll = originalScroll
eq(scrollCalls, 1, "mouse wheel events reach the details scroller")

love.event.poll = function()
  local sent = false
  return function()
    if not sent then
      sent = true
      return "mousepressed", 515, 430, 1, true
    end
  end
end
local syntheticMouseLoop = love.errorhandler("src/core/Game2.lua:42: crash")
eq(syntheticMouseLoop(), nil,
  "synthetic mouse presses do not duplicate touch input")

love.event.poll = function()
  local sent = false
  return function()
    if not sent then
      sent = true
      return "touchpressed", "finger", 0.81, 0.75
    end
  end
end
local touchLoop = love.errorhandler("src/core/Game2.lua:42: crash")
eq(touchLoop(), 1, "touching Close game exits the crash screen")

T.finish()
