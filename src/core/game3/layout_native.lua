-- Native FRLG mid-grid layout handle (16px cells).

local LayoutNative = {}
LayoutNative.__index = LayoutNative

local function wrap_border(cx, cy, w, h, bw, bh)
  -- FRLG: out-of-bounds samples border tiled from (0,0).
  local bx = cx % bw
  if bx < 0 then bx = bx + bw end
  local by = cy % bh
  if by < 0 then by = by + bh end
  return bx, by
end

function LayoutNative.fromDecoded(decoded, mapId, pair)
  local self = setmetatable({
    mapId = mapId,
    pair = pair or "sevii_outdoor",
    width = decoded.width or 0,
    height = decoded.height or 0,
    trueWidth = decoded.trueWidth or decoded.width or 0,
    trueHeight = decoded.trueHeight or decoded.height or 0,
    borderWidth = decoded.borderWidth or 1,
    borderHeight = decoded.borderHeight or 1,
    borderMids = decoded.borderMids or { 0 },
    cells = decoded.cells or {},
    overrides = {}, -- [cy*1024+cx] = { mid, coll, elev }
  }, LayoutNative)
  return self
end

function LayoutNative:cellAt(cx, cy)
  local key = cy * 1024 + cx
  local ov = self.overrides[key]
  if ov then return ov end
  local tw = self.trueWidth or self.width
  local th = self.trueHeight or self.height
  if cx >= 0 and cy >= 0 and cx < tw and cy < th then
    return self.cells[cy * self.width + cx + 1]
      or { mid = 0, coll = 0xff, elev = 0 }
  end
  local bx, by = wrap_border(
    cx, cy, tw, th, self.borderWidth, self.borderHeight)
  local mid = self.borderMids[by * self.borderWidth + bx + 1] or 0
  return { mid = mid, coll = 0xff, elev = 0 }
end

function LayoutNative:midAt(cx, cy)
  return self:cellAt(cx, cy).mid
end

function LayoutNative:collAt(cx, cy)
  return self:cellAt(cx, cy).coll
end

function LayoutNative:elevAt(cx, cy)
  return self:cellAt(cx, cy).elev
end

--- Flat 1-based COLL_* array for Collision.bindMap.
function LayoutNative:collArray()
  local w = self.width
  local h = self.height
  local tw = self.trueWidth or w
  local th = self.trueHeight or h
  local n = w * h
  if n <= 0 then return nil end
  local out = {}
  for cy = 0, h - 1 do
    for cx = 0, w - 1 do
      local i = cy * w + cx + 1
      if cx < tw and cy < th then
        local ov = self.overrides[cy * 1024 + cx]
        local c = self.cells[i]
        out[i] = (ov and ov.coll) or (c and c.coll) or 0xff
      else
        out[i] = 0xff
      end
    end
  end
  return out
end

function LayoutNative:applyOverride(x, y, mid, coll, elev)
  x, y = tonumber(x) or 0, tonumber(y) or 0
  self.overrides[y * 1024 + x] = {
    mid = tonumber(mid) or 0,
    coll = coll ~= nil and coll or 0xff,
    elev = elev or 0,
  }
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then
    FieldView._nativeDirty = true
  end
end

local function markDirty()
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then
    FieldView._nativeDirty = true
  end
end

-- pokeemerald/src/battle_pyramid.c:1523
function LayoutNative:stamp(src, ox, oy)
  if type(src) ~= "table" or type(src.cells) ~= "table" then return 0 end
  ox, oy = tonumber(ox) or 0, tonumber(oy) or 0
  local sw = src.trueWidth or src.width or 0
  local sh = src.trueHeight or src.height or 0
  local n = 0
  for y = 0, sh - 1 do
    for x = 0, sw - 1 do
      local c = src.cells[y * src.width + x + 1]
      if c then
        self.overrides[(oy + y) * 1024 + ox + x] = {
          mid = c.mid or 0, coll = c.coll ~= nil and c.coll or 0xff, elev = c.elev or 0,
        }
        n = n + 1
      end
    end
  end
  markDirty()
  return n
end

-- pokeemerald/src/fieldmap.c:357
function LayoutNative:setMetatiles(rows)
  local n = 0
  for _, r in ipairs(rows or {}) do
    local x, y = tonumber(r.x) or 0, tonumber(r.y) or 0
    local cur = self:cellAt(x, y)
    self.overrides[y * 1024 + x] = {
      mid = tonumber(r.mid) or cur.mid or 0,
      coll = r.coll ~= nil and r.coll or cur.coll,
      elev = r.elev ~= nil and r.elev or cur.elev or 0,
    }
    n = n + 1
  end
  if n > 0 then markDirty() end
  return n
end

function LayoutNative:clearOverrides()
  self.overrides = {}
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then
    FieldView._nativeDirty = true
  end
end

return LayoutNative
