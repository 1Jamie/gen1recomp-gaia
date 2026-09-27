local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_wall_clock"

return function(game)
  local ok = true
  local function check(c, label)
    print((c and "PASS " or "FAIL ") .. label)
    if not c then ok = false end
  end
  local function finish()
    love.event.quit(ok and 0 or 1)
    U.wait(10)
  end

  local Rtc = require("src.core.game3.rtc")
  Rtc.reset()
  Rtc.setFixed("2005-06-01T09:30:00")

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  check(game.boot ~= nil, "boot reached")
  if not game.boot then return finish() end
  game:_handleBootAction({ action = "new_game", name = "MAY", gender = 1 })
  U.wait(60)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  check(session ~= nil, "field session")
  if not session then return finish() end
  pcall(function()
    require("src.core.game3.map").load(nil, game, "EM_LITTLEROOT_TOWN_MAYS_HOUSE_2F", { x = 5, y = 2, facing = "up" })
  end)
  U.wait(30)
  check(Rtc.enabled(session), "Emerald session has the RTC")

  local Natives = require("src.core.game3.scripting.natives")
  Natives.ensureBound(session)
  local WallClock = require("src.ui.game3.rse.wall_clock")
  local Constants = require("src.core.game3.constants")
  local C = Constants.of("emerald")
  local Flags = require("src.core.game3.scripting.flags")
  local minuteCalls = {}
  local TimeEvents = require("src.core.game3.time_events")
  TimeEvents.onMinute("BerryTreeTimeUpdate", function(_, n) minuteCalls[#minuteCalls + 1] = n end)

  local ctx = { specialVars = { [0x8004] = 1 } }
  local handler = Natives.BY_NAME.StartWallClock
  check(handler ~= nil, "StartWallClock bound by name")
  local yielded = handler(ctx, nil)
  check(yielded == true, "StartWallClock yields the script (waitstate)")
  check(WallClock.isOpen(), "wall clock open")
  local clock = WallClock.active()
  for _ = 1, 60 do
    if clock.state == "set_input" then break end
    U.wait(1)
  end
  check(clock.state == "set_input", "set screen accepts input after fade in")
  U.still(game, DIR .. "/01_set_clock_start_1000.png")
  local h0, m0 = clock:time()
  check(h0 == 10 and m0 == 0, "starts at 10:00 (wallclock.c:694)")

  U.hold(game, "right", 20)
  local _, m20 = clock:time()
  print("[driver] minutes after 20 held frames: " .. tostring(m20))
  U.hold(game, "right", 70)
  local h2, m2 = clock:time()
  print(string.format("[driver] after 90 held frames: %02d:%02d speed=%d period=%d", h2, m2, clock.t.moveSpeed, clock.t.period))
  check(h2 == 10 and m2 == 20 and clock.t.moveSpeed == 20,
    "90 held frames: 10 minutes at delta 1 then 10 at delta 2 (wallclock.c:896)")
  U.still(game, DIR .. "/02_set_clock_after_hold.png")
  for _ = 1, 30 do
    if clock.t.minuteAngle % 6 == 0 then break end
    U.wait(1)
  end
  U.hold(game, "right", 600)
  local h3 = clock:time()
  print(string.format("[driver] after long hold: %02d:%02d period=%d", h3, select(2, clock:time()), clock.t.period))
  check((h3 >= 12) == (clock.t.period == WallClock.PERIOD.PM), "AM/PM follows the hour")
  U.wait(20)
  U.still(game, DIR .. "/03_set_clock_pm.png")
  for _ = 1, 30 do
    if clock.t.minuteAngle % 6 == 0 then break end
    U.wait(1)
  end
  U.wait(2)
  local setH, setM = clock:time()
  U.tap(game, "a")
  for _ = 1, 10 do
    if clock.state == "confirm_input" then break end
    U.wait(1)
  end
  check(clock.state == "confirm_input", "IS THIS THE CORRECT TIME? yes/no")
  U.still(game, DIR .. "/04_confirm_yes_no.png")
  U.tap(game, "a")
  for _ = 1, 120 do
    if not WallClock.isOpen() then break end
    U.wait(1)
  end
  check(not WallClock.isOpen(), "clock closes after YES")
  check(ctx.nativePoll and ctx.nativePoll() == true, "script resumes after the clock closes")
  local lt = Rtc.calcLocalTime(session)
  print(string.format("[driver] set %02d:%02d local %d %02d:%02d:%02d offset d=%d h=%d m=%d s=%d", setH, setM,
    lt.days, lt.hours, lt.minutes, lt.seconds, session.localTimeOffset.days, session.localTimeOffset.hours,
    session.localTimeOffset.minutes, session.localTimeOffset.seconds))
  check(lt.days == 0 and lt.hours == setH and lt.minutes == setM, "local time equals the time set (RtcInitLocalTimeOffset)")
  local store = session.store
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.store then store = Space.store end
  check(Flags.getFlag(store, nil, C:require("flags", "FLAG_SYS_CLOCK_SET")), "InitTimeBasedEvents sets FLAG_SYS_CLOCK_SET")
  check(type(session.lastBerryTreeUpdate) == "table" and session.lastBerryTreeUpdate.hours == setH,
    "lastBerryTreeUpdate = local time")
  U.wait(30)
  U.still(game, DIR .. "/05_back_in_room.png")

  Rtc.advance(125)
  local ran, _, minutes = TimeEvents.run(session)
  check(ran and minutes == 125, "DoTimeBasedEvents: 125 minutes reach the per-minute handler")
  check(minuteCalls[#minuteCalls] == 125, "BerryTreeTimeUpdate registry called with 125")

  local ctx2 = { specialVars = { [0x8004] = 1 } }
  Natives.BY_NAME.Special_ViewWallClock(ctx2, nil)
  local view = WallClock.active()
  check(view ~= nil and view.mode == "view", "view clock open")
  for _ = 1, 60 do
    if view.state == "view_input" then break end
    U.wait(1)
  end
  local vh, vm = view:time()
  print(string.format("[driver] view clock shows %02d:%02d", vh, vm))
  local want = (setH * 60 + setM + 125) % (24 * 60)
  check(vh * 60 + vm == want, "view clock shows set time + 125 minutes")
  U.still(game, DIR .. "/06_view_clock.png")
  U.tap(game, "b")
  for _ = 1, 120 do
    if not WallClock.isOpen() then break end
    U.wait(1)
  end
  check(not WallClock.isOpen(), "view clock closes on B")
  Rtc.reset()
  finish()
end
