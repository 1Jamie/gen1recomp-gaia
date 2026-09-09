-- End-of-turn residual scheduler (owned game3).

local Rules = require("src.core.game3.battle.rules")
local EffectCtx = require("src.core.game3.battle.effect_ctx")

local Residuals = {}

local handlers = {}

function Residuals.register(phase, fn)
  handlers[phase] = handlers[phase] or {}
  handlers[phase][#handlers[phase] + 1] = fn
end

function Residuals.clear()
  handlers = {}
end

local function runPhaseList(adapter, battler, phase, list)
  if not list then return end
  local opts = EffectCtx.borrowOpts(phase)
  for _, fn in ipairs(list) do
    if battler and adapter:isFainted(battler) then break end
    if adapter:isBattleDecided() then return end
    local ctx = EffectCtx.push(adapter, nil, battler, nil, nil, adapter:rng(), opts)
    fn(ctx)
    EffectCtx.pop()
    if battler and adapter:isFainted(battler) then
      adapter:emitFaint(battler)
      if Rules.shouldHaltBattlerOnFaint(phase) then
        break
      end
    end
  end
end

function Residuals.runTurn(adapter)
  if not adapter then return end
  if adapter:isBattleDecided() then return end
  for _, phase in ipairs(Rules.phaseOrder()) do
    if adapter:isBattleDecided() then return end
    local list = handlers[phase]
    if Rules.isFieldPhase(phase) then
      runPhaseList(adapter, nil, phase, list)
    else
      for _, battler in ipairs(adapter:activeBattlers()) do
        if not adapter:isFainted(battler) then
          runPhaseList(adapter, battler, phase, list)
        end
      end
    end
  end
end

return Residuals
