-- Shared machinery for the background workers (love.thread) that pre-render
-- things the main thread would otherwise build inside a frame: the RED++ atlas
-- bake + PNG decode worker (src/render/AtlasPrefetch.lua, atlas_worker.lua).
--
-- Three pieces:
--
--   Worker  one thread and its two process-global channels ("<x>_cmd" in,
--           "<x>_out" out).  Starts lazily; stays OFF (every request a no-op,
--           callers fall back to doing the work synchronously) without
--           love.thread, with POKEPORT_NO_THREAD=1, when the thread fails to
--           start, and for the rest of the process once it reports a fatal
--           error or dies.  A clean shutdown clears the inbox (quit must not
--           wait behind queued work), pushes quit and waits; it is registered
--           with SessionLifecycle so love.quit reaches it.
--
--   Lane    one kind of job on a Worker: high/low priority queues with dedupe
--           and front promotion, a budget of jobs in flight, a per-update send
--           cap and examine cap, and an epoch.  A Channel cannot reorder or
--           drop, so queueing lives on this side and only `inflightMax` jobs
--           sit in the worker at once: a front-of-queue request overtakes
--           everything not yet sent.  Several lanes share one Worker with
--           separate budgets, so a long run of short jobs never sits behind a
--           long one (the atlas worker has a bake lane and a decode lane).
--
--   Store   a bounded LRU map for finished results.
--
-- Epochs.  Lane:bump() makes everything the lane has pending obsolete: queued
-- entries are dropped, results still being produced are discarded when they
-- arrive (Lane:complete checks the epoch the job was sent under), and the
-- worker's inbox is cleared so obsolete jobs do not run.  Clearing the inbox also loses the jobs of the
-- OTHER lanes on that worker, so those lanes requeue what they had in flight;
-- a bump of one lane never strands another.
--
-- A job's result must echo the `epoch` it was sent with.  The module does not
-- fix a message format beyond that: the owner builds the command in its send
-- callback and reads results in its drain callback.

local Logger = require("src.core.Logger")

local WorkerLane = {}

-- ---------------------------------------------------------------------------
-- Store
-- ---------------------------------------------------------------------------
local Store = {}
Store.__index = Store

-- A map of at most `cap` entries; the least recently set / peeked one is
-- evicted first.  Values must not be nil.
function WorkerLane.newStore(cap)
  return setmetatable({ cap = cap, vals = {}, used = {}, tick = 0, n = 0 }, Store)
end

function Store:setCap(cap) self.cap = cap end

function Store:set(key, value)
  if self.vals[key] == nil then self.n = self.n + 1 end
  self.vals[key] = value
  self.tick = self.tick + 1
  self.used[key] = self.tick
  while self.n > self.cap do
    local oldK, oldT
    for k, t in pairs(self.used) do
      if not oldT or t < oldT then oldK, oldT = k, t end
    end
    self:remove(oldK)
  end
end

-- the value, without refreshing its age
function Store:get(key) return self.vals[key] end

-- the value; counts as a use
function Store:peek(key)
  local v = self.vals[key]
  if v ~= nil then
    self.tick = self.tick + 1
    self.used[key] = self.tick
  end
  return v
end

function Store:remove(key)
  if self.vals[key] ~= nil then
    self.vals[key] = nil
    self.used[key] = nil
    self.n = self.n - 1
  end
end

-- remove and return
function Store:take(key)
  local v = self.vals[key]
  self:remove(key)
  return v
end

function Store:count() return self.n end

function Store:clear()
  self.vals, self.used, self.n = {}, {}, 0
end

-- ---------------------------------------------------------------------------
-- Lane
-- ---------------------------------------------------------------------------
local Lane = {}
Lane.__index = Lane

local function resetQueues(self)
  self.high, self.low, self.byKey = {}, {}, {}
  self.inflight, self.inflightCount = {}, 0
end

-- The entry queued under `key`, if any.
function Lane:queued(key) return self.byKey[key] end

-- If `key` is already queued, return true (moving a low-priority entry to the
-- front when `front`).  Otherwise false, and the caller pushes.
function Lane:promote(key, front)
  local entry = self.byKey[key]
  if not entry then return false end
  if front then
    for i, e in ipairs(self.low) do
      if e == entry then
        table.remove(self.low, i)
        table.insert(self.high, entry)
        entry.front = true
        break
      end
    end
  end
  return true
end

-- Queue `entry` (a table) under `key`; front puts it ahead of the hints.
local pushSeq = 0

function Lane:push(key, entry, front)
  entry.key = key
  entry.front = front and true or nil
  pushSeq = pushSeq + 1
  entry.seq = pushSeq -- send order, for requeueInflight
  self.byKey[key] = entry
  table.insert(front and self.high or self.low, entry)
  return entry
end

-- A queued entry is not needed any more.  Marks it dead so the send loop
-- skips it; a job already at the worker is the owner's to ignore on arrival.
function Lane:forget(key)
  local entry = self.byKey[key]
  if entry then
    self.byKey[key] = nil
    entry.dead = true
  end
end

-- Hand queued entries to the worker.  send(entry) builds and pushes the job
-- and returns true when it went out (optionally followed by the key the job
-- is tracked under in flight, default entry.key), or false when the entry
-- was dropped.  Stops at the in-flight budget, the send cap (jobs sent) or
-- the examine cap (entries looked at), or when the worker goes off.
function Lane:pump(send)
  local worker = self.worker
  local sent, examined = 0, 0
  while worker.state and self.inflightCount < self.inflightMax
        and (not self.sendCap or sent < self.sendCap)
        and (not self.examineCap or examined < self.examineCap) do
    local entry = table.remove(self.high, 1) or table.remove(self.low, 1)
    if not entry then return end
    examined = examined + 1
    if not entry.dead then
      -- a newer entry may own the key now (requeueInflight re-points it)
      if self.byKey[entry.key] == entry then self.byKey[entry.key] = nil end
      local ok, trackKey = send(entry)
      if ok then
        local k = trackKey or entry.key
        -- a duplicate of a job already out is retired by one result only, so
        -- it must not take a second unit of the budget
        if self.inflight[k] == nil then
          self.inflightCount = self.inflightCount + 1
        end
        self.inflight[k] = entry
        sent = sent + 1
      end
    end
  end
end

-- A result arrived for `key` sent under `epoch`.  Returns the in-flight entry
-- (and retires it) only when it answers the request still in flight under the
-- current epoch; anything else (superseded, bumped away) returns nil.
function Lane:complete(key, epoch)
  local entry = self.inflight[key]
  if entry and epoch == self.epoch then
    self.inflight[key] = nil
    self.inflightCount = self.inflightCount - 1
    return entry
  end
  return nil
end

-- Drop everything queued and in flight.
function Lane:clear() resetQueues(self) end

-- Put what is in flight back at the front of the queue, to be sent again.
function Lane:requeueInflight()
  -- back to the head of the queue it came from: a background hint must not
  -- overtake front requests queued since
  -- newest first, each inserted at the head, so the oldest ends up first
  local list = {}
  for _, entry in pairs(self.inflight) do list[#list + 1] = entry end
  table.sort(list, function(a, b) return (a.seq or 0) > (b.seq or 0) end)
  for _, entry in ipairs(list) do
    table.insert(entry.front and self.high or self.low, 1, entry)
    self.byKey[entry.key] = entry
  end
  self.inflight, self.inflightCount = {}, 0
end

-- Obsolete and drop everything this lane has pending (see the header).
function Lane:bump()
  self.epoch = self.epoch + 1
  self.worker:clearInbox(self)
  self:clear()
end

-- nothing queued, nothing out at the worker
function Lane:idle()
  return self.inflightCount == 0 and next(self.byKey) == nil
end

-- queued count, in-flight count
function Lane:pending()
  local queued = 0
  for _ in pairs(self.byKey) do queued = queued + 1 end
  return queued, self.inflightCount
end

-- ---------------------------------------------------------------------------
-- Worker
-- ---------------------------------------------------------------------------
local Worker = {}
Worker.__index = Worker

-- opts: name (log label), script (thread entry), cmd / out (channel names),
-- capable() -> true when the love modules the thread needs exist,
-- onStop() runs after a fail / shutdown, once the lanes are cleared (reset the
-- owner's stores and caches there).
function WorkerLane.newWorker(opts)
  local worker = setmetatable({
    name = opts.name, script = opts.script,
    cmdName = opts.cmd, outName = opts.out,
    capable = opts.capable, onStop = opts.onStop,
    noThread = os.getenv("POKEPORT_NO_THREAD"),
    lanes = {},
    state = nil, -- nil = untried, true = running, false = off
  }, Worker)
  return worker
end

-- A lane on this worker.  opts: inflight (jobs at the worker at once, default
-- 2), sendCap (jobs sent per pump), examineCap (entries looked at per pump).
function Worker:newLane(opts)
  local lane = setmetatable({
    worker = self, epoch = 0,
    inflightMax = opts and opts.inflight or 2,
    sendCap = opts and opts.sendCap,
    examineCap = opts and opts.examineCap,
  }, Lane)
  resetQueues(lane)
  self.lanes[#self.lanes + 1] = lane
  return lane
end

-- Start the thread on first use.  true when it is running.
function Worker:ensure()
  if self.state ~= nil then return self.state end
  self.state = false
  if self.noThread == "1" then return false end
  if not (love.thread and love.thread.newThread and love.thread.getChannel
      and (not self.capable or self.capable())) then
    return false
  end
  local ok, thread = pcall(love.thread.newThread, self.script)
  if not ok or not thread then return false end
  local cmd = love.thread.getChannel(self.cmdName)
  local out = love.thread.getChannel(self.outName)
  -- channels are process-global: drop anything a previous run left behind
  pcall(cmd.clear, cmd)
  pcall(out.clear, out)
  if not pcall(function() thread:start() end) then return false end
  self.thread, self.cmd, self.out = thread, cmd, out
  self.state = true
  -- a worker that never started has nothing to end at exit; registering here
  -- (not in newWorker) keeps SessionLifecycle out of Assets' load-time graph
  if not self.registered then
    self.registered = true
    require("src.core.SessionLifecycle").registerProcessShutdown(function()
      self:shutdown()
    end)
  end
  return true
end

-- Send a command.  false when the worker is off or the message cannot cross a
-- channel (e.g. it carries a function).
function Worker:push(msg)
  if not self.cmd then return false end
  return (pcall(self.cmd.push, self.cmd, msg))
end

-- Drop every command waiting in the inbox.  Every lane except `except` (the
-- one being bumped) loses the jobs it had sent, so it queues them again.
function Worker:clearInbox(except)
  if self.cmd then pcall(self.cmd.clear, self.cmd) end
  for _, lane in ipairs(self.lanes) do
    if lane ~= except then lane:requeueInflight() end
  end
end

local function stopped(self)
  self.thread, self.cmd, self.out = nil, nil, nil
  for _, lane in ipairs(self.lanes) do lane:clear() end
  if self.onStop then self.onStop() end
end

-- The worker reported a fatal error or died: off for the rest of the process
-- (until shutdown() resets it).
function Worker:fail(reason)
  if reason then Logger.warn("%s worker off: %s", self.name, tostring(reason)) end
  if self.cmd then pcall(self.cmd.push, self.cmd, { cmd = "quit" }) end
  self.state = false
  stopped(self)
end

-- End the thread (LOVE waits for live threads at exit).  Safe to call
-- repeatedly; the next ensure() starts a fresh worker.
function Worker:shutdown()
  if self.state and self.cmd then
    pcall(self.cmd.clear, self.cmd) -- do not make quit wait behind queued work
    pcall(self.cmd.push, self.cmd, { cmd = "quit" })
  end
  if self.thread then pcall(function() self.thread:wait() end) end
  -- a worker failed by a fatal error stays off; only a clean one may restart
  if self.state ~= false then self.state = nil end
  stopped(self)
end

-- Pop finished results and give each to handle(result), stopping after `cap`
-- results for which handle returned true (the owner decides what is costly
-- enough to count).  Returns false when the worker is off, died or reported a
-- fatal error (it is failed here), true otherwise.
function Worker:drain(cap, handle)
  if not self.state then return false end
  local err = self.thread and self.thread:getError()
  if err then self:fail(err) return false end
  local counted = 0
  while counted < cap do
    local result = self.out:pop()
    if not result then break end
    if result.fatal then self:fail(result.fatal) return false end
    if handle(result) then counted = counted + 1 end
  end
  return true
end

return WorkerLane
