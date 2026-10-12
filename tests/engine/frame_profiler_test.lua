-- FrameProfiler: rolling stats, nesting, bench mode (no love needed).
--   luajit tests/engine/frame_profiler_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local P = require("src.core.FrameProfiler")

local t = 0
P.clock = function() return t end
local function adv(ms) t = t + ms / 1000 end
local function near(a, b, msg) check(math.abs(a - b) < 1e-6, msg .. (" (%s vs %s)"):format(a, b)) end

local function fresh(env)
  P.init(function(k) return env and env[k] or nil end)
end

-- 1. disabled: nothing is recorded
do
  fresh()
  P.beginFrame(true)
  P.push("update"); adv(5); P.pop("update")
  P.endFrame()
  eq(#P.sections(), 0, "disabled records no sections")
  eq(P.stats("frame").worst, 0, "disabled records no frame time")
end

-- 2. sections accumulate within a frame and nest
do
  fresh({ POKEPORT_GAME_PROF_OVERLAY = "1" })
  check(P.enabled, "overlay env starts enabled")
  P.beginFrame(true)
  P.push("outer")
  adv(2)
  P.push("inner"); adv(3); P.pop("inner")
  P.push("inner"); adv(4); P.pop("inner")
  P.pop("outer")
  adv(1)
  P.endFrame()
  near(P.stats("inner").mean, 7, "inner accumulates two calls")
  near(P.stats("outer").mean, 9, "outer includes nested time")
  near(P.stats("frame").mean, 10, "frame total")
  -- a launcher frame never records
  P.beginFrame(false)
  P.push("update"); adv(1); P.pop("update")
  P.endFrame()
  near(P.stats("frame").mean, 10, "launcher frame leaves stats unchanged")
  check(#P.sections() == 2, "launcher frame adds no section")
  -- the gap across an inactive frame is not a frame interval: with a 1ms
  -- frame before and after a 1000ms launcher gap, fps must stay ~ 1/frame
  fresh({ POKEPORT_GAME_PROF_OVERLAY = "1" })
  P.beginFrame(true); adv(1); P.endFrame()
  P.beginFrame(false); adv(1000); P.endFrame()
  P.beginFrame(true); adv(1); P.endFrame()
  eq(P.fps(), 0, "no interval spans an inactive gap")
  P.beginFrame(true); adv(1); P.endFrame()
  check(P.fps() > 500, "intervals resume after the gap")
end

-- 3. rolling window caps at 120, stats mean/p95/worst
do
  fresh({ POKEPORT_GAME_PROF_OVERLAY = "1" })
  for i = 1, 200 do
    P.beginFrame(true)
    P.push("s"); adv(i <= 80 and 100 or 1); P.pop("s")
    P.endFrame()
  end
  -- frames 81..200 remain: all 1 ms
  near(P.stats("s").worst, 1, "old frames dropped from the window")
  eq(P.stats("frame").mean > 0.99 and P.stats("frame").mean < 1.01, true, "mean over window")

  fresh({ POKEPORT_GAME_PROF_OVERLAY = "1" })
  for i = 1, 100 do
    P.beginFrame(true)
    P.push("s"); adv(i); P.pop("s")
    P.endFrame()
  end
  local s = P.stats("s")
  near(s.mean, 50.5, "mean of 1..100")
  near(s.p95, 95, "p95 of 1..100")
  near(s.worst, 100, "worst of 1..100")
  check(P.fps() > 0, "fps from frame intervals")
end

-- 4. push/pop pairing survives an early-return wrapper
do
  fresh({ POKEPORT_GAME_PROF_OVERLAY = "1" })
  local function impl(early) adv(2); if early then return "e" end adv(3); return "l" end
  local function wrapped(early)
    P.push("w"); local r = impl(early); P.pop("w"); return r
  end
  P.beginFrame(true)
  wrapped(true); wrapped(false)
  P.endFrame()
  near(P.stats("w").mean, 7, "both paths timed")
  P.beginFrame(true)
  wrapped(true)
  P.endFrame()
  near(P.stats("w").worst, 7, "worst kept")
  P.pop("w") -- stray pop outside a frame is harmless
end

-- 5. bench mode: warmup dropped, one summary, one quit
do
  local quits, out = 0, {}
  love = { event = { quit = function() quits = quits + 1 end } }
  P.out = function(s) out[#out + 1] = s end
  fresh({ POKEPORT_GAME_PROF = "10" })
  check(not P.enabled, "bench keeps overlay hidden")
  for i = 1, 100 do
    P.beginFrame(true)
    P.push("update"); adv(i <= 60 and 50 or 2); P.pop("update")
    P.endFrame()
  end
  eq(quits, 1, "quit called once")
  eq(#out, 1, "one summary emitted")
  local text = out[1]
  check(text:find("PROF update mean=2.000ms", 1, true), "warmup frames excluded")
  check(text:find("PROF frame ", 1, true), "frame line")
  check(text:find("PROF fps=", 1, true), "fps line")
  check(text:find("PROF lua_kb=", 1, true) and text:find("drawcalls=", 1, true), "lua_kb line")
  love = nil
  P.out = nil
end

-- 6. spikes: threshold, top-10 ordering, counts, context, section filter
do
  local out = {}
  love = { event = { quit = function() end } }
  P.out = function(x) out[#out + 1] = x end
  fresh({ POKEPORT_GAME_PROF = "15" })
  P.WARMUP = 0
  P.context = function() return "Screen map=PALLET" end
  -- 15 frames: totals 10 (fast), then 12 spikes of 20..31, then 2 of 40
  local totals = { 10 }
  for i = 1, 12 do totals[#totals + 1] = 19 + i end
  totals[#totals + 1] = 40
  totals[#totals + 1] = 50
  for _, tot in ipairs(totals) do
    P.beginFrame(true)
    P.push("logic"); adv(tot - 0.2); P.pop("logic")
    P.push("tiny"); adv(0.2); P.pop("tiny")
    P.endFrame()
  end
  local o16, o33 = P.spikeCounts()
  eq(o16, 14, "over16 count")
  eq(o33, 2, "over33 count")
  local l = P.spikeList()
  eq(#l, 10, "top 10 kept")
  near(l[1].total, 50, "worst first")
  near(l[2].total, 40, "second worst")
  check(l[3].total >= l[4].total, "descending")
  eq(l[1].ctx, "Screen map=PALLET", "context label")
  eq(#l[1].secs, 1, "sections under 0.5ms filtered")
  eq(l[1].secs[1][1], "logic", "kept section is logic")
  eq(#out, 1, "one summary")
  check(out[1]:find("PROF spikes over16=14 over33=2", 1, true), "spike counts line")
  check(out[1]:find("PROF spike #1 frame=15 total=50.0ms logic=49.8ms ctx=Screen map=PALLET", 1, true),
    "spike line")
  P.WARMUP = 60
  P.context = nil
  P.out = nil
  love = nil
end

-- 7. all mode + finish()
do
  local out, quits = {}, 0
  love = { event = { quit = function() quits = quits + 1 end } }
  P.out = function(x) out[#out + 1] = x end
  fresh({ POKEPORT_GAME_PROF = "all" })
  for _ = 1, 200 do
    P.beginFrame(true); P.push("a"); adv(1); P.pop("a"); P.endFrame()
  end
  eq(#out, 0, "all mode never self-terminates")
  eq(quits, 0, "all mode never quits")
  P.finish()
  eq(#out, 1, "finish emits once")
  P.finish()
  eq(#out, 1, "second finish is a no-op")
  eq(quits, 0, "finish does not quit")

  -- bench off: no-op
  fresh()
  P.finish()
  eq(#out, 1, "finish no-op when bench off")

  -- numeric mode already emitted: no-op
  fresh({ POKEPORT_GAME_PROF = "2" })
  P.WARMUP = 0
  for _ = 1, 2 do P.beginFrame(true); adv(1); P.endFrame() end
  eq(#out, 2, "numeric mode emitted")
  P.finish()
  eq(#out, 2, "finish after emit is a no-op")
  P.WARMUP = 60
  P.out = nil
  love = nil
end

-- 7b. windowed stats: ring bigger than WINDOW, old samples slow, newest fast
do
  P.out = function() end
  P.WARMUP = 0
  fresh({ POKEPORT_GAME_PROF = "all" })
  for i = 1, 450 do
    P.beginFrame(true)
    P.push("s"); adv(i <= 300 and 100 or 1); P.pop("s")
    P.endFrame()
  end
  local W = P.WINDOW
  near(P.stats("s", W).worst, 1, "windowed worst ignores old slow samples")
  near(P.stats("s", W).mean, 1, "windowed mean")
  near(P.stats("frame", W).p95, 1, "windowed frame p95")
  near(P.stats("s").worst, 100, "whole-ring stats unchanged")
  check(P.stats("s").mean > 60, "whole-ring mean includes old samples")
  near(P.stats("s", 100000).worst, 100, "oversized window clamps to ring")
  near(P.fps(W), 1000, "windowed fps uses newest intervals")
  check(P.fps() < 100, "whole-ring fps includes old intervals")
  P.out = nil
  P.WARMUP = 60
end

-- 8. GC probe: alloc_kb ring + heap min/max, only with POKEPORT_GC_PROBE=1
do
  local out = {}
  P.out = function(x) out[#out + 1] = x end
  P.WARMUP = 0
  fresh({ POKEPORT_GAME_PROF = "all" })
  for _ = 1, 3 do P.beginFrame(true); adv(1); P.endFrame() end
  P.finish()
  check(not out[#out]:find("alloc_kb", 1, true), "no alloc_kb without probe")
  out = {}
  P.out = function(x) out[#out + 1] = x end
  fresh({ POKEPORT_GAME_PROF = "all", POKEPORT_GC_PROBE = "1" })
  local keep = {}
  for i = 1, 5 do
    P.beginFrame(true)
    P.push("gc"); adv(1); P.pop("gc")
    for j = 1, 2000 do keep[#keep + 1] = { j, i } end
    P.endFrame()
  end
  P.finish()
  local txt = out[#out]
  check(txt:find("PROF alloc_kb mean=", 1, true), "alloc_kb line present")
  check(txt:find("PROF heap_kb min=", 1, true), "heap_kb line present")
  check(txt:find("PROF gc mean=", 1, true), "gc section present")
  check(not txt:find("alloc_kb mean=0.0 ", 1, true), "allocation measured > 0")
  P.out = nil
  P.WARMUP = 60
end

-- 9. frame total is work time: at most one refresh period of `present` (the
-- vsync wait) is excluded, so a GPU stall inside present still counts
do
  local oldLove = love
  love = love or {}
  local oldWindow = love.window
  local oldRR = package.loaded["src.core.RefreshRate"]
  local rr = { measured = nil, hz = function() return 120 end }
  rr.measuredHz = function() return rr.measured end
  package.loaded["src.core.RefreshRate"] = rr
  local vs = 1000 / 120
  near(P.vsyncMs(), vs, "vsyncMs from the advertised refresh rate")
  rr.measured = 30 -- half-rate vsync: the measured cadence wins
  near(P.vsyncMs(), 1000 / 30, "vsyncMs prefers the measured cadence")
  rr.measured = nil

  fresh({ POKEPORT_GAME_PROF_OVERLAY = "1" })
  P.beginFrame(true)
  P.push("update"); adv(2); P.pop("update")
  P.push("present"); adv(8); P.pop("present")
  P.endFrame()
  near(P.stats("frame").mean, 2, "vsync wait fully excluded")
  near(P.stats("present").mean, 8, "present section still recorded")
  local o16, o33 = P.spikeCounts()
  eq(o16, 0, "vsync-wait frame is not >16")
  eq(o33, 0, "vsync-wait frame is not >33")
  eq(#P.spikeList(), 0, "vsync-wait frame is not a spike")

  -- GPU stall: only one refresh period is excluded
  fresh({ POKEPORT_GAME_PROF_OVERLAY = "1" })
  P.beginFrame(true)
  P.push("update"); adv(2); P.pop("update")
  P.push("present"); adv(30); P.pop("present")
  P.endFrame()
  near(P.stats("frame").mean, 2 + 30 - vs, "present stall beyond a refresh counts")
  o16 = P.spikeCounts()
  eq(o16, 1, "present stall is >16")
  eq(#P.spikeList(), 1, "present stall is a spike")

  -- heavy update
  fresh({ POKEPORT_GAME_PROF_OVERLAY = "1" })
  P.beginFrame(true)
  P.push("update"); adv(20); P.pop("update")
  P.push("present"); adv(5); P.pop("present")
  P.endFrame()
  o16 = P.spikeCounts()
  eq(o16, 1, "heavy update is >16")
  eq(#P.spikeList(), 1, "heavy update is a spike")
  near(P.spikeList()[1].total, 20, "spike total is work time")

  -- no window API: 60 Hz default
  rr.hz = function() return nil end
  near(P.vsyncMs(), 1000 / 60, "vsyncMs defaults to 60 Hz without a known rate")
  package.loaded["src.core.RefreshRate"] = nil
  near(P.vsyncMs(), 1000 / 60, "vsyncMs defaults to 60 Hz without RefreshRate")
  package.loaded["src.core.RefreshRate"] = oldRR

  love.window = oldWindow
  love = oldLove
end

-- 10. hiding the overlay mid-bench leaves bench state alone
do
  local out, quits = {}, 0
  P.out = function(x) out[#out + 1] = x end
  P.WARMUP = 0
  love = love or {}
  local oldEvent = love.event
  love.event = { quit = function() quits = quits + 1 end }
  fresh({ POKEPORT_GAME_PROF = "5", POKEPORT_GAME_PROF_OVERLAY = "1" })
  for _ = 1, 2 do P.beginFrame(true); adv(1); P.endFrame() end
  P.setEnabled(false)
  eq(#out, 0, "hiding overlay emits nothing in bench mode")
  for _ = 1, 3 do P.beginFrame(true); adv(1); P.endFrame() end
  eq(#out, 1, "bench summary emitted once at N")
  eq(quits, 1, "quit once")
  check(out[1]:find("PROF frame mean=", 1, true), "bench summary content")
  P.finish()
  eq(#out, 1, "no second summary")
  love.event = oldEvent
  P.out = nil
  P.WARMUP = 60
end

-- 11. the bench request love.quit's scripted check reads
do
  local function env(v) return function() return v end end
  check(P.benchRequested(env("120")), "a frame count is a bench run")
  check(P.benchRequested(env("all")), "`all` is a bench run")
  check(not P.benchRequested(env("0")), "0 is not")
  check(not P.benchRequested(env(nil)), "unset is not")
end

T.finish("frame_profiler_test")
