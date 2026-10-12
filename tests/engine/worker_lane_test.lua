-- The shared background-worker machinery (src/core/WorkerLane.lua): Store,
-- Lane and Worker, driven with fake threads / channels.
--   luajit tests/engine/worker_lane_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

local WorkerLane = require("src.core.WorkerLane")

-- ---- fake threads / channels ------------------------------------------------
local channels = {}
local Channel = {}
Channel.__index = Channel
function Channel:push(msg)
  if self.reject and self.reject(msg) then error("not transferable") end
  self.queue[#self.queue + 1] = msg
end
function Channel:pop() return table.remove(self.queue, 1) end
function Channel:clear() self.queue = {} end
function Channel:getCount() return #self.queue end
local function channel(name)
  channels[name] = channels[name] or setmetatable({ queue = {} }, Channel)
  return channels[name]
end

local started, waited, threadError = 0, 0, nil
local function installThread()
  love.thread = {
    newThread = function()
      return { start = function() started = started + 1 end,
               getError = function() return threadError end,
               wait = function() waited = waited + 1 end }
    end,
    getChannel = channel,
  }
end
installThread()

local stops = 0
local function newWorker(extra)
  local opts = { name = "test", script = "x.lua", cmd = "t_cmd", out = "t_out",
                 onStop = function() stops = stops + 1 end }
  for k, v in pairs(extra or {}) do opts[k] = v end
  channel("t_cmd"):clear()
  channel("t_out"):clear()
  return WorkerLane.newWorker(opts)
end

-- ---- Store -------------------------------------------------------------------
do
  local s = WorkerLane.newStore(3)
  s:set("a", 1); s:set("b", 2); s:set("c", 3)
  eq(s:count(), 3, "store holds up to its cap")
  s:peek("a")                       -- a is now the freshest
  s:set("d", 4)
  eq(s:count(), 3, "store stays bounded")
  check(s:get("b") == nil, "least recently used entry evicted")
  check(s:get("a") == 1 and s:get("c") == 3 and s:get("d") == 4, "others kept")
  s:get("c")                        -- get does not refresh
  s:set("e", 5)
  check(s:get("c") == nil, "get() does not count as a use")
  s:set("a", 10)
  eq(s:count(), 3, "overwriting does not grow the store")
  eq(s:take("a"), 10, "take returns the value")
  check(s:get("a") == nil and s:count() == 2, "...and removes it")
  s:setCap(1); s:set("z", 1)
  eq(s:count(), 1, "setCap shrinks on the next set")
  s:clear()
  eq(s:count(), 0, "clear")
end

-- ---- Worker start and fallbacks ---------------------------------------------
do
  local w = newWorker()
  check(w:ensure(), "worker starts")
  eq(started, 1, "one thread started")
  check(w:ensure(), "ensure is idempotent")
  eq(started, 1, "no second thread")

  -- channels are process-global: leftovers from a previous run are dropped
  local w2 = newWorker({ cmd = "t2_cmd", out = "t2_out" })
  channel("t2_cmd"):push({ cmd = "stale" }); channel("t2_out"):push({ stale = true })
  w2:ensure()
  eq(channel("t2_cmd"):getCount() + channel("t2_out"):getCount(), 0,
    "start clears both channels")

  local before = started
  local w3 = newWorker(); w3.noThread = "1"
  check(not w3:ensure(), "POKEPORT_NO_THREAD=1: off")
  eq(started, before, "...without starting a thread")
  check(not w3:push({}), "push is a no-op when off")

  local saved = love.thread
  love.thread = nil
  check(not newWorker():ensure(), "no love.thread: off")
  installThread()
  check(not newWorker({ capable = function() return false end }):ensure(),
    "missing love module: off")

  love.thread.newThread = function() error("boom") end
  check(not newWorker():ensure(), "newThread failure: off")
  installThread()
  love.thread.newThread = function()
    return { start = function() error("no start") end }
  end
  check(not newWorker():ensure(), "start failure: off")
  love.thread = saved
  installThread()
end

-- ---- Lane queueing -----------------------------------------------------------
do
  local w = newWorker()
  w:ensure()
  local lane = w:newLane({ inflight = 2 })
  local sentKeys = {}
  local function send(entry)
    sentKeys[#sentKeys + 1] = entry.key
    return w:push({ cmd = "job", key = entry.key, epoch = lane.epoch })
  end

  lane:push("a", {}, false)
  lane:push("b", {}, false)
  lane:push("c", {}, false)
  check(lane:promote("a", false), "an already queued key is found")
  check(not lane:promote("zzz", false), "an unknown key is not")
  check(lane:promote("c", true), "front promotes a low-priority entry")
  lane:push("d", {}, true)
  local queued, flying = lane:pending()
  eq(queued, 4, "four queued") ; eq(flying, 0, "none in flight")
  lane:pump(send)
  eq(table.concat(sentKeys, ","), "c,d", "front entries go first, in order, up to the budget")
  queued, flying = lane:pending()
  eq(queued, 2, "two still queued"); eq(flying, 2, "two in flight")
  lane:pump(send)
  eq(#sentKeys, 2, "a full in-flight budget sends nothing more")
  check(not lane:idle(), "not idle")

  check(lane:complete("c", lane.epoch) ~= nil, "a current result retires its entry")
  check(lane:complete("c", lane.epoch) == nil, "a duplicate result is ignored")
  check(lane:complete("d", lane.epoch - 1) == nil, "a result from another epoch is ignored")
  lane:pump(send)
  eq(table.concat(sentKeys, ","), "c,d,a", "a retired slot is refilled in queue order")

  -- forget: a dead queued entry is skipped
  lane:forget("b")
  lane:complete("a", lane.epoch)
  lane:pump(send)
  eq(#sentKeys, 3, "a forgotten entry is never sent")
  check(lane:queued("b") == nil, "and no longer queued")
end

-- ---- send results, caps ------------------------------------------------------
do
  local w = newWorker()
  w:ensure()
  local lane = w:newLane({ inflight = 10, sendCap = 2 })
  for i = 1, 5 do lane:push("k" .. i, {}, false) end
  local calls = 0
  lane:pump(function(entry) calls = calls + 1 return true, "tracked:" .. entry.key end)
  eq(calls, 2, "sendCap bounds jobs sent per pump")
  check(lane.inflight["tracked:k1"] ~= nil, "a send may name the in-flight key")
  check(lane:complete("tracked:k1", lane.epoch) ~= nil, "and complete() finds it there")

  local lane2 = w:newLane({ inflight = 10, examineCap = 3 })
  for i = 1, 8 do lane2:push("e" .. i, {}, false) end
  calls = 0
  lane2:pump(function() calls = calls + 1 return false end)
  eq(calls, 3, "examineCap bounds entries looked at, sent or not")
  eq((lane2:pending()), 5, "the rest stay queued")
  lane2:pump(function() calls = calls + 1 return false end)
  eq(calls, 6, "the next pump examines more")

  local lane3 = w:newLane({ inflight = 10 })
  lane3:push("x", {}, false)
  lane3:push("y", {}, false)
  lane3:pump(function(entry) return entry.key == "y" end)
  eq(lane3.inflightCount, 1, "a dropped entry is not counted in flight")
  eq((lane3:pending()), 0, "and is not kept queued")
end

-- ---- epochs -------------------------------------------------------------------
do
  local w = newWorker()
  w:ensure()
  local a = w:newLane({ inflight = 4 })
  local b = w:newLane({ inflight = 4 })
  local function send(lane)
    return function(entry)
      return w:push({ cmd = "job", key = entry.key, epoch = lane.epoch })
    end
  end
  a:push("a1", {}, false); a:push("a2", {}, false)
  b:push("b1", {}, false); b:push("b2", {}, false)
  a:pump(send(a)); b:pump(send(b))
  a:push("a3", {}, false)
  local cmdCh = channel("t_cmd")
  eq(cmdCh:getCount(), 4, "four jobs at the worker")

  -- a bump drops this lane's jobs; the OTHER lane re-sends what it lost
  local e = a.epoch
  a:bump()
  check(a.epoch == e + 1, "bump advances the lane epoch")
  eq(b.epoch, 0, "...and only that lane's")
  eq(cmdCh:getCount(), 0, "the inbox is cleared")
  eq((a:pending()), 0, "bump drops queued entries")
  eq(a.inflightCount, 0, "and in-flight ones")
  check(a:idle(), "lane is idle")
  check(a:complete("a1", e) == nil, "a result under the old epoch is dropped")
  eq(b.inflightCount, 0, "the OTHER lane's lost jobs are queued again")
  eq((b:pending()), 2, "so a bump never strands them")

  a:pump(send(a)); b:pump(send(b))
  eq(cmdCh:getCount(), 2, "the other lane re-sends them")
  eq(cmdCh.queue[1].epoch, b.epoch, "under its current epoch")
end

-- ---- Worker drain, fail, shutdown ---------------------------------------------
do
  stops = 0
  local w = newWorker()
  w:ensure()
  local lane = w:newLane({ inflight = 8 })
  local out = channel("t_out")
  for i = 1, 6 do out:push({ key = "r" .. i }) end
  local seen = {}
  check(w:drain(3, function(r) seen[#seen + 1] = r.key return r.key ~= "r2" end),
    "drain reports a healthy worker")
  eq(table.concat(seen, ","), "r1,r2,r3,r4", "only counted results use the cap")
  eq(out:getCount(), 2, "the rest wait for the next drain")

  out:push({ fatal = "kaput" })
  local ok = w:drain(10, function() return false end)
  check(not ok, "a fatal report fails the worker")
  check(w.state == false, "worker is off")
  eq(stops, 1, "onStop ran")
  local quit = false
  for _, c in ipairs(channel("t_cmd").queue) do if c.cmd == "quit" then quit = true end end
  check(quit, "quit was pushed")
  check(not w:ensure(), "a failed worker stays off for the process")
  check(not w:drain(1, function() end), "and drain is a no-op")

  -- a thread that died
  local w2 = newWorker(); w2:ensure()
  local lane2 = w2:newLane({})
  lane2:push("q", {}, false)
  threadError = "died"
  check(not w2:drain(1, function() end), "getError fails the worker")
  check(lane2:idle() and w2.state == false, "lanes cleared")
  threadError = nil

  -- clean shutdown: inbox cleared, quit left, thread waited for, restartable
  local w3 = newWorker(); w3:ensure()
  local lane3 = w3:newLane({})
  w3:push({ cmd = "job" }); w3:push({ cmd = "job" })
  lane3:push("x", {}, false)
  local waitedBefore, stopsBefore = waited, stops
  w3:shutdown()
  eq(channel("t_cmd"):getCount(), 1, "shutdown clears pending work")
  eq(channel("t_cmd").queue[1].cmd, "quit", "and leaves only quit")
  eq(waited, waitedBefore + 1, "and waits for the thread")
  eq(stops, stopsBefore + 1, "onStop ran")
  check(lane3:idle(), "lanes cleared")
  check(w3.state == nil, "state reset so the next request restarts")
  local startedBefore = started
  check(w3:ensure(), "restarts after shutdown")
  eq(started, startedBefore + 1, "with a fresh thread")
  eq(channel("t_cmd"):getCount(), 0, "and the leftover quit is cleared")
  w3:shutdown(); w3:shutdown() -- repeatable

  -- a message that cannot cross a channel
  local w4 = newWorker(); w4:ensure()
  channel("t_cmd").reject = function(msg) return msg.bad end
  check(not w4:push({ bad = true }), "push reports an untransferable message")
  check(w4:push({ good = true }), "and a good one")
  channel("t_cmd").reject = nil
end

-- ---- requeueInflight keeps the original send order ------------------------------
do
  local w = newWorker()
  w:ensure()
  local lane = w:newLane({ inflight = 10 })
  local function send() return true end
  lane:push("l1", {}, false)
  lane:push("f1", {}, true)
  lane:push("l2", {}, false)
  lane:push("f2", {}, true)
  lane:pump(send) -- f1, f2, l1, l2 go out in that order
  lane:push("queued", {}, false)
  lane:requeueInflight()
  local function keys(q)
    local t = {}
    for _, e in ipairs(q) do t[#t + 1] = e.key end
    return table.concat(t, ",")
  end
  eq(keys(lane.high), "f1,f2", "front entries return to high in send order")
  eq(keys(lane.low), "l1,l2,queued", "others return ahead of newer low work, in order")
end

T.finish()
