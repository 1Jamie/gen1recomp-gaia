local U = require("tests.drivers.util")
local S = require("tests.drivers.em_story_util")

local d = S.new("em_story_seg3", "/tmp/em_story_seg3")

local PRE_SET = {
  "FLAG_HIDE_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F_POKE_BALL", "FLAG_HIDE_LITTLEROOT_TOWN_BRENDANS_HOUSE_RIVAL_MOM",
  "FLAG_HIDE_LITTLEROOT_TOWN_BRENDANS_HOUSE_RIVAL_SIBLING", "FLAG_HIDE_LITTLEROOT_TOWN_BRENDANS_HOUSE_TRUCK",
  "FLAG_HIDE_LITTLEROOT_TOWN_MAYS_HOUSE_2F_POKE_BALL", "FLAG_HIDE_LITTLEROOT_TOWN_MAYS_HOUSE_MOM",
  "FLAG_HIDE_LITTLEROOT_TOWN_MAYS_HOUSE_TRUCK", "FLAG_HIDE_LITTLEROOT_TOWN_PLAYERS_HOUSE_VIGOROTH_1",
  "FLAG_HIDE_LITTLEROOT_TOWN_PLAYERS_HOUSE_VIGOROTH_2", "FLAG_HIDE_ROUTE_101_BIRCH_STARTERS_BAG",
  "FLAG_HIDE_ROUTE_101_BIRCH_ZIGZAGOON_BATTLE", "FLAG_HIDE_ROUTE_101_ZIGZAGOON", "FLAG_MET_RIVAL_MOM",
  "FLAG_RESCUED_BIRCH", "FLAG_RIVAL_LEFT_FOR_ROUTE103", "FLAG_SET_WALL_CLOCK", "FLAG_SYS_CLOCK_SET",
  "FLAG_SYS_POKEMON_GET", "FLAG_SYS_TV_HOME", "FLAG_VISITED_LITTLEROOT_TOWN",
  "FLAG_ADDED_MATCH_CALL_TO_POKENAV", "FLAG_ADVENTURE_STARTED", "FLAG_BADGE01_GET", "FLAG_BADGE02_GET",
  "FLAG_DEFEATED_DEWFORD_GYM", "FLAG_DEFEATED_RIVAL_ROUTE103", "FLAG_DEFEATED_RIVAL_RUSTBORO", "FLAG_DEFEATED_RUSTBORO_GYM",
  "FLAG_DEFEATED_WALLY_MAUVILLE", "FLAG_DELIVERED_DEVON_GOODS", "FLAG_DELIVERED_STEVEN_LETTER",
  "FLAG_DOCK_REJECTED_DEVON_GOODS", "FLAG_ENABLE_BRAWLY_MATCH_CALL",
  "FLAG_ENABLE_MR_STONE_POKENAV", "FLAG_ENABLE_NORMAN_MATCH_CALL", "FLAG_ENABLE_PROF_BIRCH_MATCH_CALL",
  "FLAG_ENABLE_RIVAL_MATCH_CALL", "FLAG_ENABLE_ROXANNE_MATCH_CALL", "FLAG_ENABLE_SCOTT_MATCH_CALL", "FLAG_HAS_MATCH_CALL",
  "FLAG_HIDE_GRANITE_CAVE_STEVEN", "FLAG_HIDE_MAUVILLE_CITY_WALLY", "FLAG_HIDE_MAUVILLE_CITY_WALLYS_UNCLE",
  "FLAG_HIDE_PETALBURG_CITY_WALLYS_MOM", "FLAG_HIDE_PETALBURG_WOODS_AQUA_GRUNT", "FLAG_HIDE_PETALBURG_WOODS_DEVON_EMPLOYEE",
  "FLAG_HIDE_ROUTE_103_RIVAL", "FLAG_HIDE_ROUTE_104_MR_BRINEY_BOAT", "FLAG_HIDE_ROUTE_110_RIVAL", "FLAG_HIDE_ROUTE_110_TEAM_AQUA",
  "FLAG_HIDE_ROUTE_116_WANDAS_BOYFRIEND", "FLAG_HIDE_RUSTBORO_CITY_DEVON_CORP_3F_EMPLOYEE",
  "FLAG_HIDE_RUSTBORO_CITY_POKEMON_SCHOOL_SCOTT", "FLAG_HIDE_SLATEPORT_CITY_OCEANIC_MUSEUM_2F_CAPTAIN_STERN",
  "FLAG_HIDE_SLATEPORT_CITY_OCEANIC_MUSEUM_AQUA_GRUNTS", "FLAG_HIDE_SLATEPORT_CITY_TEAM_AQUA",
  "FLAG_INTERACTED_WITH_DEVON_EMPLOYEE_GOODS_STOLEN", "FLAG_LANDMARK_MR_BRINEY_HOUSE", "FLAG_MET_RIVAL_RUSTBORO",
  "FLAG_MR_BRINEY_SAILING_INTRO", "FLAG_POKERUS_EXPLAINED", "FLAG_RECEIVED_POKEDEX_FROM_BIRCH", "FLAG_RECEIVED_POKENAV",
  "FLAG_RECEIVED_POTION_OLDALE", "FLAG_RECEIVED_RUNNING_SHOES", "FLAG_RECEIVED_TM_BULK_UP", "FLAG_RECEIVED_TM_ROCK_TOMB",
  "FLAG_RECOVERED_DEVON_GOODS", "FLAG_REGISTERED_BRAWLY", "FLAG_REGISTERED_HALEY", "FLAG_REGISTERED_ISABEL",
  "FLAG_REGISTERED_RICKY", "FLAG_REGISTERED_STEVEN_POKENAV", "FLAG_RETURNED_DEVON_GOODS", "FLAG_SYS_B_DASH",
  "FLAG_SYS_POKEDEX_GET", "FLAG_SYS_POKENAV_GET", "FLAG_SYS_TV_START", "FLAG_VISITED_DEWFORD_TOWN",
  "FLAG_VISITED_MAUVILLE_CITY", "FLAG_VISITED_OLDALE_TOWN", "FLAG_VISITED_PETALBURG_CITY", "FLAG_VISITED_RUSTBORO_CITY",
  "FLAG_VISITED_SLATEPORT_CITY",
  "FLAG_DEFEATED_MAUVILLE_GYM", "FLAG_BADGE03_GET", "FLAG_RECEIVED_TM_SHOCK_WAVE", "FLAG_ENABLE_WATTSON_MATCH_CALL",
  "FLAG_BADGE04_GET", "FLAG_BADGE05_GET", "FLAG_BADGE06_GET", "FLAG_DEFEATED_EVIL_TEAM_MT_CHIMNEY",
  "FLAG_DEFEATED_FORTREE_GYM", "FLAG_DEFEATED_LAVARIDGE_GYM", "FLAG_DEFEATED_PETALBURG_GYM",
  "FLAG_ENABLE_FLANNERY_MATCH_CALL", "FLAG_ENABLE_WALLY_MATCH_CALL", "FLAG_ENABLE_WINONA_MATCH_CALL",
  "FLAG_EVIL_LEADER_PLEASE_STOP", "FLAG_HIDE_FORTREE_CITY_KECLEON", "FLAG_HIDE_MAUVILLE_GYM_WATTSON",
  "FLAG_HIDE_METEOR_FALLS_1F_1R_COZMO", "FLAG_HIDE_METEOR_FALLS_TEAM_MAGMA", "FLAG_HIDE_MT_CHIMNEY_TEAM_AQUA",
  "FLAG_HIDE_MT_CHIMNEY_TEAM_MAGMA", "FLAG_HIDE_ROUTE_109_MR_BRINEY", "FLAG_HIDE_ROUTE_109_MR_BRINEY_BOAT",
  "FLAG_HIDE_ROUTE_111_ROCK_SMASH_TIP_GUY", "FLAG_HIDE_ROUTE_112_TEAM_MAGMA", "FLAG_HIDE_ROUTE_118_STEVEN",
  "FLAG_HIDE_ROUTE_119_TEAM_AQUA", "FLAG_HIDE_ROUTE_120_KECLEON_BRIDGE", "FLAG_HIDE_ROUTE_120_KECLEON_BRIDGE_SHADOW",
  "FLAG_HIDE_ROUTE_120_STEVEN", "FLAG_HIDE_RUSTURF_TUNNEL_ROCK_1", "FLAG_HIDE_RUSTURF_TUNNEL_ROCK_2",
  "FLAG_HIDE_RUSTURF_TUNNEL_WANDA", "FLAG_HIDE_RUSTURF_TUNNEL_WANDAS_BOYFRIEND", "FLAG_HIDE_VERDANTURF_TOWN_SCOTT",
  "FLAG_HIDE_VERDANTURF_TOWN_WANDAS_HOUSE_WALLY", "FLAG_HIDE_WEATHER_INSTITUTE_2F_WORKERS", "FLAG_KECLEON_FLED_FORTREE",
  "FLAG_LANDMARK_FIERY_PATH", "FLAG_MET_ARCHIE_METEOR_FALLS", "FLAG_MIRAGE_TOWER_VISIBLE",
  "FLAG_PETALBURG_MART_EXPANDED_ITEMS", "FLAG_RECEIVED_CASTFORM", "FLAG_RECEIVED_DEVON_SCOPE", "FLAG_RECEIVED_GO_GOGGLES",
  "FLAG_RECEIVED_HM_FLY", "FLAG_RECEIVED_HM_ROCK_SMASH", "FLAG_RECEIVED_HM_STRENGTH", "FLAG_RECEIVED_HM_SURF",
  "FLAG_RECEIVED_METEORITE", "FLAG_RECEIVED_TM_AERIAL_ACE", "FLAG_RECEIVED_TM_FACADE", "FLAG_RECEIVED_TM_OVERHEAT",
  "FLAG_REGISTERED_BERNIE", "FLAG_REGISTERED_BROOKE", "FLAG_REGISTERED_CATHERINE", "FLAG_REGISTERED_FLANNERY",
  "FLAG_REGISTERED_ISAAC", "FLAG_REGISTERED_JACKSON", "FLAG_REGISTERED_LYDIA", "FLAG_REGISTERED_MADELINE",
  "FLAG_REGISTERED_NORMAN", "FLAG_REGISTERED_ROSE", "FLAG_REGISTERED_WILTON", "FLAG_REGISTERED_WINONA",
  "FLAG_REGISTERED_WINSTON", "FLAG_RUSTURF_TUNNEL_OPENED", "FLAG_SCOTT_CALL_FORTREE_GYM", "FLAG_SYS_TV_WATCH",
  "FLAG_VISITED_FALLARBOR_TOWN", "FLAG_VISITED_FORTREE_CITY", "FLAG_VISITED_LAVARIDGE_TOWN", "FLAG_VISITED_VERDANTURF_TOWN",
  "FLAG_RECEIVED_BIKE",
}
local PRE_CLEAR = {
  "FLAG_HIDE_LITTLEROOT_TOWN_BIRCHS_LAB_BIRCH", "FLAG_HIDE_LITTLEROOT_TOWN_FAT_MAN", "FLAG_HIDE_ROUTE_101_BOY",
  "FLAG_HIDE_ROUTE_116_DEVON_EMPLOYEE", "FLAG_HIDE_SLATEPORT_MUSEUM_POPULATION",
  "FLAG_HIDE_VERDANTURF_TOWN_WANDAS_HOUSE_WALLYS_UNCLE",
  "FLAG_ENABLE_FIRST_WALLY_POKENAV_CALL", "FLAG_HIDE_DEWFORD_HALL_SLUDGE_BOMB_MAN", "FLAG_HIDE_FALLARBOR_HOUSE_PROF_COZMO",
  "FLAG_HIDE_MAUVILLE_CITY_WATTSON", "FLAG_HIDE_MT_CHIMNEY_LAVA_COOKIE_LADY", "FLAG_HIDE_MT_CHIMNEY_TRAINERS",
  "FLAG_HIDE_PETALBURG_GYM_GREETER", "FLAG_HIDE_VERDANTURF_TOWN_WANDAS_HOUSE_WANDA",
  "FLAG_HIDE_VERDANTURF_TOWN_WANDAS_HOUSE_WANDAS_BOYFRIEND", "FLAG_HIDE_WEATHER_INSTITUTE_1F_WORKERS",
}
local PRE_VARS = {
  VAR_BIRCH_LAB_STATE = 5, VAR_BOARD_BRINEY_BOAT_STATE = 0, VAR_BRINEY_HOUSE_STATE = 1, VAR_BRINEY_LOCATION = 0,
  VAR_CABLE_CLUB_TUTORIAL_STATE = 1, VAR_DEVON_CORP_3F_STATE = 1, VAR_LITTLEROOT_INTRO_STATE = 7,
  VAR_LITTLEROOT_HOUSES_STATE_BRENDAN = 2, VAR_LITTLEROOT_RIVAL_STATE = 4, VAR_LITTLEROOT_TOWN_STATE = 4,
  VAR_OLDALE_RIVAL_STATE = 2, VAR_OLDALE_TOWN_STATE = 1, VAR_PETALBURG_CITY_STATE = 5, VAR_PETALBURG_GYM_STATE = 7,
  VAR_PETALBURG_WOODS_STATE = 1, VAR_REGISTER_BIRCH_STATE = 2, VAR_ROUTE101_STATE = 3, VAR_ROUTE104_STATE = 2,
  VAR_ROUTE110_STATE = 1, VAR_ROUTE116_STATE = 2, VAR_RUSTBORO_CITY_STATE = 8, VAR_RUSTURF_TUNNEL_STATE = 6,
  VAR_SCOTT_PETALBURG_ENCOUNTER = 1, VAR_SCOTT_STATE = 4, VAR_SLATEPORT_OUTSIDE_MUSEUM_STATE = 3, VAR_STARTER_MON = 1,
  VAR_LAVARIDGE_TOWN_STATE = 2, VAR_ROUTE118_STATE = 1, VAR_ROUTE119_STATE = 1, VAR_WEATHER_INSTITUTE_STATE = 2,
  VAR_METEOR_FALLS_STATE = 1, VAR_CABLE_CAR_STATION_STATE = 0, VAR_JAGGED_PASS_ASH_WEATHER = 0,
  VAR_WALLY_CALL_STEP_COUNTER = 250, VAR_SCOTT_FORTREE_CALL_STEP_COUNTER = 0,
}
local PRE_TRAINERS = {
  "TRAINER_ALLEN", "TRAINER_ALYSSA", "TRAINER_BRAWLY_1", "TRAINER_BRENDEN", "TRAINER_CALVIN_1", "TRAINER_CINDY_1",
  "TRAINER_CRISTIAN", "TRAINER_DEVAN", "TRAINER_EDMOND", "TRAINER_EDWARD", "TRAINER_GRUNT_MUSEUM_1", "TRAINER_GRUNT_MUSEUM_2",
  "TRAINER_GRUNT_PETALBURG_WOODS", "TRAINER_GRUNT_RUSTURF_TUNNEL", "TRAINER_HAILEY", "TRAINER_HALEY_1", "TRAINER_ISABEL_1",
  "TRAINER_JAMES_1", "TRAINER_JOCELYN", "TRAINER_JOHNSON", "TRAINER_JOSH", "TRAINER_KALEB", "TRAINER_KAREN_1",
  "TRAINER_LAURA", "TRAINER_LILITH", "TRAINER_MARC", "TRAINER_MAY_ROUTE_103_TORCHIC", "TRAINER_MAY_ROUTE_110_TORCHIC",
  "TRAINER_MAY_RUSTBORO_TORCHIC", "TRAINER_RICK", "TRAINER_RICKY_1", "TRAINER_ROXANNE_1", "TRAINER_TAKAO", "TRAINER_TIANA",
  "TRAINER_TOMMY", "TRAINER_WALLY_MAUVILLE", "TRAINER_WATTSON_1", "TRAINER_KIRK", "TRAINER_SHAWN", "TRAINER_BEN",
  "TRAINER_VIVIAN", "TRAINER_ANGELO",
  "TRAINER_ALEXIA", "TRAINER_ANGELINA", "TRAINER_ASHLEY", "TRAINER_AUTUMN", "TRAINER_AXLE", "TRAINER_BERKE",
  "TRAINER_BERNIE_1", "TRAINER_BRICE", "TRAINER_BROOKE_1", "TRAINER_CATHERINE_1", "TRAINER_CELINA", "TRAINER_CLARK",
  "TRAINER_COLE", "TRAINER_DANIELLE", "TRAINER_DARIUS", "TRAINER_DAYTON", "TRAINER_DEANDRE", "TRAINER_DEREK",
  "TRAINER_DONALD", "TRAINER_EDWARDO", "TRAINER_ELI", "TRAINER_ERIC", "TRAINER_FABIAN", "TRAINER_FLANNERY_1",
  "TRAINER_FLINT", "TRAINER_GEORGE", "TRAINER_GERALD", "TRAINER_GINA_AND_MIA_1", "TRAINER_GRUNT_MT_CHIMNEY_1",
  "TRAINER_GRUNT_MT_CHIMNEY_2", "TRAINER_GRUNT_WEATHER_INST_1", "TRAINER_GRUNT_WEATHER_INST_2",
  "TRAINER_GRUNT_WEATHER_INST_3", "TRAINER_GRUNT_WEATHER_INST_5", "TRAINER_HUMBERTO", "TRAINER_IRENE", "TRAINER_ISAAC_1",
  "TRAINER_JACE", "TRAINER_JACKSON_1", "TRAINER_JARED", "TRAINER_JAYLEN", "TRAINER_JEFF", "TRAINER_JODY",
  "TRAINER_JULIO", "TRAINER_KEEGAN", "TRAINER_LARRY", "TRAINER_LENNY", "TRAINER_LUCAS_1", "TRAINER_LYDIA_1",
  "TRAINER_LYLE", "TRAINER_MADELINE_1", "TRAINER_MARY", "TRAINER_MAXIE_MT_CHIMNEY", "TRAINER_MAY_ROUTE_119_TORCHIC",
  "TRAINER_MIKE_2", "TRAINER_NORMAN_1", "TRAINER_PARKER", "TRAINER_RANDALL", "TRAINER_ROSE_1", "TRAINER_SHAYLA",
  "TRAINER_SHELLY_WEATHER_INSTITUTE", "TRAINER_TABITHA_MT_CHIMNEY", "TRAINER_TAKASHI", "TRAINER_TORI_AND_TIA",
  "TRAINER_TYRON", "TRAINER_WILTON_1", "TRAINER_WINONA_1", "TRAINER_WINSTON_1", "TRAINER_YASU",
}
local PRE_ITEMS = {
  "ITEM_HM02", "ITEM_HM03", "ITEM_HM04", "ITEM_HM06", "ITEM_TM39", "ITEM_TM08", "ITEM_TM47", "ITEM_TM34", "ITEM_TM50",
  "ITEM_TM42", "ITEM_TM40", "ITEM_DEVON_SCOPE", "ITEM_GO_GOGGLES", "ITEM_METEORITE", "ITEM_MACH_BIKE", "ITEM_POKE_BALL",
}

local function battleShot(game, file)
  local taken = false
  return function(st, phase)
    local Ui = require("src.core.game3.battle.ui")
    if not taken and phase == "command" and Ui._mode == "menu" then
      taken = true
      U.wait(10)
      d.shot(game, file)
    end
  end
end

local function shotOnMessage(game, file, pred)
  local taken = false
  return function()
    local M = require("src.ui.game3.message")
    if not taken and M.isOpen() and (not pred or pred()) then
      taken = true
      U.wait(2)
      if M.isOpen() and M.isTyping() then M.skipReveal() end
      U.wait(3)
      d.shot(game, file)
    end
    return false
  end
end

local function setTrainerFlag(name)
  local F = require("src.core.game3.scripting.flags")
  local EM = F.forVersion("emerald")
  F.setFlag(require("src.core.game3.scripting.space").store, nil, (EM.IDS.TRAINER_FLAGS_START or 0x500)
    + S.C():require("trainers", name), true)
end

local function tid(name) return S.C():require("trainers", name) end

local function lastBattleWon(t)
  for i = #S.battles, 1, -1 do
    local b = S.battles[i]
    if not t or b.trainer == t then return b.result == "win", b end
  end
  return false
end

local function fightTrainer(game, label, name, shot, talkOpts, trainer)
  local eo = S.objectByScript(label)
  if trainer and S.trainerBeaten(trainer) then
    return d.check(true, name .. " beaten on the way (" .. trainer .. ")")
  end
  if not d.check(eo ~= nil, name .. " is on the map") then return false end
  local t = trainer and tid(trainer)
  local mine
  S.pendingBattleShot = shot
  for _ = 1, 4 do
    local before = #S.battles
    S.talkTo(game, eo, talkOpts)
    S.settle(game, { limit = 20000 })
    for i = before + 1, #S.battles do
      if not t or S.battles[i].trainer == t then mine = S.battles[i] end
    end
    if mine or not t or S.trainerBeaten(trainer) then break end
  end
  S.pendingBattleShot = nil
  return d.check(mine ~= nil and mine.result == "win", name .. " battle won (" .. tostring(mine and mine.result) .. ")")
end

local function teachHm(item, slot)
  local ItemUse = require("src.core.game3.item_use")
  local s = S.session()
  local ok, kind = ItemUse.useTm(s, s.bag, S.item(item), slot or 1)
  return ok, kind
end

local function knows(mon, move)
  for _, m in ipairs(mon and mon.moves or {}) do if m == S.move(move) then return true end end
  return false
end

local function slotWith(move)
  for i, m in ipairs(S.session().party or {}) do if knows(m, move) then return i, m end end
end

local function topId()
  local t = require("src.ui.game3.stack").top()
  return t and t.id
end

local function waitFor(pred, limit)
  for _ = 1, limit or 600 do
    if pred() then return true end
    U.wait(1)
  end
  return pred() and true or false
end

-- pokeemerald/src/region_map.c:1647
local function fly(game, secName, destMap, shot)
  local StartMenu = require("src.ui.game3.start_menu")
  local PartyMenu = require("src.ui.game3.party_menu")
  local RegionMap = require("src.ui.game3.rse.region_map")
  local slot = slotWith("MOVE_FLY")
  if not slot then d.note("no party mon knows FLY") return false end
  S.settle(game, { limit = 600 })
  U.tap(game, "start")
  if not waitFor(function() return topId() == "start" end, 120) then d.note("start menu did not open") return false end
  local row
  for i, e in ipairs(StartMenu.ENTRIES or {}) do if e.id == "pokemon" then row = i end end
  for _ = 1, 12 do
    if StartMenu.cursor == row then break end
    U.tap(game, "down") U.wait(6)
  end
  U.tap(game, "a")
  if not waitFor(function() return PartyMenu.isOpen() and PartyMenu.mode == "list" end, 240) then
    d.note("party menu did not open (" .. tostring(topId()) .. ")") return false
  end
  U.wait(20)
  for _ = 1, 12 do
    if PartyMenu.cursor == slot then break end
    U.tap(game, "down") U.wait(6)
  end
  U.tap(game, "a")
  if not waitFor(function() return PartyMenu.mode == "action" end, 120) then d.note("party action menu did not open") return false end
  local want
  for i, a in ipairs(PartyMenu.ACTIONS or {}) do if a == "FLY" then want = i end end
  if not want then d.note("no FLY action (" .. table.concat(PartyMenu.ACTIONS or {}, ",") .. ")") return false end
  for _ = 1, 8 do
    if PartyMenu.actionCursor == want then break end
    U.tap(game, "down") U.wait(6)
  end
  U.tap(game, "a")
  if not waitFor(function() return RegionMap.active() ~= nil end, 300) then d.note("fly map did not open") return false end
  local s = RegionMap.active()
  waitFor(function() return s.state == 12 end, 240)
  local target = S.C():require("region_map_sections", "MAPSEC_" .. secName)
  local tx, ty
  for y = RegionMap.CURSOR_Y_MIN, RegionMap.CURSOR_Y_MAX do
    for x = RegionMap.CURSOR_X_MIN, RegionMap.CURSOR_X_MAX do
      if not tx and RegionMap.mapSecAt(x, y) == target then tx, ty = x, y end
    end
  end
  if not tx then d.note("mapsec " .. secName .. " not on the fly map") return false end
  for _ = 1, 60 do
    if s.cursorX == tx and s.cursorY == ty then break end
    local dir = s.cursorX < tx and "right" or s.cursorX > tx and "left" or s.cursorY < ty and "down" or "up"
    local x0, y0 = s.cursorX, s.cursorY
    U.hold(game, dir, 2)
    waitFor(function() return s.cursorX ~= x0 or s.cursorY ~= y0 end, 30)
    waitFor(function() return s.inputFn == "full" end, 10)
    U.wait(1)
  end
  U.wait(8)
  if shot then d.shot(game, shot) end
  U.tap(game, "a")
  waitFor(function() return S.mapNow() == destMap end, 1500)
  local Field = require("src.core.game3.field")
  waitFor(function() return not Field.locked and not S.busy() end, 1500)
  S.settle(game, { limit = 3000 })
  return S.mapNow() == destMap
end

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

-- pokeemerald/src/field_control_avatar.c:463
local function diveDown(game)
  local P = require("src.core.game3.player")
  local m0 = S.mapNow()
  U.tap(game, "a")
  S.settle(game, { limit = 6000, until_ = function() return S.mapNow() ~= m0 and not S.busy() end })
  return S.mapNow() ~= m0 and P.underwater == true
end

-- pokeemerald/src/field_control_avatar.c:473
local function emerge(game, watch)
  local P = require("src.core.game3.player")
  local m0 = S.mapNow()
  U.tap(game, "b")
  S.settle(game, { limit = 6000, watch = watch, until_ = function() return S.mapNow() ~= m0 and not S.busy() end })
  return S.mapNow() ~= m0 and not P.underwater
end

local function diveNear(game, tx, ty, underMap)
  local C = require("src.core.game3.collision")
  local Dive = require("src.core.game3.dive")
  local P = require("src.core.game3.player")
  local tried = {}
  for _ = 1, 8 do
    local best
    S.path(game, function(x, y)
      if not tried[x .. "," .. y] and Dive.isDiveable(C.behavior(x, y)) then
        local dd = math.abs(x - tx) + math.abs(y - ty)
        if not best or dd < best[3] then best = { x, y, dd } end
      end
      return false
    end)
    if not best then return false end
    tried[best[1] .. "," .. best[2]] = true
    S.goTo(game, { best[1], best[2] }, { tries = 30, settle = { limit = 20000 } })
    if P.cellX == best[1] and P.cellY == best[2] and diveDown(game) then
      if S.mapNow() == underMap and S.path(game, { tx, ty }, { goalBlocked = true }) then return true end
      emerge(game)
    end
  end
  return false
end

local function smashAt(game, x, y)
  local Objects = require("src.core.game3.objects")
  local eo = Objects.at(x, y)
  if not eo then return false end
  S.talkTo(game, eo)
  S.settle(game, { limit = 6000 })
  S.rocksSmashed = (S.rocksSmashed or 0) + (Objects.at(x, y) and 0 or 1)
  return Objects.at(x, y) == nil
end

local function reachFrom(game, from, avoid)
  local seen = {}
  S.path(game, function(x, y) seen[x .. "," .. y] = true return false end, { from = from, avoid = avoid })
  return seen
end

local function padPlan(game, spec)
  local cur = S.mapNow()
  local def = game.data.maps[cur]
  local C = require("src.core.game3.collision")
  local P = require("src.core.game3.player")
  local warps = def and def.warps or {}
  local avoid = {}
  for _, w in ipairs(warps) do avoid[w.x .. "," .. w.y] = true end
  for _, k in ipairs(spec.avoidExtra or {}) do avoid[k] = true end
  local function touches(seen, x, y)
    for _, dd in pairs(DELTA) do if seen[(x + dd[1]) .. "," .. (y + dd[2])] then return true end end
    return false
  end
  local function isExit(w)
    return spec.exitMap and w.destMap == spec.exitMap and (not spec.exitAt or (w.x == spec.exitAt[1] and w.y == spec.exitAt[2]))
  end
  local start = { P.cellX, P.cellY, P.currentElevation }
  local q, head = { { from = start, plan = {} } }, 1
  local done = { [start[1] .. "," .. start[2]] = true }
  while head <= #q do
    local node = q[head]
    head = head + 1
    local seen = reachFrom(game, node.from, avoid)
    seen[node.from[1] .. "," .. node.from[2]] = true
    if spec.goal then
      for k in pairs(seen) do
        local x, y = k:match("(%-?%d+),(%-?%d+)")
        if spec.goal(tonumber(x), tonumber(y)) then
          local plan = { unpack(node.plan) }
          plan[#plan + 1] = { goal = true }
          return plan
        end
      end
    end
    for i, w in ipairs(warps) do
      if touches(seen, w.x, w.y) then
        if isExit(w) then
          local plan = { unpack(node.plan) }
          plan[#plan + 1] = { warp = i, x = w.x, y = w.y }
          return plan
        end
        if w.destMap == cur then
          local dw = warps[tonumber(w.destWarp)]
          if dw and not done[dw.x .. "," .. dw.y] then
            done[dw.x .. "," .. dw.y] = true
            local plan = { unpack(node.plan) }
            plan[#plan + 1] = { warp = i, x = w.x, y = w.y }
            q[#q + 1] = { from = { dw.x, dw.y, C.elevationAt(dw.x, dw.y) }, plan = plan }
          end
        end
      end
    end
  end
  return nil
end

local function padGo(game, spec)
  local m0 = S.mapNow()
  local P = require("src.core.game3.player")
  local pads = 0
  for _ = 1, spec.tries or 40 do
    if spec.exitMap and S.mapNow() == spec.exitMap then return true, pads end
    if S.mapNow() ~= m0 then return false, pads end
    if spec.goal and spec.goal(P.cellX, P.cellY) then return true, pads end
    if S.busy() then S.settle(game, spec.settle) end
    local plan = padPlan(game, spec)
    if not plan then d.note("pad plan: no route on " .. m0 .. " from " .. P.cellX .. "," .. P.cellY) return false, pads end
    local stepI = plan[1]
    local def = game.data.maps[m0]
    local avoid = {}
    for _, w in ipairs(def.warps or {}) do avoid[w.x .. "," .. w.y] = true end
    for _, k in ipairs(spec.avoidExtra or {}) do avoid[k] = true end
    if stepI.goal then
      S.goTo(game, spec.goal, { avoid = avoid, tries = 12, settle = spec.settle })
    else
      local wx, wy = stepI.x, stepI.y
      avoid[wx .. "," .. wy] = nil
      local x0, y0 = P.cellX, P.cellY
      S.goTo(game, { wx, wy }, { avoid = avoid, goalBlocked = true, tries = 12, settle = spec.settle })
      for _ = 1, 240 do
        if not (S.busy() or require("src.core.game3.warp").isBusy()) then break end
        U.wait(1)
      end
      S.settle(game, spec.settle or { limit = 600 })
      if P.cellX ~= x0 or P.cellY ~= y0 then pads = pads + 1 end
    end
  end
  return spec.exitMap and S.mapNow() == spec.exitMap or (spec.goal and spec.goal(P.cellX, P.cellY)) or false, pads
end

local function objectsByScript(label)
  local Objects = require("src.core.game3.objects")
  local Space = require("src.core.game3.scripting.space")
  local want = Space.bundle and Space.bundle.labels and Space.bundle.labels[label]
  local out = {}
  for _, lid in ipairs(Objects.listActive() or {}) do
    local eo = Objects.find(lid)
    local s = eo and not eo.hidden and (eo.scriptKey or (eo.def and (eo.def.script or eo.def.scriptKey)))
    if s and (s == label or (want and s == want)) then out[#out + 1] = eo end
  end
  return out
end

local function strengthSolve(game, goal, opts)
  opts = opts or {}
  local C = require("src.core.game3.collision")
  local P = require("src.core.game3.player")
  local boulders = objectsByScript("EventScript_StrengthBoulder")
  local orig = {}
  for _, b in ipairs(boulders) do orig[b.cellX .. "," .. b.cellY] = true end
  local rocks = {}
  for _, r in ipairs(objectsByScript("EventScript_RockSmash")) do rocks[r.cellX .. "," .. r.cellY] = true orig[r.cellX .. "," .. r.cellY] = true end
  local warpCells = {}
  for _, w in ipairs(game.data.maps[S.mapNow()].warps or {}) do
    if not C.isArrowWarpBehavior(C.behavior(w.x, w.y)) then warpCells[w.x .. "," .. w.y] = true end
  end
  local terrainCache = {}
  local function terrain(fx, fy, tx, ty, dir, elev)
    local k = fx .. "," .. fy .. ">" .. tx .. "," .. ty .. ":" .. tostring(elev)
    local v = terrainCache[k]
    if v == nil then
      local ok, why = C.canEnter(game, tx, ty, { fromX = fx, fromY = fy, dir = dir, elevation = elev, surfing = false })
      if not ok and why == "entity" and orig[tx .. "," .. ty] then ok = true end
      v = ok and true or false
      terrainCache[k] = v
    end
    return v
  end
  local function bkey(bs)
    local t = {}
    for i, b in ipairs(bs) do t[i] = b end
    table.sort(t)
    return table.concat(t, ";")
  end
  local bs0 = {}
  for _, b in ipairs(boulders) do bs0[#bs0 + 1] = b.cellX .. "," .. b.cellY end
  local start = { x = P.cellX, y = P.cellY, bs = bs0, e = P.currentElevation }
  local seen = { [start.x .. "," .. start.y .. "|" .. bkey(bs0)] = true }
  local q, head = { start }, 1
  local found
  while head <= #q and head < (opts.maxStates or 150000) do
    local st = q[head]
    head = head + 1
    if goal(st.x, st.y) then found = st break end
    local set = {}
    for i, b in ipairs(st.bs) do set[b] = i end
    for _, dir in ipairs({ "up", "down", "left", "right" }) do
      local dd = DELTA[dir]
      local tx, ty = st.x + dd[1], st.y + dd[2]
      local tk = tx .. "," .. ty
      local nst
      if set[tk] then
        local bx, by = tx + dd[1], ty + dd[2]
        local bk = bx .. "," .. by
        if not set[bk] and not warpCells[bk] and not rocks[bk] and terrain(tx, ty, bx, by, dir, 3) then
          local nb = {}
          for i, b in ipairs(st.bs) do nb[i] = (i == set[tk]) and bk or b end
          nst = { x = tx, y = ty, bs = nb, e = st.e, prev = st, dir = dir, push = true }
        end
      elseif not (warpCells[tk] and not (opts.allowWarp and opts.allowWarp(tx, ty))) and terrain(st.x, st.y, tx, ty, dir, st.e) then
        local z = C.elevationAt(tx, ty)
        local ne = (z == nil or z == 15 or C.elevationAt(st.x, st.y) == 15) and st.e or z
        nst = { x = tx, y = ty, bs = st.bs, e = ne, prev = st, dir = dir }
      end
      if nst then
        local k = nst.x .. "," .. nst.y .. "|" .. bkey(nst.bs)
        if not seen[k] then
          seen[k] = true
          q[#q + 1] = nst
        end
      end
    end
  end
  if not found then return nil, head end
  local path, pushes = {}, 0
  while found and found.prev do
    table.insert(path, 1, found.dir)
    if found.push then pushes = pushes + 1 end
    found = found.prev
  end
  return path, pushes
end

local function useStrength(game)
  if S.flag("FLAG_SYS_USE_STRENGTH") then return true end
  local P = require("src.core.game3.player")
  local bs = objectsByScript("EventScript_StrengthBoulder")
  local best
  for _, b in ipairs(bs) do
    if S.path(game, function(x, y) return math.abs(x - b.cellX) + math.abs(y - b.cellY) == 1 end) then best = b break end
  end
  if not best then return false end
  S.talkTo(game, best)
  S.settle(game, { limit = 6000 })
  return S.flag("FLAG_SYS_USE_STRENGTH")
end

local function strengthGo(game, goal, opts)
  opts = opts or {}
  local P = require("src.core.game3.player")
  local pushes = 0
  local m0 = S.mapNow()
  for _ = 1, opts.tries or 6 do
    if goal(P.cellX, P.cellY) then return true, pushes end
    if S.mapNow() ~= m0 then return false, pushes end
    local path, n = strengthSolve(game, goal, opts)
    if not path then d.note("strength solver: no solution on " .. m0 .. " from " .. P.cellX .. "," .. P.cellY .. " (" .. tostring(n) .. " states)") return false, pushes end
    if n > 0 and not S.flag("FLAG_SYS_USE_STRENGTH") then
      if not useStrength(game) then d.note("could not activate STRENGTH") return false, pushes end
      path = strengthSolve(game, goal, opts)
      if not path then return false, pushes end
    end
    local Objects = require("src.core.game3.objects")
    local rockSet = {}
    for _, r in ipairs(objectsByScript("EventScript_RockSmash")) do rockSet[r] = true end
    for _, dir in ipairs(path) do
      local dd = DELTA[dir]
      local x0, y0 = P.cellX, P.cellY
      local b = Objects.at(x0 + dd[1], y0 + dd[2])
      if b and rockSet[b] then
        S.face(game, dir)
        smashAt(game, x0 + dd[1], y0 + dd[2])
        b = Objects.at(x0 + dd[1], y0 + dd[2])
      end
      S.step(game, dir)
      for _ = 1, 120 do
        if not (P.moving or (b and b.moving)) and not S.busy() then break end
        U.wait(1)
      end
      if S.busy() then S.settle(game, opts.settle or { limit = 20000 }) end
      if b and b.cellX ~= x0 + dd[1] + 0 or (b and b.cellY ~= y0 + dd[2]) then pushes = pushes + 1 end
      if P.cellX == x0 and P.cellY == y0 then
        U.wait(10)
        if b then S.step(game, dir) U.wait(20) end
        if P.cellX == x0 and P.cellY == y0 then break end
      end
      if S.mapNow() ~= m0 then break end
    end
  end
  return goal(P.cellX, P.cellY), pushes
end

local function seek(game, target, prefix, opts)
  opts = opts or {}
  local P = require("src.core.game3.player")
  local dead = {}
  local lastMap, entry
  for _ = 1, opts.tries or 30 do
    local cur = S.mapNow()
    if cur == target then return true end
    if cur ~= lastMap then lastMap, entry = cur, cur .. "@" .. P.cellX .. "," .. P.cellY end
    if opts.repel ~= false then S.useRepel() end
    local prev, q, head = { [cur] = false }, { cur }, 1
    while head <= #q do
      local m = q[head]
      head = head + 1
      if m == target then break end
      local def = game.data.maps[m]
      for _, w in ipairs(def and def.warps or {}) do
        local nm = w.destMap
        if nm and prev[nm] == nil and (nm == target or nm:find(prefix, 1, true)) and not (m == cur and dead[entry .. ">" .. nm]) then
          prev[nm] = m
          q[#q + 1] = nm
        end
      end
    end
    if prev[target] == nil then
      d.note("seek: no map route from " .. cur .. " to " .. target)
      return false
    end
    local hop = target
    while prev[hop] ~= cur do hop = prev[hop] end
    if os.getenv("EM_STORY_DEBUG") then d.note("seek " .. cur .. " -> " .. hop .. " (" .. entry .. ")") end
    local def = game.data.maps[cur]
    local function nearHop(x, y)
      for _, w in ipairs(def.warps or {}) do
        if w.destMap == hop and math.abs(x - w.x) + math.abs(y - w.y) == 1 then return true end
      end
      return false
    end
    if #objectsByScript("EventScript_StrengthBoulder") + #objectsByScript("EventScript_RockSmash") > 0 and not S.path(game, nearHop) then
      local ok, pushes = strengthGo(game, nearHop)
      S.strengthPushes = (S.strengthPushes or 0) + (pushes or 0)
    end
    local ok = S.exitTo(game, hop, { avoidWarps = true, settle = opts.settle or { limit = 20000 } })
    S.settle(game, opts.settle or { limit = 20000 })
    if not ok and S.mapNow() == cur then dead[entry .. ">" .. hop] = true end
  end
  return S.mapNow() == target
end

local function legRoute(game, legs, opts)
  opts = opts or {}
  local P = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  for i, leg in ipairs(legs) do
    local mapId, tx, ty = leg[1], leg[2], leg[3]
    if S.mapNow() ~= mapId then
      d.note(string.format("leg %d expects %s, on %s at %d,%d", i, mapId, tostring(S.mapNow()), P.cellX, P.cellY))
      return false, i
    end
    local done = false
    for _ = 1, 6 do
      local avoid = {}
      for _, w in ipairs(game.data.maps[mapId].warps or {}) do
        if not (w.x == tx and w.y == ty) then avoid[w.x .. "," .. w.y] = true end
      end
      S.goTo(game, { tx, ty }, { avoid = avoid, goalBlocked = true, tries = 12, settle = opts.settle or { limit = 20000 } })
      for _ = 1, 240 do
        if not (Warp.isBusy() or P.moving) then break end
        U.wait(1)
      end
      S.settle(game, opts.settle or { limit = 20000 })
      if S.mapNow() ~= mapId or not (P.cellX == tx and P.cellY == ty) and math.abs(P.cellX - tx) + math.abs(P.cellY - ty) > 1 then
        done = true
        break
      end
      if P.cellX == tx and P.cellY == ty and leg.push then S.step(game, leg.push) S.settle(game, opts.settle or { limit = 20000 }) end
    end
    if not done then
      d.note(string.format("leg %d stuck on %s at %d,%d (target %d,%d)", i, mapId, P.cellX, P.cellY, tx, ty))
      return false, i
    end
    if opts.onLeg then opts.onLeg(i) end
  end
  return true, #legs
end

-- pokeemerald/data/maps/MossdeepCity_Gym/map.json:1
local MOSSDEEP_SWITCHES = {
  { 2, 21, 0 }, { 3, 30, 0 }, { 8, 10, 1 }, { 6, 7, 1 }, { 15, 34, 2 }, { 23, 24, 3 }, { 23, 21, 3 }, { 8, 6, 4 },
}
local MOSSDEEP_NO_STEP = { ["21,6"] = true }

-- pokeemerald/src/rotating_tile_puzzle.c:108
local function mossdeepSolve(game, goal)
  local C = require("src.core.game3.collision")
  local RTP = require("src.core.game3.rotating_tile_puzzle")
  local Objects = require("src.core.game3.objects")
  local P = require("src.core.game3.player")
  local start = S.C():require("metatile_labels", "METATILE_MossdeepGym_YellowArrow_Right")
  local ARROW = { [0] = { 1, 0 }, [1] = { 0, 1 }, [2] = { -1, 0 }, [3] = { 0, -1 } }
  local arrow = {}
  local W, H = C._widthCells or 0, C._heightCells or 0
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local mt = RTP.metatileAt(x, y)
      if mt >= start then
        local row, tile = math.floor((mt - start) / 8), (mt - start) % 8
        if row < 5 and tile < 4 then arrow[x .. "," .. y] = { row, ARROW[tile][1], ARROW[tile][2] } end
      end
    end
  end
  local objs = {}
  for _, lid in ipairs(Objects._order or {}) do
    local eo = Objects._byId[lid]
    if eo and eo.def and not eo.hidden and eo.visible ~= false then
      objs[#objs + 1] = { px = tonumber(eo.def.x) or eo.cellX, py = tonumber(eo.def.y) or eo.cellY, cx = eo.cellX, cy = eo.cellY }
    end
  end
  local switchAt = {}
  for _, sw in ipairs(MOSSDEEP_SWITCHES) do switchAt[sw[1] .. "," .. sw[2]] = sw[3] end
  local pads = {}
  local def = game.data.maps[S.mapNow()]
  for _, w in ipairs(def.warps or {}) do
    if w.destMap == S.mapNow() then
      local dw = def.warps[tonumber(w.destWarp)]
      if dw then pads[w.x .. "," .. w.y] = { dw.x, dw.y } end
    elseif w.destMap then
      MOSSDEEP_NO_STEP[w.x .. "," .. w.y] = true
    end
  end
  local tcache = {}
  local function terrain(fx, fy, tx, ty, dir)
    local k = fx .. "," .. fy .. ">" .. tx .. "," .. ty
    local v = tcache[k]
    if v == nil then
      local ok, why = C.canEnter(game, tx, ty, { fromX = fx, fromY = fy, dir = dir, surfing = false })
      v = (ok or why == "entity") and true or false
      tcache[k] = v
    end
    return v
  end
  local function apply(cfg, color)
    local out = {}
    for i, o in ipairs(cfg) do
      local a = arrow[o[1] .. "," .. o[2]]
      if a and a[1] == color then
        out[i] = { o[1] + a[2], o[2] + a[3], o[3] + a[2], o[4] + a[3] }
      else
        out[i] = o
      end
    end
    return out
  end
  local function ckey(cfg)
    local t = {}
    for i, o in ipairs(cfg) do t[i] = o[3] .. "," .. o[4] end
    return table.concat(t, ";")
  end
  local cfg0 = {}
  for i, o in ipairs(objs) do cfg0[i] = { o.px, o.py, o.cx, o.cy } end
  local function flood(cfg, sx, sy)
    local occ = {}
    for _, o in ipairs(cfg) do occ[o[3] .. "," .. o[4]] = true end
    local seen, q, head = {}, { { sx, sy } }, 1
    if not switchAt[sx .. "," .. sy] then seen[sx .. "," .. sy] = true end
    local edges, hit = {}, nil
    while head <= #q do
      local c = q[head]
      head = head + 1
      if goal(c[1], c[2]) then hit = c end
      for dir, dd in pairs(DELTA) do
        local nx, ny = c[1] + dd[1], c[2] + dd[2]
        local k = nx .. "," .. ny
        if not seen[k] and not occ[k] and not MOSSDEEP_NO_STEP[k] and (pads[k] or terrain(c[1], c[2], nx, ny, dir)) then
          if pads[k] then
            local l = pads[k]
            local lk = l[1] .. "," .. l[2]
            seen[k] = true
            if not seen[lk] then seen[lk] = true q[#q + 1] = { l[1], l[2] } end
          elseif switchAt[k] then
            edges[#edges + 1] = { k = k, x = nx, y = ny, color = switchAt[k], from = c }
          else
            seen[k] = true
            q[#q + 1] = { nx, ny }
          end
        end
      end
    end
    return hit, edges
  end
  local startKey = ckey(cfg0) .. "@" .. P.cellX .. "," .. P.cellY
  local visited = { [startKey] = true }
  local Q, head = { { cfg = cfg0, x = P.cellX, y = P.cellY, plan = {} } }, 1
  while head <= #Q and head < 20000 do
    local n = Q[head]
    head = head + 1
    local hit, edges = flood(n.cfg, n.x, n.y)
    if hit then return n.plan, head end
    for _, e in ipairs(edges) do
      local ncfg = apply(n.cfg, e.color)
      local key = ckey(ncfg) .. "@" .. e.k
      if not visited[key] then
        visited[key] = true
        local plan = { unpack(n.plan) }
        plan[#plan + 1] = { e.x, e.y, e.color }
        Q[#Q + 1] = { cfg = ncfg, x = e.x, y = e.y, plan = plan }
      end
    end
  end
  return nil, head
end

local function mossdeepGo(game, goal)
  local P = require("src.core.game3.player")
  local presses = 0
  for _ = 1, 30 do
    if goal(P.cellX, P.cellY) then return true, presses end
    if S.busy() then S.settle(game, { limit = 20000 }) end
    local plan, n = mossdeepSolve(game, goal)
    if not plan then d.note("mossdeep solver: no plan from " .. P.cellX .. "," .. P.cellY .. " (" .. tostring(n) .. ")") return false, presses end
    local switchCells = {}
    for _, sw in ipairs(MOSSDEEP_SWITCHES) do switchCells[#switchCells + 1] = sw[1] .. "," .. sw[2] end
    if #plan == 0 then
      padGo(game, { goal = goal, avoidExtra = switchCells, settle = { limit = 20000 } })
      if goal(P.cellX, P.cellY) then return true, presses end
    else
      local sx, sy = plan[1][1], plan[1][2]
      padGo(game, { goal = function(x, y) return math.abs(x - sx) + math.abs(y - sy) == 1 end, avoidExtra = switchCells,
        settle = { limit = 20000 } })
      if math.abs(P.cellX - sx) + math.abs(P.cellY - sy) == 1 then
        local dir = sx > P.cellX and "right" or sx < P.cellX and "left" or sy > P.cellY and "down" or "up"
        S.step(game, dir)
        S.settle(game, { limit = 20000 })
        if P.cellX == sx and P.cellY == sy then presses = presses + 1 end
      end
    end
  end
  return goal(P.cellX, P.cellY), presses
end

local function icePath(game, rows, startCell, endCell)
  local C = require("src.core.game3.collision")
  local cells, n = {}, 0
  for y = rows[1], rows[2] do
    for x = 0, (C._widthCells or 17) - 1 do
      if C.isThinIce(C.behavior(x, y)) then cells[x .. "," .. y] = true n = n + 1 end
    end
  end
  local visited, path, budget = {}, {}, 400000
  local function free(x, y) return cells[x .. "," .. y] and not visited[x .. "," .. y] end
  local function degree(x, y)
    local k = 0
    for _, dd in pairs(DELTA) do if free(x + dd[1], y + dd[2]) then k = k + 1 end end
    return k
  end
  local function dfs(x, y, count)
    budget = budget - 1
    if budget < 0 then return false end
    if count == n then return x == endCell[1] and y == endCell[2] end
    if x == endCell[1] and y == endCell[2] then return false end
    local opts = {}
    for dir, dd in pairs(DELTA) do
      local nx, ny = x + dd[1], y + dd[2]
      if free(nx, ny) then opts[#opts + 1] = { dir, nx, ny, degree(nx, ny) } end
    end
    table.sort(opts, function(a, b) if a[4] ~= b[4] then return a[4] < b[4] end return a[1] < b[1] end)
    for _, o in ipairs(opts) do
      visited[o[2] .. "," .. o[3]] = true
      path[#path + 1] = o[1]
      if dfs(o[2], o[3], count + 1) then return true end
      path[#path] = nil
      visited[o[2] .. "," .. o[3]] = nil
    end
    return false
  end
  visited[startCell[1] .. "," .. startCell[2]] = true
  if not cells[startCell[1] .. "," .. startCell[2]] then return nil, n end
  if dfs(startCell[1], startCell[2], 1) then return path, n end
  return nil, n
end

local BEATS = {}

BEATS[#BEATS + 1] = { id = "start", run = function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "QUINCY", gender = 0, start = {
    map = "EM_FORTREE_CITY", x = 5, y = 8, facing = "down", healMap = "EM_FORTREE_CITY", healX = 5, healY = 7,
  } })
  U.wait(30)
  for _, f in ipairs(PRE_SET) do S.setFlag(f, true) end
  for _, f in ipairs(PRE_CLEAR) do S.setFlag(f, false) end
  for k, v in pairs(PRE_VARS) do S.setVar(k, v) end
  for _, t in ipairs(PRE_TRAINERS) do setTrainerFlag(t) end
  local s = S.session()
  s.party = {}
  local bl = S.giveMon("SPECIES_TORCHIC", 10)
  S.setLevel(bl, 70, "SPECIES_BLAZIKEN")
  S.setMoves(bl, { "MOVE_SKY_UPPERCUT", "MOVE_FLAMETHROWER", "MOVE_STRENGTH", "MOVE_ROCK_SMASH" })
  local az = S.giveMon("SPECIES_MARILL", 10)
  S.setLevel(az, 68, "SPECIES_AZUMARILL")
  S.setMoves(az, { "MOVE_SURF", "MOVE_ICE_BEAM", "MOVE_BODY_SLAM" })
  local sw = S.giveMon("SPECIES_TAILLOW", 10)
  S.setLevel(sw, 64, "SPECIES_SWELLOW")
  S.setMoves(sw, { "MOVE_FLY", "MOVE_AERIAL_ACE", "MOVE_QUICK_ATTACK" })
  local mn = S.giveMon("SPECIES_ELECTRIKE", 10)
  S.setLevel(mn, 66, "SPECIES_MANECTRIC")
  S.setMoves(mn, { "MOVE_THUNDERBOLT", "MOVE_CRUNCH", "MOVE_QUICK_ATTACK" })
  for _, it in ipairs(PRE_ITEMS) do S.giveItem(it, 1) end
  S.giveItem("ITEM_POKE_BALL", 5)
  S.giveItem("ITEM_ULTRA_BALL", 5)
  s.money = 50000
  d.check(#s.party == 4 and knows(sw, "MOVE_FLY") and knows(az, "MOVE_SURF") and knows(bl, "MOVE_STRENGTH"),
    "segment start: Blaziken lv70 / Azumarill lv68 / Swellow lv64 / Manectric lv66 after the Feather Badge")
  S.saveCheckpoint(game, "start")
  S.loadCheckpoint(game, "start")
  S.canSurf = true
  return d.check(S.mapNow() == "EM_FORTREE_CITY" and S.flag("FLAG_BADGE06_GET") and S.hasItem("ITEM_HM02"),
    "segment start: Fortree City with 6 badges (" .. tostring(S.mapNow()) .. ")")
end }

-- pokeemerald/data/maps/Route121/scripts.inc:16
BEATS[#BEATS + 1] = { id = "to_lilycove", run = function(game)
  S.canSurf = true
  S.travel(game, { "EM_ROUTE120", "EM_ROUTE121" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_ROUTE121", "Fortree -> Route 120 -> Route 121 (" .. tostring(S.mapNow()) .. ")") then return false end
  S.goTo(game, function(x, y) return x >= 26 and y >= 5 and y <= 8 end, { tries = 40, settle = { limit = 20000,
    watch = shotOnMessage(game, "01_route121_aqua", function() return S.mapNow() == "EM_ROUTE121" end) } })
  S.settle(game, { limit = 6000, watch = shotOnMessage(game, "01_route121_aqua") })
  d.check(S.var("VAR_ROUTE121_STATE") == 1, "Route 121: the Aqua grunts move out toward Mt. Pyre (VAR_ROUTE121_STATE="
    .. S.var("VAR_ROUTE121_STATE") .. ")")
  S.travel(game, { "EM_LILYCOVE_CITY" }, { settle = { limit = 20000 } })
  S.settle(game, { limit = 600 })
  d.shot(game, "02_lilycove")
  return d.check(S.mapNow() == "EM_LILYCOVE_CITY" and S.flag("FLAG_VISITED_LILYCOVE_CITY"),
    "Route 121 -> Lilycove City (" .. tostring(S.mapNow()) .. ")")
end }

-- pokeemerald/data/maps/LilycoveCity/scripts.inc:227
BEATS[#BEATS + 1] = { id = "lilycove_rival", run = function(game)
  local may = S.objectByScript("LilycoveCity_EventScript_Rival")
  if not d.check(may ~= nil, "May is in Lilycove") then return false end
  S.talkTo(game, may)
  S.settle(game, { limit = 40000, onBattleFrame = battleShot(game, "03_lilycove_may"),
    until_ = function() return S.flag("FLAG_MET_RIVAL_LILYCOVE") and not S.busy() end })
  d.check(lastBattleWon(tid("TRAINER_MAY_LILYCOVE_TORCHIC")), "Lilycove May battle won through the battle UI")
  return d.check(S.flag("FLAG_MET_RIVAL_LILYCOVE"), "May flies off home (FLAG_MET_RIVAL_LILYCOVE)")
end }

-- pokeemerald/data/maps/LilycoveCity_DepartmentStore_1F/scripts.inc:1
BEATS[#BEATS + 1] = { id = "dept_store", run = function(game)
  S.travel(game, { "EM_LILYCOVE_CITY_DEPARTMENT_STORE_1F" }, { settle = { limit = 8000 } })
  if not d.check(S.mapNow() == "EM_LILYCOVE_CITY_DEPARTMENT_STORE_1F", "into the Lilycove Department Store") then return false end
  S.settle(game, { limit = 600 })
  d.shot(game, "04_dept_store")
  S.travel(game, { "EM_LILYCOVE_CITY" }, { settle = { limit = 8000 } })
  return d.check(S.mapNow() == "EM_LILYCOVE_CITY", "back out to Lilycove")
end }

-- pokeemerald/data/maps/AquaHideout_1F/scripts.inc:5
BEATS[#BEATS + 1] = { id = "aqua_closed", run = function(game)
  S.canSurf = true
  S.travel(game, { "EM_AQUA_HIDEOUT_1F" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_AQUA_HIDEOUT_1F", "surf across the cove into the Aqua Hideout entrance") then return false end
  local g = S.objectByScript("AquaHideout_1F_EventScript_HideoutEntranceGrunt1")
  if not d.check(g ~= nil and not S.flag("FLAG_HIDE_AQUA_HIDEOUT_1F_GRUNT_1_BLOCKING_ENTRANCE"),
    "two Aqua grunts block the hideout") then return false end
  S.talkTo(game, g)
  S.settle(game, { limit = 6000, watch = shotOnMessage(game, "05_aqua_hideout_closed") })
  local P = require("src.core.game3.player")
  local path = S.path(game, function(x, y) return y < 10 end)
  d.check(path == nil, "no way past the guards while their boss is away")
  S.travel(game, { "EM_LILYCOVE_CITY" }, { settle = { limit = 8000 } })
  return d.check(S.mapNow() == "EM_LILYCOVE_CITY", "back out to the cove (" .. tostring(S.mapNow()) .. " " .. P.cellX .. "," .. P.cellY .. ")")
end }

-- pokeemerald/data/maps/MtPyre_Summit/scripts.inc:32
BEATS[#BEATS + 1] = { id = "mt_pyre", run = function(game)
  S.canSurf = true
  S.travel(game, { "EM_ROUTE121", "EM_ROUTE122", "EM_MT_PYRE_1F" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_MT_PYRE_1F", "Lilycove -> Route 121 -> Route 122 (surf) -> Mt. Pyre ("
      .. tostring(S.mapNow()) .. ")") then return false end
  d.shot(game, "06_mt_pyre_1f")
  S.travel(game, { "EM_MT_PYRE_EXTERIOR", "EM_MT_PYRE_SUMMIT" }, { settle = { limit = 30000 } })
  if not d.check(S.mapNow() == "EM_MT_PYRE_SUMMIT", "out the back of Mt. Pyre and up the foggy slope to the summit") then
    return false
  end
  local function archieScene()
    return S.var("VAR_MT_PYRE_STATE") == 0 and (d.ran("MtPyre_Summit_EventScript_TeamAquaTrigger0")
      or d.ran("MtPyre_Summit_EventScript_TeamAquaTrigger1") or d.ran("MtPyre_Summit_EventScript_TeamAquaTrigger2"))
  end
  local archieShot = shotOnMessage(game, "07_mt_pyre_archie", archieScene)
  S.goTo(game, function(x, y) return y == 7 and x >= 22 and x <= 24 end, { tries = 40, settle = { limit = 30000,
    watch = archieShot } })
  local emblemShot = shotOnMessage(game, "08_magma_emblem", function() return S.var("VAR_MT_PYRE_STATE") == 1 end)
  S.settle(game, { limit = 30000, watch = function() archieShot() emblemShot() end,
    until_ = function() return S.flag("FLAG_RECEIVED_RED_OR_BLUE_ORB") and not S.busy() end })
  local n = 0
  for _, t in ipairs({ "TRAINER_GRUNT_MT_PYRE_1", "TRAINER_GRUNT_MT_PYRE_2", "TRAINER_GRUNT_MT_PYRE_3", "TRAINER_GRUNT_MT_PYRE_4" }) do
    if S.trainerBeaten(t) then n = n + 1 end
  end
  d.check(n >= 1, "Aqua grunts on the summit battled on the way (" .. n .. ")")
  d.check(archieScene ~= nil and S.flag("FLAG_HIDE_MT_PYRE_SUMMIT_ARCHIE") and S.var("VAR_MT_PYRE_STATE") == 1,
    "Archie takes the orb and Team Aqua leaves (VAR_MT_PYRE_STATE=" .. S.var("VAR_MT_PYRE_STATE") .. ")")
  return d.check(S.hasItem("ITEM_MAGMA_EMBLEM") and S.flag("FLAG_HIDE_JAGGED_PASS_MAGMA_GUARD"),
    "the old lady gives the MAGMA EMBLEM (FLAG_RECEIVED_RED_OR_BLUE_ORB)")
end }

-- pokeemerald/data/maps/MagmaHideout_4F/scripts.inc:4
BEATS[#BEATS + 1] = { id = "magma_hideout", run = function(game)
  if not d.check(fly(game, "LAVARIDGE_TOWN", "EM_LAVARIDGE_TOWN", "09_fly_lavaridge"),
    "FLY from Mt. Pyre to Lavaridge through the party menu and the region map (" .. tostring(S.mapNow()) .. ")") then return false end
  if S.needsHeal() then S.healAtCenter(game, "EM_LAVARIDGE_TOWN", "LavaridgeTown") end
  S.travel(game, { "EM_ROUTE112", "EM_ROUTE112_CABLE_CAR_STATION" }, { settle = { limit = 20000 } })
  local att = S.objectByScript("Route112_CableCarStation_EventScript_Attendant")
  if not d.check(att ~= nil, "Lavaridge -> Route 112 -> cable car station") then return false end
  S.talkTo(game, att)
  S.settle(game, { limit = 40000, until_ = function()
    return S.mapNow() == "EM_MT_CHIMNEY_CABLE_CAR_STATION" and S.var("VAR_CABLE_CAR_STATION_STATE") == 0 and not S.busy() end })
  S.travel(game, { "EM_MT_CHIMNEY", "EM_JAGGED_PASS" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_JAGGED_PASS" and S.var("VAR_JAGGED_PASS_STATE") >= 1,
    "cable car up, Mt. Chimney -> Jagged Pass with the MAGMA EMBLEM (VAR_JAGGED_PASS_STATE=" .. S.var("VAR_JAGGED_PASS_STATE") .. ")") then
    return false
  end
  S.travel(game, { "EM_MAGMA_HIDEOUT_1F" }, { settle = { limit = 20000,
    watch = shotOnMessage(game, "10_jagged_pass_emblem", function() return S.mapNow() == "EM_JAGGED_PASS" end) } })
  d.check(S.var("VAR_JAGGED_PASS_STATE") == 2, "the boulder shakes at the MAGMA EMBLEM and the hideout opens (VAR_JAGGED_PASS_STATE="
    .. S.var("VAR_JAGGED_PASS_STATE") .. ")")
  if not d.check(S.mapNow() == "EM_MAGMA_HIDEOUT_1F", "into the Magma Hideout (" .. tostring(S.mapNow()) .. ")") then return false end
  S.settle(game, { limit = 600 })
  d.shot(game, "11_magma_hideout")
  seek(game, "EM_MAGMA_HIDEOUT_4F", "EM_MAGMA_HIDEOUT")
  local n = 0
  for i = 1, #S.battles do if S.battles[i].map and S.battles[i].map:find("MAGMA_HIDEOUT", 1, true) then n = n + 1 end end
  if not d.check(S.mapNow() == "EM_MAGMA_HIDEOUT_4F", "through the hideout floors to Groudon's chamber (" .. tostring(S.mapNow())
    .. ", " .. n .. " battles)") then return false end
  d.check((S.strengthPushes or 0) > 0, "STRENGTH moves the 1F boulders out of the way (" .. tostring(S.strengthPushes or 0) .. " pushes)")
  fightTrainer(game, "MagmaHideout_4F_EventScript_Tabitha", "Magma Admin Tabitha", "12_tabitha_hideout", nil, "TRAINER_TABITHA_MAGMA_HIDEOUT")
  if S.needsHeal(0.5) then S.healParty() d.note("NOTE party healed in place before Maxie (driver)") end
  local maxie = S.objectByScript("MagmaHideout_4F_EventScript_Maxie")
  if not d.check(maxie ~= nil, "Maxie stands before the sleeping Groudon") then return false end
  S.talkTo(game, maxie)
  local groudonShot = false
  S.settle(game, { limit = 60000, onBattleFrame = battleShot(game, "14_maxie_hideout"),
    watch = function()
      local Objects = require("src.core.game3.objects")
      if not groudonShot and S.vmRunning() and not S.flag("FLAG_GROUDON_AWAKENED_MAGMA_HIDEOUT") then
        local g = Objects.find(1)
        if g and not g.hidden and g.moving then groudonShot = true d.shot(game, "13_groudon_awakens") end
      end
    end,
    until_ = function() return S.flag("FLAG_GROUDON_AWAKENED_MAGMA_HIDEOUT") and not S.busy() end })
  d.check(lastBattleWon(tid("TRAINER_MAXIE_MAGMA_HIDEOUT")), "Maxie battle won through the battle UI")
  return d.check(S.flag("FLAG_GROUDON_AWAKENED_MAGMA_HIDEOUT") and S.var("VAR_SLATEPORT_HARBOR_STATE") == 1,
    "Groudon awakens and leaves; Maxie goes after it (FLAG_GROUDON_AWAKENED_MAGMA_HIDEOUT)")
end }

-- pokeemerald/data/maps/SlateportCity_Harbor/scripts.inc:48
BEATS[#BEATS + 1] = { id = "slateport_harbor", run = function(game)
  seek(game, "EM_JAGGED_PASS", "EM_MAGMA_HIDEOUT")
  if not d.check(S.mapNow() == "EM_JAGGED_PASS", "back out of the hideout to Jagged Pass (" .. tostring(S.mapNow()) .. ")") then return false end
  if not d.check(fly(game, "SLATEPORT_CITY", "EM_SLATEPORT_CITY"), "FLY to Slateport (" .. tostring(S.mapNow()) .. ")") then return false end
  local stern = S.objectByScript("SlateportCity_EventScript_CaptStern")
  if not d.check(stern ~= nil and S.var("VAR_SLATEPORT_CITY_STATE") == 1, "Capt. Stern gives an interview outside the harbor") then
    return false
  end
  S.canSurf = false
  S.talkTo(game, stern)
  S.settle(game, { limit = 30000, watch = shotOnMessage(game, "15_stern_interview"),
    until_ = function() return S.mapNow() == "EM_SLATEPORT_CITY_HARBOR" and not S.busy() end })
  S.canSurf = true
  if not d.check(S.mapNow() == "EM_SLATEPORT_CITY_HARBOR" and S.var("VAR_SLATEPORT_CITY_STATE") == 2,
    "Aqua's broadcast: Stern takes the player into the harbor (" .. tostring(S.mapNow()) .. ")") then return false end
  local archieShot = shotOnMessage(game, "16_harbor_archie", function() return S.var("VAR_SLATEPORT_HARBOR_STATE") == 1 end)
  S.goTo(game, function(x, y) return x == 8 and y >= 11 and y <= 14 end, { tries = 20, settle = { limit = 20000, watch = archieShot } })
  S.settle(game, { limit = 30000, watch = archieShot,
    until_ = function() return S.var("VAR_SLATEPORT_HARBOR_STATE") == 2 and not S.busy() end })
  return d.check(S.var("VAR_SLATEPORT_HARBOR_STATE") == 2 and S.flag("FLAG_HIDE_AQUA_HIDEOUT_1F_GRUNT_1_BLOCKING_ENTRANCE"),
    "Archie steals Capt. Stern's submarine; the hideout guards leave (VAR_SLATEPORT_HARBOR_STATE=" .. S.var("VAR_SLATEPORT_HARBOR_STATE") .. ")")
end }

-- pokeemerald/data/maps/AquaHideout_B2F/scripts.inc:29
BEATS[#BEATS + 1] = { id = "aqua_hideout", run = function(game)
  S.travel(game, { "EM_SLATEPORT_CITY" }, { settle = { limit = 20000 } })
  if not d.check(fly(game, "LILYCOVE_CITY", "EM_LILYCOVE_CITY"), "FLY to Lilycove (" .. tostring(S.mapNow()) .. ")") then return false end
  if S.needsHeal() then S.healAtCenter(game, "EM_LILYCOVE_CITY", "LilycoveCity") end
  S.canSurf = true
  S.travel(game, { "EM_AQUA_HIDEOUT_1F" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_AQUA_HIDEOUT_1F" and S.objectByScript("AquaHideout_1F_EventScript_HideoutEntranceGrunt1") == nil,
    "the hideout entrance is open") then return false end
  seek(game, "EM_AQUA_HIDEOUT_B1F", "EM_AQUA_HIDEOUT")
  if not d.check(S.mapNow() == "EM_AQUA_HIDEOUT_B1F", "down to Aqua Hideout B1F") then return false end
  d.shot(game, "17_aqua_hideout_b1f")
  local matt
  -- pokeemerald/data/maps/AquaHideout_B1F/map.json:1
  local ok, n = legRoute(game, {
    { "EM_AQUA_HIDEOUT_B1F", 27, 4 }, { "EM_AQUA_HIDEOUT_B1F", 32, 19 }, { "EM_AQUA_HIDEOUT_B1F", 18, 1 },
    { "EM_AQUA_HIDEOUT_B2F", 31, 8 }, { "EM_AQUA_HIDEOUT_B2F", 3, 3 }, { "EM_AQUA_HIDEOUT_B1F", 12, 1 },
    { "EM_AQUA_HIDEOUT_B2F", 8, 8 },
  }, { settle = { limit = 20000 } })
  local totalPads = n
  if not d.check(ok and S.mapNow() == "EM_AQUA_HIDEOUT_B2F", "B1F/B2F warp pads and stairs lead to the submarine dock (" .. n .. " legs)") then
    return false
  end
  matt = S.objectByScript("AquaHideout_B2F_EventScript_Matt")
  if not d.check(matt ~= nil, "Matt guards the submarine") then return false end
  S.goTo(game, function(x, y) return math.abs(x - matt.cellX) + math.abs(y - matt.cellY) == 1 end, { tries = 20, settle = { limit = 20000 } })
  d.check(totalPads >= 1, "the hideout's warp pads carry the player around (" .. totalPads .. " pads)")
  d.shot(game, "18_aqua_hideout_dock")
  fightTrainer(game, "AquaHideout_B2F_EventScript_Matt", "Aqua Admin Matt", "19_matt", nil, "TRAINER_MATT")
  S.settle(game, { limit = 30000, until_ = function() return S.flag("FLAG_TEAM_AQUA_ESCAPED_IN_SUBMARINE") and not S.busy() end })
  return d.check(S.flag("FLAG_TEAM_AQUA_ESCAPED_IN_SUBMARINE") and S.flag("FLAG_HIDE_LILYCOVE_CITY_AQUA_GRUNTS"),
    "the submarine leaves: Archie is gone (FLAG_TEAM_AQUA_ESCAPED_IN_SUBMARINE)")
end }

-- pokeemerald/data/maps/MossdeepCity_Gym/scripts.inc:51
BEATS[#BEATS + 1] = { id = "mossdeep_gym", run = function(game)
  S.canSurf = true
  S.travel(game, { "EM_AQUA_HIDEOUT_B1F", "EM_AQUA_HIDEOUT_1F" }, { settle = { limit = 20000 } })
  if S.mapNow() ~= "EM_LILYCOVE_CITY" then seek(game, "EM_LILYCOVE_CITY", "EM_AQUA_HIDEOUT") end
  S.travel(game, { "EM_ROUTE124", "EM_MOSSDEEP_CITY" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_MOSSDEEP_CITY", "SURF from Lilycove across Route 124 to Mossdeep (" .. tostring(S.mapNow()) .. ")") then
    return false
  end
  d.shot(game, "20_mossdeep")
  if S.needsHeal() then S.healAtCenter(game, "EM_MOSSDEEP_CITY", "MossdeepCity") end
  S.travel(game, { "EM_MOSSDEEP_CITY_GYM" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_MOSSDEEP_CITY_GYM", "into the Mossdeep Gym") then return false end
  S.settle(game, { limit = 600 })
  d.shot(game, "21_mossdeep_gym")
  local tate = S.objectByScript("MossdeepCity_Gym_EventScript_TateAndLiza")
  local function nearTate(x, y)
    return (math.abs(x - 23) + math.abs(y - 7) == 1 or math.abs(x - 24) + math.abs(y - 7) == 1) and not (x == 23 and y == 7)
      and not (x == 24 and y == 7)
  end
  local ok, presses = mossdeepGo(game, nearTate)
  d.check(presses >= 1, "floor switches rotate the statues and trainers on the arrow tiles (" .. presses .. " presses)")
  if not d.check(ok, "warp pads and switches lead to Tate & Liza") then return false end
  if S.needsHeal(0.5) then S.healParty() d.note("NOTE party healed in place before Tate & Liza (driver)") end
  local P = require("src.core.game3.player")
  local tx = math.abs(P.cellX - 23) + math.abs(P.cellY - 7) == 1 and 23 or 24
  S.talkAt(game, tx, 7)
  S.settle(game, { limit = 60000, onBattleFrame = battleShot(game, "22_tate_and_liza"),
    until_ = function() return S.flag("FLAG_ENABLE_TATE_AND_LIZA_MATCH_CALL") and not S.busy() end })
  local won, rec = lastBattleWon(tid("TRAINER_TATE_AND_LIZA_1"))
  d.check(won, "Tate & Liza double battle won through the battle UI")
  d.check(S.hasItem("ITEM_TM04"), "Tate & Liza give TM04 CALM MIND")
  d.shot(game, "23_mind_badge")
  return d.check(S.flag("FLAG_BADGE07_GET") and S.var("VAR_MOSSDEEP_CITY_STATE") == 1, "MIND BADGE (FLAG_BADGE07_GET)")
end }

local function chooseHalf(game, slots)
  local PartyMenu = require("src.ui.game3.party_menu")
  for _, slot in ipairs(slots) do
    for _ = 1, 12 do
      if PartyMenu.cursor == slot then break end
      U.tap(game, "down") U.wait(6)
    end
    U.tap(game, "a")
    waitFor(function() return PartyMenu.mode == "action" end, 60)
    local want
    for i, a in ipairs(PartyMenu.ACTIONS or {}) do if a == "ENTER" then want = i end end
    for _ = 1, 8 do
      if not want or PartyMenu.actionCursor == want then break end
      U.tap(game, "down") U.wait(6)
    end
    U.tap(game, "a")
    U.wait(20)
  end
  waitFor(function() return PartyMenu.cursor == 7 end, 60)
  U.wait(10)
  return PartyMenu.cursor == 7
end

-- pokeemerald/data/maps/MossdeepCity_SpaceCenter_2F/scripts.inc:170
BEATS[#BEATS + 1] = { id = "space_center", run = function(game)
  if S.mapNow() == "EM_MOSSDEEP_CITY_GYM" then
    local P = require("src.core.game3.player")
    S.goTo(game, { 21, 6 }, { tries = 12, settle = { limit = 20000 } })
    S.settle(game, { limit = 20000, until_ = function() return P.cellY > 20 and not S.busy() end })
    d.check(P.cellX == 7 and P.cellY == 30, "the gym's exit tile warps back to the entrance (" .. P.cellX .. "," .. P.cellY .. ")")
  end
  S.travel(game, { "EM_MOSSDEEP_CITY" }, { settle = { limit = 20000 } })
  if S.needsHeal() then S.healAtCenter(game, "EM_MOSSDEEP_CITY", "MossdeepCity") end
  local trig = { ["42,21"] = true, ["41,22"] = true, ["41,23"] = true, ["41,24"] = true, ["40,25"] = true, ["40,26"] = true }
  local magmaShot = shotOnMessage(game, "24_magma_space_center")
  S.goTo(game, function(x, y) return trig[x .. "," .. y] == true end, { tries = 30, settle = { limit = 20000, watch = magmaShot } })
  S.settle(game, { limit = 20000, watch = magmaShot,
    until_ = function() return S.var("VAR_MOSSDEEP_CITY_STATE") == 2 and not S.busy() end })
  d.check(S.var("VAR_MOSSDEEP_CITY_STATE") == 2, "Team Magma storms the Space Center (VAR_MOSSDEEP_CITY_STATE=" .. S.var("VAR_MOSSDEEP_CITY_STATE") .. ")")
  S.travel(game, { "EM_MOSSDEEP_CITY_SPACE_CENTER_1F" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_MOSSDEEP_CITY_SPACE_CENTER_1F", "into the Space Center") then return false end
  fightTrainer(game, "MossdeepCity_SpaceCenter_1F_EventScript_Grunt2", "Magma Grunt on the stairs", nil, nil, "TRAINER_GRUNT_SPACE_CENTER_2")
  S.settle(game, { limit = 20000 })
  S.travel(game, { "EM_MOSSDEEP_CITY_SPACE_CENTER_2F" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_MOSSDEEP_CITY_SPACE_CENTER_2F", "up to the Space Center 2F") then return false end
  S.settle(game, { limit = 60000, until_ = function() return S.var("VAR_MOSSDEEP_SPACE_CENTER_STATE") == 2 and not S.busy() end })
  local g3 = 0
  for _, t in ipairs({ "TRAINER_GRUNT_SPACE_CENTER_5", "TRAINER_GRUNT_SPACE_CENTER_6", "TRAINER_GRUNT_SPACE_CENTER_7" }) do
    if S.trainerBeaten(t) then g3 = g3 + 1 end
  end
  d.check(g3 == 3, "three Magma grunts battled back to back on 2F (" .. g3 .. ")")
  local steven = S.objectByScript("MossdeepCity_SpaceCenter_2F_EventScript_Steven")
  if not d.check(steven ~= nil, "Steven faces Maxie and Tabitha") then return false end
  if S.needsHeal(0.9) then S.healParty() d.note("NOTE party healed in place before the multi battle (driver)") end
  local PartyMenu = require("src.ui.game3.party_menu")
  local chose = false
  S.talkTo(game, steven)
  S.settle(game, { limit = 20000, watch = shotOnMessage(game, "25_steven_space_center") })
  d.check(S.flag("FLAG_INTERACTED_WITH_STEVEN_SPACE_CENTER"), "Steven confronts Maxie over the rocket fuel")
  S.talkTo(game, steven)
  S.settle(game, { limit = 60000, onBattleFrame = battleShot(game, "27_steven_multi"),
    onIdleUi = function()
      if not chose and PartyMenu.isOpen() then
        chose = true
        U.wait(20)
        d.shot(game, "26_choose_three")
        chooseHalf(game, { 1, 2, 4 })
        U.tap(game, "a")
        U.wait(20)
        return true
      end
      return false
    end,
    until_ = function() return S.flag("FLAG_DEFEATED_MAGMA_SPACE_CENTER") and not S.busy() end })
  d.check(chose, "ChooseHalfPartyForBattle: three mons entered through the party menu")
  local won, rec = lastBattleWon(tid("TRAINER_MAXIE_MOSSDEEP"))
  d.check(won, "Steven + player multi battle vs Maxie and Tabitha won")
  d.check(#S.session().party == 4, "the party is restored after the multi battle (" .. #S.session().party .. ")")
  return d.check(S.flag("FLAG_DEFEATED_MAGMA_SPACE_CENTER") and S.var("VAR_STEVENS_HOUSE_STATE") == 1,
    "Magma leaves the Space Center (FLAG_DEFEATED_MAGMA_SPACE_CENTER, VAR_STEVENS_HOUSE_STATE=1)")
end }

-- pokeemerald/data/maps/MossdeepCity_StevensHouse/scripts.inc:28
BEATS[#BEATS + 1] = { id = "hm_dive", run = function(game)
  local diveShot = shotOnMessage(game, "28_steven_hm_dive", function() return S.mapNow() == "EM_MOSSDEEP_CITY_STEVENS_HOUSE" end)
  S.travel(game, { "EM_MOSSDEEP_CITY_SPACE_CENTER_1F", "EM_MOSSDEEP_CITY", "EM_MOSSDEEP_CITY_STEVENS_HOUSE" },
    { settle = { limit = 20000, watch = diveShot } })
  if not d.check(S.mapNow() == "EM_MOSSDEEP_CITY_STEVENS_HOUSE", "to Steven's house") then return false end
  S.settle(game, { limit = 30000, watch = diveShot,
    until_ = function() return S.flag("FLAG_RECEIVED_HM_DIVE") and not S.busy() end })
  d.check(S.hasItem("ITEM_HM08") and S.var("VAR_STEVENS_HOUSE_STATE") == 2, "Steven gives HM08 DIVE")
  teachHm("ITEM_HM08", 2)
  return d.check(knows(S.session().party[2], "MOVE_DIVE"), "Azumarill learns DIVE from HM08")
end }

-- pokeemerald/data/maps/SeafloorCavern_Room9/scripts.inc:4
BEATS[#BEATS + 1] = { id = "seafloor_cavern", run = function(game)
  S.canSurf = true
  S.travel(game, { "EM_MOSSDEEP_CITY" }, { settle = { limit = 20000 } })
  if S.needsHeal() then S.healAtCenter(game, "EM_MOSSDEEP_CITY", "MossdeepCity") end
  S.travel(game, { "EM_ROUTE127", "EM_ROUTE128" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_ROUTE128", "SURF from Mossdeep across Route 127 to Route 128 (" .. tostring(S.mapNow()) .. ")") then
    return false
  end
  local ok = diveNear(game, 38, 26, "EM_UNDERWATER_ROUTE128")
  if not d.check(ok, "DIVE into the Route 128 trench (" .. tostring(S.mapNow()) .. ")") then return false end
  U.wait(10)
  d.shot(game, "29_underwater_route128")
  S.travel(game, { "EM_UNDERWATER_SEAFLOOR_CAVERN" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_UNDERWATER_SEAFLOOR_CAVERN", "swim into the undersea cavern where the stolen submarine is moored") then
    return false
  end
  local Dive = require("src.core.game3.dive")
  local C = require("src.core.game3.collision")
  S.goTo(game, function(x, y) return not Dive.isUnableToEmerge(C.behavior(x, y)) and y >= 4 and y <= 6 and x >= 5 and x <= 8 end,
    { tries = 20, settle = { limit = 20000 } })
  emerge(game)
  if not d.check(S.mapNow() == "EM_SEAFLOOR_CAVERN_ENTRANCE", "surface inside the Seafloor Cavern (" .. tostring(S.mapNow()) .. ")") then
    return false
  end
  d.shot(game, "30_seafloor_entrance")
  S.canSurf = true
  seek(game, "EM_SEAFLOOR_CAVERN_ROOM9", "EM_SEAFLOOR_CAVERN", { tries = 60 })
  d.check((S.strengthPushes or 0) > 0 and (S.rocksSmashed or 0) > 0, "STRENGTH and ROCK SMASH clear the cavern rooms ("
    .. tostring(S.strengthPushes) .. " pushes, " .. tostring(S.rocksSmashed or 0) .. " rocks)")
  if not d.check(S.mapNow() == "EM_SEAFLOOR_CAVERN_ROOM9", "through the cavern rooms to Kyogre's chamber (" .. tostring(S.mapNow()) .. ")") then
    return false
  end
  if S.needsHeal(0.5) then S.healParty() d.note("NOTE party healed in place before Archie (driver)") end
  local kyogreShot = false
  local r128Shot = shotOnMessage(game, "33_route128_steven", function() return S.mapNow() == "EM_ROUTE128" end)
  local archieOpts = { limit = 60000, onBattleFrame = battleShot(game, "31_archie"),
    watch = function()
      r128Shot()
      if not kyogreShot and S.var("VAR_SEAFLOOR_CAVERN_STATE") == 0 and lastBattleWon(tid("TRAINER_ARCHIE")) then
        local M = require("src.ui.game3.message")
        if M.isOpen() then kyogreShot = true U.wait(4) d.shot(game, "32_kyogre_awakens") end
      end
    end,
    until_ = function() return S.flag("FLAG_KYOGRE_ESCAPED_SEAFLOOR_CAVERN") and not S.busy() end }
  S.goTo(game, { 17, 42 }, { tries = 30, settle = archieOpts })
  S.settle(game, archieOpts)
  d.check(lastBattleWon(tid("TRAINER_ARCHIE")), "Archie battle won through the battle UI")
  d.check(S.flag("FLAG_KYOGRE_ESCAPED_SEAFLOOR_CAVERN") and S.flag("FLAG_LEGENDARIES_IN_SOOTOPOLIS"),
    "the RED ORB awakens Kyogre and it escapes (FLAG_KYOGRE_ESCAPED_SEAFLOOR_CAVERN)")
  S.settle(game, { limit = 60000, watch = r128Shot,
    until_ = function() return S.var("VAR_ROUTE128_STATE") == 2 and not S.busy() end })
  return d.check(S.mapNow() == "EM_ROUTE128" and S.var("VAR_ROUTE128_STATE") == 2,
    "outside on Route 128 the weather turns; Steven sends the player to Sootopolis (VAR_ROUTE128_STATE=" .. S.var("VAR_ROUTE128_STATE") .. ")")
end }

-- pokeemerald/data/maps/SootopolisCity/scripts.inc:277
BEATS[#BEATS + 1] = { id = "sootopolis", run = function(game)
  S.canSurf = true
  S.travel(game, { "EM_ROUTE127", "EM_ROUTE126" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_ROUTE126", "SURF through the storm on Route 127 to Route 126 (" .. tostring(S.mapNow()) .. ")") then
    return false
  end
  if not d.check(diveNear(game, 45, 65, "EM_UNDERWATER_ROUTE126"), "DIVE down on Route 126 (" .. tostring(S.mapNow()) .. ")") then
    return false
  end
  S.travel(game, { "EM_UNDERWATER_SOOTOPOLIS_CITY" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_UNDERWATER_SOOTOPOLIS_CITY", "swim under the crater wall toward Sootopolis") then return false end
  d.shot(game, "34_underwater_sootopolis")
  local Dive = require("src.core.game3.dive")
  local C = require("src.core.game3.collision")
  local sceneShot = false
  local sceneWatch = function()
    local RS = package.loaded["src.ui.game3.rse.rayquaza_scene"]
    local sc = RS and RS.active and RS.active()
    if not sceneShot and sc and (sc.frames or 0) >= 150 then sceneShot = true d.shot(game, "35_sootopolis_legendaries") end
  end
  for _ = 1, 4 do
    if S.mapNow() ~= "EM_UNDERWATER_SOOTOPOLIS_CITY" then break end
    S.goTo(game, function(x, y) return Dive.trySetDiveWarp(S.session()) == 1 or not Dive.isUnableToEmerge(C.behavior(x, y)) end,
      { tries = 20, settle = { limit = 20000 } })
    emerge(game, sceneWatch)
  end
  S.settle(game, { limit = 60000, watch = sceneWatch,
    until_ = function() return S.var("VAR_SOOTOPOLIS_CITY_STATE") >= 2 and not S.busy() end })
  d.check(S.mapNow() == "EM_SOOTOPOLIS_CITY", "surface inside the Sootopolis crater (" .. tostring(S.mapNow()) .. ")")
  d.check(sceneShot, "the Groudon/Kyogre fight plays through Script_DoRayquazaScene")
  return d.check(S.var("VAR_SOOTOPOLIS_CITY_STATE") == 2,
    "Groudon and Kyogre clash in Sootopolis; Steven leads the player to Wallace (VAR_SOOTOPOLIS_CITY_STATE="
    .. S.var("VAR_SOOTOPOLIS_CITY_STATE") .. ")")
end }

-- pokeemerald/data/maps/CaveOfOrigin_B1F/scripts.inc:4
BEATS[#BEATS + 1] = { id = "cave_of_origin", run = function(game)
  S.canSurf = true
  local steven = S.objectByScript("SootopolisCity_EventScript_Steven")
  if not d.check(steven ~= nil, "Steven waits on the Sootopolis shore") then return false end
  S.talkTo(game, steven)
  S.settle(game, { limit = 30000, watch = shotOnMessage(game, "36_sootopolis_steven"),
    until_ = function() return S.flag("FLAG_STEVEN_GUIDES_TO_CAVE_OF_ORIGIN") and not S.busy() end })
  d.check(S.flag("FLAG_STEVEN_GUIDES_TO_CAVE_OF_ORIGIN"), "Steven leads the player through the city to the Cave of Origin")
  S.travel(game, { "EM_CAVE_OF_ORIGIN_ENTRANCE", "EM_CAVE_OF_ORIGIN_1F", "EM_CAVE_OF_ORIGIN_B1F" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_CAVE_OF_ORIGIN_B1F", "Sootopolis -> Cave of Origin -> B1F (" .. tostring(S.mapNow()) .. ")") then
    return false
  end
  local wallace = S.objectByScript("CaveOfOrigin_B1F_EventScript_Wallace")
  if not d.check(wallace ~= nil, "Wallace waits deep in the Cave of Origin") then return false end
  S.talkTo(game, wallace)
  local asked = false
  S.settle(game, { limit = 30000, watch = shotOnMessage(game, "37_wallace_cave_of_origin"),
    choice = function() asked = true return "SKY" end,
    until_ = function() return S.flag("FLAG_WALLACE_GOES_TO_SKY_PILLAR") and not S.busy() end })
  d.check(asked, "Wallace asks where Rayquaza is (multichoice answered SKY PILLAR)")
  return d.check(S.flag("FLAG_WALLACE_GOES_TO_SKY_PILLAR") and S.var("VAR_SOOTOPOLIS_CITY_STATE") == 3,
    "Wallace heads for Sky Pillar (VAR_SOOTOPOLIS_CITY_STATE=" .. S.var("VAR_SOOTOPOLIS_CITY_STATE") .. ")")
end }

-- pokeemerald/data/maps/SkyPillar_Top/scripts.inc:87
BEATS[#BEATS + 1] = { id = "sky_pillar", run = function(game)
  S.canSurf = true
  S.travel(game, { "EM_CAVE_OF_ORIGIN_1F", "EM_CAVE_OF_ORIGIN_ENTRANCE", "EM_SOOTOPOLIS_CITY" }, { settle = { limit = 20000 } })
  if not d.check(fly(game, "MOSSDEEP_CITY", "EM_MOSSDEEP_CITY"), "FLY out of the Sootopolis crater to Mossdeep (" .. tostring(S.mapNow()) .. ")") then
    return false
  end
  S.travel(game, { "EM_ROUTE127", "EM_ROUTE128", "EM_ROUTE129", "EM_ROUTE130", "EM_ROUTE131", "EM_SKY_PILLAR_ENTRANCE" },
    { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_SKY_PILLAR_ENTRANCE", "SURF Routes 127-131 to the Sky Pillar (" .. tostring(S.mapNow()) .. ")") then
    return false
  end
  local wallaceShot = shotOnMessage(game, "38_sky_pillar_wallace", function() return S.mapNow() == "EM_SKY_PILLAR_OUTSIDE" end)
  S.travel(game, { "EM_SKY_PILLAR_OUTSIDE" }, { settle = { limit = 20000, watch = wallaceShot } })
  S.settle(game, { limit = 30000, watch = wallaceShot,
    until_ = function() return S.var("VAR_SOOTOPOLIS_CITY_STATE") >= 4 and not S.busy() end })
  if not d.check(S.var("VAR_SOOTOPOLIS_CITY_STATE") == 4, "Wallace opens the Sky Pillar door (VAR_SOOTOPOLIS_CITY_STATE="
      .. S.var("VAR_SOOTOPOLIS_CITY_STATE") .. ")") then return false end
  S.canSurf = false
  local C = require("src.core.game3.collision")
  local cracks = 0
  local function countCracks()
    for yy = 0, (C._heightCells or 0) - 1 do
      for xx = 0, (C._widthCells or 0) - 1 do if C.isCrackedFloor(C.behavior(xx, yy)) then cracks = cracks + 1 end end
    end
  end
  local fell = false
  local legs = { "EM_SKY_PILLAR_1F", "EM_SKY_PILLAR_2F", "EM_SKY_PILLAR_3F", "EM_SKY_PILLAR_4F", "fall",
    { "EM_SKY_PILLAR_4F", arrive = { 7, 1 } }, "EM_SKY_PILLAR_5F", "EM_SKY_PILLAR_TOP" }
  for _, leg in ipairs(legs) do
    if leg == "fall" then
      if S.mapNow() == "EM_SKY_PILLAR_4F" then
        local target
        S.path(game, function(x, y)
          if not target and C.isCrackedFloor(C.behavior(x, y)) and y == 4 then target = { x, y } end
          return false
        end)
        if target then
          S.goTo(game, target, { tries = 20, settle = { limit = 20000 } })
          S.settle(game, { limit = 6000, until_ = function() return S.mapNow() == "EM_SKY_PILLAR_3F" and not S.busy() end })
        end
        fell = S.mapNow() == "EM_SKY_PILLAR_3F"
        if fell then d.shot(game, "39_sky_pillar_fell_to_3f") end
      end
    else
      S.travel(game, { leg }, { settle = { limit = 20000 } })
      local m = type(leg) == "table" and leg[1] or leg
      if S.mapNow() ~= m then d.note("stuck on " .. tostring(S.mapNow()) .. " heading to " .. m) break end
      if m ~= "EM_SKY_PILLAR_4F" then countCracks() end
    end
  end
  d.check(cracks == 0, "while Rayquaza sleeps the floors use the clean layouts (" .. cracks .. " cracked tiles off 4F)")
  d.check(fell, "the 4F cracked floor gives way underfoot and drops the player into 3F's inner room")
  if not d.check(S.mapNow() == "EM_SKY_PILLAR_TOP", "up the Sky Pillar to the top (" .. tostring(S.mapNow()) .. ")") then return false end
  local P = require("src.core.game3.player")
  if P.biking then S.session().registeredItem = S.item("ITEM_MACH_BIKE") U.tap(game, "select") U.wait(20) end
  local seenMsg = false
  local msgShot = shotOnMessage(game, "40_rayquaza_flew_off", function() seenMsg = true return S.vmRunning() end)
  S.goTo(game, { 14, 9 }, { tries = 20, settle = { limit = 30000, watch = msgShot } })
  S.settle(game, { limit = 30000, watch = msgShot,
    until_ = function() return S.var("VAR_SKY_PILLAR_STATE") == 1 and not S.busy() end })
  d.check(d.ran("SkyPillar_Top_EventScript_AwakenRayquaza") and seenMsg, "stepping up to the sleeping Rayquaza runs the awakening scene")
  return d.check(S.var("VAR_SOOTOPOLIS_CITY_STATE") == 5 and S.var("VAR_SKY_PILLAR_STATE") == 1,
    "Rayquaza awakens and flies to Sootopolis (VAR_SOOTOPOLIS_CITY_STATE=5, VAR_SKY_PILLAR_STATE=1)")
end }

-- pokeemerald/data/maps/SootopolisCity/scripts.inc:456
BEATS[#BEATS + 1] = { id = "rayquaza_scene", run = function(game)
  S.canSurf = false
  S.travel(game, { "EM_SKY_PILLAR_5F", "EM_SKY_PILLAR_4F" }, { settle = { limit = 20000 } })
  if S.mapNow() == "EM_SKY_PILLAR_4F" then
    local C = require("src.core.game3.collision")
    local target
    S.path(game, function(x, y)
      if not target and C.isCrackedFloor(C.behavior(x, y)) then target = { x, y } end
      return false
    end)
    if target then S.goTo(game, target, { tries = 20, settle = { limit = 20000 } }) end
    S.settle(game, { limit = 6000, until_ = function() return S.mapNow() == "EM_SKY_PILLAR_3F" and not S.busy() end })
  end
  S.travel(game, { "EM_SKY_PILLAR_2F", "EM_SKY_PILLAR_1F", "EM_SKY_PILLAR_OUTSIDE" }, { settle = { limit = 20000 } })
  d.check(S.mapNow() == "EM_SKY_PILLAR_OUTSIDE", "back down the Sky Pillar (4F crack drops to 3F) and outside (" .. tostring(S.mapNow()) .. ")")
  S.canSurf = true
  local flew = fly(game, "SOOTOPOLIS_CITY", "EM_SOOTOPOLIS_CITY")
  d.check(flew or S.mapNow() == "EM_SOOTOPOLIS_CITY", "FLY back to Sootopolis (" .. tostring(S.mapNow()) .. ")")
  local shotTaken = false
  S.settle(game, { limit = 60000, watch = function()
      local RS = package.loaded["src.ui.game3.rse.rayquaza_scene"]
      local sc = RS and RS.active and RS.active()
      if not shotTaken and sc and (sc.frames or 0) >= 1300 then shotTaken = true d.shot(game, "41_rayquaza_descends") end
    end,
    until_ = function() return S.var("VAR_SKY_PILLAR_STATE") >= 2 and not S.busy() end })
  S.settle(game, { limit = 20000 })
  d.check(d.ran("SootopolisCity_EventScript_StartRayquazaScene"), "Rayquaza descends on Sootopolis (Script_DoRayquazaScene)")
  d.check(S.var("VAR_SKY_PILLAR_STATE") >= 2 and not S.flag("FLAG_LEGENDARIES_IN_SOOTOPOLIS") and not S.flag("FLAG_SYS_WEATHER_CTRL"),
    "Groudon and Kyogre calm down, the weather clears (VAR_SKY_PILLAR_STATE=" .. S.var("VAR_SKY_PILLAR_STATE") .. ")")
  if not shotTaken then d.shot(game, "41_rayquaza_scene_after") end
  local maxie = S.objectByScript("SootopolisCity_EventScript_Maxie")
  local archie = S.objectByScript("SootopolisCity_EventScript_Archie")
  if not d.check(maxie ~= nil and archie ~= nil, "Maxie and Archie stand by the lake") then return false end
  S.talkTo(game, maxie)
  S.settle(game, { limit = 8000 })
  S.talkTo(game, archie)
  S.settle(game, { limit = 20000, watch = shotOnMessage(game, "42_maxie_archie") })
  d.check(S.flag("FLAG_SOOTOPOLIS_ARCHIE_MAXIE_LEAVE"), "Maxie and Archie leave (FLAG_SOOTOPOLIS_ARCHIE_MAXIE_LEAVE)")
  local wallace = S.objectByScript("SootopolisCity_EventScript_Wallace")
  if not d.check(wallace ~= nil, "Wallace waits in front of the gym") then return false end
  S.talkTo(game, wallace)
  S.settle(game, { limit = 20000, until_ = function() return S.flag("FLAG_RECEIVED_HM_WATERFALL") and not S.busy() end })
  return d.check(S.hasItem("ITEM_HM07"), "Wallace gives HM07 WATERFALL and opens the gym")
end }

-- pokeemerald/data/maps/SootopolisCity_Gym_1F/scripts.inc:81
BEATS[#BEATS + 1] = { id = "juan", run = function(game)
  if S.needsHeal() then S.healAtCenter(game, "EM_SOOTOPOLIS_CITY", "SootopolisCity") end
  S.canSurf = true
  S.travel(game, { "EM_SOOTOPOLIS_CITY_GYM_1F" }, { settle = { limit = 20000 } })
  if not d.check(S.mapNow() == "EM_SOOTOPOLIS_CITY_GYM_1F", "into the Sootopolis Gym (" .. tostring(S.mapNow()) .. ")") then return false end
  S.canSurf = false
  S.settle(game, { limit = 600 })
  d.shot(game, "43_sootopolis_gym")
  local P = require("src.core.game3.player")
  local sections = {
    { rows = { 17, 19 }, start = { 8, 19 }, finish = { 8, 17 }, count = 8 },
    { rows = { 12, 14 }, start = { 8, 14 }, finish = { 8, 12 }, count = 28 },
    { rows = { 6, 9 }, start = { 8, 9 }, finish = { 8, 6 }, count = 67 },
  }
  local walked = 0
  for i, sec in ipairs(sections) do
    S.goTo(game, { sec.start[1], sec.start[2] + 1 }, { tries = 20, settle = { limit = 20000 } })
    local path, n = icePath(game, sec.rows, sec.start, sec.finish)
    if not d.check(path ~= nil, "ice floor " .. i .. ": a route over all " .. tostring(n) .. " thin-ice tiles exactly once") then return false end
    local function stepTo(dir)
      local tx, ty = P.cellX + DELTA[dir][1], P.cellY + DELTA[dir][2]
      for _ = 1, 6 do
        if S.busy() then S.settle(game, { limit = 6000 }) end
        if P.cellX == tx and P.cellY == ty then return true end
        S.step(game, dir)
        if P.cellX == tx and P.cellY == ty then return true end
      end
      return P.cellX == tx and P.cellY == ty
    end
    stepTo("up")
    for _, dir in ipairs(path) do
      if not stepTo(dir) then d.note("ice step " .. dir .. " did not land at " .. P.cellX .. "," .. P.cellY) break end
      walked = walked + 1
      if S.mapNow() ~= "EM_SOOTOPOLIS_CITY_GYM_1F" then break end
    end
    S.settle(game, { limit = 6000, until_ = function() return S.var("VAR_ICE_STEP_COUNT") >= sec.count and not S.busy() end })
    S.settle(game, { limit = 600 })
    if i == 1 then d.shot(game, "44_ice_cracked_trail") end
    if not d.check(S.mapNow() == "EM_SOOTOPOLIS_CITY_GYM_1F" and S.var("VAR_ICE_STEP_COUNT") >= sec.count,
        "ice floor " .. i .. " cleared, the stairs appear (VAR_ICE_STEP_COUNT=" .. S.var("VAR_ICE_STEP_COUNT") .. ")") then
      return false
    end
    S.step(game, "up")
    S.step(game, "up")
    S.settle(game, { limit = 600 })
  end
  local juan = S.objectByScript("SootopolisCity_Gym_1F_EventScript_Juan")
  if not d.check(juan ~= nil, "Leader Juan at the top of the gym") then return false end
  if S.needsHeal(0.5) then S.healParty() d.note("NOTE party healed in place before Juan (driver)") end
  S.talkTo(game, juan)
  S.settle(game, { limit = 60000, onBattleFrame = battleShot(game, "45_juan"),
    until_ = function() return S.flag("FLAG_ENABLE_JUAN_MATCH_CALL") and not S.busy() end })
  d.check(lastBattleWon(tid("TRAINER_JUAN_1")), "Leader Juan battle won through the battle UI")
  d.check(S.hasItem("ITEM_TM03"), "Juan gives TM03 WATER PULSE")
  d.shot(game, "46_rain_badge")
  return d.check(S.flag("FLAG_BADGE08_GET") and S.var("VAR_SOOTOPOLIS_CITY_STATE") == 6,
    "RAIN BADGE (FLAG_BADGE08_GET), WATERFALL usable outside battle (VAR_SOOTOPOLIS_CITY_STATE=6)")
end }

return function(game)
  io.stdout:setvbuf("line")
  local from = os.getenv("EM_STORY_FROM")
  local to = os.getenv("EM_STORY_TO")
  local startAt = 1
  if from then
    for i, b in ipairs(BEATS) do
      if b.id == from then startAt = i end
    end
    if startAt > 1 then
      for _ = 1, 900 do
        if game.phase == "boot" and game.boot then break end
        U.wait(1)
      end
      if not d.check(S.loadCheckpoint(game, BEATS[startAt - 1].id), "resume from checkpoint " .. BEATS[startAt - 1].id) then
        return d.finish()
      end
      S.canSurf = true
    end
  end
  for i = startAt, #BEATS do
    local b = BEATS[i]
    d.note("BEAT " .. b.id .. " on " .. tostring(S.mapNow()))
    local t0 = os.time()
    local ok, res = xpcall(function() return b.run(game) end, debug.traceback)
    d.note("BEAT " .. b.id .. " took " .. (os.time() - t0) .. "s")
    if not ok then
      d.check(false, "beat " .. b.id .. " raised: " .. tostring(res))
      break
    end
    if res == false then
      d.note("beat " .. b.id .. " stopped at " .. tostring(S.mapNow()) .. " vm " .. S.vmWhere())
      S.saveCheckpoint(game, b.id .. "_fail")
      break
    end
    S.saveCheckpoint(game, b.id)
    if to and b.id == to then break end
  end
  d.finish()
end
