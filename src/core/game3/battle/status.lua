-- Status inflict + EOT chip (owned; KR left this to host engines).

local Status = {}

local function status_of(battler)
  return battler and (battler.status or (battler.mon and battler.mon.status))
end

function Status.set(battler, status)
  if not battler then return end
  battler.status = status
  if battler.mon then battler.mon.status = status end
end

function Status.clear(battler)
  Status.set(battler, nil)
end

--- End-of-turn burn / poison / toxic chip. Returns list of message strings.
function Status.tickChip(battler, adapter)
  local msgs = {}
  if not battler or adapter:isFainted(battler) then return msgs end
  local st = status_of(battler)
  if not st then return msgs end
  local maxHp = adapter:maxHp(battler)
  local name = adapter:displayName(battler)
  local loss = 0
  if st == "BRN" or st == "burn" then
    loss = math.max(1, math.floor(maxHp / 8))
    adapter:applyHpLoss(battler, loss)
    msgs[#msgs + 1] = name .. " is hurt by its burn!"
  elseif st == "PSN" or st == "poison" then
    loss = math.max(1, math.floor(maxHp / 8))
    adapter:applyHpLoss(battler, loss)
    msgs[#msgs + 1] = name .. " is hurt by poison!"
  elseif st == "TOX" or st == "toxic" then
    battler.toxicCounter = (battler.toxicCounter or 0) + 1
    loss = math.max(1, math.floor(maxHp * battler.toxicCounter / 16))
    adapter:applyHpLoss(battler, loss)
    msgs[#msgs + 1] = name .. " is hurt by poison!"
  end
  if adapter:isFainted(battler) then
    msgs[#msgs + 1] = name .. " fainted!"
    adapter:emitFaint(battler)
  end
  return msgs
end

--- Simple status-move stage changes for MVP. Returns message or nil.
function Status.applySetupMove(user, target, moveId, adapter)
  local Moves = require("src.core.game3.battle.moves")
  local id = Moves.normalizeId(moveId)
  if id == "GROWL" then
    adapter:changeStages(target, { attack = -1 })
    return adapter:displayName(target) .. "'s ATTACK fell!"
  elseif id == "TAIL_WHIP" or id == "LEER" then
    adapter:changeStages(target, { defense = -1 })
    return adapter:displayName(target) .. "'s DEFENSE fell!"
  elseif id == "HARDEN" then
    adapter:changeStages(user, { defense = 1 })
    return adapter:displayName(user) .. "'s DEFENSE rose!"
  elseif id == "CALM_MIND" then
    adapter:changeStages(user, { spAtk = 1, spDef = 1 })
    return adapter:displayName(user) .. "'s stats rose!"
  elseif id == "BULK_UP" then
    adapter:changeStages(user, { attack = 1, defense = 1 })
    return adapter:displayName(user) .. "'s stats rose!"
  elseif id == "DRAGON_DANCE" then
    adapter:changeStages(user, { attack = 1, speed = 1 })
    return adapter:displayName(user) .. "'s stats rose!"
  end
  return nil
end

return Status
