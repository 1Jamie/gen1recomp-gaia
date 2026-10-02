package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local check, eq = T.check, T.eq
love = require("tests.love_stub")
local channels, worker = {}, {}
love.thread = {
  newChannel = function()
    local ch = { q = {} }
    function ch:push(v) self.q[#self.q + 1] = v end
    function ch:pop() return table.remove(self.q, 1) end
    function ch:clear() self.q = {} end
    channels[#channels + 1] = ch
    return ch
  end,
  newThread = function()
    function worker:start(input, output) self.input, self.output = input, output end
    function worker:getError() return self.error end
    function worker:wait() self.joined = true end
    return worker
  end,
}
local Stream = require("src.core.game3.asset_stream")
local published, uploads = {}, 0
local cache = { assetWorkerSpec = function() return { prefix = "emerald/" } end }
local function owner()
  return Stream.new("pair", cache, "ROOT", function(data)
    for _ = 1, data.layers do uploads = uploads + 1; coroutine.yield("texture") end
    return data
  end, function(key, data) published[key] = data end)
end
local s = owner()
s:prefetch("A"); s:prefetch("A"); Stream.poll()
eq(#worker.input.q, 1, "duplicate requests are coalesced")
local request = worker.input:pop()
eq(request.spec.prefix, "emerald/", "worker receives an immutable cartridge namespace")
eq(uploads, 0, "queuing CPU work does not touch graphics")
worker.output:push({ id = request.id, data = { layers = 3 }, seconds = .01 })
Stream.update()
eq(uploads, 1, "only one texture layer uploads in an update")
Stream.update(); eq(uploads, 1, "fixed-step catchup cannot upload another layer in the same render frame")
Stream.frameComplete(); Stream.update(); eq(uploads, 2, "next render frame admits the next layer")
check(published.A == nil, "partially uploaded atlases are never published")
local result = s:get("A")
eq(uploads, 3, "unexpected demand finishes the existing partial upload without duplicating textures")
check(published.A == result and result.layers == 3, "fallback publishes the complete atlas")

s:prefetch("STALE"); Stream.poll(); request = worker.input:pop()
s:cancel()
eq(#request.cancelSignal.q, 1, "cache reset signals active CPU preparation to stop")
worker.output:push({ id = request.id, data = { layers = 1 }, seconds = .01 })
Stream.frameComplete(); Stream.update()
check(published.STALE == nil, "cache reset rejects a late result")
eq(uploads, 3, "stale data does not allocate a texture")
local nextOwner = owner()
nextOwner:prefetch("OUTSIDE"); Stream.poll(); request = worker.input:pop()
nextOwner:retain({})
eq(#request.cancelSignal.q, 1, "leaving the neighborhood interrupts active preparation")
worker.output:push({ id = request.id, data = { layers = 1 }, seconds = .01 })
Stream.frameComplete(); Stream.update()
check(published.OUTSIDE == nil, "leaving the warm neighborhood cancels queued work")
for i = 1, 100 do nextOwner:prefetch("LIMIT" .. i) end
local count = 0; for _ in pairs(nextOwner.pending) do count = count + 1 end
eq(count, Stream.MAX_PENDING, "pending assets have a residency bound")
Stream.cancelPending()
check(next(nextOwner.pending) == nil, "field stop cancels all pending requests")
Stream.shutdown()
check(worker.joined, "process teardown joins the worker before filesystem teardown")
local priorityOwner = owner()
priorityOwner:prefetch("NEAR", 1)
priorityOwner:prefetch("VISIBLE", 0)
Stream.poll(); request = worker.input:pop()
eq(request.key, "VISIBLE", "visible assets decode before nearby assets")
worker.output:push({ id = request.id, data = { layers = 1 }, seconds = .01 })
Stream.poll(); request = worker.input:pop()
eq(request.key, "NEAR", "nearby preparation follows visible preparation")
worker.output:push({ id = request.id, data = { layers = 1 }, seconds = .01 })
Stream.poll()
Stream.frameComplete(); Stream.update()
eq(coroutine.status(priorityOwner.pending.VISIBLE.co), "suspended", "visible decoded assets upload first")
check(priorityOwner.pending.NEAR.co == nil, "nearby uploads wait for the visible upload slice")
Stream.shutdown()
T.finish("game3_asset_stream_test")
