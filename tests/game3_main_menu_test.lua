#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

package.loaded["src.ui.game3.intro_guide"] = {
  beginControls = function() return { kind = "controls" } end,
  beginPikachu = function() return { kind = "pikachu" } end,
  start = function() end,
  update = function() return false end,
  draw = function() end,
}
package.loaded["src.ui.game3.naming_chrome"] = {
  install = function() return true end,
  ready = function() return true end,
  get = function() return nil end,
}

local Audio = require("src.core.game3.audio")
local calls = {}
Audio.playCry = function(sp) calls[#calls + 1] = "cry:" .. tostring(sp) return true end
Audio.fadeOutBgm = function(s) calls[#calls + 1] = "fadeout:" .. tostring(s) return true end
Audio.playSong = function(id) calls[#calls + 1] = "song:" .. tostring(id) return true end
Audio.playSe = function(id) calls[#calls + 1] = "se:" .. tostring(id) return true end

local Boot = require("src.ui.game3.boot")
local FrlgFont = require("src.ui.game3.frlg_font")
local Chrome = require("src.ui.game3.chrome")

local function keys(...)
  local set = {}
  for _, k in ipairs({ ... }) do set[k] = true end
  return { wasPressed = function(_, k) return set[k] == true end }
end

local function step(state, input, n)
  local action
  for _ = 1, (n or 1) do
    action = Boot.update(state, input, 1 / 60) or action
  end
  return action
end

local function atTitle(hasContinue)
  local boot = Boot.new()
  Boot.setHasContinue(boot, hasContinue)
  step(boot, keys("a"))
  step(boot, nil)
  for _ = 1, 120 do
    if boot.phase == Boot.PHASE.TITLE then break end
    step(boot, nil)
  end
  return boot
end

local function throughCry(boot)
  for _ = 1, 300 do
    if boot.phase ~= Boot.PHASE.TITLE_CRY then break end
    step(boot, nil)
  end
end

print("[test] 1. START on the title plays the cry, not the menu")
local boot = atTitle(true)
check(boot.phase == Boot.PHASE.TITLE, "reached TITLE")
calls = {}
step(boot, keys("start"))
check(boot.phase == "title_cry", "START -> title_cry (got " .. tostring(boot.phase) .. ")")
check(calls[1] == "cry:6", "Charizard cry played")
step(boot, nil, 89)
check(boot.phase == "title_cry", "still title_cry after 89 frames")
check((boot.white or 0) == 0, "no white yet during the 90-frame wait")
step(boot, nil, 2)
local sawFade = false
for _, c in ipairs(calls) do if c == "fadeout:4" then sawFade = true end end
check(sawFade, "FadeOutBGM(4) after the wait")
throughCry(boot)
check(boot.phase == Boot.PHASE.MENU, "with a save -> MENU after the white fade")
check(boot._titleActive == false, "title torn down")
check(boot.fadeT == 16 and boot.fadeColor == "white", "menu starts fading in from white")

print("[test] 2. Menu rows and cursor clamp")
local items = Boot.menuItems(boot)
check(#items == 2 and items[1] == "CONTINUE" and items[2] == "NEW GAME", "CONTINUE / NEW GAME only")
local hasOption = false
for _, it in ipairs(items) do if it == "OPTION" then hasOption = true end end
check(not hasOption, "no OPTION row")
step(boot, nil, 10)
check(boot.fadeT == 0, "fade-in finished")
step(boot, keys("up"))
check(boot.menuIndex == 1, "up at top stays at 1")
step(boot, keys("down"))
step(boot, nil)
step(boot, keys("down"))
check(boot.menuIndex == 2, "down at bottom stays at 2")

print("[test] 3. Menu draw never paints the title art")
local sentinels = { titleBorder = {}, titleMon = {}, titleLogo = {}, copyrightLayer = {}, titleScreen = {} }
for k, v in pairs(sentinels) do boot[k] = v end
local drewTitle, clearColor = false, nil
local origFont, origFrame = FrlgFont.draw, Chrome.stdFrame
FrlgFont.draw = function() return 0 end
Chrome.stdFrame = function() end
local origUser = Chrome.userFrame
Chrome.userFrame = function() end
_G.love = {
  graphics = {
    clear = function(r, g, b) clearColor = { r, g, b } end,
    setColor = function() end,
    rectangle = function() end,
    draw = function(img)
      for _, v in pairs(sentinels) do if img == v then drewTitle = true end end
    end,
  },
}
Boot.draw(boot)
_G.love = nil
FrlgFont.draw, Chrome.stdFrame, Chrome.userFrame = origFont, origFrame, origUser
check(not drewTitle, "no title BG image drawn under the menu")
check(clearColor and math.abs(clearColor[1] * 255 - 139) < 1 and math.abs(clearColor[3] * 255 - 255) < 1,
  "backdrop is main_menu bg.pal[0]")

print("[test] 4. B returns to the title after a black fade")
calls = {}
step(boot, keys("b"))
check(calls[1] == "se:5", "SE_SELECT on B")
check(boot.phase == Boot.PHASE.MENU and boot.fadeColor == "black", "fading to black")
step(boot, nil, 12)
check(boot.phase == Boot.PHASE.TITLE, "back on TITLE (got " .. tostring(boot.phase) .. ")")
check(boot._titleActive == true, "title re-entered")

print("[test] 5. No save goes straight to the new game")
local fresh = atTitle(false)
step(fresh, keys("start"))
local sawMenu = false
for _ = 1, 300 do
  if fresh.phase == Boot.PHASE.MENU then sawMenu = true end
  if fresh.phase ~= Boot.PHASE.TITLE_CRY then break end
  step(fresh, nil)
end
check(not sawMenu, "no menu frame without a save")
check(fresh.phase == Boot.PHASE.CONTROLS, "CONTROLS after the white fade (got " .. tostring(fresh.phase) .. ")")

print("[test] 6. A on CONTINUE fades to black, then continues")
local cont = atTitle(true)
step(cont, keys("start"))
throughCry(cont)
step(cont, nil, 10)
local action = step(cont, keys("a"))
check(action == nil and cont.fadeColor == "black", "A starts a black fade first")
action = step(cont, nil, 12)
check(action and action.action == "continue", "continue action after the fade")

print("[test] 7. Continue stats from a save")
local info = Boot.continueInfoFromSave({
  name = "BRYANTHABOI",
  gender = 1,
  playTime = { hours = 12, minutes = 5 },
  flags = { ["2089"] = true, ["2080"] = true, ["2081"] = true },
  dex = { caught = { [1] = true, [4] = true, [200] = true }, national = false },
})
check(info.name == "BRYANTH", "name clipped to 7")
check(info.hours == 12 and info.minutes == 5, "play time")
check(info.hasDex == true, "FLAG_SYS_POKEDEX_GET read")
check(info.badges == 2, "badge count 2 (got " .. tostring(info.badges) .. ")")
check(info.dexCount == 2, "kanto caught count 2 (got " .. tostring(info.dexCount) .. ")")

Audio.isBgmStopped = function() return true end

print("[test] 8. Title idle restart fades to black before the intro")
local idle = atTitle(false)
step(idle, nil, 1790)
check(idle.phase == Boot.PHASE.TITLE, "still TITLE at 30s")
calls = {}
step(idle, nil, 920)
check(idle.phase == Boot.PHASE.TITLE_RESTART, "45s idle -> title_restart, no hard cut (got " .. tostring(idle.phase) .. ")")
local sawMapFade = false
for _, c in ipairs(calls) do if c == "fadeout:10" then sawMapFade = true end end
check(sawMapFade, "FadeOutMapMusic(10) on restart")
step(idle, nil, 20)
local rf = idle.restartFade
check(rf and rf.bgY > 0 and rf.bgY < 16, "black fade in progress (bgY " .. tostring(rf and rf.bgY) .. ")")
local restartFrames = 0
while idle.phase == Boot.PHASE.TITLE_RESTART and restartFrames < 400 do
  step(idle, nil)
  restartFrames = restartFrames + 1
end
check(idle.phase == Boot.PHASE.INTRO, "intro after the black fade and wait")
check(restartFrames >= 40, "fade + 20-frame wait took " .. restartFrames .. " more frames")

local function drawSpy(state)
  local userCalls, stdCalls = {}, 0
  local oU, oS, oF = Chrome.userFrame, Chrome.stdFrame, FrlgFont.draw
  Chrome.userFrame = function(ft) userCalls[#userCalls + 1] = ft end
  Chrome.stdFrame = function() stdCalls = stdCalls + 1 end
  FrlgFont.draw = function() return 0 end
  _G.love = { graphics = {
    clear = function() end, setColor = function() end,
    rectangle = function() end, draw = function() end,
  } }
  Boot.draw(state)
  _G.love = nil
  Chrome.userFrame, Chrome.stdFrame, FrlgFont.draw = oU, oS, oF
  return userCalls, stdCalls
end

print("[test] 9. Main menu windows use the user frame")
local uf = atTitle(true)
Boot.setContinueInfo(uf, { name = "RED", gender = 0, hours = 1, minutes = 2, badges = 0, frameType = 3 })
step(uf, keys("start"))
throughCry(uf)
local userCalls, stdCalls = drawSpy(uf)
check(#userCalls == 2 and userCalls[1] == 3 and userCalls[2] == 3, "CONTINUE + NEW GAME use user frame 3")
check(stdCalls == 0, "no std frame on the menu")
check(Boot.continueInfoFromSave({ options = { frameType = 5 } }).frameType == 5, "frameType read from save options")
check(Boot.continueInfoFromSave({}).frameType == 0, "frameType defaults to 0")

local function untilWaiting(state)
  for _ = 1, 600 do
    if not state.saveError or state.saveError.waiting then return end
    step(state, nil)
  end
end

print("[test] 10. Corrupted save shows the error window before the menu")
local se = atTitle(true)
Boot.setSaveStatus(se, "error")
step(se, keys("start"))
throughCry(se)
check(se.phase == Boot.PHASE.MENU and se.saveError ~= nil, "error window after the white fade")
check(se.saveError and se.saveError.pages[1] == "The save file is corrupted.", "page 1 wording")
check(se.fadeT == 16 and se.fadeColor == "white", "error window fades in from white")
local eu, es = drawSpy(se)
check(es == 1 and #eu == 0, "error window uses the std frame only")
step(se, nil, 8)
check(se.fadeT == 0 and se.saveError.revealed == 0, "printer waits for the fade")
local r0 = se.saveError.revealed
step(se, nil, 4)
check(se.saveError.revealed == r0 + 2, "2 frames per char (got " .. (se.saveError.revealed - r0) .. ")")
untilWaiting(se)
check(se.saveError.waiting == "prompt", "page 1 waits with the down arrow")
step(se, nil, 1)
check(se.saveError.arrowFrame == 0, "arrow drawn")
calls = {}
step(se, keys("b"))
check(se.saveError.page == 2 and calls[1] == "se:5", "B advances the page with SE_SELECT")
untilWaiting(se)
check(se.saveError.waiting == "done", "last page waits")
step(se, keys("b"))
check(se.saveError ~= nil, "B does not close the last page")
step(se, keys("a"))
check(se.saveError == nil and se.phase == Boot.PHASE.MENU, "A closes the error window")
check(se.fadeT == 16 and se.fadeColor == "white", "menu fades in from white")

print("[test] 11. Deleted save shows the message then starts a new game")
local inv = atTitle(false)
Boot.setSaveStatus(inv, "invalid")
step(inv, keys("start"))
throughCry(inv)
check(inv.phase == Boot.PHASE.MENU and inv.saveError and #inv.saveError.pages == 1, "deleted message shown")
untilWaiting(inv)
check(inv.saveError.waiting == "done", "single page waits for A")
step(inv, keys("a"))
check(inv.phase == Boot.PHASE.CONTROLS, "new game after the message (got " .. tostring(inv.phase) .. ")")

if failed == 0 then
  print("\nAll game3 main menu tests passed.")
  os.exit(0)
else
  print("\n" .. failed .. " main menu test(s) failed.")
  os.exit(1)
end
