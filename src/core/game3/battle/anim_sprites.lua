-- Fixed-pool battle anim particles (pret OAM sprite slots analogue).
-- No per-frame table.insert/nil churn — acquire overwrites, release clears active.

local AnimSprites = {}

AnimSprites.MAX = 128
AnimSprites.Z = {
  BEHIND = 10,
  MID = 30,
  FRONT = 50,
}

local function clear_slot(s)
  s.active = false
  s.x = 0
  s.y = 0
  s.ox = 0
  s.oy = 0
  s.z = AnimSprites.Z.MID
  s.alpha = 1
  s.hFlip = false
  s.vFlip = false
  s.visible = true
  s.tag = nil
  s.template = nil
  s.image = nil
  s.quad = nil
  s.w = 16
  s.h = 16
  s.callback = nil
  s.palSlot = 0 -- index into VM pal buffers
  s.monoTint = nil -- {r,g,b} fast path
  s.quadX = nil
  s.quadY = nil
  s._quadX = nil
  s._quadY = nil
  s._quadW = nil
  s._quadH = nil
  s._baseW = nil
  s._baseH = nil
  s._reversed = nil
  s._inited = nil
  for i = 0, 7 do
    s.data[i] = 0
  end
end

local function new_slot()
  local s = { data = {} }
  for i = 0, 7 do s.data[i] = 0 end
  clear_slot(s)
  return s
end

function AnimSprites.init()
  if AnimSprites._pool then return end
  AnimSprites._pool = {}
  for i = 1, AnimSprites.MAX do
    AnimSprites._pool[i] = new_slot()
  end
  AnimSprites._overflowLogged = false
end

function AnimSprites.reset()
  AnimSprites.init()
  for i = 1, AnimSprites.MAX do
    clear_slot(AnimSprites._pool[i])
  end
  AnimSprites._overflowLogged = false
end

--- Acquire a free slot. Returns sprite or nil if pool exhausted.
function AnimSprites.acquire(opts)
  AnimSprites.init()
  opts = opts or {}
  for i = 1, AnimSprites.MAX do
    local s = AnimSprites._pool[i]
    if not s.active then
      clear_slot(s)
      s.active = true
      s.x = opts.x or 0
      s.y = opts.y or 0
      s.z = opts.z or AnimSprites.Z.MID
      s.tag = opts.tag
      s.template = opts.template
      s.image = opts.image
      s.quad = opts.quad
      s.w = opts.w or 16
      s.h = opts.h or 16
      s.hFlip = opts.hFlip and true or false
      s.callback = opts.callback
      s.palSlot = opts.palSlot or 0
      s.monoTint = opts.monoTint
      if opts.data then
        for k, v in pairs(opts.data) do
          s.data[k] = v
        end
      end
      return s
    end
  end
  if not AnimSprites._overflowLogged then
    print("[battle.anim] sprite pool exhausted (" .. AnimSprites.MAX .. ")")
    AnimSprites._overflowLogged = true
  end
  return nil
end

function AnimSprites.release(sprite)
  if not sprite then return end
  clear_slot(sprite)
end

function AnimSprites.activeCount()
  AnimSprites.init()
  local n = 0
  for i = 1, AnimSprites.MAX do
    if AnimSprites._pool[i].active then n = n + 1 end
  end
  return n
end

function AnimSprites.forEachActive(fn)
  AnimSprites.init()
  for i = 1, AnimSprites.MAX do
    local s = AnimSprites._pool[i]
    if s.active then fn(s, i) end
  end
end

function AnimSprites.update()
  AnimSprites.init()
  for i = 1, AnimSprites.MAX do
    local s = AnimSprites._pool[i]
    if s.active and s.callback then
      local ok, err = pcall(s.callback, s)
      if not ok then
        print("[battle.anim] sprite cb: " .. tostring(err))
        AnimSprites.release(s)
      end
    end
  end
end

--- Collect active sprites sorted by z (stable by index).
function AnimSprites.sortedDrawList(out)
  out = out or {}
  for i = #out, 1, -1 do out[i] = nil end
  AnimSprites.init()
  for i = 1, AnimSprites.MAX do
    local s = AnimSprites._pool[i]
    if s.active and s.visible then
      out[#out + 1] = s
    end
  end
  table.sort(out, function(a, b)
    if a.z ~= b.z then return a.z < b.z end
    return false
  end)
  return out
end

return AnimSprites
