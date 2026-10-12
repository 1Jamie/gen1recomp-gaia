-- RED++ atlas background bake (AtlasBake, AtlasPrefetch, atlas_worker,
-- TileRenderer.getGbcAtlas / prefetchAtlas, OverworldState.prefetchAtlases).
--   luajit tests/engine/atlas_prefetch_test.lua
-- The worker is driven in-process: the test pops the commands AtlasPrefetch
-- pushed and runs the real Worker.handle + AtlasBake over them.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

-- ---- fake ImageData / Image ------------------------------------------------
local ID = {}
ID.__index = ID
local function newID(w, h)
  return setmetatable({ w = w, h = h, px = {} }, ID)
end
function ID:getDimensions() return self.w, self.h end
function ID:getPixel(x, y)
  local p = self.px[y * self.w + x]
  if not p then return 0, 0, 0, 0 end
  return p[1], p[2], p[3], p[4]
end
function ID:setPixel(x, y, r, g, b, a) self.px[y * self.w + x] = { r, g, b, a } end

local function sameImage(a, b)
  if a.w ~= b.w or a.h ~= b.h then return false end
  for y = 0, a.h - 1 do
    for x = 0, a.w - 1 do
      local r1, g1, b1, a1 = a:getPixel(x, y)
      local r2, g2, b2, a2 = b:getPixel(x, y)
      if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 or a1 ~= a2 then return false end
    end
  end
  return true
end

-- deterministic 4-shade source with some transparent texels
local function makeSource(w, h)
  local s = newID(w, h)
  local shades = { 1, 0.67, 0.33, 0 }
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local v = shades[(x * 3 + y * 5 + math.floor(x / 8)) % 4 + 1]
      s:setPixel(x, y, v, v, v, ((x + y) % 7 == 0) and 0 or 1)
    end
  end
  return s
end

love.image = love.image or {}
local sources = {}   -- path -> ImageData (what the worker's file decode returns)
local function stubNewImageData(w, h)
  if type(w) == "string" then return sources[w] end
  return newID(w, h)
end
love.image.newImageData = stubNewImageData
local imagesBuilt = 0
love.graphics = love.graphics or {}
love.graphics.newImage = function(data)
  imagesBuilt = imagesBuilt + 1
  return { isImage = true, data = data }
end

local Assets = require("src.render.Assets")
local decodes = 0
Assets.imageData = function(path)
  decodes = decodes + 1
  return sources[path]
end

local AtlasBake = require("src.render.AtlasBake")

-- ---- 1. AtlasBake == the old inline loop -----------------------------------
local function oldLoop(src, out, perRow, groupColors, tilesetId, mapId, aliasesDef, groupAt)
  local recolorSample = AtlasBake.recolorSample
  local iw, ih = src:getDimensions()
  local total = (iw / 8) * (ih / 8)
  local tileColors = {}
  for t = 0, total - 1 do
    local colors = tileColors[t]
    if colors == nil then
      local group = groupAt(tilesetId, mapId, t)
      colors = (group and groupColors[group + 1]) or false
      tileColors[t] = colors
    end
    local ox, oy = (t % perRow) * 8, math.floor(t / perRow) * 8
    for py = 0, 7 do
      for px = 0, 7 do
        local sx, sy = ox + px, oy + py
        local r, g, b, a = src:getPixel(sx, sy)
        r, g, b, a = recolorSample(r, g, b, a, colors)
        out:setPixel(sx, sy, r, g, b, a)
      end
    end
  end
  for _, al in ipairs(aliasesDef) do
    if al.alias < total then
      local colors = groupColors[al.group + 1]
      local sxo = (al.tile % perRow) * 8
      local syo = math.floor(al.tile / perRow) * 8
      local dxo = (al.alias % perRow) * 8
      local dyo = math.floor(al.alias / perRow) * 8
      for py = 0, 7 do
        for px = 0, 7 do
          local r, g, b, a = src:getPixel(sxo + px, syo + py)
          r, g, b, a = recolorSample(r, g, b, a, colors)
          out:setPixel(dxo + px, dyo + py, r, g, b, a)
        end
      end
    end
  end
end

local function pal(n)
  return { { 255, 255, n }, { 200, 100, n }, { 100, 50, n }, { 0, 0, n } }
end

do
  local perRow = 4
  local src = makeSource(32, 24) -- 4 x 3 = 12 tiles
  local groupColors = { pal(1), pal(2), pal(3), pal(4) }
  -- tile 5 and 9 use no group (copy through), 11 is a wild group index
  local function groupAt(_, _, t)
    if t == 5 or t == 9 then return nil end
    return t % 4
  end
  local aliasesDef = {
    { tile = 1, alias = 10, group = 3 },
    { tile = 2, alias = 99, group = 1 }, -- outside the atlas: skipped
  }
  local old = newID(32, 24)
  oldLoop(src, old, perRow, groupColors, "TS", "M", aliasesDef, groupAt)

  -- the main-thread precompute (what TileRenderer hands the bake)
  local tileColors = {}
  for t = 0, 11 do
    local g = groupAt("TS", "M", t)
    tileColors[t] = (g and groupColors[g + 1]) or false
  end
  local aliases = {}
  for _, al in ipairs(aliasesDef) do
    if al.alias < 12 then
      aliases[#aliases + 1] = { tile = al.tile, alias = al.alias,
                                colors = groupColors[al.group + 1] }
    end
  end
  local new = newID(32, 24)
  AtlasBake.bake(src, new, perRow, tileColors, aliases)
  check(sameImage(old, new), "AtlasBake is bit-identical to the old inline loop")
  check(tileColors[5] == false, "no-group tiles carry false")
  -- tile 5 copied through untouched
  local r, g, b, a = new:getPixel(8, 8)
  local r0, g0, b0, a0 = src:getPixel(8, 8)
  check(r == r0 and g == g0 and b == b0 and a == a0, "false-colors tile is a straight copy")
end

-- ---- channel / thread stubs ---------------------------------------------------
local channels = {}
local Channel = {}
Channel.__index = Channel
function Channel:push(msg) self.queue[#self.queue + 1] = msg end
function Channel:pop() return table.remove(self.queue, 1) end
function Channel:clear() self.queue = {} end
function Channel:getCount() return #self.queue end
local function channel(name)
  channels[name] = channels[name] or setmetatable({ queue = {} }, Channel)
  return channels[name]
end

local threadsStarted, threadError = 0, nil
local function installThread()
  love.thread = {
    newThread = function()
      return { start = function() threadsStarted = threadsStarted + 1 end,
               getError = function() return threadError end,
               wait = function() end }
    end,
    getChannel = channel,
  }
end
installThread()

local Worker = require("src.render.atlas_worker")
local baked = {}  -- key -> ImageData the worker produced
local bakeOrder = {}
local function runWorker()
  local cmdCh, outCh = channel("atlas_cmd"), channel("atlas_out")
  while true do
    local cmd = cmdCh:pop()
    if not cmd then break end
    if cmd.cmd == "bake" then bakeOrder[#bakeOrder + 1] = cmd.key end
    Worker.handle(cmd, AtlasBake, outCh)
  end
  for _, r in ipairs(outCh.queue) do
    if r.data then baked[r.key] = r.data end
  end
end

-- ---- engine under test ---------------------------------------------------------
local PaletteFX = require("src.render.PaletteFX")
local TileRenderer = require("src.render.TileRenderer")
local AtlasPrefetch = require("src.render.AtlasPrefetch")
local Game = require("src.core.Game")
local OW = require("src.world.OverworldController")

check(TileRenderer.recolorSample == AtlasBake.recolorSample,
  "TileRenderer.recolorSample is the AtlasBake function")

-- 7 maps chained west->east, all the OVERWORLD tileset
local function newData()
  local maps = {}
  for i = 1, 7 do
    local conns = {}
    if i > 1 then conns.west = { map = "M" .. (i - 1), offset = 0 } end
    if i < 7 then conns.east = { map = "M" .. (i + 1), offset = 0 } end
    maps["M" .. i] = { id = "M" .. i, width = 10, height = 10,
                       tileset = "OVERWORLD", connections = conns }
  end
  return {
    maps = maps,
    tilesets = { OVERWORLD = { id = "OVERWORLD", image = "gfx/ts.png",
                               tilesPerRow = 4 } },
  }
end
sources["gfx/ts.png"] = makeSource(32, 24)
-- a readable PNG header lets the worker decode the file itself (no header: the
-- hint is skipped, see section 8)
love.filesystem.write("gfx/ts.png", "\137PNG\r\n\26\n" .. "\0\0\0\13" .. "IHDR" ..
  string.char(0, 0, 0, 32) .. string.char(0, 0, 0, 24))

local function keyFor(id) return "gfx/ts.png#gbc:" .. id .. PaletteFX.darkKey() end

local function reset()
  PaletteFX.mode = "redpp"
  PaletteFX.setDarkWorld(false)
  TileRenderer.invalidate() -- empties gbcAtlasCache + AtlasPrefetch
  AtlasPrefetch.shutdown()
  AtlasPrefetch._setNoThreadEnvForTest(nil)
  AtlasPrefetch._setLimitsForTest(10, 10, 10, 24)
  threadError = nil
  channel("atlas_cmd"):clear()
  channel("atlas_out"):clear()
  baked, bakeOrder = {}, {}
  installThread()
end

local function atlasOf(data, id)
  return TileRenderer._getGbcAtlas("gfx/ts.png", "OVERWORLD", id, 4, data)
end

-- a sync bake of `id` for comparison (own fresh state)
local function syncImage(data, id)
  reset()
  AtlasPrefetch._setNoThreadEnvForTest("1")
  return atlasOf(data, id)
end

-- ---- 2. ready-store hit is used, identical to a sync bake ----------------------
do
  local data = newData()
  local ref = syncImage(data, "M2")
  check(ref and ref.isImage, "sync path bakes an image")

  reset()
  check(TileRenderer.prefetchAtlas(data, "M2", false), "prefetch accepted")
  TileRenderer.prefetchAtlas(data, "M2", false) -- duplicate request
  eq((AtlasPrefetch.pending()), 1, "duplicate request is not queued twice")
  AtlasPrefetch.update(); runWorker(); AtlasPrefetch.update()
  eq(AtlasPrefetch.readyCount(), 1, "finished bake waits in the ready store")
  local made = imagesBuilt
  local img = atlasOf(data, "M2")
  eq(imagesBuilt, made + 1, "newImage happens in getGbcAtlas, once")
  check(sameImage(img.data, ref.data), "prefetched atlas is pixel-identical to the sync bake")
  eq(AtlasPrefetch.readyCount(), 0, "the entry leaves the store once filed")
  local decodedForSync = decodes
  local again = atlasOf(data, "M2")
  check(again == img, "second build reuses the cached atlas")
  eq(decodes, decodedForSync, "and decodes nothing")
end

-- ---- 3. existing cache entry is never replaced; late result dropped ------------
do
  local data = newData()
  reset()
  local first = atlasOf(data, "M3")           -- sync fill
  check(not TileRenderer.prefetchAtlas(data, "M3", false), "cached key is not prefetched")
  eq((AtlasPrefetch.pending()), 0, "nothing queued for a cached key")

  -- in flight when the sync path fills the slot
  reset()
  TileRenderer.prefetchAtlas(data, "M4", false)
  AtlasPrefetch.update()                      -- sends to the worker
  eq(select(2, AtlasPrefetch.pending()), 1, "bake is at the worker")
  local sync = atlasOf(data, "M4")            -- map built before the result
  runWorker()
  AtlasPrefetch.update()
  eq(AtlasPrefetch.readyCount(), 0, "late result is dropped (slot already filled)")
  check(atlasOf(data, "M4") == sync, "cache entry is unchanged")
  check(AtlasPrefetch.idle(), "the dropped result retired the request")

  -- queued (unsent) when the sync path fills the slot: never sent
  reset()
  TileRenderer.prefetchAtlas(data, "M5", false)
  atlasOf(data, "M5")
  AtlasPrefetch.update()
  eq(channel("atlas_cmd"):getCount(), 0, "request for a filled slot is not sent")

  -- result arrives while slot filled by a ready entry elsewhere: no replacement
  reset()
  TileRenderer.prefetchAtlas(data, "M6", false)
  AtlasPrefetch.update(); runWorker(); AtlasPrefetch.update()
  local img = atlasOf(data, "M6")
  runWorker(); AtlasPrefetch.update()
  check(atlasOf(data, "M6") == img, "filed atlas object stays the same")
end

-- ---- 4. epoch bumps -------------------------------------------------------------
do
  local data = newData()
  -- queued + ready + late all dropped by TileRenderer.invalidate
  reset()
  TileRenderer.prefetchAtlas(data, "M1", false)
  TileRenderer.prefetchAtlas(data, "M2", false)
  AtlasPrefetch._setLimitsForTest(1, 10, 1, 24)
  AtlasPrefetch.update()                    -- M1 sent, M2 still queued
  runWorker(); AtlasPrefetch.update()       -- M1 -> ready, M2 sent
  local e = AtlasPrefetch.epoch()
  TileRenderer.invalidate()
  check(AtlasPrefetch.epoch() > e, "TileRenderer.invalidate bumps the epoch")
  eq(AtlasPrefetch.readyCount(), 0, "ready store cleared")
  eq(channel("atlas_cmd"):getCount(), 0, "worker inbox cleared")
  eq(select(1, AtlasPrefetch.pending()), 0, "queue dropped")
  runWorker(); AtlasPrefetch.update()       -- M2's late result
  eq(AtlasPrefetch.readyCount(), 0, "late result from the old epoch is discarded")
  check(AtlasPrefetch.idle(), "idle again")

  -- palette mode changes bump too
  reset()
  TileRenderer.prefetchAtlas(data, "M1", false)
  AtlasPrefetch.update(); runWorker(); AtlasPrefetch.update()
  eq(AtlasPrefetch.readyCount(), 1, "one ready")
  e = AtlasPrefetch.epoch()
  PaletteFX.setMode("gbc")
  check(AtlasPrefetch.epoch() > e, "PaletteFX.setMode bumps the epoch")
  eq(AtlasPrefetch.readyCount(), 0, "and drops the ready store")
  check(not TileRenderer.prefetchAtlas(data, "M1", false), "no prefetch outside RED++")
  PaletteFX.mode = "redpp"

  -- the asset flush fan-out (Assets.register) reaches it
  reset()
  TileRenderer.prefetchAtlas(data, "M1", false)
  AtlasPrefetch.update(); runWorker(); AtlasPrefetch.update()
  e = AtlasPrefetch.epoch()
  Assets.flush()
  check(AtlasPrefetch.epoch() > e, "asset flush bumps the epoch")
  eq(AtlasPrefetch.readyCount(), 0, "flush drops the ready store")

  -- dark shift is part of the key: a lit request is not used for a dark build
  reset()
  TileRenderer.prefetchAtlas(data, "M1", false)
  PaletteFX.setDarkWorld(true)
  AtlasPrefetch.update()
  eq(channel("atlas_cmd"):getCount(), 0, "a request made lit is not sent once dark")
  PaletteFX.setDarkWorld(false)
end

-- ---- 5. fallbacks ------------------------------------------------------------------
do
  local data = newData()
  reset()
  love.thread = nil
  check(not TileRenderer.prefetchAtlas(data, "M1", false), "no love.thread: no-op")
  check(AtlasPrefetch.idle(), "no love.thread: idle")
  check(atlasOf(data, "M1") ~= nil, "no love.thread: sync atlas still built")
  AtlasPrefetch.update()

  reset()
  AtlasPrefetch._setNoThreadEnvForTest("1")
  local before = threadsStarted
  check(not TileRenderer.prefetchAtlas(data, "M1", false), "POKEPORT_NO_THREAD=1: no-op")
  eq(threadsStarted, before, "POKEPORT_NO_THREAD=1 never starts the worker")
  check(atlasOf(data, "M1") ~= nil, "POKEPORT_NO_THREAD=1: sync atlas built")

  reset()
  love.thread.newThread = function() error("boom") end
  check(not TileRenderer.prefetchAtlas(data, "M1", false), "start failure: no-op")
  check(atlasOf(data, "M1") ~= nil, "start failure: sync atlas built")

  reset()
  TileRenderer.prefetchAtlas(data, "M1", false)
  AtlasPrefetch.update()
  channel("atlas_out"):push({ fatal = "kaboom" })
  AtlasPrefetch.update()
  check(AtlasPrefetch.idle(), "fatal report drops the queue")
  check(not TileRenderer.prefetchAtlas(data, "M2", false), "and later prefetches are no-ops")
  check(atlasOf(data, "M2") ~= nil, "fatal: sync atlas built")

  reset()
  TileRenderer.prefetchAtlas(data, "M1", false)
  AtlasPrefetch.update()
  threadError = "worker crashed"
  AtlasPrefetch.update()
  check(not TileRenderer.prefetchAtlas(data, "M2", false), "dead worker: no-op")
  check(atlasOf(data, "M2") ~= nil, "dead worker: sync atlas built")
  threadError = nil

  -- a worker-side failure leaves the slot empty for the sync path
  reset()
  local savedBake = AtlasBake.bake
  AtlasBake.bake = function() error("bad bake") end
  TileRenderer.prefetchAtlas(data, "M1", false)
  AtlasPrefetch.update(); runWorker(); AtlasPrefetch.update()
  AtlasBake.bake = savedBake
  eq(AtlasPrefetch.readyCount(), 0, "failed bake stores nothing")
  check(AtlasPrefetch.idle(), "failed bake retires the request")
  check(atlasOf(data, "M1") ~= nil, "failed bake: sync atlas built")
end

-- ---- 6. ready-store cap ------------------------------------------------------------
do
  local data = newData()
  reset()
  AtlasPrefetch._setLimitsForTest(10, 10, 10, 3)
  for i = 1, 7 do TileRenderer.prefetchAtlas(data, "M" .. i, false) end
  for _ = 1, 3 do AtlasPrefetch.update(); runWorker() end
  AtlasPrefetch.update()
  eq(AtlasPrefetch.readyCount(), 3, "ready store is bounded")
  check(AtlasPrefetch.take(keyFor("M7")) ~= nil, "newest entry kept")
  check(AtlasPrefetch.take(keyFor("M1")) == nil, "oldest entry evicted")
end

-- ---- 7. prefetch selection -----------------------------------------------------------
local function bakeCmds()
  local out = {}
  for _, c in ipairs(channel("atlas_cmd").queue) do
    if c.cmd == "bake" then out[#out + 1] = c.key end
  end
  return out
end
do
  local data = newData()
  local savedData, savedRenderer = Game.data, Game.renderer
  Game.data = data
  Game.renderer = { worldViewSize = function() return 160, 144 end }
  OW._setGameForTest(Game)
  local ow = setmetatable({}, { __index = OW })

  eq(#OW.prefetchTargets(data.maps, { "M4" }, 2, 144, 136), 4, "prefetchTargets lists a map's four neighbors")

  -- standing on M4: neighbours are M2,M3,M5,M6; one crossing later M1 and M7
  reset()
  ow:prefetchAtlases("M4", false)
  AtlasPrefetch.update()
  local keys = bakeCmds()
  table.sort(keys)
  eq(table.concat(keys, ","), keyFor("M1") .. "," .. keyFor("M7"),
    "after setMap: only maps that join the neighbor set at the next crossing")

  -- resident (already cached) maps are skipped
  reset()
  atlasOf(data, "M7")
  ow:prefetchAtlases("M4", false)
  AtlasPrefetch.update()
  eq(#bakeCmds(), 1, "a resident map's atlas is not re-queued")
  eq(bakeCmds()[1], keyFor("M1"), "and the other one is")

  -- warp: destination first, then its neighbours, all ahead of old hints
  reset()
  AtlasPrefetch._setLimitsForTest(10, 10, 10, 24)
  ow:prefetchAtlases("M4", false)             -- low-priority hints queued first
  ow:prefetchAtlases("M1", true)              -- warp to M1
  AtlasPrefetch.update()
  local order = bakeCmds()
  eq(order[1], keyFor("M1"), "warp destination is first")
  eq(table.concat(order, ","),
     table.concat({ keyFor("M1"), keyFor("M2"), keyFor("M3"), keyFor("M7") }, ","),
     "warp: destination, its neighbours, then the older low-priority hint")

  -- not RED++: nothing at all
  reset()
  PaletteFX.mode = "gbc"
  ow:prefetchAtlases("M4", false)
  ow:prefetchAtlases("M4", true)
  eq((AtlasPrefetch.pending()), 0, "outside RED++ the overworld queues nothing")
  PaletteFX.mode = "redpp"

  Game.data, Game.renderer = savedData, savedRenderer
end

-- ---- 8. bake source: worker-side decode path, NX overlay, shared decode -----------
do
  local GameVersion = require("src.core.GameVersion")
  local Platform = require("src.core.Platform")
  local Overlay = require("src.core.NxAssetOverlay")
  local P2 = "assets/generated/ts2.png"
  local header = "\137PNG\r\n\26\n" .. "\0\0\0\13" .. "IHDR" ..
    string.char(0, 0, 0, 32) .. string.char(0, 0, 0, 24)
  local function data2()
    local d = newData()
    d.tilesets.OVERWORLD.image = P2
    return d
  end
  local function lastBake()
    for _, c in ipairs(channel("atlas_cmd").queue) do
      if c.cmd == "bake" then return c end
    end
  end
  sources[P2] = makeSource(32, 24)
  love.filesystem.write(P2, header)

  reset()
  TileRenderer.prefetchAtlas(data2(), "M1", false)
  AtlasPrefetch.update()
  local c = lastBake()
  eq(c.srcPath, P2, "plain: the worker decodes the file itself")
  check(c.src == nil, "plain: nothing decoded on the main thread")
  local n = 0
  for _ in pairs(c.tileColors) do n = n + 1 end
  eq(n, 12, "tile colours sized from the PNG header")

  -- a decode the worker already finished is sent along instead of re-decoding
  reset()
  local stored = newID(32, 24)
  love.image.newImageData = function(a, b) if type(a) == "string" then return stored end return newID(a, b) end
  Assets.prefetchImage(P2, true)
  AtlasPrefetch.update(); runWorker(); AtlasPrefetch.update()
  TileRenderer.prefetchAtlas(data2(), "M1", false)
  AtlasPrefetch.update()
  c = lastBake()
  check(c and c.src == stored and c.srcPath == nil, "stored tileset decode is reused as the bake source")
  love.image.newImageData = stubNewImageData

  -- NX: size and decode both go through the overlay's versioned path
  local savedSystem, savedVersion = love.system, GameVersion.get()
  love.system = { getOS = function() return "NX" end }
  Platform._resetForTests()
  GameVersion.set("yellow")
  love.filesystem.write("yellow/" .. P2, header)
  Overlay.install()
  reset()
  TileRenderer.prefetchAtlas(data2(), "M2", false)
  AtlasPrefetch.update()
  c = lastBake()
  eq(c and c.srcPath, "yellow/" .. P2, "NX: bake srcPath is the versioned path")

  -- unreadable header (no file at either path): the hint is skipped
  love.filesystem.remove("yellow/" .. P2)
  love.filesystem.remove(P2)
  reset()
  local decodesBefore = decodes
  TileRenderer.prefetchAtlas(data2(), "M3", false)
  AtlasPrefetch.update()
  check(lastBake() == nil, "no readable header: no bake is sent")
  check(AtlasPrefetch.idle(), "no readable header: the hint is dropped")
  eq(decodes, decodesBefore, "no readable header: nothing decoded on the main thread")

  -- a file the worker cannot decode (not a PNG): skipped the same way
  local P3 = "assets/generated/ts3.jpg"
  sources[P3] = makeSource(32, 24)
  love.filesystem.write("yellow/" .. P3, header)
  love.filesystem.write(P3, header)
  reset()
  local d3 = data2()
  d3.tilesets.OVERWORLD.image = P3
  TileRenderer.prefetchAtlas(d3, "M3", false)
  AtlasPrefetch.update()
  check(lastBake() == nil and AtlasPrefetch.idle(), "non-PNG: hint skipped")
  eq(decodes, decodesBefore, "non-PNG: nothing decoded on the main thread")
  Overlay.uninstall()
  love.system = savedSystem
  Platform._resetForTests()
  GameVersion.set(savedVersion)
end

-- a composed tileset sheet (UnionCenters) is never baked off a file
do
  reset()
  Assets.compose("gfx/ts.png", function() return sources["gfx/ts.png"] end)
  check(not TileRenderer.prefetchAtlas(newData(), "M1", false),
    "composed sheet: no background bake")
  check(AtlasPrefetch.idle(), "composed sheet: nothing queued")
  Assets.compose("gfx/ts.png", nil)
  check(TileRenderer.prefetchAtlas(newData(), "M1", false), "plain sheet: queued")
end

reset()
AtlasPrefetch.shutdown()
T.finish()
