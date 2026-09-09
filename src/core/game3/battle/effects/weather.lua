local Capabilities = require("src.core.game3.battle.capabilities")
local H = require("src.core.game3.battle.effects._helpers")

local Weather = {}

local function set(ctx, kind, text)
  ctx.adapter:setWeather(kind, Capabilities.weatherDefaultTurns)
  ctx.adapter:say(text)
end

function Weather.sunny(ctx) set(ctx, "SUNNY", "The sunlight\nturned harsh!") end
function Weather.rainy(ctx) set(ctx, "RAINY", "It started\nto rain!") end
function Weather.sandstorm(ctx) set(ctx, "SANDSTORM", "A sandstorm\nkicked up!") end
function Weather.hail(ctx) set(ctx, "HAIL", "It started\nto hail!") end

return Weather
