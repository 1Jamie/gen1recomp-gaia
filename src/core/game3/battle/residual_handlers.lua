-- Owned residual handlers (game3 owns status/weather/volatiles — not host).

local Residuals = require("src.core.game3.battle.residuals")
local Rules = require("src.core.game3.battle.rules")
local StatusChip = require("src.core.game3.battle.status")

local Handlers = {}
Handlers._installed = false

function Handlers.registerAll()
  if Handlers._installed then return end
  Handlers._installed = true

  Residuals.register("weather_continue", function(ctx)
    if ctx.adapter.tickWeather then
      ctx.adapter:tickWeather()
    end
  end)
  Residuals.register("weather_chip", function(_ctx) end)
  Residuals.register("weather_tick", function(_ctx) end)

  Residuals.register("status_chip", function(ctx)
    local b = ctx.target
    if not b then return end
    local msgs = StatusChip.tickChip(b, ctx.adapter)
    for _, m in ipairs(msgs) do
      ctx.adapter:say(m)
    end
  end)

  Residuals.register("leech_seed", function(ctx)
    local b = ctx.target
    if not b or not b.expSeeded then return end
    if ctx.adapter:isFainted(b) then return end
    local dmg = math.max(1, math.floor(ctx.adapter:maxHp(b) / 8))
    ctx.adapter:applyHpLoss(b, dmg)
    ctx.adapter:say(ctx.adapter:displayName(b) .. "'s health is\nsapped by LEECH SEED!")
    local src = b.expSeedSource
    if src and not ctx.adapter:isFainted(src) then
      ctx.adapter:heal(src, dmg)
    end
  end)

  Residuals.register("partial_trap_chip", function(ctx)
    local b = ctx.target
    if not b or not b.expTrapTurns then return end
    if not Rules.partialTrap.active() then return end
    local turns = b.expTrapTurns
    if turns <= 0 then
      b.expTrapTurns = nil
      b.expTrapMove = nil
      ctx.adapter:say(ctx.adapter:displayName(b) .. " was freed\nfrom " .. tostring(b.expTrapMoveName or "the bind") .. "!")
      return
    end
    local dmg = Rules.partialTrap.chipAmount(ctx.adapter:maxHp(b))
    ctx.adapter:applyHpLoss(b, dmg)
    ctx.adapter:say(ctx.adapter:displayName(b) .. " is hurt\nby " .. tostring(b.expTrapMoveName or "BIND") .. "!")
    b.expTrapTurns = turns - 1
    if b.expTrapTurns <= 0 then
      b.expTrapTurns = nil
      ctx.adapter:say(ctx.adapter:displayName(b) .. " was freed!")
    end
  end)

  Residuals.register("partial_trap_tick", function(_ctx) end)

  Residuals.register("volatiles", function(ctx)
    local b = ctx.target
    if not b then return end
    b.expJustEntered = nil

    if b.expTauntedTurns and b.expTauntedTurns > 0 then
      b.expTauntedTurns = b.expTauntedTurns - 1
      if b.expTauntedTurns <= 0 then b.expTauntedTurns = nil end
    end

    if b.expEncoreTurns and b.expEncoreTurns > 0 then
      b.expEncoreTurns = b.expEncoreTurns - 1
      if b.expEncoreTurns <= 0 then
        b.expEncoreTurns = nil
        b.expEncoreMove = nil
        ctx.adapter:say(ctx.adapter:displayName(b) .. "'s ENCORE\nended!")
      end
    end

    if b.expYawnTurns and b.expYawnTurns > 0 then
      b.expYawnTurns = b.expYawnTurns - 1
      if b.expYawnTurns <= 0 then
        b.expYawnTurns = nil
        if ctx.adapter:hp(b) > 0 and not ctx.adapter:status(b) then
          ctx.adapter:applyStatus(b, "sleep", nil, { source = "YAWN" })
          ctx.adapter:say(ctx.adapter:displayName(b) .. " fell asleep!")
        end
      end
    end

    if b.expCursed and ctx.adapter:hp(b) > 0 then
      local dmg = math.max(1, math.floor(ctx.adapter:maxHp(b) / 4))
      ctx.adapter:applyHpLoss(b, dmg)
      ctx.adapter:say(ctx.adapter:displayName(b) .. " is afflicted\nby the CURSE!")
    end

    if b.expNightmare and ctx.adapter:hp(b) > 0 then
      if not ctx.adapter:hasStatus(b, "SLP", "sleep") then
        b.expNightmare = nil
      else
        local dmg = math.max(1, math.floor(ctx.adapter:maxHp(b) / 4))
        ctx.adapter:applyHpLoss(b, dmg)
        ctx.adapter:say(ctx.adapter:displayName(b) .. " is locked\nin a NIGHTMARE!")
      end
    end

    if b.expPerishTurns and ctx.adapter:hp(b) > 0 then
      b.expPerishTurns = b.expPerishTurns - 1
      ctx.adapter:say(string.format("%s's perish count\nfell to %d!",
        ctx.adapter:displayName(b), b.expPerishTurns))
      if b.expPerishTurns <= 0 then
        b.expPerishTurns = nil
        ctx.adapter:applyHpLoss(b, ctx.adapter:hp(b))
        if ctx.adapter:isFainted(b) then
          ctx.adapter:say(ctx.adapter:displayName(b) .. " fainted!")
          ctx.adapter:emitFaint(b)
        end
      end
    end

    if ctx.adapter:hp(b) > 0 and b.expIngrain then
      local maxHp = ctx.adapter:maxHp(b)
      local cur = ctx.adapter:hp(b)
      if cur < maxHp then
        local heal = math.max(1, math.floor(maxHp / 16))
        ctx.adapter:heal(b, math.min(heal, maxHp - cur))
        ctx.adapter:say(ctx.adapter:displayName(b) .. " absorbed\nnutrients with its roots!")
      end
    end

    -- Tick side tokens once per turn (player battler residual only).
    if b.side == "player" then
      local function tick_tokens(side, healTarget, damageTarget)
        if not side or not side.tokens then return end
        local keep = {}
        for _, tok in ipairs(side.tokens) do
          tok.turns = (tok.turns or 1) - 1
          if tok.turns <= 0 then
            if tok.id == "EXP_WISH" and tok.heal and healTarget
                and ctx.adapter:hp(healTarget) > 0 then
              ctx.adapter:heal(healTarget, tok.heal)
              ctx.adapter:say(ctx.adapter:displayName(healTarget) .. "'s wish\ncame true!")
            elseif tok.id == "EXP_FUTURE_SIGHT" and tok.damage and damageTarget
                and ctx.adapter:hp(damageTarget) > 0 then
              ctx.adapter:applyHpLoss(damageTarget, tok.damage)
              ctx.adapter:say(ctx.adapter:displayName(damageTarget) .. " took\nthe Future Sight attack!")
            end
          else
            keep[#keep + 1] = tok
          end
        end
        side.tokens = keep
      end
      local pSide = ctx.adapter:ownSide(b)
      local eSide = ctx.adapter:foeSide(b)
      local foe = ctx.adapter:foeOf(b)
      tick_tokens(pSide, b, foe)   -- Wish on player side; Future Sight rare here
      tick_tokens(eSide, foe, b)   -- Future Sight on foe side hits player; Wish if foe set it
    end

    -- Side timers
    local side = ctx.adapter:ownSide(b)
    if side then
      if side.expSafeguardTurns and side.expSafeguardTurns > 0 then
        side.expSafeguardTurns = side.expSafeguardTurns - 1
        if side.expSafeguardTurns <= 0 then side.expSafeguardTurns = nil end
      end
      if side.expReflectTurns and side.expReflectTurns > 0 then
        side.expReflectTurns = side.expReflectTurns - 1
        if side.expReflectTurns <= 0 then side.expReflectTurns = nil end
      end
      if side.expLightScreenTurns and side.expLightScreenTurns > 0 then
        side.expLightScreenTurns = side.expLightScreenTurns - 1
        if side.expLightScreenTurns <= 0 then side.expLightScreenTurns = nil end
      end
      if side.expMistTurns and side.expMistTurns > 0 then
        side.expMistTurns = side.expMistTurns - 1
        if side.expMistTurns <= 0 then side.expMistTurns = nil end
      end
    end
  end)

  Residuals.register("held_items", function(_ctx) end)
  Residuals.register("abilities_eot", function(_ctx) end)
end

return Handlers
