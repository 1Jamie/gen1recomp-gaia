-- Hazards (FRLG Spikes only; Gen4+ not registered).

local H = require("src.core.game3.battle.effects._helpers")

local Hazards = {}

function Hazards.spikes(ctx)
  local side = H.foeSide(ctx)
  if not side then return H.sayFail(ctx) end
  side.hazards = side.hazards or {}
  local h = H.findHazard(ctx.adapter, side, "SPIKES")
  if h then
    if (h.layers or 1) >= 3 then return H.sayFail(ctx) end
    h.layers = (h.layers or 1) + 1
  else
    side.hazards[#side.hazards + 1] = { id = "SPIKES", layers = 1 }
  end
  ctx.adapter:say("SPIKES scattered all\naround the foe's side!")
end

return Hazards
