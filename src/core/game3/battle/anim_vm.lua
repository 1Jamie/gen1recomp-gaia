-- Pret-shaped battle anim script VM over portable IR (not live ROM pointers).
-- Opcodes mirror battle_anim_script.inc; createsprite/createvisualtask use named IDs.

local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimTasks = require("src.core.game3.battle.anim_tasks")

local AnimVm = {}

AnimVm.Z = {
  BG = 0,
  BEHIND = 10,
  ENEMY = 20,
  MID = 30,
  PLAYER = 40,
  FRONT = 50,
  HEALTHBOX = 60,
  UI = 70,
}

local ARG_COUNT = 8

-- pret SOUND_PAN_* (include/constants/battle_anim.h)
local SOUND_PAN_ATTACKER = -64
local SOUND_PAN_TARGET = 63

--- Sound tasks for loopsewithpan / waitplaysewithpan (battle_anim.c).
local soundTasks = {}

local function clear_sound_tasks()
  soundTasks = {}
end

local function resolve_pan_token(pan)
  if pan == nil then return 0 end
  if type(pan) == "number" then return pan end
  local s = tostring(pan)
  if s == "SOUND_PAN_TARGET" or s == "TARGET" then return SOUND_PAN_TARGET end
  if s == "SOUND_PAN_ATTACKER" or s == "ATTACKER" then return SOUND_PAN_ATTACKER end
  return tonumber(s) or 0
end

--- pret BattleAnimAdjustPanning (simplified for singles).
local function adjust_panning(vm, pan)
  pan = resolve_pan_token(pan)
  local atk = vm and vm._attackerSide or "player"
  local tgt = vm and vm._targetSide or "enemy"
  if atk == "player" then
    if tgt == "player" then
      if pan == SOUND_PAN_TARGET then
        pan = SOUND_PAN_ATTACKER
      elseif pan ~= SOUND_PAN_ATTACKER then
        pan = -pan
      end
    end
  elseif tgt == "enemy" then
    if pan == SOUND_PAN_ATTACKER then
      pan = SOUND_PAN_TARGET
    end
  else
    pan = -pan
  end
  if pan > SOUND_PAN_TARGET then pan = SOUND_PAN_TARGET end
  if pan < SOUND_PAN_ATTACKER then pan = SOUND_PAN_ATTACKER end
  return pan
end

local function play_se_pan(vm, se, pan)
  local Audio = require("src.core.game3.audio")
  if se then Audio.playSe(se, { pan = adjust_panning(vm, pan) }) end
end

--- pret Task_LoopAndPlaySE: first play is immediate, then every `wait` frames.
local function spawn_loop_se(vm, se, pan, wait, plays)
  wait = math.max(1, tonumber(wait) or 10)
  plays = math.max(1, tonumber(plays) or 1)
  play_se_pan(vm, se, pan)
  plays = plays - 1
  if plays > 0 then
    soundTasks[#soundTasks + 1] = {
      kind = "loop",
      se = se,
      pan = pan,
      wait = wait,
      plays = plays,
      counter = 0,
    }
  end
end

local function spawn_wait_se(vm, se, pan, wait)
  wait = math.max(0, tonumber(wait) or 0)
  if wait <= 0 then
    play_se_pan(vm, se, pan)
    return
  end
  soundTasks[#soundTasks + 1] = {
    kind = "wait",
    se = se,
    pan = pan,
    wait = wait,
    counter = 0,
  }
end

local function tick_sound_tasks(vm)
  if #soundTasks == 0 then return end
  local alive = {}
  for _, t in ipairs(soundTasks) do
    t.counter = (t.counter or 0) + 1
    if t.counter >= (t.wait or 0) then
      play_se_pan(vm, t.se, t.pan)
      if t.kind == "loop" then
        t.plays = (t.plays or 1) - 1
        t.counter = 0
        if t.plays > 0 then
          alive[#alive + 1] = t
        end
      end
      -- wait: one-shot, drop
    else
      alive[#alive + 1] = t
    end
  end
  soundTasks = alive
end

local function default_pal()
  -- 16 RGB555-ish floats as RGBA 0..1; idx0 transparent
  local p = {}
  p[0] = { 0, 0, 0, 0 }
  for i = 1, 15 do
    local g = i / 15
    p[i] = { g, g, g, 1 }
  end
  -- IMPACT-ish: white/yellow hit
  p[1] = { 1, 1, 1, 1 }
  p[2] = { 1, 0.9, 0.2, 1 }
  p[3] = { 1, 0.4, 0.1, 1 }
  return p
end

function AnimVm.new()
  local vm = {
    active = false,
    isReversed = false,
    _attackerSide = "player",
    _targetSide = "enemy",
    pc = 1,
    script = nil,
    callStack = {},
    args = {},
    framesToWait = 0,
    waitingVisual = false,
    headless = false,
    pals = { [0] = default_pal() },
    loadedTags = {},
    visualTaskCount = 0,
    _drawList = {},
    _onEnd = nil,
    _pack = nil,
    _shader = nil,
  }
  for i = 0, ARG_COUNT - 1 do vm.args[i] = 0 end
  return setmetatable(vm, { __index = AnimVm })
end

function AnimVm:attackerSide()
  return self._attackerSide
end

function AnimVm:resolveBattlerSide(token)
  if token == nil then return self._targetSide end
  if type(token) == "number" then
    -- pret ANIM_ATTACKER=0 ANIM_TARGET=1 style
    if token == 0 then return self._attackerSide end
    return self._targetSide
  end
  local s = tostring(token):lower()
  if s == "attacker" or s == "anim_attacker" or s == "0" then
    return self._attackerSide
  end
  if s == "target" or s == "anim_target" or s == "1" then
    return self._targetSide
  end
  if s == "player" or s == "enemy" then return s end
  return self._targetSide
end

function AnimVm:x(v)
  v = tonumber(v) or 0
  if self.isReversed then return -v end
  return v
end

function AnimVm:battlerCenter(side)
  local Anim = require("src.core.game3.battle.anim")
  return Anim.battlerCenter(side)
end

function AnimVm:setPack(pack)
  self._pack = pack
end

function AnimVm:idle()
  return not self.active
end

function AnimVm:busy()
  return self.active == true
end

function AnimVm:reset()
  self.active = false
  self.pc = 1
  self.script = nil
  self.callStack = {}
  self.framesToWait = 0
  self.waitingVisual = false
  self.loadedTags = {}
  self._onEnd = nil
  for i = 0, ARG_COUNT - 1 do self.args[i] = 0 end
  AnimSprites.reset()
  AnimTasks.reset()
end

local function finish(self)
  self.active = false
  self.waitingVisual = false
  self.framesToWait = 0
  local cb = self._onEnd
  self._onEnd = nil
  clear_sound_tasks()
  AnimSprites.reset()
  AnimTasks.reset()
  if cb then pcall(cb) end
end

function AnimVm:launch(script, opts)
  opts = opts or {}
  if self.headless or opts.headless then
    -- Instant-complete for tests
    if opts.onEnd then pcall(opts.onEnd) end
    return true
  end
  if type(script) ~= "table" or #script == 0 then
    if opts.onEnd then pcall(opts.onEnd) end
    return false
  end
  self:reset()
  self.active = true
  self.script = script
  self.pc = 1
  self.isReversed = opts.isReversed and true or false
  self._attackerSide = opts.attackerSide or (self.isReversed and "enemy" or "player")
  self._targetSide = opts.targetSide or (self.isReversed and "player" or "enemy")
  self._onEnd = opts.onEnd
  self.framesToWait = 0
  self.waitingVisual = false
  self._visualWaitFrames = 0
  return true
end

local function z_for_priority(subpri, isTarget)
  subpri = tonumber(subpri) or 2
  if subpri <= 1 then return AnimVm.Z.BEHIND end
  if subpri >= 4 then return AnimVm.Z.FRONT end
  return AnimVm.Z.MID
end

local function hit_splat_callback(sprite)
  -- legacy name — route through AnimCallbacks
  local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
  return AnimCallbacks.HitSplatBasic(sprite)
end

local function make_placeholder_image()
  return nil -- never invent FX art; missing tags draw nothing until extract
end

function AnimVm:ensureShader()
  return nil
end

function AnimVm:uploadPal(_slot)
  return false
end

--- Sheets are often taller/wider than one OAM cell (e.g. NOISE_LINE 32x128).
-- Always sample a bw×bh cell; never stretch the full sheet into the sprite box.
local function sprite_source_quad(s, bw, bh)
  local qx = s.quadX or 0
  local qy = s.quadY or 0
  if s.quad and s._quadX == qx and s._quadY == qy and s._quadW == bw and s._quadH == bh then
    return s.quad
  end
  if not (s.image and s.image.getDimensions) then return nil end
  local iw, ih = s.image:getDimensions()
  -- Single-cell image: no clip needed
  if iw == bw and ih == bh and qx == 0 and qy == 0 then
    s.quad = nil
    return nil
  end
  local ok, q = pcall(love.graphics.newQuad, qx, qy, bw, bh, iw, ih)
  if not ok or not q then return nil end
  s.quad = q
  s._quadX, s._quadY, s._quadW, s._quadH = qx, qy, bw, bh
  return q
end

function AnimVm:draw()
  if not (love and love.graphics) then return end
  local list = AnimSprites.sortedDrawList(self._drawList)
  for _, s in ipairs(list) do
    if s.image then
      local x = s.x + (s.ox or 0)
      local y = s.y + (s.oy or 0)
      local a = s.alpha or 1
      love.graphics.setColor(1, 1, 1, a)
      local sx = s.hFlip and -1 or 1
      local sy = s.vFlip and -1 or 1
      local bw = s._baseW or s.w or 32
      local bh = s._baseH or s.h or 32
      local dw = s.w or bw
      local dh = s.h or bh
      local q = sprite_source_quad(s, bw, bh)
      if q then
        love.graphics.draw(s.image, q, x, y, 0, sx * (dw / bw), sy * (dh / bh), bw / 2, bh / 2)
      else
        love.graphics.draw(s.image, x, y, 0, sx * (dw / bw), sy * (dh / bh), bw / 2, bh / 2)
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function tag_image(vm, tag)
  tag = tostring(tag or ""):upper():gsub("^ANIM_TAG_", "")
  local pack = vm._pack
  if pack and pack.tags and pack.tags[tag] and pack.tags[tag].image then
    return pack.tags[tag].image, pack.tags[tag]
  end
  return nil, pack and pack.tags and pack.tags[tag]
end

local function run_createsprite(vm, op)
  local AnimTemplates = require("src.core.game3.battle.anim_templates")
  local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
  local AnimTasks = require("src.core.game3.battle.anim_tasks")

  local template = tostring(op.template or "")
  local info = AnimTemplates.get(template)
  local args = op.args or {}
  local cbName = op.callback or (info and info.callback)
  local noGfx = op.noGfx or (info and info.noGfx)

  -- Invisible helper templates → visual tasks (pret sprite CB moves battler)
  if noGfx or cbName == "HorizontalLunge" or cbName == "VerticalDip"
      or cbName == "SlideMonToOffset" or cbName == "SlideMonToOriginalPos" then
    local taskName = cbName or "HorizontalLunge"
    if taskName == "HorizontalLunge" then
      AnimTasks.spawn("HorizontalLunge", 2, { args[1] or 4, args[2] or 4 }, vm)
    elseif taskName == "SlideMonToOffset" or taskName == "SlideMonToOriginalPos" then
      -- Approximate with brief shake/lunge until full slide port
      AnimTasks.spawn("HorizontalLunge", 2, { 4, 4 }, vm)
    else
      AnimTasks.spawn(taskName, 2, args, vm)
    end
    return
  end

  local tag = op.tag or (info and info.tag) or "IMPACT"
  local img, tagInfo = tag_image(vm, tag)
  if not img then
    -- No extracted sheet yet — skip particle (do not invent circles)
    return
  end

  -- Anchor: HitSplat args[3] is ANIM_TARGET/ATTACKER; Roar uses attacker
  local anchorSide = vm:resolveBattlerSide(op.animBattler or "attacker")
  if cbName == "HitSplatBasic" then
    local which = args[3]
    if which == "target" or which == 1 then
      anchorSide = vm:resolveBattlerSide("target")
    elseif which == "attacker" or which == 0 then
      anchorSide = vm:resolveBattlerSide("attacker")
    else
      for _, a in ipairs(args) do
        if type(a) == "string" and a:lower():find("target") then
          anchorSide = vm:resolveBattlerSide("target")
        end
      end
    end
  elseif cbName == "RoarNoiseLine" then
    anchorSide = vm:attackerSide()
  end

  local cx, cy = vm:battlerCenter(anchorSide)
  local ox = vm:x(tonumber(args[1]) or 0)
  local oy = tonumber(args[2]) or 0
  local bw = op.w or (info and info.w) or 32
  local bh = op.h or (info and info.h) or 32
  -- noise_line sheet is 32x128; each frame is 32x32
  if tag == "NOISE_LINE" then
    bw, bh = 32, 32
  end

  local spr = AnimSprites.acquire({
    x = cx + ox,
    y = cy + oy,
    z = z_for_priority(op.subpriority or 2),
    image = img,
    w = bw,
    h = bh,
    hFlip = false,
    template = template,
    tag = tag,
    callback = AnimCallbacks.get(cbName),
    palSlot = 0,
  })
  if spr then
    spr._baseW = bw
    spr._baseH = bh
    spr._reversed = vm.isReversed
    spr.data[0] = 0
    spr.data[1] = 0
    spr.data[2] = tonumber(args[3]) or 0 -- roar direction
    if cbName == "RoarNoiseLine" and vm.isReversed then
      spr._reversed = true
    end
  end
end

local function run_op(vm, op)
  if type(op) ~= "table" then return "ok" end
  local code = op.op or op[1]
  if code == "loadspritegfx" then
    vm.loadedTags[tostring(op.tag or "")] = true
    return "ok"
  elseif code == "unloadspritegfx" then
    vm.loadedTags[tostring(op.tag or "")] = nil
    return "ok"
  elseif code == "createsprite" then
    run_createsprite(vm, op)
    return "ok"
  elseif code == "createvisualtask" then
    local name = op.task or op.name or "stub"
    AnimTasks.spawn(name, op.priority or 2, op.args or {}, vm)
    return "ok"
  elseif code == "delay" then
    vm.framesToWait = math.max(0, tonumber(op.frames) or 1)
    return "wait"
  elseif code == "waitforvisualfinish" then
    vm.waitingVisual = true
    return "wait"
  elseif code == "nop" or code == "nop2" then
    return "ok"
  elseif code == "end" then
    finish(vm)
    return "end"
  elseif code == "playse" or code == "playsewithpan" then
    local id = op.song or op.se or op.id or op[1]
    play_se_pan(vm, id, op.pan)
    return "ok"
  elseif code == "loopsewithpan" then
    local id = op.song or op.se or op.id or op[1]
    spawn_loop_se(vm, id, op.pan, op.wait or op.frames or 10, op.plays or op.count or 1)
    return "ok"
  elseif code == "waitplaysewithpan" then
    local id = op.song or op.se or op.id or op[1]
    spawn_wait_se(vm, id, op.pan, op.wait or op.frames or 0)
    return "ok"
  elseif code == "monbg" then
    local Anim = require("src.core.game3.battle.anim")
    local side = vm:resolveBattlerSide(op.battler or "target")
    local p = Anim.present(side)
    if p then p.z = AnimVm.Z.BEHIND end
    return "ok"
  elseif code == "clearmonbg" then
    local Anim = require("src.core.game3.battle.anim")
    local side = vm:resolveBattlerSide(op.battler or "target")
    local p = Anim.present(side)
    if p then
      p.z = (side == "player") and AnimVm.Z.PLAYER or AnimVm.Z.ENEMY
    end
    return "ok"
  elseif code == "setalpha" or code == "blendoff" then
    return "ok"
  elseif code == "call" then
    local label = op.label or op.target
    local pack = vm._pack
    local sub = pack and pack.labels and pack.labels[label]
    if sub then
      vm.callStack[#vm.callStack + 1] = { script = vm.script, pc = vm.pc + 1 }
      vm.script = sub
      vm.pc = 0 -- bumped after
      return "ok"
    end
    return "ok"
  elseif code == "return" then
    local frame = table.remove(vm.callStack)
    if frame then
      vm.script = frame.script
      vm.pc = frame.pc - 1
    end
    return "ok"
  elseif code == "goto" then
    local label = op.label or op.target
    local pack = vm._pack
    local sub = pack and pack.labels and pack.labels[label]
    if sub then
      vm.script = sub
      vm.pc = 0
    end
    return "ok"
  elseif code == "setarg" then
    local id = tonumber(op.argId) or 0
    vm.args[id] = tonumber(op.value) or 0
    return "ok"
  elseif code == "invisible" or code == "visible" then
    local Anim = require("src.core.game3.battle.anim")
    local side = vm:resolveBattlerSide(op.battler or "attacker")
    local p = Anim.present(side)
    if p then p.visible = (code == "visible") end
    return "ok"
  else
    -- Unknown opcode: skip
    return "ok"
  end
end

function AnimVm:update(_dt)
  if not self.active then return end
  if self.headless then
    finish(self)
    return
  end

  tick_sound_tasks(self)
  AnimTasks.update(self)
  AnimSprites.update()

  if self.framesToWait > 0 then
    self.framesToWait = self.framesToWait - 1
    return
  end

  if self.waitingVisual then
    self._visualWaitFrames = (self._visualWaitFrames or 0) + 1
    local tasks = AnimTasks.activeCount()
    local sprs = AnimSprites.activeCount()
    if (tasks == 0 and sprs == 0) or self._visualWaitFrames > 180 then
      if self._visualWaitFrames > 180 then
        -- Force-clear stuck particles/tasks so scripts cannot soft-lock
        AnimSprites.reset()
        AnimTasks.reset()
      end
      self.waitingVisual = false
      self._visualWaitFrames = 0
    else
      return
    end
  else
    self._visualWaitFrames = 0
  end

  -- Run opcodes until wait or end (pret style burst)
  local guard = 0
  while self.active and self.framesToWait <= 0 and not self.waitingVisual and guard < 64 do
    guard = guard + 1
    local op = self.script and self.script[self.pc]
    if not op then
      finish(self)
      break
    end
    local status = run_op(self, op)
    self.pc = self.pc + 1
    if status == "end" then break end
    if status == "wait" then break end
  end
end

return AnimVm
