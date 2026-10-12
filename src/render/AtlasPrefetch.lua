-- Background pre-bake of RED++ tileset atlases (see TileRenderer's
-- getGbcAtlas, src/render/AtlasBake.lua, src/render/atlas_worker.lua).
--
-- A map's first TileRenderer under COLORS = RED++ recolors its whole atlas
-- pixel by pixel.  Done inside a seam crossing or a warp that is a visible
-- hitch on a handheld, so the overworld asks for the atlases it is about to
-- need (the maps one crossing away, a warp's destination) and the worker bakes
-- them ahead of time.  The finished ImageData waits in a bounded "ready" store
-- until getGbcAtlas turns it into an Image (newImage stays on the main thread,
-- lazily, so draining costs no GPU work).  A request that has not finished by
-- the time its map is built is simply baked synchronously as it always was,
-- and the late result is then dropped because the slot is filled.
--
-- Without love.thread, with POKEPORT_NO_THREAD=1, or if the worker fails to
-- start or dies, request() is a no-op and nothing changes.
--
-- The worker, queues, epochs and stores come from src/core/WorkerLane.lua.
-- Two lanes share the one atlas worker, each with its own queues and
-- in-flight budget so a bake never sits behind a long run of decodes (each is
-- a short job) and vice versa:
--   bakes    RED++ atlas recolours (palette dependent)
--   decodes  image FILE decodes (Assets.image / Assets.imageData read the
--            result; palette independent)
-- Every request is a closure / path that builds its payload only when it is
-- sent, so queued hints cost nothing until their turn.

local WorkerLane = require("src.core.WorkerLane")

local AtlasPrefetch = {}

local DRAIN_CAP = 2       -- bake results accepted per update

local ready = WorkerLane.newStore(24)   -- bake key -> ImageData
local dready = WorkerLane.newStore(64)  -- resolved path -> decoded ImageData

local worker = WorkerLane.newWorker({
  name = "atlas", script = "src/render/atlas_worker.lua",
  cmd = "atlas_cmd", out = "atlas_out",
  capable = function() return love.image and love.image.newImageData end,
  onStop = function()
    ready:clear()
    dready:clear()
  end,
})
local bakes = worker:newLane({ inflight = 2, sendCap = 1 })
-- decodes: examineCap bounds the resolving of queued entries per update
local decodes = worker:newLane({ inflight = 4, sendCap = 4, examineCap = 8 })

-- Set by TileRenderer: true while the key already has a gbcAtlasCache slot.
AtlasPrefetch.isFilled = function() return false end

-- Set by Assets: resolveDecodable(path) -> resolved path of a plain PNG, or
-- nil.  Resolution (a filesystem lookup per mod) is deferred to the send, so
-- queueing a hint costs the crossing nothing.
AtlasPrefetch.resolveDecodable = function(path) return path end
-- Set by Assets: the path the worker must open (NX overlay mapping)
AtlasPrefetch.workerPath = function(resolved) return resolved end

-- Everything pending or finished is obsolete (assets / mod state changed).
-- A job still running is discarded when it arrives.
function AtlasPrefetch.bump()
  bakes:bump()
  decodes:bump()
  ready:clear()
  dready:clear()
end

-- Only the palette changed: baked atlases (queued, finished, running) were
-- made for the old colours, but the decoded files and source sheets are
-- palette independent and stay.  Decodes the worker had not started are
-- re-sent (Lane:bump clears the inbox).
function AtlasPrefetch.bumpBakes()
  bakes:bump()
  ready:clear()
end

-- the bake epoch
function AtlasPrefetch.epoch() return bakes.epoch end

-- true when a bake for `key` is already at the worker or finished (a merely
-- queued one is not "known": request() promotes it when asked for the front)
function AtlasPrefetch.known(key)
  return bakes.inflight[key] ~= nil or ready:get(key) ~= nil
end

-- true when a worker is (or can be) running; callers skip building hints
-- otherwise (no love.thread, POKEPORT_NO_THREAD=1, start failure, dead worker)
function AtlasPrefetch.available()
  return worker:ensure()
end

-- Queue a bake.  make() -> payload { src, perRow, tileColors, aliases } or
-- nil to skip; it runs when the request is sent.  front puts it ahead of
-- queued hints (and promotes a hint already queued).  Returns true when a
-- request is pending.
function AtlasPrefetch.request(key, make, front)
  if not worker:ensure() then return false end
  if ready:get(key) ~= nil or bakes.inflight[key] then return true end
  if bakes:promote(key, front) then return true end
  bakes:push(key, { make = make }, front)
  return true
end

-- Hand a finished ImageData to getGbcAtlas (removes it from the store).
function AtlasPrefetch.take(key)
  return ready:take(key)
end

-- The slot was filled another way (sync bake): nothing queued or finished
-- for it is needed any more.  A bake already at the worker is dropped on
-- arrival (isFilled).
function AtlasPrefetch.forget(key)
  ready:remove(key)
  bakes:forget(key)
end

-- Queue a PNG decode of an asset path (the store is keyed by what
-- Assets.resolve makes of it).  front: ahead of queued hints.  Returns true
-- when a request is pending.
function AtlasPrefetch.requestDecode(path, front)
  if not worker:ensure() then return false end
  if decodes:promote(path, front) then return true end
  decodes:push(path, {}, front)
  return true
end

-- The decoded ImageData for a resolved path, or nil.  It STAYS in the store
-- (LRU) and is shared: a caller that mutates it must clone() first.
function AtlasPrefetch.peekDecoded(path)
  return dready:peek(path)
end

function AtlasPrefetch.decodedCount() return dready:count() end

function AtlasPrefetch.decodePending() return decodes:pending() end

local function sendDecode(entry)
  local ok, resolved = pcall(AtlasPrefetch.resolveDecodable, entry.key)
  if not (ok and resolved) or dready:get(resolved) ~= nil
     or decodes.inflight[resolved] then
    return false
  end
  local okp, path = pcall(AtlasPrefetch.workerPath, resolved)
  if okp and path and worker:push(
      { cmd = "decode", epoch = decodes.epoch, key = resolved, path = path }) then
    return true, resolved -- tracked (and stored) under the resolved path
  end
  return false
end

local function sendBake(entry)
  if AtlasPrefetch.isFilled(entry.key) then return false end
  local ok, payload = pcall(entry.make)
  if not (ok and payload) then return false end
  return worker:push({
    cmd = "bake", epoch = bakes.epoch, key = entry.key, src = payload.src,
    srcPath = payload.srcPath,
    perRow = payload.perRow, tileColors = payload.tileColors,
    aliases = payload.aliases,
  })
end

local function onResult(result)
  local key = result.key
  if result.decode then
    local entry = decodes:complete(key, result.epoch)
    -- the store is capped by count, so keep oversized (mod) sheets out of it:
    -- above ~1 MB of pixels they decode synchronously as before
    local d = result.data
    local w, h = 0, 0
    if d and d.getDimensions then w, h = d:getDimensions() end
    if entry and d and w * h * 4 <= 1048576 then
      dready:set(key, result.data)
    end
    return false -- storing a decode is free: not counted against the drain cap
  end
  -- current only if it answers the request in flight under this epoch
  if bakes:complete(key, result.epoch) and result.data
     and not AtlasPrefetch.isFilled(key) then
    ready:set(key, result.data)
  end
  return true
end

-- Per-frame drain (Game:update).  Moves finished ImageData into the stores;
-- never touches the GPU.
function AtlasPrefetch.update()
  if not worker:drain(DRAIN_CAP, onResult) then return end
  decodes:pump(sendDecode)
  bakes:pump(sendBake)
end

-- nothing queued, nothing at the worker (always true without a thread)
function AtlasPrefetch.idle()
  if not worker.state then return true end
  return bakes:idle() and decodes:idle()
end

function AtlasPrefetch.pending() return bakes:pending() end

function AtlasPrefetch.readyCount() return ready:count() end

-- End the worker thread (LOVE waits for live threads at exit).  Safe to call
-- repeatedly; the next request starts a fresh worker.  (Also registered with
-- SessionLifecycle by WorkerLane.)
function AtlasPrefetch.shutdown() worker:shutdown() end

function AtlasPrefetch._setNoThreadEnvForTest(value)
  worker.noThread = value
  worker.state = nil -- test reset: also clears a fatal "off"
end

function AtlasPrefetch._setDecodeLimitsForTest(inflightMax, sendCap, readyCap)
  decodes.inflightMax = inflightMax or 4
  decodes.sendCap = sendCap or 4
  dready:setCap(readyCap or 64)
end

function AtlasPrefetch._setLimitsForTest(inflightMax, drainCap, sendCap, readyCap)
  bakes.inflightMax = inflightMax or 2
  DRAIN_CAP = drainCap or 2
  bakes.sendCap = sendCap or 1
  ready:setCap(readyCap or 24)
end

return AtlasPrefetch
