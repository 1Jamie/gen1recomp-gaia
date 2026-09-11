-- Sprite callbacks for createsprite templates (pret Anim* ports, pooled).

local AnimSprites = require("src.core.game3.battle.anim_sprites")

local AnimCallbacks = {}

local function destroy(sprite)
  AnimSprites.release(sprite)
end

--- pret AnimHitSplatBasic — IMPACT mark at attacker/target, brief scale-in then destroy.
function AnimCallbacks.HitSplatBasic(sprite)
  sprite.data[0] = (sprite.data[0] or 0) + 1
  local life = sprite.data[0]
  local u = math.min(1, life / 8)
  local sc = 0.55 + 0.55 * u
  if life > 10 then
    sc = sc * (1 - (life - 10) / 6)
  end
  sprite.w = (sprite._baseW or 32) * sc
  sprite.h = (sprite._baseH or 32) * sc
  sprite.alpha = life <= 10 and 1 or math.max(0, 1 - (life - 10) / 6)
  if life >= 16 then
    destroy(sprite)
  end
end
AnimCallbacks.CrossImpact = AnimCallbacks.HitSplatBasic
AnimCallbacks.FlashingHitSplat = AnimCallbacks.HitSplatBasic
AnimCallbacks.HitSplatPersistent = AnimCallbacks.HitSplatBasic

--- pret AnimCuttingSlice + AnimSlice_Step (Cut, Fury Cutter, Air Cutter).
-- args[1]=dx (40), args[2]=dy (-32), args[3]=dir (0=R to L, 1=L to R).
function AnimCallbacks.CuttingSlice(sprite)
  if not sprite._inited then
    sprite._inited = true
    local dir = tonumber(sprite.data[2]) or 0
    sprite.data[0] = 0 -- frame step counter
    sprite.data[1] = -0x400 -- vx_fp (-4.0 px/frame)
    sprite.data[2] = 0x400  -- vy_fp (+4.0 px/frame)
    sprite.data[3] = 0      -- x offset accumulator (fp)
    sprite.data[4] = 0      -- y offset accumulator (fp)
    sprite.data[5] = dir
    if dir == 1 then
      sprite.data[1] = -sprite.data[1]
      sprite.hFlip = true
    else
      sprite.hFlip = false
    end
  end

  -- AnimSlice_Step
  sprite.data[3] = (sprite.data[3] or 0) + (sprite.data[1] or 0)
  sprite.data[4] = (sprite.data[4] or 0) + (sprite.data[2] or 0)
  local dir = sprite.data[5] or 0
  if dir == 0 then
    sprite.data[1] = sprite.data[1] + 0x18
  else
    sprite.data[1] = sprite.data[1] - 0x18
  end
  sprite.data[2] = sprite.data[2] - 0x18

  sprite.ox = math.floor((sprite.data[3] or 0) / 256)
  sprite.oy = math.floor((sprite.data[4] or 0) / 256)

  local step = (sprite.data[0] or 0) + 1
  sprite.data[0] = step

  -- AnimCmds: 4 frames, 5 ticks per frame (y cell 0, 32, 64, 96)
  local frame = math.min(3, math.floor((step - 1) / 5))
  sprite.quadY = frame * (sprite._baseH or 32)

  if step >= 20 then
    destroy(sprite)
  end
end
AnimCallbacks.AirCutterSlice = AnimCallbacks.CuttingSlice

--- pret AnimSlashSlice / AnimClawSlash / AnimFurySwipes (Slash, Scratch, Claw, False Swipe).
function AnimCallbacks.SlashSlice(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
  end
  local step = (sprite.data[0] or 0) + 1
  sprite.data[0] = step
  local frame = math.min(3, math.floor((step - 1) / 4))
  sprite.quadY = frame * (sprite._baseH or 32)
  if step >= 16 then
    destroy(sprite)
  end
end
AnimCallbacks.ClawSlash = AnimCallbacks.SlashSlice
AnimCallbacks.FalseSwipeSlice = AnimCallbacks.SlashSlice
AnimCallbacks.FalseSwipePositionedSlice = AnimCallbacks.SlashSlice
AnimCallbacks.FurySwipes = AnimCallbacks.SlashSlice
AnimCallbacks.RevengeScratch = AnimCallbacks.SlashSlice

--- pret AnimBite / AnimFang / AnimSuperFang (Bite, Crunch, Super Fang).
function AnimCallbacks.Bite(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
  end
  local step = (sprite.data[0] or 0) + 1
  sprite.data[0] = step
  local frame = math.min(3, math.floor((step - 1) / 4))
  sprite.quadY = frame * (sprite._baseH or 32)
  if step >= 16 then
    destroy(sprite)
  end
end
AnimCallbacks.Fang = AnimCallbacks.Bite
AnimCallbacks.SuperFang = AnimCallbacks.Bite

--- pret AnimRoarNoiseLine — noise arcs from attacker (Growl/Roar).
-- arg 0: initial x pixel offset
-- arg 1: initial y pixel offset
-- arg 2: direction (0 = upward, 1 = downward, 2 = horizontal)
function AnimCallbacks.RoarNoiseLine(sprite)
  if not sprite._inited then
    sprite._inited = true
    local dir = tonumber(sprite.data[2]) or 0
    local isOpponent = sprite._reversed and true or false

    local vx = 0x280
    local vy = 0
    local animBank = 0

    if dir == 0 then
      vx = 0x280
      vy = -0x280
      sprite.vFlip = false
    elseif dir == 1 then
      vx = 0x280
      vy = 0x280
      sprite.vFlip = true
    else
      animBank = 1
      vx = 0x280
      vy = 0
      sprite.vFlip = false
    end

    if isOpponent then
      vx = -vx
      sprite.hFlip = true
    else
      sprite.hFlip = false
    end

    sprite.data[0] = vx
    sprite.data[1] = vy
    sprite.data[3] = animBank
    sprite.data[5] = 0
    sprite.data[6] = 0
    sprite.data[7] = 0
  end

  local step = (sprite.data[5] or 0) + 1
  sprite.data[5] = step

  sprite.data[6] = (sprite.data[6] or 0) + (sprite.data[0] or 0)
  sprite.data[7] = (sprite.data[7] or 0) + (sprite.data[1] or 0)
  sprite.ox = math.floor((sprite.data[6] or 0) / 256)
  sprite.oy = math.floor((sprite.data[7] or 0) / 256)

  local bank = sprite.data[3] or 0
  local phase = math.floor((step - 1) / 3) % 2
  local cell = (bank == 0) and phase or (2 + phase)
  sprite.quadY = cell * (sprite._baseH or 32)

  if step >= 14 then
    destroy(sprite)
  end
end

--- Projectile trajectory (BulletSeed, WaterBubbleProjectile, etc.).
function AnimCallbacks.ThrowProjectile(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
    sprite.data[5] = 16
  end
  local step = (sprite.data[0] or 0) + 1
  sprite.data[0] = step
  local dur = sprite.data[5] or 16
  local u = math.min(1, step / dur)
  local h = math.sin(u * math.pi) * 20
  sprite.ox = math.floor((sprite._dx or 0) * u)
  sprite.oy = math.floor((sprite._dy or 0) * u - h)
  if step >= dur then
    destroy(sprite)
  end
end
AnimCallbacks.BulletSeed = AnimCallbacks.ThrowProjectile
AnimCallbacks.WaterBubbleProjectile = AnimCallbacks.ThrowProjectile
AnimCallbacks.SludgeProjectile = AnimCallbacks.ThrowProjectile
AnimCallbacks.BoneHitProjectile = AnimCallbacks.ThrowProjectile

--- pret AnimSpriteOnMonPos — plays sprite sheet frames centered on mon position
function AnimCallbacks.SpriteOnMonPos(sprite)
  if sprite.tag == "ECLIPSING_ORB" then
    return AnimCallbacks.EclipsingOrb(sprite)
  end
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
  end
  local step = (sprite.data[0] or 0) + 1
  sprite.data[0] = step
  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  local frame = math.min(totalFrames - 1, math.floor((step - 1) / 3))
  sprite.quadY = frame * cellH
  if step >= totalFrames * 3 then
    destroy(sprite)
  end
end

--- pret sEclipsingOrbAnimCmds (Defense Curl orb bubble expansion/contraction).
function AnimCallbacks.EclipsingOrb(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite.data[0] = 0
  end
  local step = (sprite.data[0] or 0) + 1
  sprite.data[0] = step

  local frameSeq = {
    { cell = 0, hFlip = false },
    { cell = 1, hFlip = false },
    { cell = 2, hFlip = false },
    { cell = 3, hFlip = false },
    { cell = 2, hFlip = true },
    { cell = 1, hFlip = true },
    { cell = 0, hFlip = true },
  }
  local cycleTick = (step - 1) % 21
  local idx = math.min(7, math.floor(cycleTick / 3) + 1)
  local f = frameSeq[idx] or frameSeq[1]
  sprite.quadY = f.cell * (sprite._baseH or 32)
  sprite.hFlip = f.hFlip

  if step >= 42 then
    destroy(sprite)
  end
end
--- pret AnimMovePowderParticle (PoisonPowder, StunSpore, SleepPowder, CottonSpore).
-- Sprites fall downwards with sinusoidal sway onto the target Pokémon.
function AnimCallbacks.MovePowderParticle(sprite)
  if not sprite._inited then
    sprite._inited = true
    local args = sprite._args or {}
    sprite._dur = tonumber(args[3]) or 80
    sprite._vy = (tonumber(args[4]) or 80) / 256
    local amp = tonumber(args[5]) or 5
    if sprite._reversed then amp = -amp end
    sprite._amp = amp
    sprite._speed = tonumber(args[6]) or 1
    sprite._phase = 0
    sprite._yAccum = 0
    sprite._step = 0
  end

  sprite._step = sprite._step + 1
  sprite._yAccum = sprite._yAccum + sprite._vy
  sprite.oy = math.floor(sprite._yAccum)
  sprite._phase = (sprite._phase + sprite._speed) % 256
  sprite.ox = math.floor(math.sin(sprite._phase * 2 * math.pi / 256) * sprite._amp)

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end

--- pret AnimAbsorptionOrb (Absorb, Mega Drain, Giga Drain, Leech Life).
-- Energy orbs travel from target to attacker in an arc.
function AnimCallbacks.AbsorptionOrb(sprite)
  if not sprite._inited then
    sprite._inited = true
    local args = sprite._args or {}
    sprite._dur = math.max(12, tonumber(args[4]) or 20)
    sprite._amp = tonumber(args[3]) or 16
    sprite._step = 0
    sprite._startX = sprite.x
    sprite._startY = sprite.y
    local ax, ay = sprite._attackerX or sprite.x, sprite._attackerY or sprite.y
    sprite._dx = ax - sprite._startX
    sprite._dy = ay - sprite._startY
  end

  sprite._step = sprite._step + 1
  local u = math.min(1, sprite._step / sprite._dur)
  local arc = math.sin(u * math.pi) * sprite._amp
  sprite.ox = math.floor(sprite._dx * u)
  sprite.oy = math.floor(sprite._dy * u - arc)

  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 3) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.PowerAbsorptionOrb = AnimCallbacks.AbsorptionOrb

--- Linear / projectile translation to target mon location.
function AnimCallbacks.TranslateAnimSpriteToTargetMonLocation(sprite)
  if not sprite._inited then
    sprite._inited = true
    local args = sprite._args or {}
    sprite._dur = math.max(8, tonumber(args[5]) or 16)
    sprite._step = 0
    local tx, ty = sprite._targetX or sprite.x, sprite._targetY or sprite.y
    sprite._dx = tx - sprite.x
    sprite._dy = ty - sprite.y
  end

  sprite._step = sprite._step + 1
  local u = math.min(1, sprite._step / sprite._dur)
  sprite.ox = math.floor(sprite._dx * u)
  sprite.oy = math.floor(sprite._dy * u)

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.TranslateLinearSingleSineWave = AnimCallbacks.TranslateAnimSpriteToTargetMonLocation
AnimCallbacks.PainSplitProjectile = AnimCallbacks.TranslateAnimSpriteToTargetMonLocation

--- Floating / drifting particles (Petal Dance, Sweet Scent, Razor Leaf, Flying Particle).
function AnimCallbacks.FlyingParticle(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._dur = 32
    sprite._step = 0
    local args = sprite._args or {}
    sprite._vx = (tonumber(args[3]) or 1) * (sprite._reversed and -1 or 1)
    sprite._vy = tonumber(args[4]) or 1
  end

  sprite._step = sprite._step + 1
  sprite.ox = (sprite.ox or 0) + sprite._vx
  sprite.oy = (sprite.oy or 0) + sprite._vy

  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 4) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.PetalDanceSmallFlower = AnimCallbacks.FlyingParticle
AnimCallbacks.PetalDanceBigFlower = AnimCallbacks.FlyingParticle
AnimCallbacks.SweetScentPetal = AnimCallbacks.FlyingParticle
AnimCallbacks.RazorLeafParticle = AnimCallbacks.FlyingParticle
AnimCallbacks.FallingFeather = AnimCallbacks.FlyingParticle

--- Falling rocks / projectiles (Rock Slide, Rock Tomb, Eruption).
function AnimCallbacks.FallingRock(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 20
    sprite.oy = -60
  end

  sprite._step = sprite._step + 1
  local u = math.min(1, sprite._step / sprite._dur)
  sprite.oy = math.floor(-60 + 60 * (u * u))

  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 3) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.EruptionFallingRock = AnimCallbacks.FallingRock
AnimCallbacks.RockFragment = AnimCallbacks.FallingRock
AnimCallbacks.RockTomb = AnimCallbacks.FallingRock

--- Flames rising and expanding (Ember, Flamethrower, Fire Blast, Outrage).
function AnimCallbacks.LargeFlame(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 24
  end

  sprite._step = sprite._step + 1
  sprite.oy = -(sprite._step * 0.75)

  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 3) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.OutrageFlame = AnimCallbacks.LargeFlame
AnimCallbacks.OverheatFlame = AnimCallbacks.LargeFlame
AnimCallbacks.DragonFireToTarget = AnimCallbacks.LargeFlame
AnimCallbacks.DragonRageFirePlume = AnimCallbacks.LargeFlame
AnimCallbacks.FireSpiralInward = AnimCallbacks.LargeFlame

--- Sparkling stars & twinkle particles (Wish, Swift, Moonlight, Morning Sun).
function AnimCallbacks.GrantingStars(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 20
  end

  sprite._step = sprite._step + 1
  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 3) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.SparklingStars = AnimCallbacks.GrantingStars
AnimCallbacks.EyeSparkle = AnimCallbacks.GrantingStars
AnimCallbacks.WallSparkle = AnimCallbacks.GrantingStars
AnimCallbacks.MoonlightSparkle = AnimCallbacks.GrantingStars

--- Status / Emote particles (Confuse Duck, Hearts, Tears, Alert, Anger).
function AnimCallbacks.DizzyPunchDuck(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 36
  end

  sprite._step = sprite._step + 1
  local angle = (sprite._step / 36) * math.pi * 4
  sprite.ox = math.floor(math.cos(angle) * 16)
  sprite.oy = math.floor(math.sin(angle) * 6 - 8)

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.AngerMark = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.TealAlert = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.TearDrop = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.PinkHeart = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.RedHeartRising = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.RedHeartProjectile = AnimCallbacks.TranslateAnimSpriteToTargetMonLocation

--- Swirling vortex & orbiting debris (Twister, Whirlpool, Sandstorm, Fire Spin).
function AnimCallbacks.ParticleInVortex(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 32
    sprite._radius = 24
    sprite._angle = (tonumber(sprite.data[1]) or 0) * (math.pi / 4)
  end

  sprite._step = sprite._step + 1
  sprite._angle = sprite._angle + 0.22
  sprite.rotation = sprite._angle

  local r = sprite._radius * (1.0 - (sprite._step / sprite._dur) * 0.4)
  sprite.ox = math.floor(math.cos(sprite._angle) * r + 0.5)
  sprite.oy = math.floor(math.sin(sprite._angle) * (r * 0.45) - (sprite._step * 0.6) + 0.5)

  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 3) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.MoveTwisterParticle = AnimCallbacks.ParticleInVortex
AnimCallbacks.WhirlwindLine = AnimCallbacks.ParticleInVortex
AnimCallbacks.FlyingSandCrescent = AnimCallbacks.ParticleInVortex
AnimCallbacks.OrbitFast = AnimCallbacks.ParticleInVortex
AnimCallbacks.OrbitScatter = AnimCallbacks.ParticleInVortex

--- Energy orbs with pulsing affine scale and rotation (Dragon Dance, Meteor Mash, Power Orbs).
function AnimCallbacks.DragonDanceOrb(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 28
  end

  sprite._step = sprite._step + 1
  sprite.rotation = sprite.rotation + 0.15
  local pulse = 1.0 + math.sin((sprite._step / 28) * math.pi * 3) * 0.25
  sprite.scaleX = pulse
  sprite.scaleY = pulse

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.MeteorMashStar = AnimCallbacks.DragonDanceOrb
AnimCallbacks.ReversalOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.SpitUpOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.SwallowBlueOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.SuperpowerOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.SuperpowerRock = AnimCallbacks.DragonDanceOrb
AnimCallbacks.SuperpowerFireball = AnimCallbacks.DragonDanceOrb
AnimCallbacks.EndureEnergy = AnimCallbacks.DragonDanceOrb
AnimCallbacks.TailGlowOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.ThunderboltOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.GrowingChargeOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.GrowingShockWaveOrb = AnimCallbacks.DragonDanceOrb
AnimCallbacks.SharpenSphere = AnimCallbacks.DragonDanceOrb
AnimCallbacks.TriAttackTriangle = AnimCallbacks.DragonDanceOrb

--- Projectiles & multi-hit stingers (Pin Missile, Twineedle, Spike Cannon, Poison Sting).
function AnimCallbacks.TranslateStinger(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 16
    local dx = sprite._dx or (sprite._reversed and -80 or 80)
    local dy = sprite._dy or (sprite._reversed and 40 or -40)
    sprite.rotation = math.atan2(dy, dx)
  end

  sprite._step = sprite._step + 1
  local progress = sprite._step / sprite._dur
  sprite.ox = math.floor((sprite._dx or 0) * progress + 0.5)
  sprite.oy = math.floor((sprite._dy or 0) * progress + 0.5)

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.BonemerangProjectile = AnimCallbacks.TranslateStinger
AnimCallbacks.SonicBoomProjectile = AnimCallbacks.TranslateStinger
AnimCallbacks.RockBlastRock = AnimCallbacks.TranslateStinger
AnimCallbacks.LeechLifeNeedle = AnimCallbacks.TranslateStinger
AnimCallbacks.ThrowMistBall = AnimCallbacks.TranslateStinger

--- Ice Beam / Blizzard crystal streams.
function AnimCallbacks.IceBeamParticle(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 18
  end

  sprite._step = sprite._step + 1
  sprite.rotation = sprite.rotation + 0.2
  local progress = sprite._step / sprite._dur
  sprite.ox = math.floor((sprite._dx or 0) * progress + 0.5)
  sprite.oy = math.floor((sprite._dy or 0) * progress + 0.5)

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.IcePunchSwirlingParticle = AnimCallbacks.ParticleInVortex

--- Sludge Bomb / Acid / Poison Gas particles.
function AnimCallbacks.SludgeBombHitParticle(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 20
    sprite._vx = (math.random() - 0.5) * 2.5
    sprite._vy = -math.random() * 2.0
  end

  sprite._step = sprite._step + 1
  sprite._vy = sprite._vy + 0.18 -- gravity
  sprite.ox = math.floor((sprite.ox or 0) + sprite._vx + 0.5)
  sprite.oy = math.floor((sprite.oy or 0) + sprite._vy + 0.5)

  local cellH = sprite._baseH or 32
  local totalFrames = 1
  if sprite.image and sprite.image.getDimensions then
    local _, ih = sprite.image:getDimensions()
    totalFrames = math.max(1, math.floor(ih / cellH))
  end
  sprite.quadY = (math.floor((sprite._step - 1) / 3) % totalFrames) * cellH

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.AcidPoisonDroplet = AnimCallbacks.SludgeBombHitParticle
AnimCallbacks.AcidPoisonBubble = AnimCallbacks.SludgeBombHitParticle
AnimCallbacks.InitPoisonGasCloudAnim = AnimCallbacks.SludgeBombHitParticle

--- Radial particle explosion (Explosion, Self-Destruct, Swift burst).
function AnimCallbacks.ParticleBurst(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 24
    local angle = math.random() * math.pi * 2
    local speed = 1.5 + math.random() * 2.0
    sprite._vx = math.cos(angle) * speed
    sprite._vy = math.sin(angle) * speed
  end

  sprite._step = sprite._step + 1
  sprite.ox = math.floor((sprite.ox or 0) + sprite._vx + 0.5)
  sprite.oy = math.floor((sprite.oy or 0) + sprite._vy + 0.5)
  sprite.alpha = math.max(0, 1.0 - (sprite._step / sprite._dur))

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end

--- Additive energy shields & barriers (Reflect, Light Screen, Barrier, Protect).
function AnimCallbacks.DefensiveWall(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 36
    sprite.blendMode = "add"
  end

  sprite._step = sprite._step + 1
  local pulse = 0.6 + math.sin((sprite._step / 36) * math.pi * 4) * 0.35
  sprite.alpha = pulse

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.GuardRing = AnimCallbacks.DefensiveWall
AnimCallbacks.BlendThinRing = AnimCallbacks.DefensiveWall
AnimCallbacks.Protect = AnimCallbacks.DefensiveWall
AnimCallbacks.WhiteHalo = AnimCallbacks.DefensiveWall

--- Barrier overlays & entanglements (Block, Disable, Spikes, Web).
AnimCallbacks.BlockX = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.RedX = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.SpiderWeb = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Spikes = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.StringWrap = AnimCallbacks.SpriteOnMonPos

--- Musical notes & sound waves (Sing, Heal Bell, Perish Song, Growl, Roar, Screech, Snore).
function AnimCallbacks.HealBellMusicNote(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 32
    sprite._freq = 0.15 + (tonumber(sprite.data[1]) or 0) * 0.05
  end

  sprite._step = sprite._step + 1
  sprite.oy = -(sprite._step * 0.9)
  sprite.ox = math.floor(math.sin(sprite._step * sprite._freq) * 8 + 0.5)

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.PerishSongMusicNote = AnimCallbacks.HealBellMusicNote
AnimCallbacks.PerishSongMusicNote2 = AnimCallbacks.HealBellMusicNote
AnimCallbacks.FlyingMusicNotes = AnimCallbacks.HealBellMusicNote
AnimCallbacks.SlowFlyingMusicNotes = AnimCallbacks.HealBellMusicNote
AnimCallbacks.JaggedMusicNote = AnimCallbacks.HealBellMusicNote
AnimCallbacks.UproarRing = AnimCallbacks.DefensiveWall

--- Snooze Z's and smoke puffs (Rest, Yawn, Smokescreen).
function AnimCallbacks.SleepLetterZ(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 28
  end

  sprite._step = sprite._step + 1
  sprite.oy = -(sprite._step * 0.7)
  sprite.ox = math.floor(math.sin(sprite._step * 0.2) * 6 + 0.5)
  sprite.alpha = math.max(0, 1.0 - (sprite._step / sprite._dur) * 0.7)

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.LetterZ = AnimCallbacks.SleepLetterZ
AnimCallbacks.YawnCloud = AnimCallbacks.SleepLetterZ
AnimCallbacks.BlackSmoke = AnimCallbacks.SleepLetterZ
AnimCallbacks.BreathPuff = AnimCallbacks.SleepLetterZ
AnimCallbacks.MovementWaves = AnimCallbacks.SpriteOnMonPos

--- Combat emotes and props (Metronome, Clapping, Fingers, Spoons, Eyes).
function AnimCallbacks.MetronomeFinger(sprite)
  if not sprite._inited then
    sprite._inited = true
    sprite._step = 0
    sprite._dur = 36
  end

  sprite._step = sprite._step + 1
  sprite.rotation = math.sin((sprite._step / 36) * math.pi * 6) * 0.35

  if sprite._step >= sprite._dur then
    destroy(sprite)
  end
end
AnimCallbacks.FollowMeFinger = AnimCallbacks.MetronomeFinger
AnimCallbacks.TauntFinger = AnimCallbacks.MetronomeFinger
AnimCallbacks.BellyDrumHand = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.HelpingHandClap = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.SmellingSaltsHand = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.ClappingHand = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.ClappingHand2 = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.ForesightMagnifyingGlass = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.MeanLookEye = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.BentSpoon = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Pencil = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.ThoughtBubble = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.TrickBag = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.BatonPassPokeball = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Present = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Moon = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Angel = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Devil = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.QuestionMark = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.SmellingSaltExclamation = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.GreenStar = AnimCallbacks.GrantingStars
AnimCallbacks.WeakFrustrationAngerMark = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.KnockOffStrike = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.LockOnTarget = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.LockOnMoveTarget = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.MilkBottle = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Leer = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.FallingCoin = AnimCallbacks.FallingRock
AnimCallbacks.CoinThrow = AnimCallbacks.ThrowProjectile
AnimCallbacks.FlatterSpotlight = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.FlatterConfetti = AnimCallbacks.FlyingParticle
AnimCallbacks.PsychoBoost = AnimCallbacks.ParticleInVortex
AnimCallbacks.Spotlight = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Recycle = AnimCallbacks.ParticleInVortex
AnimCallbacks.SlideHandOrFootToTarget = AnimCallbacks.TranslateStinger
AnimCallbacks.GustToTarget = AnimCallbacks.TranslateStinger
AnimCallbacks.EllipticalGust = AnimCallbacks.ParticleInVortex
AnimCallbacks.FistOrFootRandomPos = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.SporeParticle = AnimCallbacks.MovePowderParticle
AnimCallbacks.TravelDiagonally = AnimCallbacks.TranslateStinger
AnimCallbacks.RapidSpin = AnimCallbacks.ParticleInVortex
AnimCallbacks.Lick = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Conversion = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.Conversion2 = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.RaiseSprite = AnimCallbacks.SpriteOnMonPos
AnimCallbacks.ComplexPaletteBlend = AnimCallbacks.SpriteOnMonPos

function AnimCallbacks.SimpleFadeOut(sprite)
  sprite.data[0] = (sprite.data[0] or 0) + 1
  local life = sprite.data[0]
  sprite.alpha = 1 - life / 20
  if life >= 20 then destroy(sprite) end
end

--- noGfx helpers are handled as visual tasks, not sprites.
AnimCallbacks.HorizontalLunge = nil
AnimCallbacks.VerticalDip = nil
AnimCallbacks.SlideMonToOriginalPos = nil
AnimCallbacks.SlideMonToOffset = nil

function AnimCallbacks.get(name)
  if not name then return AnimCallbacks.HitSplatBasic end
  return AnimCallbacks[name] or AnimCallbacks.SimpleFadeOut
end

return AnimCallbacks

