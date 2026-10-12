-- Background image FILE decode (AtlasPrefetch.requestDecode, the "decode"
-- worker command, Assets.image / Assets.imageData store hits, the sprite-path
-- helpers and OverworldState.prefetchAtlases' decode hints).
--   luajit tests/engine/image_prefetch_test.lua
-- The worker is driven in-process like atlas_prefetch_test.lua.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

-- ---- fake ImageData / Image ----------------------------------------------------
local ID = {}
ID.__index = ID
local function newID(w, h, tag)
  return setmetatable({ w = w, h = h, px = {}, tag = tag }, ID)
end
function ID:getDimensions() return self.w, self.h end
function ID:getPixel(x, y)
  local p = self.px[y * self.w + x]
  if not p then return 0, 0, 0, 0 end
  return p[1], p[2], p[3], p[4]
end
function ID:setPixel(x, y, r, g, b, a) self.px[y * self.w + x] = { r, g, b, a } end
function ID:clone()
  local c = newID(self.w, self.h, self.tag)
  for k, v in pairs(self.px) do c.px[k] = { v[1], v[2], v[3], v[4] } end
  return c
end
function ID:typeOf() return false end
function ID:mapPixel() end

local decodes = {}  -- path -> times decoded
love.image = love.image or {}
love.image.newImageData = function(a, b)
  if type(a) == "string" then
    decodes[a] = (decodes[a] or 0) + 1
    local id = newID(16, 16, a)
    id:setPixel(0, 0, 0.5, 0.5, 0.5, 1)
    return id
  end
  return newID(a, b)
end
local newImageArgs = {}
love.graphics = love.graphics or {}
love.graphics.newImage = function(a)
  newImageArgs[#newImageArgs + 1] = a
  if type(a) == "string" then decodes[a] = (decodes[a] or 0) + 1 end
  return { isImage = true, src = a,
           getDimensions = function() return 16, 16 end }
end
love.graphics.newQuad = function() return {} end

-- ---- channel / thread stubs ----------------------------------------------------
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

local AtlasBake = require("src.render.AtlasBake")
local Worker = require("src.render.atlas_worker")
local sentCmds = {}
local function runWorker()
  local cmdCh, outCh = channel("atlas_cmd"), channel("atlas_out")
  while true do
    local cmd = cmdCh:pop()
    if not cmd then break end
    sentCmds[#sentCmds + 1] = cmd
    Worker.handle(cmd, AtlasBake, outCh)
  end
end

local Assets = require("src.render.Assets")
local AtlasPrefetch = require("src.render.AtlasPrefetch")
local PaletteFX = require("src.render.PaletteFX")
local GameVersion = require("src.core.GameVersion")
local Platform = require("src.core.Platform")
local Overlay = require("src.core.NxAssetOverlay")

local function reset()
  AtlasPrefetch.shutdown()
  AtlasPrefetch._setNoThreadEnvForTest(nil)
  AtlasPrefetch._setDecodeLimitsForTest()
  AtlasPrefetch._setLimitsForTest()
  Assets.invalidate()
  threadError = nil
  channel("atlas_cmd"):clear()
  channel("atlas_out"):clear()
  decodes, newImageArgs, sentCmds = {}, {}, {}
  installThread()
end
local function settle()
  AtlasPrefetch.update(); runWorker(); AtlasPrefetch.update()
end

local P = "assets/generated/sprites/red.png"

-- ---- worker command ------------------------------------------------------------
do
  reset()
  local out = { queue = {}, push = function(self, m) self.queue[#self.queue + 1] = m end }
  Worker.handle({ cmd = "decode", epoch = 3, key = P }, AtlasBake, out)
  eq(out.queue[1].key, P, "decode result carries the path")
  check(out.queue[1].decode and out.queue[1].data and out.queue[1].epoch == 3,
    "decode result is flagged, carries the ImageData and the epoch")
  local saved = love.image.newImageData
  love.image.newImageData = function() error("bad png") end
  Worker.handle({ cmd = "decode", epoch = 3, key = "x.png" }, AtlasBake, out)
  love.image.newImageData = saved
  check(out.queue[2].failed and not out.queue[2].data, "decode error is reported, not thrown")
  -- bake from a path: the worker decodes the file itself
  Worker.handle({ cmd = "bake", epoch = 1, key = "k", srcPath = "t.png", perRow = 2,
                  tileColors = {}, aliases = {} }, AtlasBake, out)
  check(out.queue[3].data and decodes["t.png"] == 1, "bake with srcPath decodes in the worker")
end

-- ---- store hit used by Assets.image / imageData --------------------------------
do
  reset()
  PaletteFX.mode = "redpp" -- RED++ keeps the ImageData (OBJ / atlas recolours re-read it)
  check(Assets.prefetchImage(P, false), "decode request accepted")
  check(not AtlasPrefetch.idle(), "not idle while a decode is pending")
  settle()
  eq(AtlasPrefetch.decodedCount(), 1, "decoded ImageData waits in the store")
  eq(decodes[P], 1, "decoded once (by the worker)")
  local img = Assets.image(P)
  check(img.src and img.src.tag == P, "Assets.image uploads the stored ImageData")
  eq(decodes[P], 1, "and decodes nothing on the main thread")
  check(Assets.image(P) == img, "second call is the cached Image")
  eq(AtlasPrefetch.decodedCount(), 1, "the ImageData stays in the store")

  local a = Assets.imageData(P)
  local b = Assets.imageData(P)
  check(a ~= b, "each imageData call gets its own object")
  check(a ~= AtlasPrefetch.peekDecoded(P), "never the stored object")
  a:setPixel(0, 0, 1, 0, 0, 1)
  local r = AtlasPrefetch.peekDecoded(P):getPixel(0, 0)
  eq(r, 0.5, "mutating a returned ImageData leaves the stored copy unchanged")
  eq((b:getPixel(0, 0)), 0.5, "and the other clone")
  eq(decodes[P], 1, "imageData from the store decodes nothing")
  PaletteFX.mode = "gbc"
end

-- ---- the stored decode survives the upload in EVERY colour mode -------------------
-- SpriteRenderer.getObpImage re-reads the sheet through Assets.imageData in
-- dmgObj / ogObj / gen2Obp / gbc-pack alike.
for _, mode in ipairs({ "gbc", "redpp" }) do
  reset()
  PaletteFX.mode = mode
  Assets.prefetchImage(P, false); settle()
  eq(AtlasPrefetch.decodedCount(), 1, mode .. ": decoded and waiting")
  Assets.image(P)
  eq(AtlasPrefetch.decodedCount(), 1, mode .. ": the stored ImageData is kept after upload")
  check(newImageArgs[1] ~= P, mode .. ": ...and the upload came from the store")
  local before = decodes[P]
  Assets.imageData(P)
  eq(decodes[P], before, mode .. ": the OBJ-bake read after the upload decodes nothing")
end
PaletteFX.mode = "gbc"

-- ---- send-time skips are bounded per update --------------------------------------
do
  reset()
  AtlasPrefetch._setDecodeLimitsForTest(64, 64, 64)
  -- thirty paths that resolve to nothing decodable cost a resolve each: one
  -- update looks at a bounded number of them
  local realResolve = AtlasPrefetch.resolveDecodable
  AtlasPrefetch.resolveDecodable = function() return nil end
  for i = 1, 30 do
    Assets.prefetchImage("assets/generated/c" .. i .. ".png", false)
  end
  AtlasPrefetch.update()
  local queued = AtlasPrefetch.decodePending()
  check(queued >= 30 - 8 and queued < 30, "one update examines at most 8 queued entries (" .. queued .. " left)")
  for _ = 1, 4 do AtlasPrefetch.update() end
  eq((AtlasPrefetch.decodePending()), 0, "later updates drain the rest")
  eq(#channel("atlas_cmd").queue, 0, "unresolvable paths were never sent")
  AtlasPrefetch.resolveDecodable = realResolve
end

-- ---- NX asset overlay: the worker gets the path main would open ------------------
do
  local savedSystem, savedVersion = love.system, GameVersion.get()
  love.system = { getOS = function() return "NX" end }
  Platform._resetForTests()
  GameVersion.set("yellow")
  love.filesystem.write("yellow/" .. P, "yellow-png")
  Overlay.install()

  reset()
  Assets.prefetchImage(P, false); settle()
  eq(sentCmds[1].key, P, "NX: the store key stays the resolved path")
  eq(sentCmds[1].path, "yellow/" .. P, "NX: the worker is sent the versioned path")
  check(AtlasPrefetch.peekDecoded(P) ~= nil, "NX: result stored under the resolved key")

  -- no versioned copy: the unprefixed path is what main would open too
  reset()
  local other = "assets/generated/sprites/other.png"
  Assets.prefetchImage(other, false); settle()
  eq(sentCmds[1].path, other, "NX: no versioned file, the plain path is sent")

  -- a mod override is not under assets/generated: untouched
  check(Overlay.mapPath("mods/m/overrides/x.png") == "mods/m/overrides/x.png",
    "NX: non-generated paths are not remapped")

  Overlay.uninstall()
  check(Overlay.mapPath(P) == P, "uninstalled overlay maps nothing")
  reset()
  Assets.prefetchImage(P, false); settle()
  eq(sentCmds[1].path, P, "no overlay: the plain path")
  love.filesystem.remove("yellow/" .. P)
  love.system = savedSystem
  Platform._resetForTests()
  GameVersion.set(savedVersion)
end

-- ---- Assets entry never replaced; excluded paths --------------------------------
do
  reset()
  local first = Assets.image(P)             -- sync fill
  eq(decodes[P], 1, "sync decode through newImage(path) form")
  check(newImageArgs[1] == P, "no store: newImage gets the path")
  Assets.prefetchImage(P, false)
  settle()
  check(Assets.image(P) == first, "a late decode never replaces the cached Image")

  reset()
  check(not Assets.prefetchImage("assets/generated/foo@2x.png"), "@2x names are excluded")
  check(not Assets.prefetchImage("assets/generated/foo.dds"), "non-PNG is excluded")
  check(AtlasPrefetch.idle(), "nothing queued for excluded paths")
  Assets.image("assets/generated/foo@2x.png")
  check(newImageArgs[1] == "assets/generated/foo@2x.png", "excluded path loads by filename")
end

-- ---- epoch ---------------------------------------------------------------------
do
  reset()
  Assets.prefetchImage(P, false)
  settle()
  Assets.prefetchImage("assets/generated/b.png", false)
  AtlasPrefetch.update()                 -- b is at the worker
  Assets.prefetchImage("assets/generated/c.png", false)
  local e = AtlasPrefetch.epoch()
  Assets.invalidate()
  check(AtlasPrefetch.epoch() > e, "Assets.invalidate bumps the epoch")
  eq(AtlasPrefetch.decodedCount(), 0, "decoded store dropped")
  eq(channel("atlas_cmd"):getCount(), 0, "worker inbox cleared")
  eq((AtlasPrefetch.decodePending()), 0, "queued decodes dropped")
  runWorker(); AtlasPrefetch.update()
  eq(AtlasPrefetch.decodedCount(), 0, "late result from the old epoch is discarded")
  check(AtlasPrefetch.idle(), "idle again")

  -- a palette change only obsoletes bakes: decoded files (stored, queued and
  -- the one already sitting in the worker's inbox) survive it
  reset()
  Assets.prefetchImage(P, false); settle()
  Assets.prefetchImage("assets/generated/b.png", false)
  AtlasPrefetch.update()                 -- b is in the worker's inbox
  Assets.prefetchImage("assets/generated/c.png", false)  -- still queued
  e = AtlasPrefetch.epoch()
  PaletteFX.setMode("redpp")             -- invalidateColorCaches -> bumpBakes
  check(AtlasPrefetch.epoch() > e, "palette change bumps the bake epoch")
  eq(AtlasPrefetch.decodedCount(), 1, "palette change keeps the decoded store")
  check(AtlasPrefetch.peekDecoded(P) ~= nil, "...and the decoded sheet is still served")
  local queuedAfter = AtlasPrefetch.decodePending()
  eq(queuedAfter, 2, "queued and un-started decodes are kept (b re-queued, c)")
  for _ = 1, 3 do settle() end
  eq(AtlasPrefetch.decodedCount(), 3, "every decode is still delivered")
  check(AtlasPrefetch.idle(), "and nothing is stranded in flight")
  PaletteFX.setMode("gbc")

  -- a mod-set change (installLoader) re-resolves paths: also a bump
  reset()
  Assets.prefetchImage(P, false); settle()
  e = AtlasPrefetch.epoch()
  Assets.installLoader(nil)
  check(AtlasPrefetch.epoch() > e and AtlasPrefetch.decodedCount() == 0,
    "installLoader drops the store")
  -- the store is keyed by the RESOLVED path
  reset()
  Assets.loader = { overrideOrder = function() return { { id = "m", path = "mods/m" } } end,
                    derivedPath = function() return nil end }
  local savedGet = love.filesystem.getInfo
  love.filesystem.getInfo = function(p) if p == "mods/m/overrides/sprites/red.png" then return {} end end
  Assets.prefetchImage(P, false); settle()
  eq(sentCmds[1].key, "mods/m/overrides/sprites/red.png", "mod override: the resolved path is decoded")
  check(Assets.image(P).src.tag == "mods/m/overrides/sprites/red.png", "and used for the shadowed asset")
  love.filesystem.getInfo = savedGet
  Assets.loader = nil
  Assets.invalidate()
end

-- ---- fallbacks -----------------------------------------------------------------
do
  reset()
  love.thread = nil
  check(not Assets.prefetchImage(P), "no love.thread: no-op")
  check(AtlasPrefetch.idle(), "no love.thread: idle")
  check(Assets.image(P) ~= nil and decodes[P] == 1, "no love.thread: sync image")
  check(Assets.imageData(P) ~= nil, "no love.thread: sync imageData")

  reset()
  AtlasPrefetch._setNoThreadEnvForTest("1")
  local before = threadsStarted
  check(not Assets.prefetchImage(P), "POKEPORT_NO_THREAD=1: no-op")
  eq(threadsStarted, before, "POKEPORT_NO_THREAD=1 never starts the worker")

  reset()
  love.thread.newThread = function() error("boom") end
  check(not Assets.prefetchImage(P), "start failure: no-op")

  reset()
  Assets.prefetchImage(P); AtlasPrefetch.update()
  channel("atlas_out"):push({ fatal = "kaboom" })
  AtlasPrefetch.update()
  check(AtlasPrefetch.idle() and not Assets.prefetchImage("assets/generated/z.png"),
    "fatal: queue dropped, later requests no-ops")
  check(Assets.image(P) ~= nil, "fatal: sync image")

  reset()
  Assets.prefetchImage(P); AtlasPrefetch.update()
  threadError = "worker crashed"
  AtlasPrefetch.update()
  check(not Assets.prefetchImage("assets/generated/z.png"), "dead worker: no-op")
  threadError = nil

  reset()
  local savedND = love.image.newImageData
  love.image.newImageData = function() error("corrupt") end
  Assets.prefetchImage(P); settle()
  love.image.newImageData = savedND
  eq(AtlasPrefetch.decodedCount(), 0, "failed decode stores nothing")
  check(AtlasPrefetch.idle(), "failed decode retires the request")
  check(Assets.image(P) ~= nil, "failed decode: sync image")
end

-- ---- budget, priority, LRU -------------------------------------------------------
do
  reset()
  AtlasPrefetch._setDecodeLimitsForTest(2, 4, 64)
  for i = 1, 5 do Assets.prefetchImage("assets/generated/s" .. i .. ".png", false) end
  Assets.prefetchImage("assets/generated/s5.png", true) -- promote
  Assets.prefetchImage("assets/generated/s5.png", true) -- duplicate
  local queued = AtlasPrefetch.decodePending()
  eq(queued, 5, "duplicates are not queued twice")
  AtlasPrefetch.update()
  local q, flying = AtlasPrefetch.decodePending()
  eq(flying, 2, "in-flight decode budget is respected")
  eq(q, 3, "the rest wait")
  runWorker()
  eq(sentCmds[1].key, "assets/generated/s5.png", "front request overtakes queued hints")
  for _ = 1, 4 do settle() end
  eq(AtlasPrefetch.decodedCount(), 5, "all decodes eventually land")

  reset()
  AtlasPrefetch._setDecodeLimitsForTest(8, 8, 3)
  for i = 1, 6 do Assets.prefetchImage("assets/generated/s" .. i .. ".png", false) end
  for _ = 1, 3 do settle() end
  eq(AtlasPrefetch.decodedCount(), 3, "decoded store is bounded")
  check(AtlasPrefetch.peekDecoded("assets/generated/s6.png") ~= nil, "newest kept")
  check(AtlasPrefetch.peekDecoded("assets/generated/s1.png") == nil, "oldest evicted")
end

-- ---- PNG header size ---------------------------------------------------------------
do
  local head = "\137PNG\r\n\26\n" .. "\0\0\0\13" .. "IHDR" ..
    string.char(0, 0, 0, 128) .. string.char(0, 0, 1, 64)
  local saved = love.filesystem.read
  love.filesystem.read = function(p) if p == "t.png" then return head, #head end end
  local w, h = Assets.pngSize("t.png")
  eq(w, 128, "png width from the header")
  eq(h, 320, "png height from the header")
  check(Assets.pngSize("nope.png") == nil, "unreadable file: nil")
  love.filesystem.read = saved
end

-- ---- sprite path helper parity -------------------------------------------------------
local SpriteRenderer = require("src.render.SpriteRenderer")
local NPC = require("src.world.NPC")
do
  reset()
  local loaded = {}
  local realImage = Assets.image
  Assets.image = function(path) loaded[#loaded + 1] = path; return realImage(path) end
  local defs = {
    vanilla = { image = "assets/generated/sprites/red.png", frames = 3 },
    mod = { image = "mods/foo/sprites/hero.png", frames = 1, frameWidth = 24 },
  }
  for name, def in pairs(defs) do
    loaded = {}
    SpriteRenderer.new(def, "seed")
    eq(loaded[1], SpriteRenderer.imagePath(def), name .. " def: SpriteRenderer.new loads imagePath")
  end
  check(SpriteRenderer.imagePath({}) == nil and SpriteRenderer.imagePath(nil) == nil,
    "no image: nil")
  local data = { sprites = { SPRITE_RED = defs.vanilla, SPRITE_MOD = defs.mod } }
  eq(NPC.spriteImagePath(data, { sprite = "SPRITE_MOD" }), defs.mod.image,
    "NPC.spriteImagePath resolves through data.sprites")
  check(NPC.spriteImagePath(data, { sprite = "NOPE" }) == nil, "unknown sprite: nil")
  Assets.image = realImage
end

-- ---- overworld hints (every colour mode) ---------------------------------------------
local Game = require("src.core.Game")
local OW = require("src.world.OverworldController")
do
  local maps = {}
  for i = 1, 7 do
    local conns = {}
    if i > 1 then conns.west = { map = "M" .. (i - 1), offset = 0 } end
    if i < 7 then conns.east = { map = "M" .. (i + 1), offset = 0 } end
    maps["M" .. i] = { id = "M" .. i, width = 10, height = 10, tileset = "OVERWORLD",
      connections = conns,
      objects = {
        { index = 0, sprite = "S" .. i, name = "shown" },
        { index = 1, sprite = "SHIDDEN", name = "hid", hidden = true },
      } }
  end
  local sprites = { SHIDDEN = { image = "assets/generated/sprites/hidden.png" } }
  for i = 1, 7 do sprites["S" .. i] = { image = "assets/generated/sprites/s" .. i .. ".png" } end
  local data = { maps = maps, sprites = sprites,
    tilesets = { OVERWORLD = { id = "OVERWORLD", image = "assets/generated/ts.png", tilesPerRow = 4 } } }
  local savedData, savedRenderer, savedSave = Game.data, Game.renderer, Game.save
  Game.data = data
  Game.save = { objectToggles = {}, itemsTaken = {}, defeatedTrainers = {} }
  Game.renderer = { worldViewSize = function() return 160, 144 end }
  OW._setGameForTest(Game)
  local ow = setmetatable({}, { __index = OW })
  local function decodeKeys()
    local out = {}
    for _, c in ipairs(channel("atlas_cmd").queue) do
      if c.cmd == "decode" then out[#out + 1] = c.key end
    end
    table.sort(out)
    return out
  end

  for _, mode in ipairs({ "gbc", "redpp" }) do
    reset()
    AtlasPrefetch._setDecodeLimitsForTest(64, 64, 64)
    PaletteFX.mode = mode
    ow:prefetchAtlases("M4", false)
    AtlasPrefetch.update()
    eq(table.concat(decodeKeys(), ","),
       table.concat({ "assets/generated/sprites/s1.png", "assets/generated/sprites/s7.png",
                      "assets/generated/ts.png" }, ","),
       mode .. ": next-hop maps' tileset + visible-object sheets are decoded ahead")
  end

  -- a hidden object comes back when its toggle says so
  reset()
  AtlasPrefetch._setDecodeLimitsForTest(64, 64, 64)
  PaletteFX.mode = "gbc"
  Game.save.objectToggles = { M1 = { hid = true } }
  ow:prefetchAtlases("M4", false)
  AtlasPrefetch.update()
  local keys = table.concat(decodeKeys(), ",")
  check(keys:find("hidden.png", 1, true) ~= nil, "objectVisible filter is the rebuildGhosts one")
  Game.save.objectToggles = {}

  -- every mode: a sheet whose Image is already cached is still decoded, the
  -- sprite OBJ bake (getObpImage) re-reads its pixels through imageData
  reset()
  AtlasPrefetch._setDecodeLimitsForTest(64, 64, 64)
  PaletteFX.mode = "gbc"
  Assets.image("assets/generated/sprites/s1.png")
  channel("atlas_cmd"):clear()
  ow:prefetchAtlases("M4", false)
  AtlasPrefetch.update()
  check(table.concat(decodeKeys(), ","):find("s1.png", 1, true) ~= nil,
    "gbc: a cached Image's sheet is still decoded for the OBJ bake")

  -- Image cached AND an OBJ-palette bake exists: the pixels are never read
  -- again, so no decode is queued (the tileset hint stays)
  reset()
  AtlasPrefetch._setDecodeLimitsForTest(64, 64, 64)
  PaletteFX.mode = "gbc"
  local S1 = "assets/generated/sprites/s1.png"
  SpriteRenderer.new({ image = S1 }) -- caches the sheet by its raw path
  SpriteRenderer.obpImage(S1, { {0,0,0}, {0,0,0}, {0,0,0}, {0,0,0} }, 1)
  check(SpriteRenderer.isBaked(S1), "Image and OBJ bake are held")
  channel("atlas_cmd"):clear()
  ow:prefetchAtlases("M4", false)
  AtlasPrefetch.update()
  local skipKeys = table.concat(decodeKeys(), ",")
  check(not skipKeys:find("s1.png", 1, true), "cached Image + OBJ bake: sheet not decoded")
  check(skipKeys:find("s7.png", 1, true) and skipKeys:find("ts.png", 1, true),
    "other sheets and the tileset are still decoded")
  SpriteRenderer.invalidate()
  check(not SpriteRenderer.hasObp(S1), "invalidate forgets the OBJ bakes")

  -- non-RED++: a cached tileset Image is skipped, unless an animated tile's
  -- variants still have to be built from its pixels
  do
    local TR = require("src.render.TileRenderer")
    local TS = "assets/generated/ts.png"
    local tsDef = data.tilesets.OVERWORLD
    local realHas = TR.hasImage
    TR.hasImage = function(path) return path == TS or realHas(path) end
    tsDef.animatedTiles = { { tile = 5, kind = "hshift", offsets = { 0, 1 } } }
    local function tsDecoded()
      return table.concat(decodeKeys(), ","):find("ts.png", 1, true) ~= nil
    end
    reset()
    AtlasPrefetch._setDecodeLimitsForTest(64, 64, 64)
    PaletteFX.mode = "gbc"
    ow:prefetchAtlases("M4", false)
    AtlasPrefetch.update()
    check(tsDecoded(), "cached tileset with an unbuilt animated variant: hint still queued")
    reset()
    AtlasPrefetch._setDecodeLimitsForTest(64, 64, 64)
    PaletteFX.mode = "gbc"
    TR._shiftVariantsForTest()[TS .. "#5"] = {}
    ow:prefetchAtlases("M4", false)
    AtlasPrefetch.update()
    check(not tsDecoded(), "cached tileset with everything built: hint skipped")
    TR._shiftVariantsForTest()[TS .. "#5"] = nil
    tsDef.animatedTiles = nil
    TR.hasImage = realHas
  end

  -- warp: destination first
  reset()
  AtlasPrefetch._setDecodeLimitsForTest(64, 64, 64)
  PaletteFX.mode = "gbc"
  ow:prefetchAtlases("M4", false)
  ow:prefetchAtlases("M7", true)
  AtlasPrefetch.update()
  local first
  for _, c in ipairs(channel("atlas_cmd").queue) do
    if c.cmd == "decode" then first = c.key break end
  end
  eq(first, "assets/generated/ts.png", "warp: destination's decodes jump the hint queue")
  local seenS7 = false
  for _, c in ipairs(channel("atlas_cmd").queue) do
    if c.key == "assets/generated/sprites/s7.png" then seenS7 = true end
  end
  check(seenS7, "warp: destination sprite queued")

  -- per-setMap cap on low-priority hints
  reset()
  AtlasPrefetch._setDecodeLimitsForTest(64, 64, 64)
  PaletteFX.mode = "gbc"
  for i = 1, 7 do
    for j = 2, 40 do
      table.insert(maps["M" .. i].objects, { index = j, sprite = "SX" .. i .. "_" .. j })
      sprites["SX" .. i .. "_" .. j] = { image = "assets/generated/sprites/x" .. i .. "_" .. j .. ".png" }
    end
  end
  ow:prefetchAtlases("M4", false)
  local q = AtlasPrefetch.decodePending()
  check(q <= 32, "low-priority decode hints are capped per setMap (" .. q .. ")")

  PaletteFX.mode = "redpp"
  Game.data, Game.renderer, Game.save = savedData, savedRenderer, savedSave
end

reset()
AtlasPrefetch.shutdown()
T.finish()
