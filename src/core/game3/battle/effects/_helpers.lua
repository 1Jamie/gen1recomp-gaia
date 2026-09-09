-- Effect helpers (owned; no src.core.Strings / no KR).

local H = {}

function H.displayName(ctx, battler)
  return ctx.adapter:displayName(battler)
end

function H.sayFail(ctx)
  ctx.adapter:sayFail()
end

function H.ownSide(ctx)
  return ctx.adapter:ownSide(ctx.user)
end

function H.foeSide(ctx)
  return ctx.adapter:foeSide(ctx.user)
end

function H.findHazard(adapter, side, id)
  if adapter.findHazard then return adapter:findHazard(side, id) end
  if not side or not side.hazards then return nil end
  for _, h in ipairs(side.hazards) do
    if h.id == id then return h end
  end
  return nil
end

function H.hasType(ctx, battler, typeId)
  local types = ctx.adapter:types(battler) or {}
  local Types = require("src.core.game3.battle.types")
  local want = typeId
  if type(typeId) == "number" then
    want = Types.name(typeId)
  end
  for _, t in ipairs(types) do
    if t == want or t == typeId then return true end
  end
  -- Also check raw battler type ids.
  if battler then
    if battler.type1 == typeId or battler.type2 == typeId then return true end
  end
  return false
end

function H.lastMove(ctx, battler)
  if not battler then return nil end
  if ctx.adapter.lastMoveOf then
    return ctx.adapter:lastMoveOf(battler)
  end
  return battler.lastMoveId or battler.lastMove
end

function H.preparedMoves(ctx, battler)
  local mon = ctx.adapter:mon(battler)
  if not mon then return {} end
  local out = {}
  for i = 1, 4 do
    local id = mon.moves and mon.moves[i]
    if id then
      out[#out + 1] = { id = id, pp = mon.pp and mon.pp[i] or 0, slot = i }
    end
  end
  return out
end

return H
