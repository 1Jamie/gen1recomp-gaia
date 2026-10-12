package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

package.loaded["src.core.game3.prewarm"] = { session = function() end }

local GameVersion = require("src.core.GameVersion")
local Rng = require("src.core.game3.rng")
local Roamer = require("src.core.game3.roamer")
local Runtime = require("src.core.game3.runtime")
local Schema = require("src.core.game3.save_schema_firered")
local Space = require("src.core.game3.scripting.space")
local Game3 = require("src.core.Game3")
local RseInit = require("src.core.game3.rse.init")

local realStart, realPerturb, realReturn = Runtime.start, Rng.perturb, Space.runOnReturnToField
local atMapLoad
Runtime.start = function(_, _, session)
  atMapLoad = session.roamer and { map = session.roamer.map, history = { unpack(session.roamer.history or {}) } }
end
Rng.perturb = function() return realPerturb(0x55) end
Space.runOnReturnToField = function() end

local FIXTURE = {
  firered = {
    { "FR_ROUTE_1", "FR_ROUTE_2", "FR_ROUTE_21_NORTH", "FR_ROUTE_22", false, false, false },
    { "FR_ROUTE_2", "FR_ROUTE_1", "FR_ROUTE_3", "FR_ROUTE_22", false, false, false },
    { "FR_ROUTE_3", "FR_ROUTE_2", "FR_ROUTE_4", false, false, false, false },
    { "FR_ROUTE_22", "FR_ROUTE_1", "FR_ROUTE_2", "FR_ROUTE_23", false, false, false },
  },
  emerald = {
    { "EM_ROUTE110", "EM_ROUTE111", "EM_ROUTE117", "EM_ROUTE118", "EM_ROUTE134", false },
    { "EM_ROUTE111", "EM_ROUTE110", "EM_ROUTE117", "EM_ROUTE118", false, false },
    { "EM_ROUTE117", "EM_ROUTE111", "EM_ROUTE110", "EM_ROUTE118", false, false },
    { "EM_ROUTE119", "EM_ROUTE118", "EM_ROUTE120", false, false, false },
    { "EM_ROUTE120", "EM_ROUTE119", "EM_ROUTE121", false, false, false },
  },
  ruby = {
    { "RS_ROUTE110", "RS_ROUTE111", "RS_ROUTE117", "RS_ROUTE118", "RS_ROUTE134", false },
    { "RS_ROUTE111", "RS_ROUTE110", "RS_ROUTE117", "RS_ROUTE118", false, false },
    { "RS_ROUTE117", "RS_ROUTE111", "RS_ROUTE110", "RS_ROUTE118", false, false },
  },
}

local function fake_game()
  local g = setmetatable({ options = {} }, { __index = Game3 })
  local enter = g._enterField
  g._enterField = function(self, ...)
    local realCall = RseInit.call
    RseInit.call = function() end
    enter(self, ...)
    RseInit.call = realCall
  end
  return g
end

local function save_for(version, seed, roamer)
  Rng.SeedRng(seed)
  Rng.SeedRng2(seed + 1)
  Rng.SeedWildEncounterRng(seed + 2)
  return {
    engine = "game3", version = version, map = roamer.saveMap, x = 5, y = 5, facing = "down",
    name = "RED", trainerId = 1, secretId = 2, rng = Rng.getState(),
    roamer = { species = 244, level = 50, active = roamer.active, map = roamer.map,
      history = { roamer.h1, roamer.h2, roamer.h3 }, hp = 150, status = 0, ivs = 0 },
  }
end

local function expect_head(version, save)
  local sets = FIXTURE[version]
  Rng.setState(save.rng)
  if Schema.rulesFor(version).PERTURB_FIELD_RNG ~= false then realPerturb(0x55) end
  return sets[(Rng.Random() % #sets) + 1][1], Rng.getState().value
end

local function run(version, seed, roamer)
  GameVersion.set(version)
  local session = Schema.fromSaveTable(save_for(version, seed, roamer))
  Roamer._locations[Roamer.config(session)] = FIXTURE[version]
  atMapLoad = nil
  fake_game():_enterField(session, "continue")
  return session
end

for _, version in ipairs({ "firered", "emerald", "ruby" }) do
  local sets = FIXTURE[version]
  local saveMap, roamerMap, h1 = sets[3][3], sets[3][1], sets[2][1]
  local fromSaveOnly = Schema.fromSaveTable(save_for(version, 0x4242, {
    saveMap = saveMap, active = true, map = roamerMap, h1 = h1, h2 = sets[1][1], h3 = sets[2][1] }))
  eq(fromSaveOnly.roamer.map, roamerMap, version .. " loading a save table alone keeps the roamer map")
  eq(Rng.getState().value, 0x4242, version .. " loading a save table alone draws no Random()")

  local moved, kept, total = 0, 0, 0
  for seed = 1, 300 do
    local roamer = { saveMap = saveMap, active = true, map = roamerMap, h1 = h1, h2 = sets[1][1], h3 = sets[2][1] }
    local want, wantRng = expect_head(version, save_for(version, seed, roamer))
    local session = run(version, seed, roamer)
    local r = session.roamer
    total = total + 1
    if r.map == want and Rng.getState().value == wantRng then moved = moved + 1 end
    if want == roamerMap and r.map == roamerMap then kept = kept + 1 end
    if seed == 1 then
      eq(r.history[1], saveMap, version .. " continue pushes the saved map into a cleared history")
      eq(r.history[2], false, version .. " continue clears history slot 2")
      eq(r.history[3], false, version .. " continue clears history slot 3")
      eq(atMapLoad and atMapLoad.map, r.map, version .. " roamer moves before the saved map loads")
    end
  end
  eq(moved, total, version .. " continue re-rolls to Random() % sets of the continue-time RNG in one draw")
  check(kept > 0, version .. " a draw landing on the saved set head keeps it (location cleared at boot)")

  local session = run(version, 7, { saveMap = saveMap, active = false, map = roamerMap, h1 = h1 })
  local noDraw = Rng.getState().value
  Rng.setState(save_for(version, 7, { saveMap = saveMap }).rng)
  if Schema.rulesFor(version).PERTURB_FIELD_RNG ~= false then realPerturb(0x55) end
  eq(noDraw, Rng.getState().value, version .. " an inactive roamer draws no Random() on continue")
  eq(session.roamer.history[1], saveMap, version .. " an inactive roamer still records the saved map")

  GameVersion.set(version)
  local fresh = Schema.fromSaveTable(save_for(version, 9, { saveMap = saveMap, active = true, map = roamerMap, h1 = h1 }))
  Roamer._locations[Roamer.config(fresh)] = FIXTURE[version]
  fake_game():_enterField(fresh, "new_game")
  eq(fresh.roamer.map, roamerMap, version .. " new game entry leaves the roamer alone")
end

Runtime.start, Rng.perturb, Space.runOnReturnToField = realStart, realPerturb, realReturn
T.finish("game3 roamer continue")
