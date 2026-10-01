return function(game)
  local U = require("tests.drivers.util")
  local Browser = require("src.ui.kit.FileBrowser")
  local Importer = require("src.import.RomImporter")
  local shots = assert(os.getenv("POKEPORT_SHOT_DIR"))
  local failed = false
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    failed = failed or not ok
    return ok
  end
  love.filesystem.createDirectory("picker2605/images")
  love.filesystem.createDirectory("picker2605/videos")
  love.filesystem.write("picker2605/FireRed.gba", "picker fixture")
  love.filesystem.write("picker2605/Emerald.GBA", "picker fixture")
  love.filesystem.write("picker2605/notes.txt", "picker fixture")
  local fixture = love.filesystem.getSaveDirectory() .. "/picker2605"
  local imp = Importer.new(function() end, { launcher = true })
  imp.android, imp.nativePicker, imp.isNX = false, false, false
  imp.baseRomDiscovery = false
  imp._findFetch = nil
  imp._pumpFindFetch = function() end
  imp._refreshFindSources = function(self) self.findSources = {} end
  local selected, count = nil, 0
  imp.startPath = function(_, path) selected, count = path, count + 1 end
  local realGetenv = os.getenv
  os.getenv = function(name)
    if name == "POKEPORT_HANDHELD" then return "1" end
    return realGetenv(name)
  end
  imp:choose("firered")
  os.getenv = realGetenv
  if not check(Browser.active and Browser.mode == "rom", "2605_handheld_choose_opens_rom_modal") then
    love.event.quit(1)
    return
  end
  Browser.setDirectory(fixture)
  local names = {}
  for i, entry in ipairs(Browser.entries) do names[entry.name] = i end
  check(names["images"] ~= nil and names["videos"] ~= nil, "2605_directories_visible")
  check(names["FireRed.gba"] ~= nil and names["Emerald.GBA"] ~= nil, "2605_lower_upper_gba_visible")
  check(names["notes.txt"] == nil, "2605_unrelated_file_hidden")
  if not names["FireRed.gba"] then love.event.quit(1) return end
  Browser.selectedIdx = names["FireRed.gba"]
  local realDraw = game.draw
  game.draw = function() imp:draw() end
  U.wait(2)
  check(U.still(game, shots .. "/2605_firered_gba_visible_selected.png"), "2605_gba_modal_shot")
  Browser.gamepadpressed("a")
  check(selected == fixture .. "/FireRed.gba" and count == 1, "2605_exact_gba_path_selected_once")
  check(not Browser.active, "2605_selection_closes_modal")
  Browser.gamepadpressed("a")
  check(count == 1, "2605_closed_modal_does_not_repeat_selection")
  game.draw = realDraw
  love.event.quit(failed and 1 or 0)
end
