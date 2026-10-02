local run = require("tests.drivers.game3_seam_walk_stress")
local function stats(v)
  table.sort(v)
  local sum = 0; for _, n in ipairs(v) do sum = sum + n end
  return string.format("n=%d mean=%.3f p99=%.3f max=%.3f", #v, sum / math.max(1, #v), v[math.ceil(#v * .99)] or 0, v[#v] or 0)
end
return function(game)
  local samples = { update = {}, draw = {}, seam = {}, pair = {}, sprite = {} }
  local function wrap(owner, key, label, onlySeams)
    local old = owner[key]
    owner[key] = function(...)
      local t = love.timer.getTime()
      local a, b, c = old(...)
      local ms = (love.timer.getTime() - t) * 1000
      local args = { ... }
      if not onlySeams or (args[4] and args[4].seamless) then
        local v = samples[label]; v[#v + 1] = ms
        if (label == "pair" or label == "sprite") and ms > 1 then
          print(string.format("SEAM_ASSET_STALL %s id=%s ms=%.3f", label, tostring(args[1]), ms))
        end
      end
      return a, b, c
    end
  end
  wrap(game, "update", "update")
  wrap(game, "draw", "draw")
  wrap(require("src.core.game3.map"), "load", "seam", true)
  wrap(require("src.core.game3.tileset_native"), "get", "pair")
  wrap(require("src.core.game3.ow_sprites"), "get", "sprite")
  run(game)
  for label, v in pairs(samples) do print("SEAM_PROFILE " .. label .. " " .. stats(v)) end
end
