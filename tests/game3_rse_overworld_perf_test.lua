package.path = "./?.lua;./?/init.lua;" .. package.path

-- R/S/E overworld per-frame work: shader-send dedupe, scroll-only tiled
-- weather batches, in-place effect list compaction, pooled actor records with
-- off-screen culling, and the muddy-slope metatile write skip.

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

-- ---------------------------------------------------------------- love stand-ins
local color = { 1, 1, 1, 1 }
local batchesMade, batchDraws = 0, {}
love.graphics.setColor = function(r, g, b, a) color = { r, g, b, a or 1 } end
love.graphics.getColor = function() return color[1], color[2], color[3], color[4] end
-- quads are userdata in LOVE; drawTiled tells a single quad from a part list by type
love.graphics.newQuad = function() return newproxy() end
love.graphics.newSpriteBatch = function(image, size)
  batchesMade = batchesMade + 1
  local b = { image = image, size = size, sprites = {}, clears = 0, isBatch = true }
  function b:add(q, x, y) self.sprites[#self.sprites + 1] = { q = q, x = x, y = y } end
  function b:clear() self.sprites = {}; self.clears = self.clears + 1 end
  function b:setColor(r, g, bl, a) self.col = { r, g, bl, a } end
  return b
end
love.graphics.draw = function(obj, x, y)
  if type(obj) == "table" and obj.isBatch then
    batchDraws[#batchDraws + 1] = { batch = obj, x = x, y = y }
  end
end

local R = require("src.core.game3.field_weather_rse")

-- ---------------------------------------------------------------- drawTiled
do
  local sheet = { image = {}, quads = {}, cols = 8, w = 64, h = 64 * 4 }
  local cw, ch = 240, 160
  local function tiled(baseX, baseY)
    batchDraws = {}
    R._drawTiled(sheet, 2, baseX, baseY, 0, 0, cw, ch)
    return batchDraws[1]
  end

  love.graphics.setColor(1, 1, 1, 1)
  local d = tiled(10, 20)
  check(d ~= nil, "drawTiled draws one batch")
  local sx, sy = d.x, d.y
  eq(sx, (10 % 64) - 128, "draw offset sx is the old first column (-118)")
  eq(sy, (20 % 64) - 128, "draw offset sy is the old first row (-108)")
  local nx, ny = math.floor((cw - sx) / 64) + 1, math.floor((ch - sy) / 64) + 1
  eq(#d.batch.sprites, nx * ny, "batch holds one sprite per tile")
  local ok = true
  for j = 0, ny - 1 do
    for i = 0, nx - 1 do
      local s = d.batch.sprites[j * nx + i + 1]
      -- batch position + draw offset == the position the old code added at
      if not (s and s.x == i * 64 and s.y == j * 64
          and s.x + sx == sx + i * 64 and s.y + sy == sy + j * 64) then ok = false end
    end
  end
  check(ok, "tiles laid out from 0,0 in row-major order, 64px apart")
  eq(d.batch.sprites[1].q, d.batch.sprites[2].q, "tiles share one quad")
  local made, clears = batchesMade, d.batch.clears

  -- scrolling only: offset moves, batch untouched
  local d2 = tiled(11, 20)
  check(d2.batch == d.batch, "same batch object after a scroll step")
  eq(batchesMade, made, "no new batch on scroll")
  eq(d2.batch.clears, clears, "batch not rebuilt on scroll")
  eq(d2.x, sx + 1, "draw offset follows the scroll")
  tiled(12, 21)
  eq(d.batch.clears, clears, "still not rebuilt after more scrolling")

  -- frame change rebuilds
  batchDraws = {}
  R._drawTiled(sheet, 3, 12, 21, 0, 0, cw, ch)
  eq(d.batch.clears, clears + 1, "frame change rebuilds")
  -- colour change rebuilds (tint bucket)
  love.graphics.setColor(1, 1, 1, 0.5)
  batchDraws = {}
  R._drawTiled(sheet, 3, 12, 21, 0, 0, cw, ch)
  local tint = batchDraws[1].batch
  eq(tint.clears, 1, "tinted batch built once")
  eq(tint.col[4], 0.5, "tinted batch carries the colour")
  batchDraws = {}
  R._drawTiled(sheet, 3, 13, 21, 0, 0, cw, ch)
  eq(tint.clears, 1, "tint unchanged: no rebuild")
  love.graphics.setColor(1, 1, 1, 0.25)
  batchDraws = {}
  R._drawTiled(sheet, 3, 13, 21, 0, 0, cw, ch)
  eq(tint.clears, 2, "colour change rebuilds")
  love.graphics.setColor(1, 1, 1, 1)
  -- tile count change rebuilds (larger canvas)
  local before = d.batch.clears
  batchDraws = {}
  R._drawTiled(sheet, 3, 12, 21, 0, 0, cw + 128, ch)
  check(batchDraws[1].batch.clears >= 1 and batchDraws[1].batch ~= d.batch or batchDraws[1].batch.clears == before + 1,
    "tile count change rebuilds")
  eq(#batchDraws[1].batch.sprites, (math.floor((cw + 128 - batchDraws[1].x) / 64) + 1) * ny,
    "wider view holds more columns")
end

-- ---------------------------------------------------------------- send dedupe
do
  local sends = {}
  local function newShader()
    local sh = { sent = {} }
    function sh:send(name, v)
      sends[#sends + 1] = name
      self.sent[name] = v
    end
    return sh
  end
  local S = R.state
  local sh = newShader()
  S.colorMapIndex = 3
  R._colorMapUniforms(sh, 0)
  local n1 = #sends
  check(n1 == 3, "first call sends useMask, mode and row (" .. n1 .. ")")
  R._colorMapUniforms(sh, 0)
  R._colorMapUniforms(sh, 0)
  eq(#sends, n1, "unchanged values are not resent")
  S.colorMapIndex = 4
  R._colorMapUniforms(sh, 0)
  eq(#sends, n1 + 1, "only the changed row is resent")
  eq(sh.sent.row, 3, "row follows colorMapIndex")
  S.colorMapIndex = -2
  R._colorMapUniforms(sh, 0)
  eq(sh.sent.mode, 2, "negative index switches to dither mode")
  eq(sh.sent.dtable, 1, "dither table sent")
  S.colorMapIndex = 0
  local n2 = #sends
  R._colorMapUniforms(sh, 0)
  eq(sh.sent.mode, 0, "no map sends mode 0")
  eq(#sends, n2 + 1, "only mode resent")
  -- a second shader keeps its own record
  local sh2 = newShader()
  R._colorMapUniforms(sh2, 0)
  eq(sh2.sent.mode, 0, "separate shader gets its own sends")
  eq(sh2.sent.useMask, 0, "separate shader gets useMask")
  S.colorMapIndex = 0
end

-- ---------------------------------------------------------------- effect list / actors
local objects = { _order = {}, _byId = {}, stepObjects = function() end,
  fadeAlpha = function() return 1 end }
package.loaded["src.core.game3.objects"] = objects
local img = {}
local sheets = { dis = { image = img, fw = 16, fh = 16, quads = { [0] = { id = "q" } } } }
package.loaded["src.core.game3.field_effects"] = {
  loadSheet = function(name) return sheets[name] end,
  manifestObject = function(name) return sheets[name] end,
}
package.loaded["src.core.game3.ow_sprites"] = { get = function() return nil end }
local Fx = require("src.core.game3.field_effects_rse")

do
  local function entry(tag, extra)
    local e = { tag = tag, timer = 0, delay = 100, a = {} }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
  end
  local function finishing(tag, extra)
    local e = entry(tag, extra)
    e.delay = nil
    e.onStep = function() return true end
    return e
  end
  local function tags(list)
    local t = {}
    for i, e in ipairs(list) do t[i] = e.tag end
    return table.concat(t, ",")
  end

  Fx._list = {}
  local a, b, c, d = entry("a"), finishing("b"), entry("c"), finishing("d")
  Fx._list = { a, b, c, d }
  local list = Fx._list
  Fx.step()
  eq(tags(Fx._list), "a,c", "finished entries removed, order kept")
  eq(#Fx._list, 2, "no stale tail entries")
  check(rawget(Fx._list, 3) == nil and rawget(Fx._list, 4) == nil, "tail slots cleared")
  check(Fx._list == list, "list compacted in place")
  eq(a.timer, 1, "kept entry stepped once")
  eq(c.timer, 1, "later kept entry stepped once")

  -- an effect spawned by onDone is stepped this frame and kept
  local spawned = entry("spawned")
  local done = finishing("done", { onDone = function() Fx._list[#Fx._list + 1] = spawned end })
  Fx._list = { entry("x"), done, entry("y") }
  Fx.step()
  eq(tags(Fx._list), "x,y,spawned", "spawned entry appended and kept")
  eq(spawned.timer, 1, "spawned entry stepped on its spawn frame")

  -- onDone spawning when the finished entry is last
  local spawned2 = entry("spawned2")
  Fx._list = { entry("p"), finishing("last", { onDone = function() Fx._list[#Fx._list + 1] = spawned2 end }) }
  Fx.step()
  eq(tags(Fx._list), "p,spawned2", "spawn from the last entry is kept")
  eq(spawned2.timer, 1, "and stepped")

  -- everything finishes
  Fx._list = { finishing("1"), finishing("2") }
  Fx.step()
  eq(#Fx._list, 0, "all finished leaves an empty list")
  Fx._list = {}
end

do
  local function obj(id, px, py, extra)
    local eo = { localId = id, visible = true, px = px, py = py, elevation = 3,
      disguise = { sheet = "dis", a = { frame = 0 } } }
    for k, v in pairs(extra or {}) do eo[k] = v end
    return eo
  end
  local near, far, nopos = obj(1, 100, 80), obj(2, 5000, 80), obj(3, nil, nil)
  objects._order = { 1, 2, 3 }
  objects._byId = { [1] = near, [2] = far, [3] = nopos }
  Fx._list = {}

  local function find(actors, eo)
    for _, a in ipairs(actors) do if a.fxObject == eo then return a end end
  end

  local f1 = {}
  Fx.collectActors(f1)
  check(find(f1, near) and find(f1, far) and find(f1, nopos), "no camera: nothing culled")
  eq(#f1, 3, "no camera: three records")

  local f2 = {}
  Fx.collectActors(f2, 0, 0)
  check(find(f2, near) ~= nil, "on-screen object kept with a camera")
  check(find(f2, far) == nil, "far off-screen object culled with a camera")
  check(find(f2, nopos) ~= nil, "object without px/py never culled")
  local f2b = {}
  Fx.collectActors(f2b, 4990, 0)
  check(find(f2b, far) ~= nil and find(f2b, near) == nil, "culling follows the camera")
  local rec = find(f2, near)

  -- reuse across frames: same table, fields refreshed, stale state cleared
  rec.priority, rec.subpriority, rec.fixedPriority = 1, 99, true
  near.px = 120
  local f3 = {}
  Fx.collectActors(f3, 0, 0)
  local rec3 = find(f3, near)
  check(rec3 == rec, "record reused across frames")
  eq(rec3.x, 120 + 8 - 8, "position refreshed on reuse")
  check(rec3.priority == nil and rec3.subpriority == nil and rec3.fixedPriority == nil,
    "draw-order state reset on reuse")
  eq(rec3.disguiseObject, near, "disguise link set")
  eq(rec3.kind, "field_effect_rse", "kind kept")
  check(find(f3, nopos) == find(f2, nopos), "per-object record identity")
  check(find(f3, near).draw == find(f3, nopos).draw, "shared draw function")

  -- effect entries are pooled too
  local e = { name = "fx", layer = "actor", x = 10, y = 20, sortBias = 0.5, sheet = sheets.dis, a = { frame = 0 } }
  Fx._list = { e }
  objects._order, objects._byId = {}, {}
  local g1, g2 = {}, {}
  Fx.collectActors(g1, 0, 0)
  Fx.collectActors(g2, 0, 0)
  check(#g1 == 1 and g1[1] == g2[1], "effect record reused")
  eq(g1[1].sortY, 20 - 8 + 0.5, "effect sortY")
  Fx._list = {}
end

-- ---------------------------------------------------------------- muddy slope
do
  local ids = {
    A = { METATILE_General_MuddySlope_Frame0 = 10, METATILE_General_MuddySlope_Frame1 = 11,
      METATILE_General_MuddySlope_Frame2 = 12, METATILE_General_MuddySlope_Frame3 = 13 },
    B = { METATILE_General_MuddySlope_Frame0 = 110, METATILE_General_MuddySlope_Frame1 = 111,
      METATILE_General_MuddySlope_Frame2 = 112, METATILE_General_MuddySlope_Frame3 = 113 },
  }
  local function consts(which)
    return { require = function(_, _, name) return ids[which][name] end }
  end
  local cA, cB = consts("A"), consts("B")
  local active = cA
  local Collision = require("src.core.game3.collision")
  local Steps = require("src.core.game3.step_callbacks_rse")
  package.loaded["src.core.game3.constants"] = { active = function() return active end }

  local writes = {}
  local Field = { _session = { map = "M" }, metatileOverrides = {} }
  function Field.setMetatile(x, y, id, imp)
    writes[#writes + 1] = { x = x, y = y, id = id }
    Field.metatileOverrides.M = Field.metatileOverrides.M or {}
    Field.metatileOverrides.M[y * 1024 + x] = { x = x, y = y, metatile = id, impassable = imp }
  end
  package.loaded["src.core.game3.field"] = Field
  local player = { cellX = 1, cellY = 1, moving = false }
  package.loaded["src.core.game3.player"] = player
  package.loaded["src.core.game3.map"] = { current = "M" }

  Collision.isMuddySlope = function() return true end
  Collision.behavior = function() return 0 end

  Steps.muddySlopeTask({})            -- binds the map
  player.cellX = 2
  Steps.muddySlopeTask({})            -- slot created, time 32 -> 31 (Frame1)
  eq(#writes, 1, "first frame writes the cell")
  eq(writes[1].id, 11, "first frame is Frame1 of Ruby/Sapphire constants")
  for _ = 1, 7 do Steps.muddySlopeTask({}) end   -- times 30..24: same frame
  eq(#writes, 1, "no setMetatile while the cell already holds the frame")
  Steps.muddySlopeTask({})            -- time 23: next frame
  eq(#writes, 2, "setMetatile when the frame changes")
  eq(writes[2].id, 12, "next frame is Frame2")

  -- an impassable override of the same metatile is rewritten
  Field.metatileOverrides.M[1 * 1024 + 2].impassable = true
  for _ = 1, 3 do Steps.muddySlopeTask({}) end
  eq(#writes, 3, "impassable override of the same id is rewritten once")

  -- another game: ids differ, the cache must not serve the old ones
  active = cB
  for _ = 1, 4 do Steps.muddySlopeTask({}) end   -- run to the next frame boundary
  local last = writes[#writes]
  check(last.id >= 110 and last.id <= 113, "switched constants resolve their own ids (got " .. tostring(last.id) .. ")")
  active = cA
  local before = #writes
  for _ = 1, 8 do Steps.muddySlopeTask({}) end
  check(#writes > before and writes[#writes].id < 100, "switching back resolves the first game's ids")
end

T.finish()
