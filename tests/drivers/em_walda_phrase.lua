local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")
local U = require("tests.drivers.util")

local d = S.new("em_walda_phrase", "/tmp/em_walda_phrase")
local LABEL = "RustboroCity_Flat1_2F_EventScript_WaldasDad"
local LETTERS = "BCDFGHJKLMNPQRSTVWZbcdfghjkmnpqs"

local function validPhrase(Walda, trainerId)
  math.randomseed(20260927)
  for _ = 1, 1000000 do
    local chars = {}
    for i = 1, 15 do
      local at = math.random(#LETTERS)
      chars[i] = LETTERS:sub(at, at)
    end
    local phrase = table.concat(chars)
    local decoded = Walda.calculate(phrase, trainerId)
    if decoded then return phrase, decoded end
  end
end

return function(game)
  local ok, err = xpcall(function()
    local session = M.boot(game, d)
    if not session then return end
    d.check(M.goTo(game, "EM_RUSTBORO_CITY_FLAT1_2F", 4, 5, "up"), "Rustboro Flat 1 2F loaded")
    d.shot(game, "01_walda_house")
    local Naming = require("src.ui.game3.naming")
    local Walda = require("src.core.game3.scripting.natives_walda_rse")
    local phrase, result = validPhrase(Walda, session.trainerId or session.id)
    d.check(phrase ~= nil, "generated a valid phrase for this trainer ID")
    local presented = false
    local done = M.talk(game, LABEL, {
      answers = { "yes" },
      onFrame = function()
        if Naming.isOpen() and not presented then
          presented = true
          d.shot(game, "02_walda_naming")
          Naming.close(phrase)
        end
      end,
    })
    d.check(done, "WaldasDad script completed the naming and wallpaper check")
    d.check(presented, "DoWaldaNamingScreen opened the WALDA naming screen")
    d.check(session.waldaPhrase and session.waldaPhrase.phrase == phrase, "the entered Walda phrase persisted")
    d.check(session.waldaPhrase and session.waldaPhrase.unlocked == true,
      "TryGetWallpaperWithWaldaPhrase unlocked the matching wallpaper")
    local friends = require("src.import.gba.versions_game").game("emerald").STORAGE_FRIENDS
    local expectedIcon = result.iconId < friends.iconCount and result.iconId or 0
    local expectedPattern = result.patternId < friends.patternCount and result.patternId or 0
    d.check(session.waldaPhrase and session.waldaPhrase.iconId == expectedIcon
      and session.waldaPhrase.patternId == expectedPattern
      and session.waldaPhrase.colors[1] == result.colors[1]
      and session.waldaPhrase.colors[2] == result.colors[2],
      "wallpaper icon, pattern, and palette match the phrase decoder")
    d.shot(game, "03_walda_phrase_saved")

    local Storage = require("src.core.game3.storage")
    local BoxStorage = require("src.ui.game3.box_storage_ui")
    local PcChrome = require("src.ui.game3.pc_chrome")
    PcChrome.ensure()
    local storage = Storage.ensure(session)
    local friendsId = #PcChrome.wallpaperNames() + 1
    storage.boxes[storage.currentBox or 1].wallpaper = friendsId
    BoxStorage.show({ session = session })
    U.wait(20)
    d.shot(game, "04_friends_wallpaper_rendered")
    local rendered = PcChrome.friendsWallpaper(session.waldaPhrase)
    local w, h
    if rendered then w, h = rendered:getDimensions() end
    d.check(PcChrome.hasFriends() and rendered ~= nil and w == 160 and h == 144,
      "Friends wallpaper renderer builds the 160x144 pattern and icon image")
    local cached = PcChrome.friendsWallpaper(session.waldaPhrase)
    d.check(cached == rendered, "Friends wallpaper caches the decoded phrase image")
    local colors = session.waldaPhrase.colors
    local originalColor = colors[1]
    colors[1] = (originalColor + 1) % 32768
    local recolored = PcChrome.friendsWallpaper(session.waldaPhrase)
    colors[1] = originalColor
    d.check(recolored ~= rendered, "a changed Walda palette produces a distinct wallpaper render")
    BoxStorage.close()
  end, debug.traceback)
  if not ok then d.check(false, "driver error: " .. tostring(err)) end
  d.finish()
end
