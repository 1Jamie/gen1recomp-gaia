package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local K = require("tests.save_compat._codec")
local G3 = require("tests.fixtures.save.gen3_build")
local Gen3Save = require("src.save_convert.Gen3Save")
local PcChrome = require("src.ui.game3.pc_chrome")
local UI = require("src.ui.game3.box_storage_ui")

local names, friends = PcChrome.wallpaperNames, PcChrome.hasFriends
PcChrome.wallpaperNames = function() return { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 } end
PcChrome.hasFriends = function() return true end

local function press(key) UI.handleInput({ wasPressed = function(_, k) return k == key end }) end
for _, version in ipairs({ "firered", "leafgreen", "emerald" }) do
  for _, unlocked in ipairs({ false, true }) do
    local save = assert(K.import(3, version, G3.emit(G3.base(version))))
    save.version = version
    save.waldaPhrase = { unlocked = unlocked }
    UI._session, UI.open, UI.mode, UI.wallpaperCursor = save, true, "pick_wallpaper", 16
    press("down")
    local count = version == "emerald" and unlocked and 17 or 16
    T.eq(UI.wallpaperCursor, count == 17 and 17 or 1, version .. ": the picker includes Friends only after unlock")
    UI.wallpaperCursor = 1
    press("up")
    T.eq(UI.wallpaperCursor, count, version .. ": reverse navigation wraps over the available wallpapers")
    press("a")
    T.eq(save.storage.boxes[save.storage.currentBox or 1].wallpaper, count, version .. ": choosing a wallpaper updates saved storage")
    local decoded = assert(Gen3Save.forVersion(version).decode(assert(K.export(3, version, save))))
    T.eq(decoded.storage.boxes[decoded.storage.currentBox + 1].wallpaper, count - 1,
      version .. ": the selected wallpaper exports with the original cartridge ID")
  end
end

PcChrome.wallpaperNames, PcChrome.hasFriends = names, friends
T.finish()
