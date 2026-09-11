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

local function battlerSpeed(battler)
  if not battler then return 0 end
  local mon = battler.mon
  local spe = tonumber(mon and (mon.speed or mon.spe)) or 50
  if battler.stages and battler.stages.speed then
    local Damage = require("src.core.game3.battle.damage")
    spe = spe * Damage.stageMul(battler.stages.speed)
  end
  return spe
end

local function sortedBattlers(adapter)
  local list = adapter:activeBattlers() or {}
  table.sort(list, function(a, b)
    local speA = battlerSpeed(a)
    local speB = battlerSpeed(b)
    if speA ~= speB then
      return speA > speB
    end
    return (a.side == "player")
  end)
  return list
end

local function runStepAndRecord(adapter, battler, phase, fn, events)
  if battler and adapter:isFainted(battler) then return false end
  if adapter:isBattleDecided() then return false end

  local active = adapter:activeBattlers() or {}
  local hpBefore = {}
  for _, b in ipairs(active) do
    if b and b.side then
      hpBefore[b.side] = adapter:hp(b)
    end
  end

  local capturedMsgs = {}
  local prevSay = adapter._say
  adapter._say = function(text)
    capturedMsgs[#capturedMsgs + 1] = tostring(text or "")
  end

  local opts = EffectCtx.borrowOpts(phase)
  local ctx = EffectCtx.push(adapter, nil, battler, nil, nil, adapter:rng(), opts)
  fn(ctx)
  EffectCtx.pop()

  adapter._say = prevSay

  local hpChanges = {}
  local faints = {}
  for _, b in ipairs(active) do
    if b and b.side then
      local before = hpBefore[b.side] or 0
      local after = adapter:hp(b)
      if before ~= after then
        hpChanges[#hpChanges + 1] = {
          side = b.side,
          from = before,
          to = after,
          maxHp = adapter:maxHp(b),
        }
      end
      if adapter:isFainted(b) and before > 0 then
        faints[#faints + 1] = { side = b.side }
        adapter:emitFaint(b)
      end
    end
  end

  if #capturedMsgs > 0 or #hpChanges > 0 or #faints > 0 then
    events[#events + 1] = {
      phase = phase,
      target = battler,
      msgs = capturedMsgs,
      hpChanges = hpChanges,
      faints = faints,
    }
  end

  if battler and adapter:isFainted(battler) then
    if Rules.shouldHaltBattlerOnFaint(phase) then
      return true
    end
  end
  return false
end

function Residuals.collectEvents(adapter)
  local events = {}
  if not adapter or adapter:isBattleDecided() then return events end

  for _, phase in ipairs(Rules.phaseOrder()) do
    if adapter:isBattleDecided() then break end
    local list = handlers[phase]
    if list and #list > 0 then
      if Rules.isFieldPhase(phase) then
        for _, fn in ipairs(list) do
          if adapter:isBattleDecided() then break end
          runStepAndRecord(adapter, nil, phase, fn, events)
        end
      else
        local battlers = sortedBattlers(adapter)
        for _, battler in ipairs(battlers) do
          if not adapter:isFainted(battler) then
            for _, fn in ipairs(list) do
              if adapter:isBattleDecided() then break end
              local halt = runStepAndRecord(adapter, battler, phase, fn, events)
              if halt then break end
            end
          end
        end
      end
    end
  end

  return events
end

function Residuals.runTurn(adapter)
  local events = Residuals.collectEvents(adapter)
  return events
end

return Residuals
