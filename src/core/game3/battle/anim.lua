-- Battle animation host: present state, HP tween, busy gate, VM launch facade.
-- Engine stays pure; this layer owns display offsets and pacing.

local Task = require("src.core.game3.task")
local AnimVm = require("src.core.game3.battle.anim_vm")
local AnimSprites = require("src.core.game3.battle.anim_sprites")

local Anim = {}

Anim.Z = AnimVm.Z

-- pret sBattlerCoords (singles) — CreateSprite CENTER
Anim.ENEMY_MON = { x = 176, y = 40 }
Anim.PLAYER_MON = { x = 72, y = 80 }

Anim._vm = nil
Anim._headless = false
Anim._pack = nil
Anim._packLoaded = false
Anim._hpTweening = false
Anim._expTweening = false
Anim._introTweening = 0
Anim._seqBusy = false
Anim._statusQueue = {}
Anim._present = {
  player = nil,
  enemy = nil,
}
Anim._stage = nil

local function default_present(side)
  local z = (side == "player") and Anim.Z.PLAYER or Anim.Z.ENEMY
  return {
    side = side,
    ox = 0,
    oy = 0,
    alpha = 1,
    visible = true,
    z = z,
    hFlip = false,
    darken = 0,
    scale = 1,
    sx = 1,
    sy = 1,
    displayHp = nil,
    displayMaxHp = nil,
    displayExp = nil,
    displayLevel = nil,
    flash = 0,
  }
end

local function default_stage(headless)
  return {
    slide = headless and 1 or 0,
    slideDone = headless and true or false,
    trainer = {
      player = { visible = false, ox = 0, oy = 0, frame = 0, gender = 0 },
      enemy = { visible = false, ox = 0, oy = 0, picId = nil },
    },
    ball = { visible = false, x = 0, y = 0, frame = 0, side = nil },
    healthbox = {
      player = { visible = headless and true or false, ox = 0 },
      enemy = { visible = headless and true or false, ox = 0 },
    },
    partyBar = {
      player = { visible = false, ox = 0, balls = {} },
      enemy = { visible = false, ox = 0, balls = {} },
    },
    bgSlide = {
      enemyOx = 0,
      playerOx = 0,
    },
  }
end

function Anim.x(v)
  local vm = Anim._vm
  if vm and vm.isReversed then return -(tonumber(v) or 0) end
  return tonumber(v) or 0
end

function Anim.present(side)
  if side == "attacker_side" and Anim._vm then
    side = Anim._vm:attackerSide()
  end
  if side ~= "player" and side ~= "enemy" then return nil end
  if not Anim._present[side] then
    Anim._present[side] = default_present(side)
  end
  return Anim._present[side]
end

function Anim.battlerCenter(side)
  local base = (side == "player") and Anim.PLAYER_MON or Anim.ENEMY_MON
  local p = Anim.present(side)
  local cx = base.x + (p and p.ox or 0)
  local cy = base.y + (p and p.oy or 0)
  return cx, cy
end

function Anim.reset(opts)
  opts = opts or {}
  Anim._headless = opts.headless and true or false
  Anim._hpTweening = false
  Anim._expTweening = false
  Anim._introTweening = 0
  Anim._seqBusy = false
  Anim._statusQueue = {}
  Anim._present.player = default_present("player")
  Anim._present.enemy = default_present("enemy")
  Anim._stage = default_stage(Anim._headless)
  if not Anim._headless then
    Anim._present.player.visible = false
    Anim._present.enemy.visible = false
  end
  if not Anim._vm then
    Anim._vm = AnimVm.new()
  end
  Anim._vm.headless = Anim._headless
  Anim._vm:reset()
  if Anim._pack then
    Anim._vm:setPack(Anim._pack)
  end
  AnimSprites.reset()
end

function Anim.setSeqBusy(v)
  Anim._seqBusy = v and true or false
end

function Anim.hpTweening()
  return Anim._hpTweening == true
end

--- True while a clip or HP bar is mid-flight (NOT while the host sequencer merely has steps left).
-- Including seqBusy here soft-locks Battle.update: animating waits on busy() before AnimSeq.update().
function Anim.busy()
  if Anim._headless then return false end
  if Anim._hpTweening then return true end
  if Anim._expTweening then return true end
  if (Anim._introTweening or 0) > 0 then return true end
  if Anim._vm and Anim._vm:busy() then return true end
  return false
end

function Anim.stage()
  if not Anim._stage then
    Anim._stage = default_stage(Anim._headless)
  end
  return Anim._stage
end

function Anim.introSlideDone()
  local s = Anim.stage()
  return s and s.slideDone == true
end

--- Pret faint presentation: SE_FAINT + sink/slide off, then hide mon + healthbox.
-- Opponent: SpriteCB_AnimFaintOpponent — +8px every 2 frames, ~8 steps.
-- Player: SpriteCB_FaintSlideAnim — +5px/frame until below screen.
function Anim.faintMon(side, opts)
  opts = opts or {}
  side = side or "enemy"
  local p = Anim.present(side)
  local stage = Anim.stage()
  local hb = stage and stage.healthbox and stage.healthbox[side]
  local AnimSprites = require("src.core.game3.battle.anim_sprites")
  AnimSprites.clearHost(side)

  local function hide_all()
    if p then
      p.visible = false
      p.oy = 0
    end
    if hb then hb.visible = false end
  end

  if Anim._headless or not p then
    hide_all()
    if opts.onComplete then opts.onComplete() end
    return
  end

  if opts.playSe ~= false then
    local okA, Audio = pcall(require, "src.core.game3.audio")
    local okS, SE = pcall(require, "src.core.game3.se_ids")
    if okA and okS and Audio.playSe and SE and SE.SE_FAINT then
      Audio.playSe(SE.SE_FAINT)
    end
  end

  local fromOy = p.oy or 0
  if side == "enemy" then
    -- data[3] ≈ 8 − yOffset/8 → ~8 steps; 2 frames each → 16 frames, +64px.
    local steps = 8
    local frames = steps * 2
    Anim.tweenStage(frames, function(u)
      local step = math.min(steps, math.floor(u * steps + 1e-9))
      p.oy = fromOy + step * 8
    end, function()
      hide_all()
      if opts.onComplete then opts.onComplete() end
    end)
  else
    -- Player back sprite center y=80; +5/frame until below 160.
    local screenH = 160
    do
      local ok, Display = pcall(require, "src.core.game3.display")
      if ok and Display and Display.H then screenH = Display.H end
    end
    local need = math.max(1, math.ceil((screenH - (Anim.PLAYER_MON.y or 80) + 32) / 5))
    local frames = math.max(16, need + 2)
    Anim.tweenStage(frames, function(_, t)
      p.oy = fromOy + 5 * (t.frames or 1)
    end, function()
      hide_all()
      if opts.onComplete then opts.onComplete() end
    end)
  end
end

--- Tween helper that raises Anim.busy via _introTweening (in-flight only).
function Anim.tweenStage(frames, onStep, onComplete)
  if Anim._headless then
    if onStep then onStep(1) end
    if onComplete then onComplete() end
    return nil
  end
  Anim._introTweening = (Anim._introTweening or 0) + 1
  return Task.tween(frames, onStep, function()
    Anim._introTweening = math.max(0, (Anim._introTweening or 1) - 1)
    if onComplete then onComplete() end
  end)
end

function Anim.seqBusy()
  return Anim._seqBusy == true
end

function Anim.vm()
  return Anim._vm
end

--- Sync display HP from logical battler (instant).
function Anim.syncDisplayFromState(st)
  if not st then return end
  local Experience = require("src.core.game3.battle.experience")
  for _, side in ipairs({ "player", "enemy" }) do
    local b = st[side]
    local p = Anim.present(side)
    if b and b.mon and p then
      p.displayHp = tonumber(b.mon.hp) or 0
      p.displayMaxHp = tonumber(b.mon.maxHp) or 1
      p.displayLevel = tonumber(b.mon.level) or 1
      local prog = Experience.progress(b.mon)
      p.displayExp = prog.progressPercent or 0
    end
  end
end

--- Lerp display HP; onComplete when done. frames ≈ pret healthbar speed.
function Anim.tweenHp(side, fromHp, toHp, maxHp, opts)
  opts = opts or {}
  local p = Anim.present(side)
  if not p then
    if opts.onComplete then opts.onComplete() end
    return
  end
  maxHp = math.max(1, tonumber(maxHp) or p.displayMaxHp or 1)
  fromHp = tonumber(fromHp)
  toHp = tonumber(toHp)
  if fromHp == nil then fromHp = p.displayHp or toHp or 0 end
  if toHp == nil then toHp = fromHp end
  p.displayMaxHp = maxHp
  if Anim._headless or opts.instant then
    p.displayHp = toHp
    if opts.onComplete then opts.onComplete() end
    return
  end
  local delta = math.abs(toHp - fromHp)
  -- pret-ish: ~1 HP per frame-ish for small, cap duration
  local frames = math.max(4, math.min(40, math.floor(delta / math.max(1, maxHp / 48)) + 4))
  if opts.frames then frames = opts.frames end
  Anim._hpTweening = true
  p.displayHp = fromHp
  Task.tween(frames, function(u)
    p.displayHp = fromHp + (toHp - fromHp) * u
  end, function()
    p.displayHp = toHp
    Anim._hpTweening = false
    if opts.onComplete then opts.onComplete() end
  end)
end

--- Lerp player EXP bar ratio 0..1 within current level band.
function Anim.tweenExp(side, fromRatio, toRatio, opts)
  opts = opts or {}
  side = side or "player"
  local p = Anim.present(side)
  if not p then
    if opts.onComplete then opts.onComplete() end
    return
  end
  fromRatio = math.max(0, math.min(1, tonumber(fromRatio) or p.displayExp or 0))
  toRatio = math.max(0, math.min(1, tonumber(toRatio) or fromRatio))
  if opts.level then p.displayLevel = opts.level end
  if Anim._headless or opts.instant then
    p.displayExp = toRatio
    if opts.onComplete then opts.onComplete() end
    return
  end
  local delta = math.abs(toRatio - fromRatio)
  local frames = math.max(8, math.min(48, math.floor(delta * 40) + 8))
  if opts.frames then frames = opts.frames end
  Anim._expTweening = true
  p.displayExp = fromRatio
  Task.tween(frames, function(u)
    p.displayExp = fromRatio + (toRatio - fromRatio) * u
  end, function()
    p.displayExp = toRatio
    Anim._expTweening = false
    if opts.onComplete then opts.onComplete() end
  end)
end

function Anim.displayExpRatio(side, battler)
  local p = Anim.present(side or "player")
  if p and p.displayExp ~= nil then
    return math.max(0, math.min(1, p.displayExp)), p.displayLevel
  end
  if battler and battler.mon then
    local Experience = require("src.core.game3.battle.experience")
    local prog = Experience.progress(battler.mon)
    return prog.progressPercent or 0, tonumber(battler.mon.level) or 1
  end
  return 0, 1
end

function Anim.displayHpRatio(side, battler)
  local p = Anim.present(side)
  local hp, maxHp
  if p and p.displayHp ~= nil then
    hp = p.displayHp
    maxHp = p.displayMaxHp or (battler and battler.mon and battler.mon.maxHp) or 1
  elseif battler and battler.mon then
    hp = tonumber(battler.mon.hp) or 0
    maxHp = tonumber(battler.mon.maxHp) or 1
  else
    return 0, 0, 1
  end
  maxHp = math.max(1, tonumber(maxHp) or 1)
  hp = math.max(0, tonumber(hp) or 0)
  return math.max(0, math.min(1, hp / maxHp)), hp, maxHp
end

--- GBA indexed sheets store transparent as palette index 0 (often magenta #6229FF).
-- Love2D expands that to opaque pixels — punch them to alpha 0.
local function punch_gba_transparent(imageData)
  if not imageData or not imageData.mapPixel then return imageData end
  -- Exact pret key color and near-matches (98/255, 41/255, 1)
  local kr, kg, kb = 98 / 255, 41 / 255, 1
  imageData:mapPixel(function(_x, _y, r, g, b, a)
    if a < 0.01 then return 0, 0, 0, 0 end
    -- Exact key
    if math.abs(r - kr) < 0.004 and math.abs(g - kg) < 0.004 and math.abs(b - kb) < 0.004 then
      return 0, 0, 0, 0
    end
    -- Generic bright magenta/blue key used across pret sheets (high B, mid R, low G)
    if b > 0.95 and r > 0.30 and r < 0.50 and g < 0.25 then
      return 0, 0, 0, 0
    end
    return r, g, b, a
  end)
  return imageData
end

local function hydrate_tag_images(pack)
  if not pack or not pack.tags then return end
  if not (love and love.image and love.graphics) then return end
  local ok, Dataset = pcall(require, "src.core.game3.dataset")
  local cache = ok and Dataset.cache and Dataset.cache() or nil
  local root = "data/generated/gba/pokemon/battle_anims/"
  for tag, info in pairs(pack.tags) do
    if type(info) == "table" and not info.image and info.file then
      local bytes = nil
      local rel = root .. info.file
      if cache and cache.read then
        bytes = cache:read(rel)
        if not bytes then bytes = cache:read("firered/" .. rel) end
      end
      if type(bytes) == "string" and #bytes > 0 then
        local okFd, fileData = pcall(love.filesystem.newFileData, bytes, info.file)
        if okFd and fileData then
          local okId, imageData = pcall(love.image.newImageData, fileData)
          if okId and imageData then
            punch_gba_transparent(imageData)
            local okImg, image = pcall(love.graphics.newImage, imageData)
            if okImg and image then
              image:setFilter("nearest", "nearest")
              info.image = image
              info.w = image:getWidth()
              info.h = image:getHeight()
            end
          end
        end
      end
    end
  end
end

local function load_pack()
  if Anim._packLoaded then return Anim._pack end
  Anim._packLoaded = true
  local chunk
  local ok, Dataset = pcall(require, "src.core.game3.dataset")
  local cache = ok and Dataset.cache and Dataset.cache() or nil
  local rels = {
    "data/generated/gba/pokemon/battle_anims/pack.lua",
    "firered/data/generated/gba/pokemon/battle_anims/pack.lua",
  }
  if cache and cache.read then
    for _, rel in ipairs(rels) do
      local src = cache:read(rel)
      if type(src) == "string" and #src > 0 then
        local loader = loadstring or load
        local fn, err = loader(src, "@" .. rel)
        if fn then
          local ok2, result = pcall(fn)
          if ok2 and type(result) == "table" then
            chunk = result
            break
          end
        else
          print("[battle.anim] pack load error: " .. tostring(err))
        end
      end
    end
  end
  if not chunk then
    local okR, mod = pcall(require, "src.core.game3.battle.anim_pack_fallback")
    if okR then chunk = mod end
  end
  if chunk then
    hydrate_tag_images(chunk)
  end
  Anim._pack = chunk
  if Anim._vm and chunk then Anim._vm:setPack(chunk) end
  return chunk
end

function Anim.loadPack(pack)
  Anim._pack = pack
  Anim._packLoaded = true
  if Anim._vm then Anim._vm:setPack(pack) end
end

local GENERIC_HIT = {
  { op = "loadspritegfx", tag = "IMPACT" },
  { op = "monbg", battler = "target" },
  { op = "createsprite", template = "gHorizontalLungeSpriteTemplate", animBattler = "attacker", subpriority = 2, args = { 4, 4 } },
  { op = "delay", frames = 6 },
  { op = "createsprite", template = "gBasicHitSplatSpriteTemplate", animBattler = "attacker", subpriority = 2, tag = "IMPACT", args = { 0, 0, "target", 2 } },
  { op = "createvisualtask", task = "AnimTask_ShakeMon", priority = 2, args = { "target", 3, 0, 6, 1 } },
  { op = "waitforvisualfinish" },
  { op = "clearmonbg", battler = "target" },
  { op = "end" },
}

local GENERIC_STATUS = {
  { op = "createvisualtask", task = "AnimTask_ShakeMon", priority = 2, args = { "attacker", 1, 0, 8, 1 } },
  { op = "waitforvisualfinish" },
  { op = "end" },
}

local GENERIC_MISS = {
  { op = "delay", frames = 8 },
  { op = "end" },
}

function Anim.scriptForMove(moveId)
  local pack = load_pack()
  moveId = tonumber(moveId) or moveId
  if pack and pack.moves then
    local s = pack.moves[moveId] or pack.moves[tostring(moveId)]
    if s then return s end
  end
  return GENERIC_HIT
end

function Anim.scriptForStatus(statusId)
  local pack = load_pack()
  if pack and pack.status and pack.status[statusId] then
    return pack.status[statusId]
  end
  return GENERIC_STATUS
end

--- Launch move anim. opts: { attackerSide, isReversed, onEnd, miss }
function Anim.launchMove(moveId, opts)
  opts = opts or {}
  if not Anim._vm then Anim.reset({ headless = Anim._headless }) end
  if opts.miss then
    return Anim._vm:launch(GENERIC_MISS, opts)
  end
  local script = Anim.scriptForMove(moveId)
  return Anim._vm:launch(script, opts)
end

--- Status: only when primary idle; else queue.
function Anim.launchStatus(statusId, opts)
  opts = opts or {}
  if not Anim._vm then Anim.reset({ headless = Anim._headless }) end
  if Anim._vm:busy() then
    Anim._statusQueue[#Anim._statusQueue + 1] = { statusId = statusId, opts = opts }
    return false
  end
  local script = Anim.scriptForStatus(statusId)
  return Anim._vm:launch(script, opts)
end

local function pump_status_queue()
  if Anim._vm and Anim._vm:busy() then return end
  local next = table.remove(Anim._statusQueue, 1)
  if next then
    Anim.launchStatus(next.statusId, next.opts)
  end
end

function Anim.update(dt)
  if Anim._headless then return end
  -- HP tweens live on shared Task list
  if Anim._vm then
    Anim._vm:update(dt)
  end
  pump_status_queue()
end

function Anim.drawParticles(minZ, maxZ)
  if Anim._headless then return end
  if Anim._vm then Anim._vm:draw(minZ, maxZ) end
end

return Anim
