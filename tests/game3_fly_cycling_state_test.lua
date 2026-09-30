package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local GameVersion = require("src.core.GameVersion")
local Field = require("src.core.game3.field")
local Player = require("src.core.game3.player")
local Flags = require("src.core.game3.scripting.flags")
local Runtime = require("src.core.game3.runtime")
local Space = require("src.core.game3.scripting.space")
local Map = require("src.core.game3.map")
local realLoad = Map.load
local realHeal = package.loaded["src.core.game3.heal_locations"]
package.loaded["src.core.game3.heal_locations"] = {
  normalizeSession = function() end,
  model = function() return "heal_row" end,
}
Space.runImmediately = function() end

for _, version in ipairs({ "firered", "leafgreen", "emerald" }) do
  GameVersion.set(version)
  local defs = Flags.forVersion(version)
  local roadName = version == "emerald" and "FLAG_SYS_CYCLING_ROAD" or "FLAG_SYS_ON_CYCLING_ROAD"
  local road, scene = assert(defs.IDS[roadName]), defs.VAR_IDS.VAR_MAP_SCENE_ROUTE16
  for _, mode in ipairs({ "fly", "field_move", "whiteout" }) do
    local s = { version = version, flags = {}, vars = {}, party = {},
      store = { flags = {}, vars = {} }, biking = true, bikeType = "mach" }
    local live = { version = version, flags = {}, vars = {},
      store = { flags = {}, vars = {} }, biking = true, bikeType = "acro" }
    local script = { flags = {}, vars = {} }
    local g = { session = s, save = { biking = true, bikeType = "mach", position = { biking = true } } }
    Field._session, Field._game, Runtime.session, Runtime._game, Space.store = s, g, live, g, script
    for _, store in ipairs({ s, s.store, script, live, live.store }) do
      Flags.setFlag(store, nil, road, true)
      store.flags[roadName] = true
      if scene then
        Flags.setVar(store, nil, scene, 1)
        store.vars[tostring(scene)], store.vars.VAR_MAP_SCENE_ROUTE16 = 1, 1
      end
    end
    Player.biking, Player.bikeType, Player.surfing = true, "mach", true
    local loads = 0
    Map.load = function(_, _, mapId)
      loads = loads + 1
      for _, store in ipairs({ s, s.store, script, live, live.store }) do
        T.check(not Flags.getFlag(store, nil, road) and store.flags[roadName] == nil,
          version .. " " .. mode .. " clears road flag before map load")
        if scene then
          T.eq(Flags.getVar(store, nil, scene), 0, version .. " " .. mode .. " resets scene before map load")
          T.eq(store.vars[tostring(scene)], nil, "scene decimal alias cleared")
          T.eq(store.vars.VAR_MAP_SCENE_ROUTE16, nil, "scene symbolic alias cleared")
        end
      end
      T.check(not Player.biking and not s.biking and not live.biking and not g.save.biking
        and not g.save.position.biking, version .. " " .. mode .. " on foot at map load")
      T.check(Player.bikeType == nil and s.bikeType == nil and live.bikeType == nil
        and g.save.bikeType == nil, version .. " " .. mode .. " clears bike type")
      s.map, live.map = mapId, mapId
    end
    local dest = { map = version == "emerald" and "EM_MAUVILLE_CITY" or "FR_CELADON_CITY", x = 1, y = 1 }
    if mode == "fly" then
      Field.flyTo(nil, nil, { dest = dest })
    else
      Field.respawnAtHeal({ fieldMove = mode == "field_move", warp = dest })
    end
    T.eq(loads, 1, version .. " " .. mode .. " loads one destination")
    T.check(not Player.biking and not live.biking and not g.save.biking,
      version .. " " .. mode .. " remains on foot after landing")
  end
end
Map.load = realLoad
package.loaded["src.core.game3.heal_locations"] = realHeal
T.finish("game3_fly_cycling_state")
