-- Visual-task registry + fixed task pool (pret gTasks for battle anims).
-- Default stub finishes in 1 frame so unknown createvisualtask still ends scripts.

local AnimSprites = require("src.core.game3.battle.anim_sprites")

local AnimTasks = {}

AnimTasks.MAX = 48

local function clear_task(t)
  t.active = false
  t.func = nil
  t.name = nil
  t.priority = 0
  for i = 0, 15 do
    t.data[i] = 0
  end
end

function AnimTasks.init()
  if AnimTasks._pool then return end
  AnimTasks._pool = {}
  for i = 1, AnimTasks.MAX do
    local t = { data = {} }
    for j = 0, 15 do t.data[j] = 0 end
    clear_task(t)
    AnimTasks._pool[i] = t
  end
end

function AnimTasks.reset()
  AnimTasks.init()
  for i = 1, AnimTasks.MAX do
    clear_task(AnimTasks._pool[i])
  end
end

function AnimTasks.activeCount()
  AnimTasks.init()
  local n = 0
  for i = 1, AnimTasks.MAX do
    if AnimTasks._pool[i].active then n = n + 1 end
  end
  return n
end

local function destroy_task(t)
  clear_task(t)
end

--- Stub: lasts 1 frame then finishes (keeps waitforvisualfinish moving).
local function stub_task(t)
  t.data[15] = (t.data[15] or 0) + 1
  if t.data[15] >= 1 then
    destroy_task(t)
  end
end

-- Registry: name → function(task, vm)
AnimTasks.REGISTRY = {}

--- AnimTask_ShakeMon: args target, xShake, yShake, duration, amplitude-ish
function AnimTasks.ShakeMon(t, vm)
  local side = vm:resolveBattlerSide(t.data[0])
  local Anim = require("src.core.game3.battle.anim")
  local p = Anim.present(side)
  if not p then
    destroy_task(t)
    return
  end
  local xAmp = math.max(4, tonumber(t.data[1]) or 3)
  local yAmp = tonumber(t.data[2]) or 0
  local dur = math.max(10, tonumber(t.data[3]) or 6)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local phase = frame % 4
  local sx = (phase == 0 or phase == 3) and xAmp or -xAmp
  local sy = (phase == 0 or phase == 3) and yAmp or -yAmp
  if vm.isReversed then sx = -sx end
  p.ox = sx
  p.oy = sy
  p.flash = frame
  if frame >= dur then
    p.ox = 0
    p.oy = 0
    p.flash = 0
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.ShakeMon = AnimTasks.ShakeMon
AnimTasks.REGISTRY.AnimTask_ShakeMon = AnimTasks.ShakeMon
AnimTasks.REGISTRY.ShakeMon2 = AnimTasks.ShakeMon
AnimTasks.REGISTRY.AnimTask_ShakeMon2 = AnimTasks.ShakeMon
AnimTasks.REGISTRY.ShakeMonInPlace = AnimTasks.ShakeMon
AnimTasks.REGISTRY.AnimTask_ShakeMonInPlace = AnimTasks.ShakeMon

--- Horizontal lunge of attacker (visual task style used by gHorizontalLungeSpriteTemplate CB).
function AnimTasks.HorizontalLunge(t, vm)
  local Anim = require("src.core.game3.battle.anim")
  local side = vm:attackerSide()
  local p = Anim.present(side)
  if not p then
    destroy_task(t)
    return
  end
  local speed = math.max(6, tonumber(t.data[0]) or 4)
  local dur = math.max(6, tonumber(t.data[1]) or 4)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local dir = vm.isReversed and -1 or 1
  if frame < dur then
    p.ox = dir * speed * 3
  elseif frame < dur * 2 then
    p.ox = 0
    destroy_task(t)
  else
    p.ox = 0
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.HorizontalLunge = AnimTasks.HorizontalLunge

--- Sound tasks: finish on a short timer (cry audio optional later).
function AnimTasks.SoundTaskWait(t, _vm)
  t.data[14] = (t.data[14] or 0) + 1
  if t.data[14] >= 18 then
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.SoundTask_PlayDoubleCry = AnimTasks.SoundTaskWait
AnimTasks.REGISTRY.SoundTask_WaitForCry = AnimTasks.SoundTaskWait
AnimTasks.REGISTRY.PlayDoubleCry = AnimTasks.SoundTaskWait

--- BlendColorCycle stub: nudge pal toward a tint for a few frames then restore.
function AnimTasks.BlendColorCycle(t, vm)
  local frame = t.data[14] or 0
  t.data[14] = frame + 1
  local pal = vm.pals[0]
  if pal and frame == 0 then
    t.data[10] = 1 -- marked
    for i = 1, 15 do
      local c = pal[i]
      if c then
        c[1] = math.min(1, (c[1] or 0) + 0.15)
      end
    end
  end
  if frame >= 8 then
    -- restore rough defaults
    if pal then
      pal[1] = { 1, 1, 1, 1 }
      pal[2] = { 1, 0.9, 0.2, 1 }
      pal[3] = { 1, 0.4, 0.1, 1 }
    end
    destroy_task(t)
  end
end

AnimTasks.REGISTRY.BlendColorCycle = AnimTasks.BlendColorCycle
AnimTasks.REGISTRY.AnimTask_BlendColorCycle = AnimTasks.BlendColorCycle
AnimTasks.REGISTRY.AnimTask_BlendColorCycleByTag = AnimTasks.BlendColorCycle
AnimTasks.REGISTRY.AnimTask_BlendColorCycleExclude = AnimTasks.BlendColorCycle

function AnimTasks.spawn(name, priority, args, vm)
  AnimTasks.init()
  name = tostring(name or "stub")
  -- Strip g prefix / AnimTask_ variants for lookup
  local key = name
  key = key:gsub("^g", "")
  local fn = AnimTasks.REGISTRY[name]
    or AnimTasks.REGISTRY[key]
    or AnimTasks.REGISTRY["AnimTask_" .. key]
  if not fn then
    fn = stub_task
  end
  for i = 1, AnimTasks.MAX do
    local t = AnimTasks._pool[i]
    if not t.active then
      clear_task(t)
      t.active = true
      t.name = name
      t.priority = tonumber(priority) or 2
      t.func = fn
      if type(args) == "table" then
        for ai, av in ipairs(args) do
          local v = av
          if type(v) == "string" then
            -- leave string battler tokens in data via parallel map
            t.data[ai - 1] = v
          else
            t.data[ai - 1] = tonumber(v) or 0
          end
        end
        -- Also store string battler ids in high slots if present
        for ai, av in ipairs(args) do
          if type(av) == "string" then
            t.data[ai - 1] = av
          end
        end
      end
      return t
    end
  end
  print("[battle.anim] task pool exhausted")
  return nil
end

function AnimTasks.update(vm)
  AnimTasks.init()
  for i = 1, AnimTasks.MAX do
    local t = AnimTasks._pool[i]
    if t.active and t.func then
      local ok, err = pcall(t.func, t, vm)
      if not ok then
        print("[battle.anim] task " .. tostring(t.name) .. ": " .. tostring(err))
        destroy_task(t)
      end
    end
  end
end

--- Destroy helper for sprite callbacks / tasks that finish themselves.
AnimTasks.destroy = destroy_task

return AnimTasks
