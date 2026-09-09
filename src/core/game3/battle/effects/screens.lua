-- Screens (FRLG Reflect / Light Screen / Safeguard only).

local Capabilities = require("src.core.game3.battle.capabilities")
local H = require("src.core.game3.battle.effects._helpers")

local Screens = {}

function Screens.safeguard(ctx)
  local side = H.ownSide(ctx)
  if not side then return H.sayFail(ctx) end
  if (side.expSafeguardTurns or 0) > 0 then return H.sayFail(ctx) end
  side.expSafeguardTurns = Capabilities.safeguardDefaultTurns
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. "'s team became\ncloaked in a mystic veil!")
end

function Screens.reflect(ctx)
  local side = H.ownSide(ctx)
  if not side then return H.sayFail(ctx) end
  if (side.expReflectTurns or 0) > 0 then return H.sayFail(ctx) end
  side.expReflectTurns = Capabilities.screenDefaultTurns
  ctx.adapter:say("REFLECT raised\n" .. H.displayName(ctx, ctx.user) .. "'s DEFENSE!")
end

function Screens.lightScreen(ctx)
  local side = H.ownSide(ctx)
  if not side then return H.sayFail(ctx) end
  if (side.expLightScreenTurns or 0) > 0 then return H.sayFail(ctx) end
  side.expLightScreenTurns = Capabilities.screenDefaultTurns
  ctx.adapter:say("LIGHT SCREEN raised\n" .. H.displayName(ctx, ctx.user) .. "'s SP. DEF!")
end

function Screens.mist(ctx)
  local side = H.ownSide(ctx)
  if not side then return H.sayFail(ctx) end
  if (side.expMistTurns or 0) > 0 then return H.sayFail(ctx) end
  side.expMistTurns = 5
  ctx.adapter:say(H.displayName(ctx, ctx.user) .. "'s side became\nshrouded in MIST!")
end

return Screens
