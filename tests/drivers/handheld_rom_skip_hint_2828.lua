return function(game)
  local U = require("tests.drivers.util")
  local Browser = require("src.ui.kit.FileBrowser")
  local Importer = require("src.import.RomImporter")
  local Logger = require("src.core.Logger")
  local shots = assert(os.getenv("POKEPORT_SHOT_DIR"))
  local failed = false
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    failed = failed or not ok
    return ok
  end
  local MIB = 1024 * 1024
  local head = ("\0"):rep(0xAC) .. "BPRE" .. "\0\0" .. "\150" .. ("\0"):rep(9) .. "\1"
  local fixture = "FireRed_hack_2828.gba"
  love.filesystem.write(fixture, head .. ("\0"):rep(16 * MIB - #head))
  local imp = Importer.new(function() end, { launcher = true })
  imp.android, imp.nativePicker, imp.isNX = false, false, false
  imp.baseRomDiscovery = false
  imp._findFetch = nil
  imp._pumpFindFetch = function() end
  imp._refreshFindSources = function(self) self.findSources = {} end
  imp.ready.firered = false
  imp.tab = "firered"
  local realGetenv = os.getenv
  os.getenv = function(name)
    if name == "POKEPORT_HANDHELD" then return "1" end
    return realGetenv(name)
  end
  imp:choose("firered")
  os.getenv = realGetenv
  check(Browser.active and Browser.mode == "rom", "2828_handheld_choose_opens_rom_modal")
  check(type(Browser.hint) == "string" and Browser.hint:find(fixture, 1, true) ~= nil
    and Browser.hint:find("FireRed (USA) rev 1", 1, true) ~= nil,
    "2828_browser_hint_names_skipped_file: " .. tostring(Browser.hint))
  check(imp.notice and imp.notice.version == "firered"
    and imp.notice.detail:find("unknown SHA%-1 %x+") ~= nil,
    "2828_column_notice_carries_sha1: " .. tostring(imp.notice and imp.notice.detail))
  local inLog = false
  for _, line in ipairs(Logger.history) do
    if line:find("skipped ROM candidate", 1, true) and line:find(fixture, 1, true) then inLog = true end
  end
  check(inLog, "2828_skip_reason_logged")
  local realDraw = game.draw
  game.draw = function() imp:draw() end
  U.wait(2)
  check(U.still(game, shots .. "/2828_01_browser_skip_hint.png"), "2828_browser_hint_shot")
  Browser.close(nil)
  U.wait(2)
  check(U.still(game, shots .. "/2828_02_column_skip_notice.png"), "2828_column_notice_shot")
  game.draw = realDraw
  love.filesystem.remove(fixture)
  love.event.quit(failed and 1 or 0)
end
