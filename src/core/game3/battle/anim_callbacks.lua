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
  -- Affine-ish: start small, settle
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

--- pret AnimRoarNoiseLine — noise arcs from attacker (Growl/Roar).
-- Sheet: 32x128 = four 32x32 cells. AnimCmds use tile indices 0/16/32/48
-- → cell rows 0,1,2,3. Anim 0 (diag) = cells 0↔1; anim 1 (horiz) = cells 2↔3.
-- data[0]=vx_fp, data[1]=vy_fp, data[2]=dir, data[3]=animBank,
-- data[4]=animTimer, data[5]=life, data[6]/[7]=pos accum
function AnimCallbacks.RoarNoiseLine(sprite)
  if not sprite._inited then
    sprite._inited = true
    local dir = tonumber(sprite.data[2]) or 0
    local vx, vy = 0x280, 0
    local animBank = 0 -- cells 0/1
    if dir == 0 then
      vx, vy = 0x280, -0x280
    elseif dir == 1 then
      vx, vy = 0x280, 0x280
      sprite.vFlip = true
    else
      -- StartSpriteAnim(sprite, 1) — horizontal zigzag cells
      animBank = 1
    end
    -- pret: opponent-side attacker flips travel + hFlip (vm.isReversed)
    if sprite._reversed then
      vx = -vx
      sprite.hFlip = true
    end
    sprite.data[0] = vx
    sprite.data[1] = vy
    sprite.data[3] = animBank
    sprite.data[4] = 0 -- anim timer
    sprite.data[5] = 0 -- life
    sprite.data[6] = 0
    sprite.data[7] = 0
    sprite.quadX = 0
    sprite.quadY = animBank * 64 -- cell 0 or 2
  end

  -- ANIMCMD_FRAME(n, 3) ping-pong between bank cells every 3 frames
  local life = (sprite.data[5] or 0)
  local bank = sprite.data[3] or 0
  local phase = math.floor(life / 3) % 2
  sprite.quadY = bank * 64 + phase * 32

  sprite.data[6] = (sprite.data[6] or 0) + (sprite.data[0] or 0)
  sprite.data[7] = (sprite.data[7] or 0) + (sprite.data[1] or 0)
  sprite.ox = math.floor((sprite.data[6] or 0) / 256)
  sprite.oy = math.floor((sprite.data[7] or 0) / 256)
  sprite.data[5] = life + 1
  if sprite.data[5] >= 14 then
    destroy(sprite)
  end
end

function AnimCallbacks.SimpleFadeOut(sprite)
  sprite.data[0] = (sprite.data[0] or 0) + 1
  local life = sprite.data[0]
  sprite.alpha = 1 - life / 20
  if life >= 20 then destroy(sprite) end
end

--- noGfx helpers are handled as visual tasks, not sprites.
AnimCallbacks.HorizontalLunge = nil

function AnimCallbacks.get(name)
  if not name then return AnimCallbacks.HitSplatBasic end
  return AnimCallbacks[name] or AnimCallbacks.SimpleFadeOut
end

return AnimCallbacks
