local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")
local M = require("tests.drivers.em_misc_util")

local d = S.new("em_routes_132_134", "/tmp/em_routes_132_134")

local function mod(name) return require(name) end

return function(game)
  local session = M.boot(game, d)
  if not session then return d.finish() end
  local Collision = mod("src.core.game3.collision")
  local Player = mod("src.core.game3.player")
  local Encounters = mod("src.core.game3.encounters")
  Encounters.onStep = function() return nil end
  session.party = {}
  S.giveMon("SPECIES_SWAMPERT", 80, { "MOVE_SURF", "MOVE_WATERFALL", "MOVE_DIVE", "MOVE_EARTHQUAKE" })
  for i = 1, 8 do S.setFlag(string.format("FLAG_BADGE0%d_GET", i), true) end
  S.canSurf = true

  M.goTo(game, "EM_PACIFIDLOG_TOWN", 10, 10, "left")
  local sx, sy
  for x = 1, 8 do
    for y = 1, 38 do
      if not sx and Collision.isWater(x, y) and Collision.isSurfable(Collision.behavior(x, y)) then sx, sy = x, y end
    end
  end
  d.check(sx ~= nil, "Pacifidlog has open water on its west side (" .. tostring(sx) .. "," .. tostring(sy) .. ")")
  M.goTo(game, "EM_PACIFIDLOG_TOWN", sx, sy, "left")
  Player.surfing = true
  U.wait(20)
  d.shot(game, "01_pacifidlog")

  local visited = {}
  local chain = { "EM_ROUTE132", "EM_ROUTE133", "EM_ROUTE134", "EM_SLATEPORT_CITY" }
  for i, m in ipairs(chain) do
    local ok = S.travel(game, { m }, { repel = false })
    visited[#visited + 1] = S.mapNow()
    d.check(ok and S.mapNow() == m, "surfed into " .. m .. " (" .. tostring(S.mapNow()) .. " " .. Player.cellX .. "," .. Player.cellY .. ")")
    d.shot(game, string.format("%02d_%s", i + 1, m:lower()))
    if S.mapNow() ~= m then break end
  end
  d.finish()
end
