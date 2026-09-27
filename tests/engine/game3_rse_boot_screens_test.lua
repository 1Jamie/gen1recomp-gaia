package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Truck = require("src.core.game3.truck_sequence")
local WallClock = require("src.ui.game3.rse.wall_clock")
local MainMenu = require("src.ui.game3.rse.main_menu_rse")
local Naming = require("src.ui.game3.naming")
local Kit = require("src.ui.game3.rse.scene_kit")

-- pokeemerald/src/field_special_scene.c:192
local function mockHost()
  local log = { se = {}, metatiles = {}, lock = {}, pans = 0, fading = false }
  local H = {}
  function H.setMetatile(x, y, id) log.metatiles[#log.metatiles + 1] = { x, y, id } end
  function H.drawWholeMapView() end
  function H.lock(on) log.lock[#log.lock + 1] = on end
  function H.setCameraPanning(x, y) log.pans = log.pans + 1; log.lastPan = { x, y } end
  function H.setBoxOffset(id, x, y) log.box = log.box or {}; log.box[id] = { x, y } end
  function H.playSe(name) log.se[#log.se + 1] = { name = name, frame = log.frame } end
  function H.blackout() log.black = true end
  function H.fadeInFromBlack() log.fading = 16 end
  function H.fadeActive()
    if log.fading and log.fading > 0 then
      log.fading = log.fading - 1
      return true
    end
    return false
  end
  function H.installPanAhead() log.panAhead = true end
  return H, log
end

local host, log = mockHost()
local seq = Truck.execute(host, { spawn = false })
check(log.black, "truck starts on a black screen")
eq(log.lock[1], true, "controls locked")
eq(log.metatiles[1][3], Truck.METATILE.DoorClosedFloor_Top, "door closed first")
local frames = 0
while not Truck.step(seq) and frames < 2000 do
  frames = frames + 1
  log.frame = seq.frames
end
eq(#log.se, 4, "four truck SEs")
eq(log.se[1].name, "SE_TRUCK_MOVE", "move first")
eq(log.se[1].frame, 89, "SE_TRUCK_MOVE on frame 90")
eq(log.se[2].name, "SE_TRUCK_STOP", "then stop")
check(log.se[2].frame >= 90 + 150 + 300, "stop after the 300-frame ride")
eq(log.se[3].name, "SE_TRUCK_UNLOAD", "then unload")
eq(log.se[4].name, "SE_TRUCK_DOOR", "then door")
eq(log.se[4].frame - log.se[3].frame, 120, "door 120 frames after unload")
eq(log.lock[#log.lock], false, "controls unlocked at the end")
eq(log.metatiles[#log.metatiles][3], Truck.METATILE.ExitLight_Bottom, "exit light opened")
check(log.panAhead, "pan-ahead reinstalled")
eq(Truck.cameraBobY(120), -1, "bob every 120")
eq(Truck.cameraBobY(3), 1, "bob low phase")
eq(Truck.cameraBobY(7), 0, "bob rest")
eq(Truck.boxYMovement(60), -1, "box jump at (t+120)%180==0")
Truck.reset()
local h2, l2 = mockHost()
check(Truck.endSequence(h2), "end sequence when idle")
eq(l2.box[Truck.LOCALID_BOX_TOP][1], 3, "box top rest x")
eq(l2.box[Truck.LOCALID_BOX_BOTTOM_L][2], -3, "box bottom-left rest y")

-- pokeemerald/src/wallclock.c:896
eq(WallClock.calcMinHandDelta(5), 1, "slow delta")
eq(WallClock.calcMinHandDelta(11), 2, "delta >10")
eq(WallClock.calcMinHandDelta(31), 3, "delta >30")
eq(WallClock.calcMinHandDelta(61), 6, "delta >60")
eq(WallClock.calcNewMinHandAngle(0, WallClock.MOVE.BACKWARD, 1), 359, "backward wraps")
eq(WallClock.calcNewMinHandAngle(359, WallClock.MOVE.FORWARD, 1), 0, "forward wraps at 360-delta")
eq(WallClock.calcNewMinHandAngle(354, WallClock.MOVE.FORWARD, 61), 0, "fast forward wraps")
local t = { hours = 11, minutes = 59, period = WallClock.PERIOD.AM }
WallClock.advanceClock(t, WallClock.MOVE.FORWARD)
eq(t.hours, 12, "advance to noon")
eq(t.period, WallClock.PERIOD.PM, "noon flips to PM")
WallClock.advanceClock(t, WallClock.MOVE.BACKWARD)
eq(t.hours, 11, "back to 11")
eq(t.period, WallClock.PERIOD.AM, "11 flips back to AM")
t = { hours = 23, minutes = 59, period = WallClock.PERIOD.PM }
WallClock.advanceClock(t, WallClock.MOVE.FORWARD)
eq(t.hours, 0, "midnight wraps")
eq(t.period, WallClock.PERIOD.AM, "midnight is AM")
eq(WallClock.sin2(90), 4096, "Sin2(90)")
eq(WallClock.sin2(30), 2048, "Sin2(30) = gSineDegreeTable[30]")
eq(WallClock.sin2(210), -2048, "Sin2 negates past 180")
eq(WallClock.cos2(0), 4096, "Cos2(0)")
local px, py = WallClock.indicatorOffset(45)
eq(px, 21, "PM indicator x at 45 deg")
eq(py, 21, "PM indicator y at 45 deg")

-- pokeemerald/src/main_menu.c:512
local items = MainMenu.items(MainMenu.TYPE.HAS_NO_SAVED_GAME)
eq(table.concat(items, ","), "NEW_GAME,OPTION,EXIT", "no save: NEW GAME, OPTION + port EXIT")
items = MainMenu.items(MainMenu.TYPE.HAS_SAVED_GAME)
eq(table.concat(items, ","), "CONTINUE,NEW_GAME,OPTION,EXIT", "saved game rows")
items = MainMenu.items(MainMenu.TYPE.HAS_MYSTERY_GIFT)
eq(table.concat(items, ","), "CONTINUE,NEW_GAME,MYSTERY_GIFT,OPTION,EXIT", "mystery gift rows")
items = MainMenu.items(MainMenu.TYPE.HAS_MYSTERY_EVENTS)
eq(items[#items], "EXIT", "EXIT always the last row")
eq(MainMenu.menuType(false, nil, "ok"), MainMenu.TYPE.HAS_NO_SAVED_GAME, "no save type")
eq(MainMenu.menuType(true, { mysteryGift = false }, "ok"), MainMenu.TYPE.HAS_SAVED_GAME, "save type")
eq(MainMenu.menuType(true, { mysteryGift = true }, "ok"), MainMenu.TYPE.HAS_MYSTERY_GIFT, "gift type")
eq(MainMenu.menuType(true, { mysteryGift = true }, "invalid"), MainMenu.TYPE.HAS_NO_SAVED_GAME,
  "erased save shows the no-save menu")
eq(MainMenu.windowFor(MainMenu.TYPE.HAS_SAVED_GAME, 1).height, 6, "continue box 6 tiles tall")
eq(MainMenu.windowFor(MainMenu.TYPE.HAS_SAVED_GAME, 2).top, 9, "NEW GAME at tile 9")
eq(MainMenu.windowFor(MainMenu.TYPE.HAS_NO_SAVED_GAME, 2).top, 5, "OPTION at tile 5 without save")
eq(MainMenu.windowFor(MainMenu.TYPE.HAS_NO_SAVED_GAME, 3).top, 9, "EXIT row below OPTION")
local info = MainMenu.continueInfoFromSave({
  name = "MAY", gender = 1, playTime = { hours = 3, minutes = 7 },
  flags = { [0x867] = true, [0x868] = true, [0x861] = true },
  vars = {},
}, "emerald")
eq(info.badges, 2, "badges counted from FLAG_BADGE01_GET")
check(info.hasDex, "FLAG_SYS_POKEDEX_GET")
check(not info.mysteryGift, "no mystery gift flag")
eq(info.gender, 1, "gender carried")

-- pokeemerald/src/naming_screen.c:280
local kb = {
  chars = {
    { { { char = "a" }, { char = "b" } } },
    { { { char = "A" }, { char = "B" } } },
    { { { char = "0" } } },
  },
  columnCounts = { 2, 2, 1 },
  columnX = { { 0, 12 }, { 0, 12 }, { 0 } },
}
local pages = Naming.pagesFromKeyboard(kb)
eq(pages[1].id, "UPPER", "first page is upper")
eq(pages[1].rows[1][1], "A", "upper from KEYBOARD_LETTERS_UPPER")
eq(pages[2].rows[1][2], "b", "lower second")
eq(pages[3].rows[1][1], "0", "symbols third")
eq(pages[1].colX[2], 12, "column x from cache")
check(Naming.templateFromManifest(nil, "RIVAL") == nil, "FR manifest has no templates -> FR path")
local man = { templates = { { title = "YOUR NAME?", maxChars = 7 }, {}, {}, {}, { title = "Tell him the words.", maxChars = 15 } } }
eq(Naming.templateFromManifest(man, "WALDA").maxChars, 15, "WALDA template")
check(not pcall(Naming.templateFromManifest, man, "RIVAL"), "RIVAL template absent on Emerald")

-- pokeemerald/src/text.c:1013
local ir = {
  { t = "text", s = "AB" }, { t = "ext", cmd = 0x08, args = { 3 } }, { t = "text", s = "C" }, { t = "eos" },
}
local pausedFrames = 0
local p = Kit.printer(ir, { speed = 2, onPause = function() pausedFrames = pausedFrames + 1 end })
local n = 0
local none = { new = {}, held = {} }
while p:isActive() and n < 100 do
  p:run(none)
  n = n + 1
end
eq(p.lines[1], "ABC", "printed all chars")
eq(pausedFrames, 4, "pause callback fires each pause frame")
check(n >= 3 * 2 + 4, "speed and pause add frames")

-- pokeemerald/src/reset_rtc_screen.c:400
local ResetRtc = require("src.ui.game3.rse.reset_rtc_screen")
local ClearSave = require("src.ui.game3.rse.clear_save_screen")
local BerryFix = require("src.ui.game3.rse.berry_fix_screen")
local tt = { hours = 23 }
ResetRtc.moveTimeUpDown(tt, "hours", 0, 23, { up = true })
eq(tt.hours, 0, "reset RTC hours wrap up")
ResetRtc.moveTimeUpDown(tt, "hours", 0, 23, { down = true })
eq(tt.hours, 23, "reset RTC hours wrap down")
tt = { days = 1 }
ResetRtc.moveTimeUpDown(tt, "days", 1, 9999, { down = true })
eq(tt.days, 9999, "days wrap to 9999")
local C = require("src.core.game3.constants").of("emerald")
local st = { flags = {}, vars = {} }
check(not ResetRtc.canReset(st, "emerald"), "CanResetRTC false by default")
st.flags[C:require("flags", "FLAG_SYS_RESET_RTC_ENABLE")] = true
st.vars[C:require("vars", "VAR_RESET_RTC_ENABLE")] = 0x920
check(ResetRtc.canReset(st, "emerald"), "CanResetRTC needs the flag and 0x920")
eq(ResetRtc.INPUT_MAP[ResetRtc.SELECTION.HOURS].right, ResetRtc.SELECTION.MINS, "hours -> minutes on RIGHT")

local RomText = require("src.core.game3.rom_text")
RomText.overrides.gText_ClearAllSaveData = { { t = "text", s = "Clear all save data?" }, { t = "eos" } }
RomText.overrides.gText_ClearingData = { { t = "text", s = "Clearing data..." }, { t = "eos" } }
local cleared = false
local cs = ClearSave.new({ clearSave = function() cleared = true end })
local none2 = { new = {}, held = {} }
local out
for _ = 1, 200 do
  out = cs:frame(none2)
  if cs.state == "choice" then break end
end
eq(cs.yesNo.cursor, 1, "clear save defaults to NO")
cs:frame({ new = { a = true }, held = {} })
for _ = 1, 200 do
  out = cs:frame(none2)
  if out then break end
end
eq(out, "intro", "NO soft-resets")
check(not cleared, "NO keeps the save")
cleared = false
cs = ClearSave.new({ clearSave = function() cleared = true end })
for _ = 1, 200 do
  cs:frame(none2)
  if cs.state == "choice" then break end
end
cs:frame({ new = { up = true }, held = {} })
cs:frame({ new = { a = true }, held = {} })
for _ = 1, 200 do
  out = cs:frame(none2)
  if out then break end
end
check(cleared, "YES clears the save")

local bf = BerryFix.new()
bf:frame({ new = { a = true }, held = {} })
eq(bf.state, "connect", "berry fix: A -> connect scene")
bf:frame({ new = { a = true }, held = {} })
eq(bf.state, "turn_off", "then turn-off-power scene (waits for a link partner)")
eq(bf:frame({ new = { b = true }, held = {} }), "intro", "port EXIT (B) soft-resets")

T.finish("game3 rse boot screens")
