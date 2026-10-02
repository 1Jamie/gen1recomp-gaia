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
    if type(old) ~= "function" then return end
    samples[label] = samples[label] or {}
    owner[key] = function(...)
      local t = love.timer.getTime()
      local a, b, c = old(...)
      local ms = (love.timer.getTime() - t) * 1000
      local args = { ... }
      if not onlySeams or (args[4] and args[4].seamless) then
        local v = samples[label]; v[#v + 1] = ms
        if label == "objects" or label == "ghost_spawn" or label == "field_cells" then
          local route = (label == "field_cells" and owner._cellPreparationRoute) or owner._lastPreparationRoute or "sync"
          local name = label .. "_" .. route
          samples[name] = samples[name] or {}; samples[name][#samples[name] + 1] = ms
          if label == "objects" then print(string.format("OBJECT_RELOAD map=%s count=%s ms=%.3f route=%s", tostring(args[2]), tostring(a), ms, route)) end
          if label == "field_cells" then
            local id = require("src.core.game3.map").current
            if owner._profileMap ~= id then
              owner._profileMap = id
              local Plan = package.loaded["src.core.game3.field_plan"] or {}
              print(string.format("VOID_TRANSITION map=%s ms=%.3f route=%s fade=%s miss=%s graph=%s", tostring(id), ms, route,
                tostring(owner._voidFrom and owner._voidFrom.t), tostring(Plan._lastMiss), tostring(Plan._graphMiss)))
            end
          end
        end
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
  local Objects = require("src.core.game3.objects")
  wrap(Objects, "loadMap", "objects")
  wrap(Objects, "spawnFromDefs", "ghost_spawn")
  local hasPlan, Plan = pcall(require, "src.core.game3.field_plan")
  if hasPlan then wrap(Plan, "prefetch", "plan_snapshot") end
  wrap(require("src.core.game3.field_view"), "draw", "field_cells")
  run(game)
  for label, v in pairs(samples) do print("SEAM_PROFILE " .. label .. " " .. stats(v)) end
end
