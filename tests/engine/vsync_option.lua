package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local VSync = require("src.core.VSync")

VSync.reset()

T.same(VSync.MODES, { "on", "off", "adaptive" }, "three modes, in row order")

T.eq(VSync.default(), "on", "with nothing to ask, vsync reads ON")
T.eq(VSync.normalize(nil), "on", "so a save with no key is ON")
T.eq(VSync.normalize("junk"), "on", "and so is garbage")
T.eq(VSync.normalize("adaptive"), "adaptive", "a real mode is kept")

T.eq(VSync.label("on"), "ON", "ON prints as ON")
T.eq(VSync.label("off"), "OFF", "OFF as OFF")
T.eq(VSync.label("adaptive"), "ADAPTIVE", "and ADAPTIVE spells itself out")

T.eq(VSync.cycle("on", 1), "off", "ON cycles to OFF")
T.eq(VSync.cycle("off", 1), "adaptive", "OFF to ADAPTIVE")
T.eq(VSync.cycle("adaptive", 1), "on", "and ADAPTIVE wraps to ON")
T.eq(VSync.cycle("on", -1), "adaptive", "stepping back wraps the other way")
T.eq(VSync.cycle(nil, 1), "off", "a missing key normalizes before it steps")

T.eq(VSync.apply("off"), "off", "apply answers with what it stored")
T.eq(VSync.isOn(), false, "and OFF is not on")
T.eq(VSync.apply("adaptive"), "adaptive", "adaptive applies")
T.eq(VSync.isOn(), true, "and counts as on: it still syncs a frame in time")
VSync.applyOptions({})
T.eq(VSync.isOn(), true, "an options table with no key falls back to the boot mode")


local calls = {}
local interval = 0
love.window.getVSync = function() return interval end
love.window.setVSync = function(v) calls[#calls + 1] = v; interval = v end
VSync.reset()

T.eq(VSync.default(), "off", "a handheld booted with vsync 0 defaults to OFF")
T.eq(VSync.normalize(nil), "off", "so its saves with no key stay OFF")
T.eq(VSync.isOn(), false, "and the run loop sees vsync off")

VSync.apply("on")
T.eq(calls[#calls], 1, "ON sets the swap interval to 1")
T.eq(VSync.isOn(), true, "and the loop sees vsync on")
VSync.apply("adaptive")
T.eq(calls[#calls], -1, "ADAPTIVE asks for the late-swap interval")
VSync.applyOptions({ vsync = "off" })
T.eq(calls[#calls], 0, "and OFF turns it off")
T.eq(#calls, 3, "one driver call per apply, no repeats")

-- Driver reports 0 after we asked for ON (vblank_mode=0 / Gamescope quirk):
-- isOn stays true so PresentProbe still tries a real wait on native X11.
VSync.reset()
calls = {}
interval = 0
love.window.getVSync = function() return 0 end
love.window.setVSync = function(v) calls[#calls + 1] = v end
VSync.apply("on")
T.eq(calls[#calls], 1, "ON still asks the driver for interval 1")
T.eq(VSync.isOn(), true, "requested ON stays wanted even if getVSync is 0")
T.eq(VSync.effective(), "off", "while effective tracks the driver bit")

love.window.getVSync, love.window.setVSync = nil, nil
VSync.reset()

T.finish("vsync option")
