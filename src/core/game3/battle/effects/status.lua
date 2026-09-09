local Rules = require("src.core.game3.battle.rules")
local H = require("src.core.game3.battle.effects._helpers")

local Status = {}

function Status.burn(ctx)
  if Rules.substitute.blocks("burn", ctx.target, ctx.adapter) then return H.sayFail(ctx) end
  if ctx.adapter:applyStatus(ctx.target, "BRN", ctx.user, { moveType = ctx.move and ctx.move.type }) then
    ctx.adapter:say(H.displayName(ctx, ctx.target) .. " was burned!")
  else
    H.sayFail(ctx)
  end
end

function Status.poison(ctx)
  if Rules.substitute.blocks("status", ctx.target, ctx.adapter) then return H.sayFail(ctx) end
  if ctx.adapter:applyStatus(ctx.target, "PSN", ctx.user, {}) then
    ctx.adapter:say(H.displayName(ctx, ctx.target) .. " was poisoned!")
  else
    H.sayFail(ctx)
  end
end

function Status.toxic(ctx)
  if Rules.substitute.blocks("status", ctx.target, ctx.adapter) then return H.sayFail(ctx) end
  if ctx.adapter:applyStatus(ctx.target, "TOX", ctx.user, {}) then
    ctx.target.toxicCounter = 0
    ctx.adapter:say(H.displayName(ctx, ctx.target) .. " was badly\npoisoned!")
  else
    H.sayFail(ctx)
  end
end

function Status.sleep(ctx)
  if Rules.substitute.blocks("status", ctx.target, ctx.adapter) then return H.sayFail(ctx) end
  if ctx.adapter:applyStatus(ctx.target, "SLP", ctx.user, {}) then
    ctx.adapter:say(H.displayName(ctx, ctx.target) .. " fell asleep!")
  else
    H.sayFail(ctx)
  end
end

function Status.paralyze(ctx)
  if Rules.substitute.blocks("status", ctx.target, ctx.adapter) then return H.sayFail(ctx) end
  if ctx.adapter:applyStatus(ctx.target, "PAR", ctx.user, {}) then
    ctx.adapter:say(H.displayName(ctx, ctx.target) .. " is paralyzed!\nIt may be unable to move!")
  else
    H.sayFail(ctx)
  end
end

function Status.taunt(ctx)
  if Rules.substitute.blocks("taunt", ctx.target, ctx.adapter) then return H.sayFail(ctx) end
  ctx.target.expTauntedTurns = 3
  ctx.adapter:say(H.displayName(ctx, ctx.target) .. " fell for\nthe TAUNT!")
end

function Status.yawn(ctx)
  if Rules.substitute.blocks("yawn", ctx.target, ctx.adapter) then return H.sayFail(ctx) end
  if ctx.adapter:status(ctx.target) then return H.sayFail(ctx) end
  if ctx.target.expYawnTurns then return H.sayFail(ctx) end
  ctx.target.expYawnTurns = 2
  ctx.adapter:say(H.displayName(ctx, ctx.target) .. " grew\ndrowsy!")
end

return Status
